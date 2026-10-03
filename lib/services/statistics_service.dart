import '../core/constants/app_constants.dart';
import '../core/utils/app_date_utils.dart';
import '../core/utils/logger.dart';
import '../models/committee.dart';
import '../models/committee_turn.dart';
import '../models/enums.dart';
import '../models/member.dart';
import '../models/payment.dart';
import '../models/payment_schedule.dart';
import '../models/statistics.dart';
import '../repositories/interfaces/committee_repository.dart';
import '../repositories/interfaces/member_repository.dart';
import '../repositories/interfaces/payment_repository.dart';
import '../repositories/interfaces/turn_repository.dart';
import 'payment_calculator.dart';

/// Builds the aggregated numbers for the dashboard and the statistics screen.
///
/// Everything here is *derived*: no table stores a total, so a total can never
/// drift away from the payments it was calculated from.
class StatisticsService {
  const StatisticsService({
    required CommitteeRepository committeeRepository,
    required MemberRepository memberRepository,
    required PaymentRepository paymentRepository,
    required TurnRepository turnRepository,
    required PaymentCalculator calculator,
  }) : _committees = committeeRepository,
       _members = memberRepository,
       _payments = paymentRepository,
       _turns = turnRepository,
       _calculator = calculator;

  final CommitteeRepository _committees;
  final MemberRepository _members;
  final PaymentRepository _payments;
  final TurnRepository _turns;
  final PaymentCalculator _calculator;

  static const AppLogger _log = AppLogger('StatisticsService');

  /// Whole-app summary. Uses aggregate SQL for the big numbers and only loads
  /// rows when a name or a chart is genuinely needed.
  Future<DashboardStats> dashboard() async {
    try {
      final DateTime now = DateTime.now();
      final DateTime startOfToday = DateTime(now.year, now.month, now.day);

      final int totalCommittees = await _committees.count();
      if (totalCommittees == 0) {
        return const DashboardStats(
          totalCommittees: 0,
          activeCommittees: 0,
          completedCommittees: 0,
          draftCommittees: 0,
          totalMembers: 0,
          totalCollected: 0,
          totalPending: 0,
          pendingPaymentCount: 0,
          overduePaymentCount: 0,
          completedTurns: 0,
          totalTurns: 0,
        );
      }

      final int active = (await _committees.getByStatus(CommitteeStatus.active.name)).length;
      final int completed = (await _committees.getByStatus(CommitteeStatus.completed.name)).length;
      final int draft = (await _committees.getByStatus(CommitteeStatus.draft.name)).length;

      final double collected = await _payments.sumPaidAll();
      final int pendingCount = await _payments.countPendingAll();
      final int overdue = await _payments.countOverdueAll(startOfToday);
      final int completedTurns = await _turns.countCompletedAll();
      final int totalTurns = await _turns.countAll();

      double pendingAmount = 0;
      int totalMembers = 0;
      String? recipientName;
      String? recipientCommittee;
      double recipientAmount = 0;

      final List<Committee> activeCommittees = await _committees.getByStatus(
        CommitteeStatus.active.name,
      );
      for (final Committee committee in activeCommittees) {
        final List<Member> members = await _members.getByCommittee(committee.id);
        totalMembers += members.length;
        final List<Payment> payments = await _payments.getByCommittee(committee.id);
        pendingAmount += _calculator.pendingInPeriod(payments);

        final CommitteeTurn? activeTurn = await _turns.getActive(committee.id);
        if (activeTurn != null) {
          for (final Member member in members) {
            if (member.id == activeTurn.memberId) {
              recipientName = member.name;
              recipientCommittee = committee.name;
              recipientAmount = activeTurn.expectedAmount;
              break;
            }
          }
        }
      }

      // Upcoming deadline
      DateTime? nextDue;
      String? nextDueCommittee;
      for (final Committee committee in activeCommittees) {
        final List<PaymentSchedule> periods = _calculator.buildSchedule(committee);
        for (final PaymentSchedule period in periods) {
          if (period.dueDate.isBefore(startOfToday)) continue;
          if (nextDue == null || period.dueDate.isBefore(nextDue)) {
            nextDue = period.dueDate;
            nextDueCommittee = committee.name;
          }
          break; // only the next open period per committee
        }
      }

      int dueSoon = 0;
      for (final Committee committee in activeCommittees) {
        final List<Payment> payments = await _payments.getByCommittee(committee.id);
        final DateTime limit = AppDateUtils.addDays(
          startOfToday,
          AppConstants.dueSoonWindowDays,
        );
        dueSoon += payments
            .where(
              (Payment p) =>
                  !p.isPaid && !p.dueDate.isBefore(startOfToday) && !p.dueDate.isAfter(limit),
            )
            .length;
      }

      final List<PeriodCollection> recent = await _recentPeriods(activeCommittees, limit: 5);
      final ({List<double> values, List<String> labels}) trend = await _collectionTrend();

      return DashboardStats(
        totalCommittees: totalCommittees,
        activeCommittees: active,
        completedCommittees: completed,
        draftCommittees: draft,
        totalMembers: totalMembers,
        totalCollected: collected,
        totalPending: pendingAmount,
        pendingPaymentCount: pendingCount,
        overduePaymentCount: overdue,
        dueSoonPaymentCount: dueSoon,
        completedTurns: completedTurns,
        totalTurns: totalTurns,
        nextDueDate: nextDue,
        nextDueCommitteeName: nextDueCommittee,
        currentRecipientName: recipientName,
        currentRecipientCommittee: recipientCommittee,
        currentTurnAmount: recipientAmount,
        recentPayments: recent,
        monthlyCollection: trend.values,
        monthlyLabels: trend.labels,
      );
    } catch (error) {
      _log.error('Dashboard statistics failed', error);
      rethrow;
    }
  }

