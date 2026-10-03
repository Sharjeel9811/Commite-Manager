import 'package:sqflite/sqflite.dart' show Transaction;

import '../core/errors/app_exception.dart';
import '../core/utils/crypto_helper.dart';
import '../core/utils/logger.dart';
import '../core/utils/validators.dart';
import '../database/app_database.dart';
import '../models/committee.dart';
import '../models/enums.dart';
import '../models/member.dart';
import '../models/payment.dart';
import '../repositories/interfaces/committee_repository.dart';
import '../repositories/interfaces/member_repository.dart';
import '../repositories/interfaces/payment_repository.dart';
import 'schedule_service.dart';

/// Member management rules.
///
/// The roster may only change while a committee has not started collecting.
/// Once money has moved the rotation is frozen, which is what guarantees that
/// "turn 3 always belongs to the same person" stays true for the whole life of
/// the committee. All roster changes are allowed by exactly one guard method
/// ([_assertCanChangeRoster]) so the rule cannot drift between operations.
class MemberService {
  const MemberService({
    required MemberRepository memberRepository,
    required CommitteeRepository committeeRepository,
    required PaymentRepository paymentRepository,
    required ScheduleService scheduleService,
    required AppDatabase appDatabase,
  }) : _members = memberRepository,
       _committees = committeeRepository,
       _payments = paymentRepository,
       _scheduleService = scheduleService,
       _db = appDatabase;

  final MemberRepository _members;
  final CommitteeRepository _committees;
  final PaymentRepository _payments;
  final ScheduleService _scheduleService;
  final AppDatabase _db;

  static const AppLogger _log = AppLogger('MemberService');

  // ------------------------------------------------------------------ Reads

  Future<List<Member>> listOf(String committeeId) => _members.getByCommittee(committeeId);

  Future<Member> getById(String id) async {
    final Member? member = await _members.getById(id);
    if (member == null) throw const NotFoundException('This member could not be found.');
    return member;
  }

  Future<Committee> committeeOf(String memberId) async {
    final Member member = await getById(memberId);
    return _getCommittee(member.committeeId);
  }

  Future<int> countOf(String committeeId) => _members.countByCommittee(committeeId);

  Future<List<Payment>> paymentsOf(String memberId) => _payments.getByMember(memberId);

  // -------------------------------------------------------------- Mutations

  /// Adds a member and rebuilds the schedule so the new member gets the last
  /// turn and an extra period.
  Future<Member> add({
    required String committeeId,
    required String name,
    String? phoneNumber,
    String? address,
    String? notes,
    MemberRole role = MemberRole.member,
  }) async {
    final Committee committee = await _getCommittee(committeeId);
    await _assertCanChangeRoster(committee);
    _validate(name: name, phoneNumber: phoneNumber);

    final int nextTurn = await _members.nextTurnNumber(committeeId);
    final Member member = Member(
      id: CryptoHelper.newId(),
      committeeId: committeeId,
      name: name.trim(),
      phoneNumber: _clean(phoneNumber),
      address: _clean(address),
      notes: _clean(notes),
      turnNumber: nextTurn,
      role: role,
      isActive: true,
      createdAt: DateTime.now(),
    );

    await _db.transaction<void>((Transaction txn) async {
      await _members.insert(member);
      await _rebuildSchedule(committee, <Member>[...await _members.getByCommittee(committeeId)]);
    });
    _log.info('Added ${member.name} as turn $nextTurn to "${committee.name}"');
    return member;
  }

  /// Edits a member's details. Always allowed — renaming somebody does not
  /// change the money that moved.
  Future<Member> update({
    required String memberId,
    required String name,
    String? phoneNumber,
    String? address,
    String? notes,
    MemberRole? role,
    bool? isActive,
  }) async {
    final Member member = await getById(memberId);
    _validate(name: name, phoneNumber: phoneNumber);

    final Member updated = member.copyWith(
      name: name.trim(),
      phoneNumber: _clean(phoneNumber),
      address: _clean(address),
      notes: _clean(notes),
      role: role,
      isActive: isActive,
    );
    await _members.update(updated);
    return updated;
  }

