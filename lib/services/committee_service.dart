import 'package:sqflite/sqflite.dart' show Transaction;

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/utils/app_date_utils.dart';
import '../core/utils/crypto_helper.dart';
import '../core/utils/logger.dart';
import '../core/utils/validators.dart';
import '../database/app_database.dart';
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
import '../repositories/interfaces/schedule_repository.dart';
import '../repositories/interfaces/turn_repository.dart';
import 'payment_calculator.dart';
import 'schedule_service.dart';
import 'turn_service.dart';

/// Everything you can *do* with a committee: the use-case layer.
///
/// It is the only class that combines the individual repositories into a
/// meaningful operation, and it is the class the providers talk to. It contains
/// no Flutter imports and no SQL — that is what makes it unit-testable.
class CommitteeService {
  const CommitteeService({
    required CommitteeRepository committeeRepository,
    required MemberRepository memberRepository,
    required PaymentRepository paymentRepository,
    required ScheduleRepository scheduleRepository,
    required TurnRepository turnRepository,
    required ScheduleService scheduleService,
    required TurnService turnService,
    required PaymentCalculator calculator,
    required AppDatabase appDatabase,
  }) : _committees = committeeRepository,
       _members = memberRepository,
       _payments = paymentRepository,
       _schedules = scheduleRepository,
       _turns = turnRepository,
       _scheduleService = scheduleService,
       _turnService = turnService,
       _calculator = calculator,
       _database = appDatabase;

  final CommitteeRepository _committees;
  final MemberRepository _members;
  final PaymentRepository _payments;
  final ScheduleRepository _schedules;
  final TurnRepository _turns;
  final ScheduleService _scheduleService;
  final TurnService _turnService;
  final PaymentCalculator _calculator;
  final AppDatabase _database;

  static const AppLogger _log = AppLogger('CommitteeService');

  // ------------------------------------------------------------------ Reads

  Future<List<Committee>> getAll() => _committees.getAll();

  Future<List<Committee>> activeCommittees() =>
      _committees.getByStatus(CommitteeStatus.active.name);

  Future<Committee> getById(String id) async {
    final Committee? committee = await _committees.getById(id);
    if (committee == null) {
      throw const NotFoundException('This committee could not be found.');
    }
    return committee;
  }

  Future<List<Committee>> search(String query) => _committees.search(query);

  Future<List<Committee>> filterByStatus(CommitteeStatus? status) =>
      status == null ? _committees.getAll() : _committees.getByStatus(status.name);

  /// Everything the details screen needs, in one call: one consistent snapshot
  /// instead of five independent queries that could disagree with each other.
  Future<CommitteeBundle> loadBundle(String committeeId) async {
    final Committee committee = await getById(committeeId);
    final List<Member> members = await _members.getByCommittee(committeeId);
    final List<Payment> payments = await _payments.getByCommittee(committeeId);
    final List<CommitteeTurn> turns = await _turns.getByCommittee(committeeId);
    final List<PaymentSchedule> periods = await _schedules.getByCommittee(committeeId);
    return CommitteeBundle(
      committee: committee,
      members: members,
      payments: payments,
      turns: turns,
      periods: periods,
    );
  }

  Future<CommitteeStats> statsFor(String committeeId) async {
    final CommitteeBundle bundle = await loadBundle(committeeId);
    return _calculator.computeCommitteeStats(
      committee: bundle.committee,
      members: bundle.members,
      payments: bundle.payments,
      turns: bundle.turns,
    );
  }

  Future<List<PeriodCollection>> historyFor(String committeeId) async {
    final CommitteeBundle bundle = await loadBundle(committeeId);
    return _calculator.buildHistory(
      committee: bundle.committee,
      members: bundle.members,
      payments: bundle.payments,
      turns: bundle.turns,
    );
  }

  Future<List<MemberContribution>> memberContributionsFor(String committeeId) async {
    final CommitteeBundle bundle = await loadBundle(committeeId);
    return _calculator.computeMemberContributions(
      members: bundle.members,
      payments: bundle.payments,
      turns: bundle.turns,
    );
  }

  // ----------------------------------------------------------------- Create

