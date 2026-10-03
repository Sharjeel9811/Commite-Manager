import 'package:intl/intl.dart';

import '../constants/app_constants.dart';

/// Date helpers shared by the whole app.
///
/// Named `AppDateUtils` so it never collides with Flutter's own `DateUtils`.
class AppDateUtils {
  const AppDateUtils._();

  static final DateFormat _dayMonthYear = DateFormat('dd MMM yyyy');
  static final DateFormat _dayMonth = DateFormat('dd MMM');
  static final DateFormat _monthYear = DateFormat('MMMM yyyy');
  static final DateFormat _time = DateFormat('hh:mm a');
  static final DateFormat _dateTime = DateFormat('dd MMM yyyy, hh:mm a');
  static final DateFormat _weekday = DateFormat('EEEE');

  /// Strips the time component — every date in this app is a calendar day.
  static DateTime dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

  static DateTime get today => dateOnly(DateTime.now());

  /// Adds calendar months, clamping the day so that
  /// 31 Jan + 1 month = 28/29 Feb instead of overflowing into March.
  ///
  /// Negative months are supported. The quotient must be floored, not
  /// truncated: `~/` truncates towards zero, so Jan 2027 minus one month would
  /// compute year 2027 and month 12, giving December *2027* instead of 2026.
  static DateTime addMonths(DateTime date, int months) {
    final int totalMonths = (date.year * 12 + date.month - 1) + months;
    final int year = totalMonths ~/ 12;
    final int month = totalMonths % 12 + 1;
    final int lastDay = DateTime(year, month + 1, 0).day;
    final int day = date.day > lastDay ? lastDay : date.day;
    return DateTime(year, month, day);
  }

  static DateTime addDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);

  static DateTime addWeeks(DateTime date, int weeks) => addDays(date, weeks * 7);

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool isToday(DateTime value) => isSameDay(value, DateTime.now());

  static bool isPast(DateTime value) => dateOnly(value).isBefore(today);

  static bool isFuture(DateTime value) => dateOnly(value).isAfter(today);

  /// Whole days between [from] and [to] (positive when [to] is later).
  static int daysBetween(DateTime from, DateTime to) =>
      dateOnly(to).difference(dateOnly(from)).inDays;

  /// How long a payment is already late, clamped at zero.
  ///
  /// Never negative: a payment whose due date is still ahead is "0 days
  /// overdue", not an impossible negative span. The old implementation could
  /// report negative days for unpaid-but-not-yet-due rows.
  static int daysLate(DateTime dueDate, {DateTime? asOf}) {
    final int late = daysBetween(dueDate, asOf ?? DateTime.now());
    return late < 0 ? 0 : late;
  }

  /// Whether [dueDate] falls inside the "due soon" window (defaults to the
  /// shared [AppConstants.dueSoonWindowDays], inclusive of today).
  static bool isDueSoon(DateTime dueDate, {DateTime? asOf}) {
    final int days = daysBetween(asOf ?? DateTime.now(), dueDate);
    if (days < 0) return false;
    return days <= AppConstants.dueSoonWindowDays;
  }

  /// Human friendly "Due in 3 days" / "Due in 2 weeks" / "Overdue by 1 month".
  ///
  /// Time is bucketed into the largest natural unit that still fits, so the
  /// dashboard reads like a modern calendar app instead of a pure "N days"
  /// counter: days for under a week, weeks for under a month, months beyond.
  static String relativeDueText(DateTime dueDate, {DateTime? asOf}) {
    final int days = daysBetween(asOf ?? DateTime.now(), dueDate);
    if (days == 0) return 'Due today';
    if (days == 1) return 'Due tomorrow';
    if (days > 1) return 'Due in ${_bucketed(days)}';
    return 'Overdue by ${_bucketed(days.abs())}';
  }

  static String _bucketed(int amount) {
    if (amount < 7) return '$amount ${_plural('day', amount)}';
    if (amount < 30) {
      final int weeks = (amount / 7).ceil();
      return '$weeks ${_plural('week', weeks)}';
    }
    final int months = (amount / 30).ceil();
    return '$months ${_plural('month', months)}';
  }

  static String _plural(String noun, int count) => count == 1 ? noun : '${noun}s';

  static String formatDayMonthYear(DateTime value) => _dayMonthYear.format(value);
  static String formatDayMonth(DateTime value) => _dayMonth.format(value);
  static String formatMonthYear(DateTime value) => _monthYear.format(value);
  static String formatTime(DateTime value) => _time.format(value);
  static String formatDateTime(DateTime value) => _dateTime.format(value);
  static String weekdayName(DateTime value) => _weekday.format(value);

  /// "1 Jan 2026" style short date used inside dense list rows.
  static String formatCompact(DateTime value) => DateFormat('d MMM yy').format(value);
}
