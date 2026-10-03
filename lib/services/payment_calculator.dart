import '../models/committee.dart';
import '../models/committee_turn.dart';
import '../models/enums.dart';
import '../models/member.dart';
import '../models/payment.dart';
import '../models/payment_schedule.dart';
import '../models/statistics.dart';

/// Every money / count calculation used by the app lives in this one class.
///
/// It has **no dependencies at all** — no database, no Flutter, no providers.
/// That makes it trivially unit-testable (see `test/payment_calculator_test.dart`)
/// and means a business rule can never accidentally depend on the UI.
///
/// ### Open/Closed
/// New rules are added as new methods. Existing methods are never edited to
/// accommodate a new committee type or a new statistic.
class PaymentCalculator {
  const PaymentCalculator();

  // ------------------------------------------------------------ Money basics

  /// One member's payout.
  ///
  /// The member who collects a period's pot does **not** pay into it — the pot
  /// is made of the other `memberCount - 1` members' contributions.
  double poolPerTurn(Committee committee) =>
      committee.contributionAmount * (committee.memberCount <= 1 ? 0 : committee.memberCount - 1);

  /// Money collected in a single period: everyone who paid.
  double collectedInPeriod(List<Payment> payments) => payments
      .where((Payment p) => p.isPaid)
      .fold<double>(0, (double sum, Payment p) => sum + p.amount);

  /// Money still outstanding in a period.
  double pendingInPeriod(List<Payment> payments) => payments
      .where((Payment p) => !p.isPaid)
      .fold<double>(0, (double sum, Payment p) => sum + p.amount);

  double totalPaid(List<Payment> payments) => collectedInPeriod(payments);

  double totalPending(List<Payment> payments) => pendingInPeriod(payments);

  double totalAmount(List<Payment> payments) =>
      payments.fold<double>(0, (double sum, Payment p) => sum + p.amount);

  // ------------------------------------------------------------- Count basics

  int paidCount(List<Payment> payments) => payments.where((Payment p) => p.isPaid).length;

  int pendingCount(List<Payment> payments) => payments.where((Payment p) => !p.isPaid).length;

  int overdueCount(List<Payment> payments, {DateTime? asOf}) =>
      payments.where((Payment p) => p.isOverdue).length;

  /// 0.0 - 100.0 of the payments in the given list that are settled.
  double completionPercent(List<Payment> payments) {
    if (payments.isEmpty) return 0;
    return (paidCount(payments) / payments.length) * 100;
  }

  // ---------------------------------------------------------------- Filtering

  /// The single implementation of the "All / Paid / Pending / Overdue" filter,
  /// used by the payments screen *and* the history screen.
  List<Payment> filter(List<Payment> payments, PaymentFilter filter) {
    switch (filter) {
      case PaymentFilter.all:
        return payments;
      case PaymentFilter.paid:
        return payments.where((Payment p) => p.isPaid).toList(growable: false);
      case PaymentFilter.pending:
        return payments.where((Payment p) => !p.isPaid).toList(growable: false);
      case PaymentFilter.overdue:
        return payments.where((Payment p) => p.isOverdue).toList(growable: false);
    }
  }

  // ------------------------------------------------------------------ Turn map

  /// Builds the ordered "who collects when" list.
  ///
  /// The order comes from `members.turn_number`, which the database guarantees
  /// is unique inside a committee. Turn *N* is funded by period *N*.
  List<CommitteeTurn> buildTurns({required Committee committee, required List<Member> members}) {
    final List<Member> ordered = List<Member>.of(members)
      ..sort((Member a, Member b) => a.turnNumber.compareTo(b.turnNumber));
    final DateTime now = DateTime.now();
    final double pool = poolPerTurn(committee);
    final List<CommitteeTurn> turns = <CommitteeTurn>[];

    for (final Member member in ordered) {
      final int turnNumber = member.turnNumber;
      final int periodNumber = turnNumber.clamp(1, committee.durationPeriods);
      final DateTime dueDate = committee.frequency.dueDateForPeriod(
        periodNumber,
        committee.startDate,
      );
      turns.add(
        CommitteeTurn(
          id: '${committee.id}_turn_$turnNumber',
          committeeId: committee.id,
          turnNumber: turnNumber,
          memberId: member.id,
          periodNumber: periodNumber,
          expectedAmount: pool,
          collectedAmount: 0,
          dueDate: dueDate,
          status: turnNumber == 1 ? TurnStatus.active : TurnStatus.upcoming,
          createdAt: now,
        ),
      );
    }
    return turns;
  }