  /// Creates a committee together with its members, periods, turns and the full
  /// payment matrix — atomically, through [ScheduleService].
  Future<Committee> create({
    required String name,
    required String? description,
    required double contributionAmount,
    required PaymentFrequency frequency,
    required DateTime startDate,
    required List<MemberDraft> memberDrafts,
    bool isDemo = false,
  }) async {
    _validateCreate(
      name: name,
      contributionAmount: contributionAmount,
      startDate: startDate,
      memberDrafts: memberDrafts,
    );

    final int duration = memberDrafts.length;
    final DateTime start = DateTime(startDate.year, startDate.month, startDate.day);

    final Committee committee = Committee(
      id: CryptoHelper.newId(),
      name: name.trim(),
      description: (description ?? '').trim().isEmpty ? null : description!.trim(),
      contributionAmount: contributionAmount,
      frequency: frequency,
      startDate: start,
      durationPeriods: duration,
      memberCount: duration,
      currentTurn: 1,
      completedTurns: 0,
      status: CommitteeStatus.active,
      createdAt: DateTime.now(),
      isDemo: isDemo,
    );

    final List<Member> members = <Member>[
      for (int i = 0; i < memberDrafts.length; i++)
        memberDrafts[i].toMember(committeeId: committee.id, turnNumber: i + 1, isDemo: isDemo),
    ];

    await _scheduleService.createWithSchedule(committee, members);
    return committee;
  }

  void _validateCreate({
    required String name,
    required double contributionAmount,
    required DateTime startDate,
    required List<MemberDraft> memberDrafts,
  }) {
    final Map<String, String> errors = <String, String>{};

    final String? nameError = Validators.committeeName(name);
    if (nameError != null) errors['name'] = nameError;

    if (contributionAmount < AppConstants.minContributionAmount) {
      errors['amount'] = 'Contribution amount must be greater than 0';
    } else if (contributionAmount > AppConstants.maxContributionAmount) {
      errors['amount'] = 'That amount is unrealistically large';
    }

    final String? startError = Validators.startDate(startDate);
    if (startError != null) errors['startDate'] = startError;

    if (memberDrafts.length < AppConstants.minCommitteeMembers) {
      errors['members'] = 'A committee needs at least ${AppConstants.minCommitteeMembers} members';
    } else if (memberDrafts.length > AppConstants.maxCommitteeMembers) {
      errors['members'] = 'Maximum ${AppConstants.maxCommitteeMembers} members supported';
    }

    for (int i = 0; i < memberDrafts.length; i++) {
      final MemberDraft draft = memberDrafts[i];
      final String? nameErr = Validators.memberName(draft.name);
      if (nameErr != null) errors['member$i'] = nameErr;
      final String? phoneErr = Validators.phoneNumber(draft.phoneNumber);
      if (phoneErr != null) errors['member$i'] = phoneErr;
    }

    if (errors.isNotEmpty) {
      throw ValidationException('Please correct the highlighted fields.', fieldErrors: errors);
    }
  }

  // ------------------------------------------------------------------- Edit

  /// Updates the descriptive fields. Always allowed.
  Future<Committee> updateDetails({
    required String id,
    required String name,
    String? description,
  }) async {
    final Committee committee = await getById(id);
    final String? nameError = Validators.committeeName(name);
    if (nameError != null) {
      throw ValidationException(nameError, fieldErrors: <String, String>{'name': nameError});
    }
    final Committee updated = committee.copyWith(
      name: name.trim(),
      description: (description ?? '').trim().isEmpty ? null : description!.trim(),
    );
    await _committees.update(updated);
    return updated;
  }

  /// Changes the contribution amount.
  ///
  /// Refused as soon as any payment has been recorded: rewriting past amounts
  /// would make the history lie about how much was agreed.
  ///
  /// The committee, its payment rows and its turn expectations are rewritten
  /// **inside one transaction**. Without it, a failure halfway through would
  /// leave the committee advertising a new amount while the generated payments
  /// still carry the old one — a history that quietly stops adding up.
  Future<Committee> updateContribution({
    required String id,
    required double contributionAmount,
  }) async {
    final Committee committee = await getById(id);
    if (contributionAmount < AppConstants.minContributionAmount) {
      throw const ValidationException('Contribution amount must be greater than 0.');
    }
    if (contributionAmount > AppConstants.maxContributionAmount) {
      throw ValidationException(
        'The amount must not exceed ${AppConstants.maxContributionAmount.toStringAsFixed(0)}.',
      );
    }
    if (await _payments.countPaid(id) > 0) {
      throw const BusinessRuleException(
        'The amount can no longer be changed because payments have already been recorded.',
      );
    }

    return _database.transaction((Transaction _) async {
      final Committee updated = committee.copyWith(contributionAmount: contributionAmount);
      await _committees.update(updated);

      // Keep the generated rows consistent with the new amount.
      final List<Payment> payments = await _payments.getByCommittee(id);
      for (final Payment payment in payments) {
        await _payments.update(payment.copyWithAmount(contributionAmount));
      }
      final double pool = _calculator.poolPerTurn(updated);
      final List<CommitteeTurn> turns = await _turns.getByCommittee(id);
      for (final CommitteeTurn turn in turns) {
        await _turns.update(turn.copyWithExpected(pool));
      }
      return updated;
    });
  }

