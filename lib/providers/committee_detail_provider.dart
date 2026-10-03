import 'package:flutter/foundation.dart';

import '../core/errors/app_exception.dart';
import '../core/utils/currency_formatter.dart';
import '../core/utils/logger.dart';
import '../models/committee.dart';
import '../models/committee_turn.dart';
import '../models/enums.dart';
import '../models/member.dart';
import '../models/payment.dart';
import '../models/payment_schedule.dart';
import '../models/statistics.dart';
import '../services/committee_service.dart';
import '../services/member_service.dart';
import '../services/reminder_service.dart';
import '../services/statistics_service.dart';

/// State for one open committee screen: its members, its periods, its numbers.
///
/// A single provider serves the members screen, the payments screen and the
/// details screen because they all need the *same* snapshot of the same
/// committee. Re-fetching three times would be wasteful; re-fetching once on
/// every payment keeps all three consistent.
class CommitteeDetailProvider extends ChangeNotifier {
  CommitteeDetailProvider({
    required CommitteeService committeeService,
    required MemberService memberService,
    required StatisticsService statisticsService,
    required ReminderService reminderService,
  }) : _committees = committeeService,
       _memberService = memberService,
       _reminders = reminderService;

  final CommitteeService _committees;
  final MemberService _memberService;
  final ReminderService _reminders;
  static const AppLogger _log = AppLogger('CommitteeDetailProvider');

  String? _committeeId;
  Committee? _committee;
  List<Member> _members = const <Member>[];
  List<MemberContributionView> _contributions = const <MemberContributionView>[];
  CommitteeStats? _stats;
  List<PeriodView> _periods = const <PeriodView>[];
  String? _error;
  bool _loading = false;
  bool _hasPaidPayments = false;
  String _memberQuery = '';
  int _selectedPeriod = 1;

  // ------------------------------------------------------------------ Getters

  String? get committeeId => _committeeId;
  Committee? get committee => _committee;
  List<Member> get members => _members;
  String? get error => _error;
  bool get isLoading => _loading;
  int get selectedPeriod => _selectedPeriod;
  String get memberQuery => _memberQuery;

  List<Member> get visibleMembers {
    final String term = _memberQuery.trim().toLowerCase();
    if (term.isEmpty) return _members;
    return _members
        .where(
          (Member m) => m.name.toLowerCase().contains(term) || (m.phoneNumber ?? '').contains(term),
        )
        .toList(growable: false);
  }

  List<MemberContributionView> get contributions => _contributions;

  CommitteeStats? get stats => _stats;

  List<PeriodView> get periods => _periods;

  List<PeriodView> get openPeriods =>
      _periods.where((PeriodView p) => !p.isClosed).toList(growable: false);

  List<PeriodView> get closedPeriods =>
      _periods.where((PeriodView p) => p.isClosed).toList(growable: false);

  bool get hasMembers => _members.isNotEmpty;

  bool get canEditRoster => (_committee?.isEditable ?? false) && !_hasPaidPayments;

  /// Handy for the details header: `9 x Rs 10,000` (everyone except the
  /// collecting member pays into a pot).
  String get poolFormula {
    final Committee? c = _committee;
    if (c == null) return '';
    return '${c.memberCount <= 1 ? 0 : c.memberCount - 1} x ${CurrencyFormatter.format(c.contributionAmount)}';
  }

  PeriodView? get selectedPeriodView {
    for (final PeriodView view in _periods) {
      if (view.periodNumber == _selectedPeriod) return view;
    }
    return _periods.isEmpty ? null : _periods.first;
  }

  // ------------------------------------------------------------------ Loading

