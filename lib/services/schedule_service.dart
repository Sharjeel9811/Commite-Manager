import 'package:sqflite/sqflite.dart' hide DatabaseException;

import '../core/utils/logger.dart';
import '../database/app_database.dart';
import '../models/committee.dart';
import '../models/committee_turn.dart';
import '../models/member.dart';
import '../models/payment_schedule.dart';
import '../repositories/interfaces/committee_repository.dart';
import '../repositories/interfaces/member_repository.dart';
import '../repositories/interfaces/payment_repository.dart';
import '../repositories/interfaces/schedule_repository.dart';
import '../repositories/interfaces/turn_repository.dart';
import 'payment_calculator.dart';

/// Builds and repairs the *whole* schedule of a committee: periods, turns and
/// the payment matrix — always atomically.
///
/// Splitting this out of `CommitteeService` keeps "what a schedule looks like"
/// separate from "what a committee is" (Single Responsibility) and gives the
/// app a safe, idempotent repair path for the roster.
class ScheduleService {
  const ScheduleService({
    required CommitteeRepository committeeRepository,
    required MemberRepository memberRepository,
    required ScheduleRepository scheduleRepository,
    required TurnRepository turnRepository,
    required PaymentRepository paymentRepository,
    required PaymentCalculator calculator,
    required AppDatabase appDatabase,
  }) : _committees = committeeRepository,
       _members = memberRepository,
       _schedules = scheduleRepository,
       _turns = turnRepository,
       _payments = paymentRepository,
       _calculator = calculator,
       _db = appDatabase;

  final CommitteeRepository _committees;
  final MemberRepository _members;
  final ScheduleRepository _schedules;
  final TurnRepository _turns;
  final PaymentRepository _payments;
  final PaymentCalculator _calculator;
  final AppDatabase _db;

  static const AppLogger _log = AppLogger('ScheduleService');

  // ----------------------------------------------------------------- Create

  /// Creates a brand new committee together with every row it needs, in one
  /// transaction.
  ///
  /// The committee header is written **first**, because every period, turn and
  /// payment carries a foreign key back to it — inserting the children first
  /// would be rejected by SQLite. If the app dies half way through, the database
  /// ends up with either *nothing* or *everything*, never a half-built
  /// committee.
  Future<void> createWithSchedule(Committee committee, List<Member> members) async {
    await _db.transaction<void>((Transaction txn) async {
      await _committees.insert(committee);
      await _members.insertAll(members);
      await generateRowsFor(committee, members);
      _log.info(
        'Created "${committee.name}": ${members.length} members, '
        '${committee.durationPeriods} periods, '
        '${members.length * (committee.durationPeriods <= 1 ? 0 : committee.durationPeriods - 1)} payments '
        '(recipient skips their own period)',
      );
    });
  }

  /// Rebuilds the generated rows of an **existing** committee.
  ///
  /// The header is left untouched because it already exists; only the derived
  /// rows (periods, turns, payments) are replaced. Used when the roster
  /// changes and the committee must be resized.
  Future<void> rebuildRows(Committee committee, List<Member> members) async {
    await _db.transaction<void>((Transaction txn) async {
      await clearRows(committee.id);
      await generateRowsFor(committee, members);
      _log.info('Rebuilt schedule for "${committee.name}" (${members.length} members)');
    });
  }

  /// Inserts the periods, turns and payment rows for [committee].
  ///
  /// Does **not** open a transaction — the caller decides the transaction
  /// boundary, so this method can be reused from a rebuild as well.
  Future<void> generateRowsFor(Committee committee, List<Member> members) async {
    if (members.isEmpty) return;

    final List<Member> ordered = List<Member>.of(members)
      ..sort((Member a, Member b) => a.turnNumber.compareTo(b.turnNumber));

    final List<PaymentSchedule> schedules = _calculator.buildSchedule(committee);
    await _schedules.insertAll(schedules);

    await _turns.insertAll(_calculator.buildTurns(committee: committee, members: ordered));

    await _payments.insertAll(
      _calculator.buildPayments(committee: committee, members: ordered, schedules: schedules),
    );
  }

  /// Wipes the generated rows (payments + periods + turns) of a committee.
  ///
  /// Deliberately does **not** open a transaction: the callers ([rebuildRows],
  /// `MemberService`, [ensureFor]) already own one, and sqflite cannot nest
  /// transactions on the same connection.
  Future<void> clearRows(String committeeId) async {
    await _turns.deleteByCommittee(committeeId);
    await _payments.deleteByCommittee(committeeId);
    await _schedules.deleteByCommittee(committeeId);
  }

  /// Idempotent repair run once at app start: makes sure the database contains
  /// the schedule implied by the committee definition.
  Future<void> ensureFor(Committee committee) async {
    final List<Member> members = await _members.getByCommittee(committee.id);
    if (members.isEmpty) return;

    final List<PaymentSchedule> periods = await _schedules.getByCommittee(committee.id);
    final List<CommitteeTurn> turns = await _turns.getByCommittee(committee.id);

    if (periods.length == committee.durationPeriods && turns.length == members.length) {
      return;
    }
    _log.warn('Repairing schedule for ${committee.id}');
    await _db.transaction<void>((Transaction txn) async {
      await clearRows(committee.id);
      await generateRowsFor(committee, members);
    });
  }

  // ------------------------------------------------------------------ Reads

  Future<List<PaymentSchedule>> periodsOf(String committeeId) =>
      _schedules.getByCommittee(committeeId);

  Future<PaymentSchedule?> periodOf(String committeeId, int periodNumber) =>
      _schedules.getByPeriod(committeeId, periodNumber);

  /// The period whose due date has not passed yet, else the earliest open one.
  Future<PaymentSchedule?> currentPeriod(String committeeId) =>
      _schedules.getNextOpen(committeeId, DateTime.now());

  /// The next period that still needs money, starting from the current one.
  Future<PaymentSchedule?> nextUpcomingPeriod(String committeeId, int fromPeriod) async {
    final List<PaymentSchedule> all = await _schedules.getByCommittee(committeeId);
    for (final PaymentSchedule schedule in all) {
      if (schedule.periodNumber >= fromPeriod && !schedule.isClosed) return schedule;
    }
    return all.isEmpty ? null : all.last;
  }

  Future<List<PaymentSchedule>> openPeriods(String committeeId) async {
    final List<PaymentSchedule> all = await _schedules.getByCommittee(committeeId);
    return all.where((PaymentSchedule s) => !s.isClosed).toList(growable: false);
  }

  Future<List<PaymentSchedule>> closedPeriods(String committeeId) async {
    final List<PaymentSchedule> all = await _schedules.getByCommittee(committeeId);
    return all.where((PaymentSchedule s) => s.isClosed).toList(growable: false);
  }

  Future<void> closePeriod(PaymentSchedule schedule) => _schedules.closePeriod(schedule.id);

  Future<void> reopenPeriod(PaymentSchedule schedule) => _schedules.reopenPeriod(schedule.id);

  Future<int> pendingCountFor(String committeeId, int periodNumber) =>
      _payments.countPendingInPeriod(committeeId, periodNumber);

  Future<int> totalCountFor(String committeeId, int periodNumber) =>
      _payments.countByPeriod(committeeId, periodNumber);
}