  /// Removes a member and shortens the committee by one period.
  Future<void> remove(String memberId) async {
    final Member member = await getById(memberId);
    final Committee committee = await _getCommittee(member.committeeId);
    await _assertCanChangeRoster(committee);
    if (committee.memberCount <= 2) {
      throw const BusinessRuleException(
        'A committee must keep at least 2 members. Delete the committee instead.',
      );
    }

    await _db.transaction<void>((Transaction txn) async {
      await _members.delete(member.id);
      await _rebuildSchedule(committee, await _members.getByCommittee(committee.id));
    });
    _log.info('Removed ${member.name} from "${committee.name}"');
  }

  /// Applies a brand-new turn order.
  Future<void> reorderTurns(String committeeId, List<Member> orderedMembers) async {
    final Committee committee = await _getCommittee(committeeId);
    await _assertCanChangeRoster(committee);

    if (orderedMembers.length != committee.memberCount) {
      throw const BusinessRuleException('The turn order must contain every member exactly once.');
    }
    if (orderedMembers.map((Member m) => m.id).toSet().length != orderedMembers.length) {
      throw const BusinessRuleException('A member cannot appear twice in the turn order.');
    }

    await _db.transaction<void>((Transaction txn) async {
      await _members.reorder(committeeId, <String>[for (final Member m in orderedMembers) m.id]);
      await _rebuildSchedule(committee, await _members.getByCommittee(committeeId));
    });
    _log.info('Turn order updated for "${committee.name}"');
  }

  /// Marks a member inactive without deleting their history. Always allowed —
  /// it is a soft switch, not a structural change.
  Future<Member> setActive(String memberId, bool isActive) async {
    final Member member = await getById(memberId);
    final Member updated = member.copyWith(isActive: isActive);
    await _members.update(updated);
    return updated;
  }

  // ------------------------------------------------------------------ Guards

  /// The single source of truth for "may the roster be changed?".
  Future<void> _assertCanChangeRoster(Committee committee) async {
    if (committee.isCompleted) {
      throw const BusinessRuleException(
        'This committee is finished, so its members can no longer be changed.',
      );
    }
    if (committee.completedTurns > 0) {
      throw const BusinessRuleException(
        'Members can no longer be added or removed because a turn has already been completed.',
      );
    }
    if (await _payments.countPaid(committee.id) > 0) {
      throw const BusinessRuleException(
        'Members can no longer be added or removed because payments have been recorded.',
      );
    }
  }

  // --------------------------------------------------------------- Internals

  /// Deletes every generated row and regenerates it from the current roster.
  ///
  /// Rebuilding (rather than patching) is safe here precisely *because*
  /// [_assertCanChangeRoster] guarantees no payment has been recorded — so there
  /// is no history to lose, and the schedule can never end up inconsistent.
  ///
  /// Runs inside the transaction the caller already opened, so it must not open
  /// one of its own.
  Future<void> _rebuildSchedule(Committee committee, List<Member> members) async {
    final int count = members.length;
    final Committee resized = committee.copyWith(
      memberCount: count,
      durationPeriods: count,
      currentTurn: committee.currentTurn > count ? count : committee.currentTurn,
    );

    if (resized.memberCount != committee.memberCount ||
        resized.durationPeriods != committee.durationPeriods) {
      await _committees.update(resized);
    }

    await _scheduleService.clearRows(committee.id);
    await _scheduleService.generateRowsFor(resized, members);
  }

  Future<Committee> _getCommittee(String id) async {
    final Committee? committee = await _committees.getById(id);
    if (committee == null) throw const NotFoundException('This committee could not be found.');
    return committee;
  }

  void _validate({required String name, String? phoneNumber}) {
    final Map<String, String> errors = <String, String>{};
    final String? nameError = Validators.memberName(name);
    final String? phoneError = Validators.phoneNumber(phoneNumber);
    if (nameError != null) errors['name'] = nameError;
    if (phoneError != null) errors['phone'] = phoneError;
    if (errors.isNotEmpty) {
      throw ValidationException('Please correct the highlighted fields.', fieldErrors: errors);
    }
  }

  static String? _clean(String? value) {
    final String trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