  /// The period rows for a committee: one per installment.
  List<PaymentSchedule> buildSchedule(Committee committee) {
    final List<PaymentSchedule> schedules = <PaymentSchedule>[];
    for (int period = 1; period <= committee.durationPeriods; period++) {
      final DateTime due = committee.frequency.dueDateForPeriod(period, committee.startDate);
      final DateTime previous = period == 1
          ? committee.startDate
          : committee.frequency.dueDateForPeriod(period - 1, committee.startDate);
      schedules.add(
        PaymentSchedule(
          id: '${committee.id}_period_$period',
          committeeId: committee.id,
          periodNumber: period,
          label: committee.frequency.periodLabel(period, due),
          startDate: previous,
          dueDate: due,
        ),
      );
    }
    return schedules;
  }

  /// The full payment matrix: every member owes money in every period **except**
  /// the period whose pot they collect.
  ///
  /// The amount is read from the period's schedule when possible so that a
  /// future "amount changed mid-committee" feature only has to touch the
  /// schedule, not this class.
  List<Payment> buildPayments({
    required Committee committee,
    required List<Member> members,
    required List<PaymentSchedule> schedules,
  }) {
    final Map<int, PaymentSchedule> byPeriod = <int, PaymentSchedule>{
      for (final PaymentSchedule s in schedules) s.periodNumber: s,
    };
    // Every period is collected for one member — the one whose turn number
    // equals the period number — and that member does not pay into it.
    final Set<int> recipients = <int>{
      for (final Member member in members)
        if (member.turnNumber >= 1 && member.turnNumber <= committee.durationPeriods)
          member.turnNumber,
    };
    final DateTime now = DateTime.now();
    final List<Payment> payments = <Payment>[];

    for (final PaymentSchedule schedule in schedules) {
      final DateTime dueDate = schedule.dueDate;
      final bool isRecipientPeriod = recipients.contains(schedule.periodNumber);
      for (final Member member in members) {
        // The member receiving this period's pot does not pay into it.
        if (isRecipientPeriod && member.turnNumber == schedule.periodNumber) continue;
        payments.add(
          Payment(
            id: '${committee.id}_${schedule.periodNumber}_${member.id}',
            committeeId: committee.id,
            scheduleId: byPeriod[schedule.periodNumber]!.id,
            memberId: member.id,
            periodNumber: schedule.periodNumber,
            amount: committee.contributionAmount,
            dueDate: dueDate,
            status: PaymentStatus.pending,
            createdAt: now,
          ),
        );
      }
    }
    return payments;
  }

  // -------------------------------------------------------------- Statistics

  /// Builds the per-committee summary shown on the details + statistics screen.
  CommitteeStats computeCommitteeStats({
    required Committee committee,
    required List<Member> members,
    required List<Payment> payments,
    required List<CommitteeTurn> turns,
    DateTime? now,
  }) {
    final DateTime asOf = now ?? DateTime.now();

    final int currentTurnIndex = committee.currentTurn.clamp(1, committee.durationPeriods);
    final CommitteeTurn? currentTurn = _turnByNumber(turns, currentTurnIndex);
    final CommitteeTurn? nextTurn = _turnByNumber(turns, currentTurnIndex + 1);

    return CommitteeStats(
      committeeId: committee.id,
      totalMembers: members.length,
      activeMembers: members.where((Member m) => m.isActive).length,
      contributionAmount: committee.contributionAmount,
      expectedPool: poolPerTurn(committee),
      totalCollected: totalPaid(payments),
      totalPending: totalPending(payments),
      paidCount: paidCount(payments),
      pendingCount: pendingCount(payments),
      overdueCount: payments
          .where((Payment p) => !p.isPaid && p.dueDate.isBefore(_startOfDay(asOf)))
          .length,
      completedTurns: turns.where((CommitteeTurn t) => t.isCompleted).length,
      totalTurns: committee.durationPeriods,
      // One source of truth: the turn we are actually collecting. Deriving this
      // from the calendar instead made a lapsed committee report "period 6"
      // while still naming period 1's recipient and period 1's due date.
      currentPeriod: currentTurnIndex,
      totalPeriods: committee.durationPeriods,
      expectedPeriod: currentPeriodFor(committee, asOf),
      currentRecipientName: currentTurn == null ? null : _nameOf(members, currentTurn.memberId),
      nextRecipientName: nextTurn == null ? null : _nameOf(members, nextTurn.memberId),
      nextDueDate:
          currentTurn?.dueDate ??
          committee.frequency.dueDateForPeriod(
            currentTurnIndex,
            committee.startDate,
          ),
      startDate: committee.startDate,
      endDate: committee.lastDueDate,
    );
  }