  /// Per-committee numbers, used by the details screen and the statistics tab.
  Future<CommitteeStats> forCommittee(String committeeId) async {
    final Committee? committee = await _committees.getById(committeeId);
    if (committee == null) {
      return _emptyStats(committeeId);
    }
    final List<Member> members = await _members.getByCommittee(committeeId);
    final List<Payment> payments = await _payments.getByCommittee(committeeId);
    final List<CommitteeTurn> turns = await _turns.getByCommittee(committeeId);
    return _calculator.computeCommitteeStats(
      committee: committee,
      members: members,
      payments: payments,
      turns: turns,
    );
  }

  /// Total money the organiser is currently holding in open pools.
  Future<double> currentPoolFor(String committeeId) async {
    final CommitteeStats stats = await forCommittee(committeeId);
    final double pool = stats.totalCollected - stats.totalPending;
    return pool < 0 ? 0 : pool;
  }

  Future<List<PeriodCollection>> allHistory({int limit = 100}) async {
    final List<Committee> all = await _committees.getAll();
    final List<PeriodCollection> merged = <PeriodCollection>[];
    for (final Committee committee in all) {
      merged.addAll(await _historyOf(committee));
    }
    merged.sort((PeriodCollection a, PeriodCollection b) => b.dueDate.compareTo(a.dueDate));
    return merged.take(limit).toList(growable: false);
  }

  // ------------------------------------------------------------------ Helpers

  Future<List<PeriodCollection>> _historyOf(Committee committee) async {
    final List<Member> members = await _members.getByCommittee(committee.id);
    final List<Payment> payments = await _payments.getByCommittee(committee.id);
    final List<CommitteeTurn> turns = await _turns.getByCommittee(committee.id);
    return _calculator.buildHistory(
      committee: committee,
      members: members,
      payments: payments,
      turns: turns,
    );
  }

  Future<List<PeriodCollection>> _recentPeriods(
    List<Committee> committees, {
    required int limit,
  }) async {
    final List<PeriodCollection> all = <PeriodCollection>[];
    for (final Committee committee in committees) {
      all.addAll(await _historyOf(committee));
    }
    all.sort((PeriodCollection a, PeriodCollection b) => b.dueDate.compareTo(a.dueDate));
    return all.take(limit).toList(growable: false);
  }

  /// Collected money per period for the last 6 periods — feeds the trend chart.
  ///
  /// Public because the statistics screen needs the series on its own, without
  /// paying for the whole dashboard aggregate every time it rebuilds.
  Future<({List<double> values, List<String> labels})> collectionTrend() => _collectionTrend();

  Future<({List<double> values, List<String> labels})> _collectionTrend() async {
    final List<({int periodNumber, double total, DateTime dueDate})> rows = await _payments
        .collectionByPeriodAll();
    rows.sort(
      (
        ({int periodNumber, double total, DateTime dueDate}) a,
        ({int periodNumber, double total, DateTime dueDate}) b,
      ) => a.dueDate.compareTo(b.dueDate),
    );
    final List<({int periodNumber, double total, DateTime dueDate})> tail = rows.length > 6
        ? rows.sublist(rows.length - 6)
        : rows;
    return (
      values: <double>[
        for (final ({int periodNumber, double total, DateTime dueDate}) r in tail) r.total,
      ],
      labels: <String>[
        for (final ({int periodNumber, double total, DateTime dueDate}) r in tail)
          AppDateUtils.formatCompact(r.dueDate),
      ],
    );
  }

  CommitteeStats _emptyStats(String committeeId) => CommitteeStats(
    committeeId: committeeId,
    totalMembers: 0,
    activeMembers: 0,
    contributionAmount: 0,
    expectedPool: 0,
    totalCollected: 0,
    totalPending: 0,
    paidCount: 0,
    pendingCount: 0,
    overdueCount: 0,
    completedTurns: 0,
    totalTurns: 0,
    currentPeriod: 1,
    totalPeriods: 0,
    currentRecipientName: null,
    nextRecipientName: null,
    nextDueDate: null,
    startDate: DateTime.now(),
    endDate: DateTime.now(),
  );
}
