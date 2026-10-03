import 'package:flutter/material.dart';

import '../core/utils/app_date_utils.dart';

/// How often a committee collects money.
///
/// Adding a new rhythm (for example "fortnightly-custom") means adding one enum
/// value and one `switch` branch inside this file. **No other class in the
/// project has to change** — that is the Open/Closed Principle applied to the
/// one place where the whole system would otherwise be hard-coded to "monthly".
enum PaymentFrequency {
  weekly('Weekly', 'Every week'),
  biweekly('Every 2 Weeks', 'Every two weeks'),
  monthly('Monthly', 'Every month'),
  quarterly('Quarterly', 'Every three months');

  const PaymentFrequency(this.label, this.description);

  final String label;
  final String description;

  String get storageKey => name;

  static PaymentFrequency fromStorage(String? value) => PaymentFrequency.values.firstWhere(
    (PaymentFrequency item) => item.name == value,
    orElse: () => PaymentFrequency.monthly,
  );

  /// The due date of the period that starts on/after [from].
  DateTime nextDueDate(DateTime from) {
    switch (this) {
      case PaymentFrequency.weekly:
        return AppDateUtils.addWeeks(from, 1);
      case PaymentFrequency.biweekly:
        return AppDateUtils.addWeeks(from, 2);
      case PaymentFrequency.monthly:
        return AppDateUtils.addMonths(from, 1);
      case PaymentFrequency.quarterly:
        return AppDateUtils.addMonths(from, 3);
    }
  }

  /// The due date of period number [period] (1-based) starting from [startDate].
  DateTime dueDateForPeriod(int period, DateTime startDate) {
    DateTime cursor = AppDateUtils.dateOnly(startDate);
    for (int i = 1; i < period; i++) {
      cursor = nextDueDate(cursor);
    }
    return cursor;
  }

  /// Human readable name of a period, e.g. "October 2026" or "Week of 12 Oct".
  String periodLabel(int period, DateTime dueDate) {
    switch (this) {
      case PaymentFrequency.weekly:
      case PaymentFrequency.biweekly:
        return 'Week ${AppDateUtils.formatDayMonth(dueDate)}';
      case PaymentFrequency.monthly:
        return AppDateUtils.formatMonthYear(dueDate);
      case PaymentFrequency.quarterly:
        return 'Q${((dueDate.month - 1) ~/ 3) + 1} ${dueDate.year}';
    }
  }

  /// A short, sortable label used by search.
  String periodLabelForStart(int period, DateTime startDate) =>
      periodLabel(period, dueDateForPeriod(period, startDate));

  /// Approximate number of days between two periods — used for reminder maths.
  int get approxIntervalDays => switch (this) {
    PaymentFrequency.weekly => 7,
    PaymentFrequency.biweekly => 14,
    PaymentFrequency.monthly => 30,
    PaymentFrequency.quarterly => 91,
  };

  IconData get icon => switch (this) {
    PaymentFrequency.weekly => Icons.calendar_view_week,
    PaymentFrequency.biweekly => Icons.calendar_view_week_outlined,
    PaymentFrequency.monthly => Icons.calendar_month,
    PaymentFrequency.quarterly => Icons.calendar_today,
  };
}

/// Lifecycle of a committee.
enum CommitteeStatus {
  draft('Draft', 'Set up but not started yet'),
  active('Active', 'Collecting and distributing'),
  completed('Completed', 'Every member has received their turn'),
  archived('Archived', 'Hidden from the main dashboard');

  const CommitteeStatus(this.label, this.description);

  final String label;
  final String description;

  static CommitteeStatus fromStorage(String? value) => CommitteeStatus.values.firstWhere(
    (CommitteeStatus item) => item.name == value,
    orElse: () => CommitteeStatus.draft,
  );

  IconData get icon => switch (this) {
    CommitteeStatus.draft => Icons.edit_note,
    CommitteeStatus.active => Icons.play_circle_outline,
    CommitteeStatus.completed => Icons.verified_outlined,
    CommitteeStatus.archived => Icons.inventory_2_outlined,
  };
}