  /// Which period is "live" right now: the earliest period whose due date has
  /// not passed yet, otherwise the last one.
  int currentPeriodFor(Committee committee, DateTime now) {
    final DateTime today = _startOfDay(now);
    int current = 1;
    for (int period = 1; period <= committee.durationPeriods; period++) {
      final DateTime due = committee.frequency.dueDateForPeriod(period, committee.startDate);
      if (!due.isBefore(today)) return period;
      current = period;
    }
    return current.clamp(1, committee.durationPeriods).toInt();
  }

  /// Per-member contribution summary for the member list screen.
  List<MemberContribution> computeMemberContributions({
    required List<Member> members,
    required List<Payment> payments,
    required List<CommitteeTurn> turns,
  }) {
    return members
        .map((Member member) {
          final List<Payment> mine = payments
              .where((Payment p) => p.memberId == member.id)
              .toList(growable: false);
          final CommitteeTurn? turn = _turnByMember(turns, member.id);
          return MemberContribution(
            memberId: member.id,
            name: member.name,
            turnNumber: member.turnNumber,
            paidCount: paidCount(mine),
            pendingCount: pendingCount(mine),
            amountPaid: totalPaid(mine),
            hasReceivedTurn: turn?.isCompleted ?? false,
            receivedAt: turn?.completedAt,
          );
        })
        .toList(growable: false);
  }

  /// Groups payments by period and attaches the recipient of that period's turn.
  List<PeriodCollection> buildHistory({
    required Committee committee,
    required List<Member> members,
    required List<Payment> payments,
    required List<CommitteeTurn> turns,
  }) {
    final Map<int, List<Payment>> byPeriod = <int, List<Payment>>{};
    for (final Payment payment in payments) {
      byPeriod.putIfAbsent(payment.periodNumber, () => <Payment>[]).add(payment);
    }

    final List<PeriodCollection> history = <PeriodCollection>[];
    for (int period = 1; period <= committee.durationPeriods; period++) {
      final List<Payment> rows = byPeriod[period] ?? const <Payment>[];
      final CommitteeTurn? turn = _turnByPeriod(turns, period);
      final DateTime due = rows.isEmpty
          ? committee.frequency.dueDateForPeriod(period, committee.startDate)
          : rows.first.dueDate;
      history.add(
        PeriodCollection(
          committeeId: committee.id,
          committeeName: committee.name,
          periodNumber: period,
          label: committee.frequency.periodLabel(period, due),
          dueDate: due,
          expectedAmount: committee.contributionAmount * rows.length,
          collectedAmount: collectedInPeriod(rows),
          paidCount: paidCount(rows),
          totalCount: rows.length,
          recipientName: turn == null ? null : _nameOf(members, turn.memberId),
          turnStatus: (turn?.status ?? TurnStatus.upcoming).name,
          isClosed: turn?.isCompleted ?? false,
          completedAt: turn?.completedAt,
        ),
      );
    }
    return history.reversed.toList(growable: false);
  }

  String? _nameOf(List<Member> members, String memberId) {
    for (final Member member in members) {
      if (member.id == memberId) return member.name;
    }
    return null;
  }

  CommitteeTurn? _turnByNumber(List<CommitteeTurn> turns, int turnNumber) {
    for (final CommitteeTurn turn in turns) {
      if (turn.turnNumber == turnNumber) return turn;
    }
    return null;
  }

  CommitteeTurn? _turnByMember(List<CommitteeTurn> turns, String memberId) {
    for (final CommitteeTurn turn in turns) {
      if (turn.memberId == memberId) return turn;
    }
    return null;
  }

  CommitteeTurn? _turnByPeriod(List<CommitteeTurn> turns, int periodNumber) {
    for (final CommitteeTurn turn in turns) {
      if (turn.periodNumber == periodNumber) return turn;
    }
    return null;
  }

  static DateTime _startOfDay(DateTime value) => DateTime(value.year, value.month, value.day);
}