  Future<Committee> setStatus(String id, CommitteeStatus status) async {
    final Committee committee = await getById(id);
    final Committee updated = committee.copyWith(status: status);
    await _committees.update(updated);
    return updated;
  }

  // ----------------------------------------------------------------- Delete

  /// Deletes a committee. `ON DELETE CASCADE` removes every dependent row, so
  /// no orphaned payments can survive.
  Future<void> delete(String id) async {
    await getById(id);
    await _committees.delete(id);
    _log.info('Deleted committee $id');
  }

  Future<void> deleteAll() => _committees.deleteAll();

  Future<int> count() => _committees.count();

  // ------------------------------------------------------------------ Turns

  Future<List<CommitteeTurn>> turnsFor(String id) => _turnService.turnsOf(id);

  Future<CurrentRecipient> currentRecipientOf(String id) async {
    final ({Member? member, int turnNumber, double expectedAmount}) result = await _turnService
        .currentRecipient(id);
    return CurrentRecipient(
      member: result.member,
      turnNumber: result.turnNumber,
      expectedAmount: result.expectedAmount,
    );
  }

  Future<Member?> nextRecipientOf(String id) => _turnService.nextRecipient(id);

  /// The nearest upcoming payment deadline across every active committee.
  Future<UpcomingDeadline?> nextDeadline() async {
    final List<Committee> active = await _committees.getByStatus(CommitteeStatus.active.name);
    final DateTime now = DateTime.now();
    PaymentSchedule? best;
    Committee? owner;

    for (final Committee committee in active) {
      final PaymentSchedule? current = await _scheduleService.currentPeriod(committee.id);
      if (current == null) continue;
      if (best == null || current.dueDate.isBefore(best.dueDate)) {
        best = current;
        owner = committee;
      }
    }
    if (owner == null || best == null) return null;
    return UpcomingDeadline(committee: owner, period: best, now: now);
  }

  /// Repairs the schedule of every committee — called once at app start.
  Future<void> repairAllSchedules() async {
    final List<Committee> all = await _committees.getAll();
    for (final Committee committee in all) {
      try {
        await _scheduleService.ensureFor(committee);
      } catch (error) {
        _log.error('Could not repair schedule for ${committee.id}', error);
      }
    }
  }
}

/// Who is collecting right now.
class CurrentRecipient {
  const CurrentRecipient({
    required this.member,
    required this.turnNumber,
    required this.expectedAmount,
  });

  final Member? member;
  final int turnNumber;
  final double expectedAmount;

  String? get name => member?.name;
}

/// The nearest deadline across the whole app.
class UpcomingDeadline {
  const UpcomingDeadline({required this.committee, required this.period, required this.now});

  final Committee committee;
  final PaymentSchedule period;
  final DateTime now;

  /// Whole calendar days to the deadline, relative to the snapshot clock.
  ///
  /// Negative when the deadline has already passed. Uses the same shared
  /// calendar arithmetic as the rest of the app, so "Overdue", "Due today"
  /// and the dashboard headline can never disagree about what day it is.
  int get daysLeft =>
      AppDateUtils.daysBetween(AppDateUtils.dateOnly(now), period.dueDate);

  bool get isOverdue => daysLeft < 0;

  bool get isToday => daysLeft == 0;
}

/// A consistent snapshot of everything about one committee.
class CommitteeBundle {
  const CommitteeBundle({
    required this.committee,
    required this.members,
    required this.payments,
    required this.turns,
    required this.periods,
  });

  final Committee committee;
  final List<Member> members;
  final List<Payment> payments;
  final List<CommitteeTurn> turns;
  final List<PaymentSchedule> periods;

  List<Member> get activeMembers => members.where((Member m) => m.isActive).toList(growable: false);
}

/// A member as typed into the "add members" step of the creation wizard.
///
/// Forms never talk to the database, so they hand the service plain drafts,
/// which the service converts into [Member] entities with generated ids.
class MemberDraft {
  const MemberDraft({
    required this.name,
    this.phoneNumber,
    this.address,
    this.notes,
    this.role = MemberRole.member,
  });

  final String name;
  final String? phoneNumber;
  final String? address;
  final String? notes;
  final MemberRole role;

  Member toMember({required String committeeId, required int turnNumber, bool isDemo = false}) =>
      Member(
        id: CryptoHelper.newId(),
        committeeId: committeeId,
        name: name.trim(),
        phoneNumber: _clean(phoneNumber),
        address: _clean(address),
        notes: _clean(notes),
        turnNumber: turnNumber,
        role: role,
        isActive: true,
        isDemo: isDemo,
        createdAt: DateTime.now(),
      );

  static String? _clean(String? value) {
    final String trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