  /// Loads (or reloads) everything for [committeeId].
  Future<void> open(String committeeId) async {
    _committeeId = committeeId;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
final CommitteeBundle bundle = await _committees.loadBundle(committeeId);
      _committee = bundle.committee;
      _members = bundle.members;
      _hasPaidPayments = bundle.payments.any((Payment p) => p.isPaid);
      _contributions = _buildContributions(bundle);
      _periods = _buildPeriods(bundle);
      _selectedPeriod = _pickDefaultPeriod(bundle);
    } catch (error) {
      _log.error('Could not open committee $committeeId', error);
      _error = describeError(error);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Light refresh used after a payment is recorded.
  Future<void> refresh() async {
    final String? id = _committeeId;
    if (id == null) return;
    await open(id);
  }

  void selectPeriod(int periodNumber) {
    if (_selectedPeriod == periodNumber) return;
    _selectedPeriod = periodNumber;
    notifyListeners();
  }

  void searchMembers(String value) {
    _memberQuery = value;
    notifyListeners();
  }

  // --------------------------------------------------------------- Mutations

  Future<Member> addMember({
    required String name,
    String? phoneNumber,
    String? address,
    String? notes,
    MemberRole role = MemberRole.member,
  }) async {
    final String? id = _committeeId;
    if (id == null) throw StateError('No committee is open.');
    final Member member = await _memberService.add(
      committeeId: id,
      name: name,
      phoneNumber: phoneNumber,
      address: address,
      notes: notes,
      role: role,
    );
    await _afterRosterChange();
    return member;
  }

  Future<Member> updateMember({
    required String memberId,
    required String name,
    String? phoneNumber,
    String? address,
    String? notes,
    MemberRole? role,
  }) async {
    final Member member = await _memberService.update(
      memberId: memberId,
      name: name,
      phoneNumber: phoneNumber,
      address: address,
      notes: notes,
      role: role,
    );
    await refresh();
    return member;
  }

  Future<void> removeMember(String memberId) async {
    await _memberService.remove(memberId);
    await _afterRosterChange();
  }

  Future<void> reorderTurns(List<Member> ordered) async {
    final String? id = _committeeId;
    if (id == null) throw StateError('No committee is open.');
    await _memberService.reorderTurns(id, ordered);
    await _afterRosterChange();
  }

  Future<void> updateCommitteeDetails(String name, String? description) async {
    final String? id = _committeeId;
    if (id == null) throw StateError('No committee is open.');
    await _committees.updateDetails(id: id, name: name, description: description);
    await refresh();
  }

  Future<void> updateContributionAmount(double amount) async {
    final String? id = _committeeId;
    if (id == null) throw StateError('No committee is open.');
    await _committees.updateContribution(id: id, contributionAmount: amount);
    await refresh();
  }

  Future<void> archive(bool archived) async {
    final String? id = _committeeId;
    if (id == null) throw StateError('No committee is open.');
    await _committees.setStatus(id, archived ? CommitteeStatus.archived : CommitteeStatus.active);
    await _reminders.rescheduleAll();
    await refresh();
  }

  Future<void> _afterRosterChange() async {
    await _reminders.rescheduleAll();
    await refresh();
  }

  // ----------------------------------------------------------------- Assembly

  List<MemberContributionView> _buildContributions(CommitteeBundle bundle) {
    final Map<String, int> paidByMember = <String, int>{};
    final Map<String, int> pendingByMember = <String, int>{};
    final Map<String, double> amountByMember = <String, double>{};

    for (final Payment payment in bundle.payments) {
      if (payment.isPaid) {
        paidByMember[payment.memberId] = (paidByMember[payment.memberId] ?? 0) + 1;
        amountByMember[payment.memberId] = (amountByMember[payment.memberId] ?? 0) + payment.amount;
      } else {
        pendingByMember[payment.memberId] = (pendingByMember[payment.memberId] ?? 0) + 1;
      }
    }

    return bundle.members
        .map(
          (Member m) => MemberContributionView(
            member: m,
            paidCount: paidByMember[m.id] ?? 0,
            pendingCount: pendingByMember[m.id] ?? 0,
            amountPaid: amountByMember[m.id] ?? 0,
            hasReceivedTurn: bundle.turns.any(
              (CommitteeTurn t) => t.memberId == m.id && t.isCompleted,
            ),
            receivedAt: _completionOf(bundle, m.id),
          ),
        )
        .toList(growable: false);
  }

  DateTime? _completionOf(CommitteeBundle bundle, String memberId) {
    for (final CommitteeTurn turn in bundle.turns) {
      if (turn.memberId == memberId) return turn.completedAt;
    }
    return null;
  }

  List<PeriodView> _buildPeriods(CommitteeBundle bundle) {
    final List<PeriodView> views = <PeriodView>[];
    final Committee committee = bundle.committee;

    for (final PaymentSchedule schedule in bundle.periods) {
      final List<Payment> rows = bundle.payments
          .where((Payment p) => p.periodNumber == schedule.periodNumber)
          .toList(growable: false);
      final int paid = rows.where((Payment p) => p.isPaid).length;
      final double collected = rows
          .where((Payment p) => p.isPaid)
          .fold<double>(0, (double s, Payment p) => s + p.amount);
      String? recipient;
      bool turnDone = false;
      DateTime? completedAt;
      for (final CommitteeTurn turn in bundle.turns) {
        if (turn.periodNumber == schedule.periodNumber) {
          turnDone = turn.isCompleted;
          completedAt = turn.completedAt;
          for (final Member m in bundle.members) {
            if (m.id == turn.memberId) recipient = m.name;
          }
        }
      }
      views.add(
        PeriodView(
          periodNumber: schedule.periodNumber,
          label: schedule.label,
          dueDate: schedule.dueDate,
          isClosed: schedule.isClosed,
          totalCount: rows.length,
          paidCount: paid,
          pendingCount: rows.length - paid,
          collectedAmount: collected,
          expectedAmount: committee.contributionAmount * rows.length,
          recipientName: recipient,
          turnCompleted: turnDone,
          completedAt: completedAt,
        ),
      );
    }
    views.sort((PeriodView a, PeriodView b) => a.periodNumber.compareTo(b.periodNumber));
    return views;
  }

  int _pickDefaultPeriod(CommitteeBundle bundle) {
    final int current = _calculatorPeriod(bundle.committee, DateTime.now());
    for (final PeriodView view in _periods) {
      if (view.periodNumber == current && !view.isClosed) return current;
    }
    for (final PeriodView view in _periods) {
      if (!view.isClosed) return view.periodNumber;
    }
    return _periods.isEmpty ? 1 : _periods.last.periodNumber;
  }

  int _calculatorPeriod(Committee committee, DateTime now) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    int current = 1;
    for (int period = 1; period <= committee.durationPeriods; period++) {
      final DateTime due = committee.frequency.dueDateForPeriod(period, committee.startDate);
      if (!due.isBefore(today)) return period;
      current = period;
    }
    return current.clamp(1, committee.durationPeriods).toInt();
  }
}

