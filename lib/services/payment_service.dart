import 'package:sqflite/sqflite.dart' show Transaction;

import '../core/errors/app_exception.dart';
import '../core/utils/logger.dart';
import '../database/app_database.dart';
import '../models/committee.dart';
import '../models/enums.dart';
import '../models/member.dart';
import '../models/payment.dart';
import '../models/payment_schedule.dart';
import '../repositories/interfaces/committee_repository.dart';
import '../repositories/interfaces/member_repository.dart';
import '../repositories/interfaces/payment_repository.dart';
import '../repositories/interfaces/schedule_repository.dart';
import 'payment_calculator.dart';
import 'turn_service.dart';

/// Recording, undoing and filtering payments.
///
/// Every write goes through a transaction and is followed by
/// [TurnService.reconcileInTransaction], so "a payment was marked" and "the turn
/// may have advanced" always happen together or not at all.
class PaymentService {
  const PaymentService({
    required PaymentRepository paymentRepository,
    required CommitteeRepository committeeRepository,
    required MemberRepository memberRepository,
    required ScheduleRepository scheduleRepository,
    required TurnService turnService,
    required PaymentCalculator calculator,
    required AppDatabase appDatabase,
  }) : _payments = paymentRepository,
       _committees = committeeRepository,
       _members = memberRepository,
       _schedules = scheduleRepository,
       _turns = turnService,
       _calculator = calculator,
       _db = appDatabase;

  final PaymentRepository _payments;
  final CommitteeRepository _committees;
  final MemberRepository _members;
  final ScheduleRepository _schedules;
  final TurnService _turns;
  final PaymentCalculator _calculator;
  final AppDatabase _db;

  static const AppLogger _log = AppLogger('PaymentService');

  // ------------------------------------------------------------------ Reads

  Future<List<Payment>> forCommittee(String committeeId) => _payments.getByCommittee(committeeId);

  Future<List<Payment>> forPeriod(String committeeId, int periodNumber) =>
      _payments.getByPeriod(committeeId, periodNumber);

  Future<List<Payment>> forMember(String memberId) => _payments.getByMember(memberId);

  /// The period most worth showing when someone opens the collection screen.
  ///
  /// This deliberately prefers the *oldest period still owing money* over the
  /// current calendar month. A committee that has fallen behind used to land on
  /// today's month - which always exists, because the schedule is generated
  /// upfront - leaving the genuinely overdue period invisible behind the `??`
  /// fallback that could therefore never fire. The user saw a screen of payments
  /// for a month that has not arrived while the money they are actually owed sat
  /// hidden one tab away.
  ///
  /// Falls back to the live turn, then to the next open period, so an
  /// up-to-date committee behaves exactly as before.
  Future<PaymentSchedule?> defaultPeriod(String committeeId, Committee committee) async {
    final List<Payment> all = await _payments.getByCommittee(committeeId);
    final Map<int, int> pendingByPeriod = <int, int>{};
    for (final Payment p in all) {
      if (!p.isPaid) pendingByPeriod.update(p.periodNumber, (int n) => n + 1, ifAbsent: () => 1);
    }
    if (pendingByPeriod.isNotEmpty) {
      final int oldest = pendingByPeriod.keys.reduce((int a, int b) => a < b ? a : b);
      final PaymentSchedule? owed = await _schedules.getByPeriod(committeeId, oldest);
      if (owed != null) return owed;
    }

    final int current = committee.currentTurn.clamp(1, committee.durationPeriods);
    return await _schedules.getByPeriod(committeeId, current) ??
        await _schedules.getNextOpen(committeeId, DateTime.now());
  }

