import 'package:sqflite/sqflite.dart' hide DatabaseException;

import '../core/errors/app_exception.dart';
import '../core/utils/logger.dart';
import '../database/app_database.dart';
import '../models/committee.dart';
import '../models/committee_turn.dart';
import '../models/enums.dart';
import '../models/member.dart';
import '../models/payment_schedule.dart';
import '../repositories/interfaces/committee_repository.dart';
import '../repositories/interfaces/member_repository.dart';
import '../repositories/interfaces/payment_repository.dart';
import '../repositories/interfaces/schedule_repository.dart';
import '../repositories/interfaces/turn_repository.dart';

/// Owns **one** rule: *when does a turn complete, and who collects next?*
///
/// This is the heart of the rotation. It has no knowledge of the UI, of
/// notifications, or of which database technology is used — it is handed
/// repository **interfaces**, which is Dependency Inversion in practice.
class TurnService {
  const TurnService({
    required CommitteeRepository committeeRepository,
    required MemberRepository memberRepository,
    required TurnRepository turnRepository,
    required PaymentRepository paymentRepository,
    required ScheduleRepository scheduleRepository,
    required AppDatabase appDatabase,
  }) : _committees = committeeRepository,
       _members = memberRepository,
       _turns = turnRepository,
       _payments = paymentRepository,
       _schedules = scheduleRepository,
       _db = appDatabase;

  final CommitteeRepository _committees;
  final MemberRepository _members;
  final TurnRepository _turns;
  final PaymentRepository _payments;
  final ScheduleRepository _schedules;
  final AppDatabase _db;

  static const AppLogger _log = AppLogger('TurnService');

  /// Re-checks a committee after any payment change and moves the rotation on.
  ///
  /// Runs in one transaction so a payment + its turn update can never diverge.
  Future<Committee> reconcile(String committeeId) async {
    return _db.transaction<Committee>((Transaction txn) async {
      final Committee? committee = await _committees.getById(committeeId);
      if (committee == null) {
        throw NotFoundException('This committee no longer exists.');
      }
      return _reconcile(committee);
    });
  }

  /// Reconciles inside a transaction the caller already opened.
  Future<Committee> reconcileInTransaction(Committee committee) =>
      _reconcile(committee);

  Future<Committee> _reconcile(Committee committee) async {
    final List<CommitteeTurn> turns = await _turns.getByCommittee(committee.id);
    if (turns.isEmpty) return committee;

    // Recompute every turn from period completion. A period with no rows is
    // never complete, even though 0 >= 0 would otherwise be true.
    for (final CommitteeTurn turn in turns) {
      final int totalInPeriod = await _payments.countByPeriod(
        committee.id,
        turn.periodNumber,
      );
      final int paidInPeriod = await _payments.countPaidInPeriod(
        committee.id,
        turn.periodNumber,
      );
      final double collected = await _payments.sumPaidInPeriod(
        committee.id,
        turn.periodNumber,
      );
      final bool funded = totalInPeriod > 0 && paidInPeriod == totalInPeriod;
      if (funded) {
        await _turns.update(
          turn.copyWith(
            status: TurnStatus.completed,
            collectedAmount: collected,
            completedAt: turn.completedAt ?? DateTime.now(),
          ),
        );
        await _closePeriod(committee.id, turn.periodNumber);
      } else {
        await _turns.update(
          turn.copyWith(
            status: TurnStatus.upcoming,
            collectedAmount: collected,
            clearCompletedAt: true,
          ),
        );
        await _reopenPeriod(committee.id, turn.periodNumber);
      }
    }

    // The earliest non-completed turn is the only active turn.
    final List<CommitteeTurn> fresh = await _turns.getByCommittee(committee.id);
    final int completedTurns = fresh
        .where((CommitteeTurn t) => t.isCompleted)
        .length;
    final CommitteeTurn? firstOpen = _firstUncompleted(fresh);
    for (final CommitteeTurn turn in fresh) {
      final TurnStatus desired = turn.isCompleted
          ? TurnStatus.completed
          : (turn.id == firstOpen?.id
                ? TurnStatus.active
                : TurnStatus.upcoming);
      if (turn.status != desired) {
        await _turns.update(
          turn.copyWith(
            status: desired,
            clearCompletedAt: desired != TurnStatus.completed,
          ),
        );
      }
    }

    final bool allDone = firstOpen == null;
    final CommitteeStatus status = allDone
        ? CommitteeStatus.completed
        : CommitteeStatus.active;
    final int currentTurn = firstOpen?.turnNumber ?? committee.durationPeriods;

    final Committee updated = committee.copyWith(
      completedTurns: completedTurns,
      currentTurn: currentTurn < 1 ? 1 : currentTurn,
      status: status,
      updatedAt: DateTime.now(),
    );

    if (updated.completedTurns != committee.completedTurns ||
        updated.currentTurn != committee.currentTurn ||
        updated.status != committee.status) {
      await _committees.update(updated);
      _log.info(
        '"${committee.name}" -> turn ${updated.currentTurn}, '
        '$completedTurns/${committee.durationPeriods} completed, ${status.name}',
      );
    }
    return updated;
  }

  Future<void> _closePeriod(String committeeId, int periodNumber) async {
    final PaymentSchedule? schedule = await _schedules.getByPeriod(
      committeeId,
      periodNumber,
    );
    if (schedule != null && !schedule.isClosed) {
      await _schedules.closePeriod(schedule.id);
    }
  }

  Future<void> _reopenPeriod(String committeeId, int periodNumber) async {
    final PaymentSchedule? schedule = await _schedules.getByPeriod(
      committeeId,
      periodNumber,
    );
    if (schedule != null && schedule.isClosed) {
      await _schedules.reopenPeriod(schedule.id);
    }
  }

  CommitteeTurn? _firstUncompleted(List<CommitteeTurn> turns) {
    for (final CommitteeTurn turn in turns) {
      if (!turn.isCompleted) return turn;
    }
    return null;
  }

  // ------------------------------------------------------------------ Queries

  /// Who is collecting the pool right now.
  Future<({Member? member, int turnNumber, double expectedAmount})>
  currentRecipient(String committeeId) async {
    final CommitteeTurn? turn = await _turns.getActive(committeeId);
    if (turn == null) return (member: null, turnNumber: 0, expectedAmount: 0.0);
    final Member? member = await _members.getById(turn.memberId);
    return (
      member: member,
      turnNumber: turn.turnNumber,
      expectedAmount: turn.expectedAmount,
    );
  }

  /// Who collects after the current recipient.
  Future<Member?> nextRecipient(String committeeId) async {
    final Committee? committee = await _committees.getById(committeeId);
    if (committee == null) return null;
    final CommitteeTurn? next = await _turns.getByNumber(
      committeeId,
      committee.currentTurn + 1,
    );
    if (next == null) return null;
    return _members.getById(next.memberId);
  }

  Future<List<CommitteeTurn>> turnsOf(String committeeId) =>
      _turns.getByCommittee(committeeId);

  Future<CommitteeTurn?> turnOfMember(String memberId) =>
      _turns.getByMember(memberId);

  /// Guards against a member appearing twice in the rotation. The database has
  /// `UNIQUE (committee_id, member_id)` as the real guarantee; this gives the
  /// user a readable message before the driver error can happen.
  Future<void> assertMemberHasTurn(String committeeId, String memberId) async {
    final CommitteeTurn? turn = await _turns.getByMember(memberId);
    if (turn == null || turn.committeeId != committeeId) {
      throw const BusinessRuleException(
        'This member is not part of the turn order for this committee.',
      );
    }
  }
}
