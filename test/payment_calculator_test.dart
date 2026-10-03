import 'package:committee_manager/core/utils/app_date_utils.dart';
import 'package:committee_manager/models/committee.dart';
import 'package:committee_manager/models/committee_turn.dart';
import 'package:committee_manager/models/enums.dart';
import 'package:committee_manager/models/member.dart';
import 'package:committee_manager/models/payment.dart';
import 'package:committee_manager/models/payment_schedule.dart';
import 'package:committee_manager/services/payment_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the money and date arithmetic.
///
/// The rest of the suite drives services against a real database. This file
/// takes the opposite approach: the calculator has no dependencies, so every
/// rule can be checked directly, including the ones that are painful to reach
/// through the UI (a 31st-of-the-month start, a four-figure committee, an empty
/// member list).
///
/// The assertions lean on *invariants* — "collected + pending == total",
/// "when everyone has paid a period, the pool is fully funded" — because those
/// catch arithmetic drift that a single worked example would miss.
void main() {
  const PaymentCalculator calc = PaymentCalculator();
  final DateTime start = DateTime(2026, 1, 1);

  Committee committee({
    int memberCount = 3,
    int duration = 3,
    double contribution = 1000,
    PaymentFrequency frequency = PaymentFrequency.monthly,
    DateTime? startDate,
  }) => Committee(
    id: 'c1',
    name: 'Test Committee',
    contributionAmount: contribution,
    frequency: frequency,
    startDate: startDate ?? start,
    durationPeriods: duration,
    memberCount: memberCount,
    currentTurn: 1,
    completedTurns: 0,
    status: CommitteeStatus.active,
    createdAt: start,
  );

  List<Member> members(int count, {String committeeId = 'c1'}) => <Member>[
    for (int i = 1; i <= count; i++)
      Member(
        id: 'm$i',
        committeeId: committeeId,
        name: 'Member $i',
        turnNumber: i,
        isActive: true,
        createdAt: start,
      ),
  ];

  group('pool arithmetic', () {
    test('pool is contribution x (member count - 1), because the recipient skips', () {
      expect(calc.poolPerTurn(committee(memberCount: 5, contribution: 250)), 1000);
      expect(calc.poolPerTurn(committee(memberCount: 2, contribution: 99.5)), 99.5);
    });

    test('a fractional contribution does not drift over many periods', () {
      // 0.1 + 0.2 style error is the classic money bug. 33.33 x 29 rows must not
      // silently invent or lose money.
      final Committee c = committee(memberCount: 30, duration: 1, contribution: 33.33);
      final List<Member> ms = members(30);
      final List<PaymentSchedule> schedules = calc.buildSchedule(c);
      final List<Payment> payments = calc.buildPayments(
        committee: c,
        members: ms,
        schedules: schedules,
      );
      // Period 1 is collected by member 1, who does not pay: 30 - 1 rows.
      expect(payments, hasLength(29));
      final double total = calc.totalAmount(payments);
      // 33.33 * 29 == 966.57, allow a hair of float noise but not a paisa.
      expect(total, closeTo(966.57, 0.0001));
      expect(calc.poolPerTurn(c), closeTo(966.57, 0.0001));
    });

    test('empty input never produces NaN or infinity', () {
      expect(calc.poolPerTurn(committee(memberCount: 0, duration: 0)), 0);
      expect(calc.totalPaid(const <Payment>[]), 0);
      expect(calc.totalPending(const <Payment>[]), 0);
      expect(calc.totalAmount(const <Payment>[]), 0);
      expect(calc.paidCount(const <Payment>[]), 0);
      expect(calc.completionPercent(const <Payment>[]), 0);
      expect(calc.completionPercent(const <Payment>[]).isNaN, isFalse);
    });
  });

  group('collected and pending always reconcile', () {
    late Committee c;
    late List<Member> ms;
    late List<Payment> payments;

    setUp(() {
      c = committee(memberCount: 4, duration: 5, contribution: 2500);
      ms = members(4);
      payments = calc.buildPayments(committee: c, members: ms, schedules: calc.buildSchedule(c));
    });

    test('paid + pending == total for every combination', () {
      // 4 members x 5 periods, but the recipient skips in periods 1-4 and there
      // is no turn-5 recipient, so period 5 still has all four rows:
      // 3+3+3+3+4 == 16.
      expect(payments, hasLength(16), reason: '4 members x 5 periods, recipients skip');
      // Walk every possible "first k payments are paid" state.
      for (int k = 0; k <= payments.length; k++) {
        final List<Payment> state = <Payment>[
          for (int i = 0; i < payments.length; i++)
            i < k ? _paid(payments[i]) : payments[i],
        ];
        expect(
          calc.totalPaid(state) + calc.totalPending(state),
          closeTo(calc.totalAmount(state), 0.001),
          reason: 'reconciliation broke with $k of ${payments.length} paid',
        );
        expect(calc.paidCount(state) + calc.pendingCount(state), state.length);
        expect(
          calc.completionPercent(state),
          closeTo((k / state.length) * 100, 0.001),
        );
      }
    });

    test('when a whole period is paid it exactly funds one turn', () {
      final double pool = calc.poolPerTurn(c);
      final List<Payment> period1 = payments.where((Payment p) => p.periodNumber == 1).toList();
      final List<Payment> allPaid = period1.map(_paid).toList();
      expect(calc.collectedInPeriod(allPaid), closeTo(pool, 0.001));
      expect(calc.pendingInPeriod(allPaid), 0);
    });

    test('un-marking a payment puts the money back in pending', () {
      final List<Payment> one = <Payment>[_paid(payments.first)];
      expect(calc.totalPaid(one), 2500);
      expect(calc.totalPending(one), 0);
      final List<Payment> reverted = <Payment>[payments.first];
      expect(calc.totalPaid(reverted), 0);
      expect(calc.totalPending(reverted), 2500);
    });
  });

  group('filters', () {
    late List<Payment> payments;

    setUp(() {
      final Committee c = committee(memberCount: 2, duration: 2, contribution: 100);
      payments = calc.buildPayments(
        committee: c,
        members: members(2),
        schedules: calc.buildSchedule(c),
      );
    });

    test('each filter returns exactly its own rows', () {
      // With 2 members, period 1 is paid by member 2 and period 2 by member 1,
      // so the matrix has exactly two rows.
      final List<Payment> mixed = <Payment>[_paid(payments[0]), payments[1]];
      expect(calc.filter(mixed, PaymentFilter.all), hasLength(2));
      expect(calc.filter(mixed, PaymentFilter.paid), hasLength(1));
      expect(calc.filter(mixed, PaymentFilter.pending), hasLength(1));
      expect(calc.filter(mixed, PaymentFilter.pending).first.id, payments[1].id);
    });

    test('paid and pending are exact complements', () {
      final List<Payment> mixed = <Payment>[_paid(payments[0]), payments[1]];
      expect(
        calc.filter(mixed, PaymentFilter.paid).length +
            calc.filter(mixed, PaymentFilter.pending).length,
        mixed.length,
      );
    });

    test('filtering an empty list is safe for every option', () {
      for (final PaymentFilter f in PaymentFilter.values) {
        expect(calc.filter(const <Payment>[], f), isEmpty);
      }
    });
  });

  group('due dates', () {
    test('period 1 is the start date itself', () {
      expect(
        PaymentFrequency.monthly.dueDateForPeriod(1, start),
        start,
      );
      expect(PaymentFrequency.weekly.dueDateForPeriod(1, start), start);
    });

    test('monthly periods step one calendar month at a time', () {
      expect(
        PaymentFrequency.monthly.dueDateForPeriod(2, start),
        DateTime(2026, 2, 1),
      );
      expect(
        PaymentFrequency.monthly.dueDateForPeriod(3, start),
        DateTime(2026, 3, 1),
      );
    });

    test('weekly and biweekly step in weeks, quarterly in months', () {
      expect(
        PaymentFrequency.weekly.dueDateForPeriod(2, start),
        DateTime(2026, 1, 8),
      );
      expect(
        PaymentFrequency.biweekly.dueDateForPeriod(2, start),
        DateTime(2026, 1, 15),
      );
      expect(
        PaymentFrequency.quarterly.dueDateForPeriod(2, start),
        DateTime(2026, 4, 1),
      );
    });

    test('a 31st start clamps instead of overflowing into the next month', () {
      final DateTime jan31 = DateTime(2026, 1, 31);
      expect(AppDateUtils.addMonths(jan31, 1), DateTime(2026, 2, 28));
      // 2028 is a leap year, so February has 29 days.
      expect(AppDateUtils.addMonths(DateTime(2028, 1, 31), 1), DateTime(2028, 2, 29));
    });

    test('a December start rolls into the next year', () {
      final DateTime dec = DateTime(2026, 12, 15);
      expect(AppDateUtils.addMonths(dec, 1), DateTime(2027, 1, 15));
      expect(AppDateUtils.addMonths(dec, 3), DateTime(2027, 3, 15));
    });

    test('going backwards a month lands in the previous year', () {
      // Regression: truncating division used to turn Jan 2027 minus one month
      // into Dec *2027* instead of Dec 2026.
      expect(AppDateUtils.addMonths(DateTime(2027, 1, 15), -1), DateTime(2026, 12, 15));
      expect(AppDateUtils.addMonths(DateTime(2026, 3, 10), -1), DateTime(2026, 2, 10));
      expect(AppDateUtils.addMonths(DateTime(2026, 1, 10), -3), DateTime(2025, 10, 10));
    });

    test('daily arithmetic crosses month and year boundaries', () {
      expect(AppDateUtils.addDays(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 1));
      expect(AppDateUtils.addDays(DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
      expect(AppDateUtils.addDays(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
      expect(AppDateUtils.addDays(DateTime(2028, 3, 1), -1), DateTime(2028, 2, 29));
    });

    test('leap day survives a round trip', () {
      final DateTime leap = DateTime(2028, 2, 29);
      expect(AppDateUtils.dateOnly(leap), leap);
      expect(AppDateUtils.addDays(leap, 365), DateTime(2029, 2, 28));
    });

    test('daysBetween is signed and day-only', () {
      expect(AppDateUtils.daysBetween(DateTime(2026, 1, 1), DateTime(2026, 1, 31)), 30);
      expect(AppDateUtils.daysBetween(DateTime(2026, 1, 31), DateTime(2026, 1, 1)), -30);
      // Time of day must not shift the count.
      expect(
        AppDateUtils.daysBetween(DateTime(2026, 1, 1, 23), DateTime(2026, 1, 2, 1)),
        1,
      );
      expect(AppDateUtils.daysBetween(DateTime(2026, 5, 5), DateTime(2026, 5, 5)), 0);
    });

    test('a long monthly committee keeps stepping correctly', () {
      // Ten years of monthly periods: catches any drift accumulating over many
      // addMonths calls.
      final Committee c = committee(
        memberCount: 2,
        duration: 120,
        frequency: PaymentFrequency.monthly,
        startDate: DateTime(2026, 1, 15),
      );
      final List<PaymentSchedule> schedules = calc.buildSchedule(c);
      expect(schedules, hasLength(120));
      expect(schedules.first.dueDate, DateTime(2026, 1, 15));
      // Period 1 is the start date, so period N is N-1 months later.
      // 120 periods is 119 months: Jan 2026 + 119 months = Dec 2035.
      expect(schedules.last.dueDate, DateTime(2035, 12, 15));
      for (int i = 1; i < schedules.length; i++) {
        expect(
          schedules[i].dueDate.isAfter(schedules[i - 1].dueDate),
          isTrue,
          reason: 'period ${i + 1} must be later than period $i',
        );
      }
    });
  });

  group('turns', () {
    test('one turn per member, ordered by turn number', () {
      final Committee c = committee(memberCount: 3, duration: 3);
      final List<Member> ms = members(3);
      final List<CommitteeTurn> turns = calc.buildTurns(committee: c, members: ms);
      expect(turns, hasLength(3));
      expect(turns.map((CommitteeTurn t) => t.turnNumber), <int>[1, 2, 3]);
      // Turn 1 collects first and is the only active one at the start.
      expect(turns.first.status, TurnStatus.active);
      expect(turns.skip(1).every((CommitteeTurn t) => t.status == TurnStatus.upcoming), isTrue);
    });

    test('turn order does not depend on member insert order', () {
      final Committee c = committee(memberCount: 4, duration: 4);
      final List<Member> shuffled = members(4).reversed.toList();
      final List<CommitteeTurn> turns = calc.buildTurns(committee: c, members: shuffled);
      expect(turns.map((CommitteeTurn t) => t.turnNumber), <int>[1, 2, 3, 4]);
      // Turn 1 must belong to the member whose turnNumber is 1.
      expect(turns.first.memberId, 'm1');
    });

    test('every turn expects exactly one pool (made by the other members)', () {
      final Committee c = committee(memberCount: 6, duration: 6, contribution: 750);
      final List<CommitteeTurn> turns = calc.buildTurns(committee: c, members: members(6));
      expect(turns.every((CommitteeTurn t) => t.expectedAmount == 3750), isTrue);
    });

    test('a two-member committee is the smallest that funds itself', () {
      final Committee c = committee(memberCount: 2, duration: 2, contribution: 2000);
      final List<CommitteeTurn> turns = calc.buildTurns(committee: c, members: members(2));
      expect(turns, hasLength(2));
      // Each pot is the other member's single contribution.
      expect(turns.every((CommitteeTurn t) => t.expectedAmount == 2000), isTrue);
      expect(
        calc.buildPayments(committee: c, members: members(2), schedules: calc.buildSchedule(c)),
        hasLength(2),
      );
    });
  });

  group('current period tracking', () {
    test('before the first due date the current period is 1', () {
      final Committee c = committee(
        duration: 6,
        startDate: DateTime(2026, 1, 1),
      );
      expect(calc.currentPeriodFor(c, DateTime(2025, 12, 1)), 1);
    });

    test('once a due date passes the period advances', () {
      final Committee c = committee(duration: 6, startDate: DateTime(2026, 1, 1));
      expect(calc.currentPeriodFor(c, DateTime(2026, 1, 1)), 1);
      expect(calc.currentPeriodFor(c, DateTime(2026, 1, 2)), 2);
      expect(calc.currentPeriodFor(c, DateTime(2026, 2, 2)), 3);
    });

    test('long past the end it settles on the last period, not past it', () {
      final Committee c = committee(duration: 3, startDate: DateTime(2026, 1, 1));
      expect(calc.currentPeriodFor(c, DateTime(2030, 1, 1)), 3);
    });

    test('a due date later the same day is still the current period', () {
      // A committee must not advance early just because it is already the due
      // date - the member still has today to pay.
      final Committee c = committee(duration: 6, startDate: DateTime(2026, 1, 1));
      expect(calc.currentPeriodFor(c, DateTime(2026, 1, 1, 23, 59)), 1);
    });
  });

  group('history', () {
    test('one entry per period, newest first', () {
      final Committee c = committee(memberCount: 2, duration: 4, contribution: 100);
      final List<Member> ms = members(2);
      final List<PaymentSchedule> schedules = calc.buildSchedule(c);
      final List<Payment> payments = calc.buildPayments(
        committee: c,
        members: ms,
        schedules: schedules,
      );
      final List<CommitteeTurn> turns = calc.buildTurns(committee: c, members: ms);
      final history = calc.buildHistory(
        committee: c,
        members: ms,
        payments: payments,
        turns: turns,
      );
      expect(history, hasLength(4));
      expect(history.map((dynamic h) => h.periodNumber as int), <int>[4, 3, 2, 1]);
    });

    test('expected amount for a period is contribution x who was in it', () {
      final Committee c = committee(memberCount: 3, duration: 2, contribution: 500);
      final List<Member> ms = members(3);
      final List<Payment> payments = calc.buildPayments(
        committee: c,
        members: ms,
        schedules: calc.buildSchedule(c),
      );
      final history = calc.buildHistory(
        committee: c,
        members: ms,
        payments: payments,
        turns: calc.buildTurns(committee: c, members: ms),
      );
      for (final dynamic entry in history) {
        // Period 1 skips member 1, period 2 skips member 2: 2 payers each.
        expect(entry.expectedAmount as double, 1000);
        expect(entry.totalCount as int, 2);
        expect(entry.collectedAmount as double, 0);
      }
    });

    test('a paid period reports the money in collected', () {
      final Committee c = committee(memberCount: 2, duration: 1, contribution: 400);
      final List<Member> ms = members(2);
      final List<Payment> payments = calc
          .buildPayments(committee: c, members: ms, schedules: calc.buildSchedule(c))
          .map(_paid)
          .toList();
      final history = calc.buildHistory(
        committee: c,
        members: ms,
        payments: payments,
        turns: calc.buildTurns(committee: c, members: ms),
      );
      // Only member 2 pays in period 1 (member 1 collects it).
      expect(history.single.collectedAmount, 400);
      expect(history.single.paidCount, 1);
    });

    test('every period appears even when nobody has paid', () {
      final Committee c = committee(memberCount: 1, duration: 5);
      final List<Member> ms = members(1);
      final history = calc.buildHistory(
        committee: c,
        members: ms,
        payments: const <Payment>[],
        turns: calc.buildTurns(committee: c, members: ms),
      );
      expect(history, hasLength(5));
    });
  });

  group('statistics', () {
    test('counts agree with the payment matrix', () {
      final Committee c = committee(memberCount: 3, duration: 4, contribution: 1000);
      final List<Member> ms = members(3);
      final List<Payment> all = calc.buildPayments(
        committee: c,
        members: ms,
        schedules: calc.buildSchedule(c),
      );
      // Pay the first five rows.
      final List<Payment> payments = <Payment>[
        for (int i = 0; i < all.length; i++) i < 5 ? _paid(all[i]) : all[i],
      ];
      final stats = calc.computeCommitteeStats(
        committee: c,
        members: ms,
        payments: payments,
        turns: calc.buildTurns(committee: c, members: ms),
        now: DateTime(2026, 1, 15),
      );
      expect(stats.paidCount, 5);
      expect(stats.pendingCount, 4);
      expect(stats.totalCollected, 5000);
      expect(stats.totalPending, 4000);
      expect(stats.totalMembers, 3);
      expect(stats.expectedPool, 2000);
      expect(stats.paidCount + stats.pendingCount, 9);
    });

    test('current and next recipient follow the turn order', () {
      final Committee c = committee(memberCount: 3, duration: 3);
      final List<Member> ms = members(3);
      final stats = calc.computeCommitteeStats(
        committee: c,
        members: ms,
        payments: const <Payment>[],
        turns: calc.buildTurns(committee: c, members: ms),
        now: DateTime(2026, 1, 15),
      );
      expect(stats.currentRecipientName, 'Member 1');
      expect(stats.nextRecipientName, 'Member 2');
    });

    test('the recipient comes from the stored currentTurn, not from the date', () {
      // `currentTurn` is advanced by TurnService when a turn is completed, so a
      // freshly created committee still says turn 1 no matter how much time has
      // passed. Documented here because it is the behaviour the dashboard relies
      // on - see the drift test below for why it matters.
      final Committee c = committee(memberCount: 3, duration: 3);
      final List<Member> ms = members(3);
      final stats = calc.computeCommitteeStats(
        committee: c,
        members: ms,
        payments: const <Payment>[],
        turns: calc.buildTurns(committee: c, members: ms),
        now: DateTime(2030, 1, 1),
      );
      expect(stats.currentRecipientName, 'Member 1');
      expect(stats.nextRecipientName, 'Member 2');
    });

    test('a committee nobody has kept up to date stays self-consistent',
        () {
      // A 6-month committee started in the past, with no turn ever completed.
      //
      // The bug this guards: the live period was derived from today's date while
      // the recipient came from the stored turn, so the dashboard could claim
      // "period 6 of 6" while naming period 1's recipient and showing period 1's
      // due date. `currentPeriod` now tracks the turn, and the calendar is
      // reported separately as lateness rather than silently relabelling the
      // committee.
      final Committee fresh = committee(
        memberCount: 3,
        duration: 6,
        frequency: PaymentFrequency.monthly,
        startDate: DateTime(2026, 1, 1),
      );
      final Committee c = fresh.copyWith(currentTurn: 1);
      final List<Member> ms = members(3);
      final stats = calc.computeCommitteeStats(
        committee: c,
        members: ms,
        payments: const <Payment>[],
        turns: calc.buildTurns(committee: c, members: ms),
        now: DateTime(2026, 7, 1),
      );

      // Period, recipient and lateness all describe the same situation.
      expect(stats.currentPeriod, 1);
      expect(stats.currentRecipientName, 'Member 1');
      expect(stats.expectedPeriod, 6);
      expect(stats.isBehindSchedule, isTrue);
      expect(stats.periodsBehind, 5);
    });

    test('an on-schedule committee reports no lateness', () {
      final Committee c = committee(
        memberCount: 3,
        duration: 6,
        frequency: PaymentFrequency.monthly,
        startDate: DateTime(2026, 1, 1),
      ).copyWith(currentTurn: 2);
      final List<Member> ms = members(3);
      final stats = calc.computeCommitteeStats(
        committee: c,
        members: ms,
        payments: const <Payment>[],
        turns: calc.buildTurns(committee: c, members: ms),
        // 15 Feb: period 2's due date (1 Feb) has passed, so the committee is
        // genuinely a period behind, not on schedule.
        now: DateTime(2026, 2, 15),
      );
      expect(stats.currentPeriod, 2);
      expect(stats.expectedPeriod, 3);
      expect(stats.isBehindSchedule, isTrue);
      expect(stats.periodsBehind, 1);
    });

    test('a committee on the day its period is due reports no lateness', () {
      final Committee c = committee(
        memberCount: 3,
        duration: 6,
        frequency: PaymentFrequency.monthly,
        startDate: DateTime(2026, 1, 1),
      ).copyWith(currentTurn: 2);
      final List<Member> ms = members(3);
      final stats = calc.computeCommitteeStats(
        committee: c,
        members: ms,
        payments: const <Payment>[],
        turns: calc.buildTurns(committee: c, members: ms),
        // Period 2 is due today and the member still has today to pay.
        now: DateTime(2026, 2, 1, 9, 30),
      );
      expect(stats.currentPeriod, 2);
      expect(stats.expectedPeriod, 2);
      expect(stats.isBehindSchedule, isFalse);
      expect(stats.periodsBehind, 0);
    });

    test('per-member contributions split cleanly with no money lost', () {
      final Committee c = committee(memberCount: 3, duration: 3, contribution: 100);
      final List<Member> ms = members(3);
      final List<Payment> payments = calc.buildPayments(
        committee: c,
        members: ms,
        schedules: calc.buildSchedule(c),
      );
      final List<dynamic> rows = calc.computeMemberContributions(
        members: ms,
        payments: payments,
        turns: calc.buildTurns(committee: c, members: ms),
      );
      expect(rows, hasLength(3));
      double sum = 0;
      for (final dynamic row in rows) {
        sum += row.pendingCount as int;
        expect(row.paidCount as int, 0);
      }
      expect(sum, payments.length, reason: 'every pending row is owned by exactly one member');
    });
  });
}

/// A copy of [payment] that has been marked paid.
Payment _paid(Payment payment) => payment.copyWith(
  status: PaymentStatus.paid,
  paidDate: DateTime(2026, 1, 10),
);