  /// Joins payments with member names so the list screen can render rows
  /// without an N+1 query per row.
  Future<List<PaymentRow>> rowsFor(String committeeId, PaymentFilter filter) async {
    final List<Payment> payments = await _payments.getByCommittee(committeeId);
    final List<Member> members = await _members.getByCommittee(committeeId);
    final Map<String, String> names = <String, String>{
      for (final Member m in members) m.id: m.name,
    };
    final Map<String, int> turnNumbers = <String, int>{
      for (final Member m in members) m.id: m.turnNumber,
    };

    final List<Payment> filtered = _calculator.filter(payments, filter);
    return filtered
        .map(
          (Payment p) => PaymentRow(
            payment: p,
            memberName: names[p.memberId] ?? 'Unknown member',
            turnNumber: turnNumbers[p.memberId] ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<List<PaymentRow>> rowsForPeriod(
    String committeeId,
    int periodNumber,
    PaymentFilter filter,
  ) async {
    final List<Payment> payments = await _payments.getByPeriod(committeeId, periodNumber);
    final List<Member> members = await _members.getByCommittee(committeeId);
    final Map<String, String> names = <String, String>{
      for (final Member m in members) m.id: m.name,
    };
    final Map<String, int> turnNumbers = <String, int>{
      for (final Member m in members) m.id: m.turnNumber,
    };
    return _calculator
        .filter(payments, filter)
        .map(
          (Payment p) => PaymentRow(
            payment: p,
            memberName: names[p.memberId] ?? 'Unknown member',
            turnNumber: turnNumbers[p.memberId] ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<Payment> getById(String id) async {
    final Payment? payment = await _payments.getById(id);
    if (payment == null) throw const NotFoundException('This payment could not be found.');
    return payment;
  }

  // --------------------------------------------------------------- Mutations

  /// Marks a payment as received.
  ///
  /// Refuses a second call with [DuplicateException] (the repository's
  /// `status = 'pending'` guard plus the UNIQUE constraint make it
  /// impossible), then re-evaluates the turn.
  Future<void> markPaid({
    required String paymentId,
    DateTime? paidAt,
    PaymentMethod? method,
    String? notes,
  }) async {
    final Payment payment = await getById(paymentId);
    if (payment.isPaid) {
      throw const DuplicateException('This payment has already been recorded.');
    }
    final Committee? committee = await _committees.getById(payment.committeeId);
    if (committee == null) throw const NotFoundException('The committee no longer exists.');

    await _db.transaction<void>((Transaction txn) async {
      await _payments.markPaid(
        paymentId,
        paidAt ?? DateTime.now(),
        method: method?.name,
        notes: notes,
      );
      await _turns.reconcileInTransaction(committee);
      _log.info('Payment ${payment.periodNumber}/${payment.memberId} marked paid');
    });
  }

  /// Marks every unpaid row of a period as paid — the "everyone paid" shortcut.
  Future<int> markPeriodPaid({
    required String committeeId,
    required int periodNumber,
    PaymentMethod? method,
  }) async {
    final Committee committee = await _requireCommittee(committeeId);
    final List<Payment> payments = await _payments.getByPeriod(committeeId, periodNumber);
    final List<Payment> unpaid = payments.where((Payment p) => !p.isPaid).toList(growable: false);

    await _db.transaction<void>((Transaction txn) async {
      final DateTime now = DateTime.now();
      for (final Payment payment in unpaid) {
        await _payments.markPaid(payment.id, now, method: method?.name);
      }
      await _turns.reconcileInTransaction(committee);
    });
    _log.info('Marked ${unpaid.length} payments paid for period $periodNumber');
    return unpaid.length;
  }

  /// Undoes a payment. The turn it funded automatically re-opens.
  Future<void> markUnpaid(String paymentId) async {
    final Payment payment = await getById(paymentId);
    if (!payment.isPaid) {
      throw const BusinessRuleException('This payment is already marked as pending.');
    }
    final Committee? committee = await _committees.getById(payment.committeeId);
    if (committee == null) throw const NotFoundException('The committee no longer exists.');

    await _db.transaction<void>((Transaction txn) async {
      await _payments.markUnpaid(paymentId);
      await _turns.reconcileInTransaction(committee);
      _log.warn('Payment ${payment.id} reverted to pending');
    });
  }

  /// Records a part payment as paid. The real bachat committees sometimes
  /// collect less than the full amount in a period, so the row keeps its
  /// promised amount while the notes record what was actually received.
  Future<void> markPaidWithNote(String paymentId, String note) async {
    await markPaid(paymentId: paymentId, notes: note);
  }

  // -------------------------------------------------------------- Aggregates

  Future<double> collectedIn(String committeeId) => _payments.sumPaid(committeeId);

  Future<double> pendingIn(String committeeId) => _payments.sumPending(committeeId);

  Future<int> pendingCountIn(String committeeId) => _payments.countPending(committeeId);

  Future<int> overdueCountIn(String committeeId) =>
      _payments.countOverdue(committeeId, DateTime.now());

  /// Count of members that still owe money in a period.
  Future<int> unpaidInPeriod(String committeeId, int periodNumber) =>
      _payments.countPendingInPeriod(committeeId, periodNumber);

  /// The next due date that has not been fully paid — powers the dashboard card.
  Future<DateTime?> nextDueDate(String committeeId) async {
    final List<PaymentSchedule> periods = await _schedules.getByCommittee(committeeId);
    for (final PaymentSchedule period in periods) {
      if (period.isClosed) continue;
      if (await _payments.countPendingInPeriod(committeeId, period.periodNumber) > 0) {
        return period.dueDate;
      }
    }
    return null;
  }

  Future<Committee> _requireCommittee(String id) async {
    final Committee? committee = await _committees.getById(id);
    if (committee == null) throw const NotFoundException('This committee could not be found.');
    return committee;
  }
}

/// A payment joined with the member it belongs to — exactly what a list row
/// needs, and nothing more (Interface Segregation at the data level).
class PaymentRow {
  const PaymentRow({required this.payment, required this.memberName, required this.turnNumber});

  final Payment payment;
  final String memberName;
  final int turnNumber;

  String get id => payment.id;
  double get amount => payment.amount;
  bool get isPaid => payment.isPaid;
  bool get isOverdue => payment.isOverdue;
  bool get isDueSoon => payment.isDueSoon;
  bool get isSeverelyOverdue => payment.isSeverelyOverdue;
  int get daysOverdue => payment.daysOverdue;
  DateTime get dueDate => payment.dueDate;
  DateTime? get paidDate => payment.paidDate;
  String get statusLabel => payment.displayStatusLabel;
  String get overdueLabel => payment.overdueLabel;
  PaymentStatus get status => payment.effectiveStatus;
  PaymentMethod? get method => payment.method;
}
