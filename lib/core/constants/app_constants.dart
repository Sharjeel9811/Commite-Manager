/// Centralised application-wide constants.
///
/// Having every magic value in one place means the rest of the code never
/// hard-codes a number, string or duration. This is part of the
/// "Single Responsibility" of the *core* layer: global configuration only.
class AppConstants {
  const AppConstants._();

  // ---------------------------------------------------------------- Branding
  static const String appName = 'Committee Manager';
  static const String appTagline = 'Bachat Committee, perfectly managed.';
  static const String appVersion = '1.0.0';

  // --------------------------------------------------------------- Database
  static const String databaseName = 'committee_manager.db';
  static const String databaseDirectoryName = 'committee_manager';
  static const int databaseVersion = 2;

  // ------------------------------------------------------------------- Auth
  static const int minPinLength = 4;
  static const int maxPinLength = 6;
  // PIN hashing itself (algorithm, iteration count, salt) lives in
  // `CryptoHelper`, because it is crypto mechanics rather than policy.
  static const int maxPinAttempts = 5;
  static const Duration pinLockout = Duration(minutes: 5);
  static const int otpLength = 6;
  static const int otpMaxAttempts = 5;
  static const Duration otpValidity = Duration(minutes: 5);
  static const Duration otpResendCooldown = Duration(seconds: 30);

  /// The app locks itself after this much inactivity.
  static const Duration sessionIdleTimeout = Duration(minutes: 5);

  // ------------------------------------------------------------------ Money
  static const String defaultCurrencyCode = 'PKR';
  static const String defaultCurrencySymbol = 'Rs';
  static const int currencyDecimalDigits = 0;

  // ------------------------------------------------------------- Committee
  static const int minCommitteeMembers = 2;
  static const int maxCommitteeMembers = 200;
  static const int maxCommitteeNameLength = 60;
  static const int maxMemberNameLength = 60;
  static const double minContributionAmount = 1;
  static const double maxContributionAmount = 100000000;
  static const int maxRemindersPerCommittee = 60;

  // ---------------------------------------------------------- Notifications
  static const String notificationChannelId = 'committee_manager_reminders';
  static const String notificationChannelName = 'Committee reminders';
  static const String notificationChannelDescription =
      'Payment due dates, overdue payments and upcoming committee turns.';
  static const int reminderHour = 9;
  static const int reminderMinute = 0;
  static const int leadDaysBeforeDue = 1;
  static const int leadDaysBeforeTurn = 3;

  /// A payment is "due soon" when its due date is inside this many days.
  ///
  /// Drives the due-soon stats chip, the dashboard cut-off and any "nudge it
  /// now" logic. Kept here so the whole app nudges at the same pace.
  static const int dueSoonWindowDays = 3;

  /// Past this many days an overdue payment is escalated to "severely overdue"
  /// so the UI can draw attention with a stronger colour and wording.
  static const int severelyOverdueDays = 30;

  // ------------------------------------------------------------------ Names
  static const String demoCommitteeNameSuffix = ' (Sample)';
}
