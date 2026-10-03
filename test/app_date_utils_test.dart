import 'package:committee_manager/core/constants/app_constants.dart';
import 'package:committee_manager/core/utils/app_date_utils.dart';
import 'package:committee_manager/models/enums.dart';
import 'package:committee_manager/models/payment.dart';
import 'package:flutter_test/flutter_test.dart';

/// Focused tests for the "what does this date mean" helpers.
///
/// The rest of the suite treats time as a side effect; these tests pin the
/// human-facing contracts so wording and windows can change deliberately
/// instead of drifting when a screen refactor rewrites a string.
void main() {
  group('AppDateUtils.daysLate', () {
    final DateTime today = DateTime(2026, 10, 3);

    test('is zero when a payment is not due yet', () {
      expect(AppDateUtils.daysLate(DateTime(2026, 10, 5), asOf: today), 0);
    });

    test('is zero on the due date itself', () {
      expect(AppDateUtils.daysLate(today, asOf: today), 0);
    });

    test('counts whole days after the due date', () {
      expect(AppDateUtils.daysLate(DateTime(2026, 9, 30), asOf: today), 3);
    });

    test('never reports a negative span for a future row', () {
      expect(AppDateUtils.daysLate(DateTime(2027, 1, 1), asOf: today), 0);
    });

    test('ignores the time of day', () {
      final DateTime due = DateTime(2026, 9, 30, 23, 59);
      expect(AppDateUtils.daysLate(due, asOf: DateTime(2026, 10, 3, 0, 1)), 3);
    });
  });

  group('AppDateUtils.isDueSoon', () {
    final DateTime today = DateTime(2026, 10, 3);

    test('true for today', () {
      expect(AppDateUtils.isDueSoon(today, asOf: today), isTrue);
    });

    test('true inside the shared window', () {
      expect(
        AppDateUtils.isDueSoon(AppDateUtils.addDays(today, AppConstants.dueSoonWindowDays), asOf: today),
        isTrue,
      );
    });

    test('false just after the window', () {
      expect(
        AppDateUtils.isDueSoon(AppDateUtils.addDays(today, AppConstants.dueSoonWindowDays + 1), asOf: today),
        isFalse,
      );
    });

    test('false for a past due date', () {
      expect(AppDateUtils.isDueSoon(AppDateUtils.addDays(today, -1), asOf: today), isFalse);
    });
  });

  group('AppDateUtils.relativeDueText', () {
    final DateTime today = DateTime(2026, 10, 3);

    test('same day', () {
      expect(AppDateUtils.relativeDueText(today, asOf: today), 'Due today');
    });

    test('one day ahead', () {
      expect(
        AppDateUtils.relativeDueText(AppDateUtils.addDays(today, 1), asOf: today),
        'Due tomorrow',
      );
    });

    test('a few days ahead', () {
      expect(
        AppDateUtils.relativeDueText(AppDateUtils.addDays(today, 3), asOf: today),
        'Due in 3 days',
      );
    });

    test('switches to weeks after a week', () {
      expect(
        AppDateUtils.relativeDueText(AppDateUtils.addDays(today, 7), asOf: today),
        'Due in 1 week',
      );
      expect(
        AppDateUtils.relativeDueText(AppDateUtils.addDays(today, 14), asOf: today),
        'Due in 2 weeks',
      );
    });

    test('switches to months after 30 days', () {
      expect(
        AppDateUtils.relativeDueText(AppDateUtils.addDays(today, 30), asOf: today),
        'Due in 1 month',
      );
      expect(
        AppDateUtils.relativeDueText(AppDateUtils.addDays(today, 61), asOf: today),
        'Due in 3 months',
      );
    });

    test('one day late', () {
      expect(
        AppDateUtils.relativeDueText(AppDateUtils.addDays(today, -1), asOf: today),
        'Overdue by 1 day',
      );
    });

    test('several days late', () {
      expect(
        AppDateUtils.relativeDueText(AppDateUtils.addDays(today, -3), asOf: today),
        'Overdue by 3 days',
      );
    });

    test('late in weeks and months', () {
      expect(
        AppDateUtils.relativeDueText(AppDateUtils.addDays(today, -8), asOf: today),
        'Overdue by 2 weeks',
      );
      expect(
        AppDateUtils.relativeDueText(AppDateUtils.addDays(today, -45), asOf: today),
        'Overdue by 2 months',
      );
    });

    test('is year-agnostic (carries across month boundaries)', () {
      final DateTime newYearEve = DateTime(2026, 12, 31);
      expect(
        AppDateUtils.relativeDueText(DateTime(2027, 1, 2), asOf: newYearEve),
        'Due in 2 days',
      );
    });
  });

  group('AppDateUtils calendar helpers', () {
    test('addMonths clamps the day of a short month', () {
      final DateTime jan31 = DateTime(2026, 1, 31);
      expect(AppDateUtils.addMonths(jan31, 1), DateTime(2026, 2, 28));
    });

    test('addMonths handles year boundaries', () {
      expect(AppDateUtils.addMonths(DateTime(2026, 1, 31), -1), DateTime(2025, 12, 31));
    });

    test('addDays is calendar-daily, not 24-hourly', () {
      final DateTime lateEvening = DateTime(2026, 3, 31, 23, 59);
      // The app stores calendar days, so the helper returns the next day at
      // midnight rather than 23:59 twenty-four hours later.
      expect(AppDateUtils.addDays(lateEvening, 1), DateTime(2026, 4, 1));
    });
  });

  group('Payment due-date labels', () {
    final DateTime now = DateTime(2026, 10, 3);

    Payment build({required DateTime dueDate, bool paid = false}) => Payment(
      id: 'p1',
      committeeId: 'c1',
      scheduleId: 's1',
      memberId: 'm1',
      periodNumber: 1,
      amount: 500,
      dueDate: dueDate,
      paidDate: paid ? now : null,
      status: paid ? PaymentStatus.paid : PaymentStatus.pending,
      createdAt: now,
    );

    test('daysOverdue is 0 for an unpaid not-yet-due row', () {
      final Payment p = build(dueDate: DateTime(2026, 10, 10));
      expect(p.daysOverdue, 0);
      expect(p.isOverdue, isFalse);
      expect(p.isSeverelyOverdue, isFalse);
      // Never negative, even mid-day before the due date.
      expect(p.daysOverdue >= 0, isTrue);
    });

    test('a paid row never reports overdue days', () {
      final Payment p = build(dueDate: DateTime(2026, 9, 1), paid: true);
      expect(p.daysOverdue, 0);
      expect(p.isOverdue, isFalse);
    });

    test('a recently overdue row is overdue but not severe', () {
      final Payment p = build(
        dueDate: DateTime(2026, 9, 30),
      );
      expect(p.isOverdue, isTrue);
      expect(p.isSeverelyOverdue, isFalse);
      // Age buckets: 30+ days escalates, below threshold does not.
      expect(p.daysOverdue, lessThan(AppConstants.severelyOverdueDays));
    });

    test('a row late past the escalation threshold is severely overdue', () {
      final Payment p = build(dueDate: DateTime(2026, 8, 1));
      expect(p.daysOverdue, greaterThanOrEqualTo(AppConstants.severelyOverdueDays));
      expect(p.isSeverelyOverdue, isTrue);
    });

    test('overdueLabel is empty for a row that is not overdue', () {
      final Payment p = build(dueDate: DateTime(2026, 10, 10));
      expect(p.overdueLabel, '');
    });

    test('overdueLabel shows the single-day form for exactly one day late', () {
      final Payment p = build(dueDate: DateTime(2026, 10, 2));
      expect(p.overdueLabel, 'Overdue 1 day');
    });

    test('overdueLabel switches to the multi-day form', () {
      final Payment p = build(dueDate: DateTime(2026, 9, 28));
      expect(p.overdueLabel, 'Overdue 5 days');
    });

    test('overdueLabel escalates wording past the threshold', () {
      final Payment p = build(dueDate: DateTime(2026, 8, 1));
      expect(p.overdueLabel, contains('Severely overdue'));
    });
  });
}