/// A member's turn in the collection order.
enum TurnStatus {
  upcoming('Upcoming', 'Not started yet'),
  active('In progress', 'This member collects the pool now'),
  completed('Completed', 'The pool has been handed over');

  const TurnStatus(this.label, this.description);

  final String label;
  final String description;

  static TurnStatus fromStorage(String? value) => TurnStatus.values.firstWhere(
    (TurnStatus item) => item.name == value,
    orElse: () => TurnStatus.upcoming,
  );

  bool get isClosed => this == TurnStatus.completed;
}

/// Payment state. `overdue` is *derived* (see `Payment.isOverdue`) and is never
/// stored, which keeps the database free of data that could go stale.
enum PaymentStatus {
  pending('Pending', 'Not paid yet'),
  paid('Paid', 'Received by the collector');

  const PaymentStatus(this.label, this.description);

  final String label;
  final String description;

  static PaymentStatus fromStorage(String? value) => PaymentStatus.values.firstWhere(
    (PaymentStatus item) => item.name == value,
    orElse: () => PaymentStatus.pending,
  );

  bool get isPaid => this == PaymentStatus.paid;
}

/// A human readable filter for the payments screen.
enum PaymentFilter {
  all('All'),
  paid('Paid'),
  pending('Pending'),
  overdue('Overdue');

  const PaymentFilter(this.label);

  final String label;
}

/// Optional extra fields captured when a payment is recorded.
enum PaymentMethod {
  cash('Cash'),
  bankTransfer('Bank transfer'),
  easypaisa('Easypaisa / JazzCash'),
  cheque('Cheque'),
  other('Other');

  const PaymentMethod(this.label);

  final String label;

  static PaymentMethod? fromStorage(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final PaymentMethod method in PaymentMethod.values) {
      if (method.name == value) return method;
    }
    return PaymentMethod.other;
  }
}

/// Who a member is inside the committee.
enum MemberRole {
  member('Member'),
  organizer('Organizer');

  const MemberRole(this.label);

  final String label;

  static MemberRole fromStorage(String? value) => MemberRole.values.firstWhere(
    (MemberRole item) => item.name == value,
    orElse: () => MemberRole.member,
  );
}

/// How a verification code is delivered.
///
/// The app is email-only: there is a single, deliberately boring path from
/// "user presses send" to "code arrives in their inbox". An SMS channel would
/// mean a paid provider, per-country sender-ID rules and a second failure mode
/// to explain in the UI, none of which the app needs to collect a committee.
enum OtpChannel {
  email('Email');

  const OtpChannel(this.label);

  final String label;

  /// Reads a stored value, tolerating rows written when SMS still existed.
  /// Anything unrecognised - including a legacy `'sms'` - resolves to email,
  /// which is the only channel there is now.
  static OtpChannel fromStorage(String? value) => OtpChannel.values.firstWhere(
    (OtpChannel item) => item.name == value,
    orElse: () => OtpChannel.email,
  );
}

/// Account role of the single local user.
enum UserRole {
  owner('Owner');

  const UserRole(this.label);

  final String label;

  static UserRole fromStorage(String? value) => UserRole.values.firstWhere(
    (UserRole item) => item.name == value,
    orElse: () => UserRole.owner,
  );
}

/// Which language the app displays in.
enum AppLanguage {
  english('English', 'en'),
  urdu('اردو', 'ur');

  const AppLanguage(this.label, this.code);

  final String label;
  final String code;

  static AppLanguage fromStorage(String? value) => AppLanguage.values.firstWhere(
    (AppLanguage item) => item.code == value,
    orElse: () => AppLanguage.english,
  );
}

/// How the app decides which theme to use.
enum AppThemePreference {
  system('Follow system'),
  light('Light'),
  dark('Dark');

  const AppThemePreference(this.label);

  final String label;

  static AppThemePreference fromStorage(String? value) => AppThemePreference.values.firstWhere(
    (AppThemePreference item) => item.name == value,
    orElse: () => AppThemePreference.system,
  );

  ThemeMode get themeMode => switch (this) {
    AppThemePreference.system => ThemeMode.system,
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
  };
}