// ---------------------------------------------------------------- View models
//
// Providers expose *small* view models rather than the whole database graph.
// This keeps the widget layer honest: a screen can only depend on the numbers
// it actually needs, which is Interface Segregation applied to state.

class MemberContributionView {
  const MemberContributionView({
    required this.member,
    required this.paidCount,
    required this.pendingCount,
    required this.amountPaid,
    required this.hasReceivedTurn,
    this.receivedAt,
  });

  final Member member;
  final int paidCount;
  final int pendingCount;
  final double amountPaid;
  final bool hasReceivedTurn;
  final DateTime? receivedAt;

  int get totalDue => paidCount + pendingCount;

  double get percent => totalDue == 0 ? 0 : (paidCount / totalDue) * 100;

  bool get isUpToDate => pendingCount == 0;
}

class PeriodView {
  const PeriodView({
    required this.periodNumber,
    required this.label,
    required this.dueDate,
    required this.isClosed,
    required this.totalCount,
    required this.paidCount,
    required this.pendingCount,
    required this.collectedAmount,
    required this.expectedAmount,
    required this.recipientName,
    required this.turnCompleted,
    this.completedAt,
  });

  final int periodNumber;
  final String label;
  final DateTime dueDate;
  final bool isClosed;
  final int totalCount;
  final int paidCount;
  final int pendingCount;
  final double collectedAmount;
  final double expectedAmount;
  final String? recipientName;
  final bool turnCompleted;
  final DateTime? completedAt;

  bool get isComplete => totalCount > 0 && paidCount == totalCount;

  double get percent => totalCount == 0 ? 0 : (paidCount / totalCount) * 100;
}
