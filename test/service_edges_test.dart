import 'package:committee_manager/core/constants/app_constants.dart';
import 'package:committee_manager/core/errors/app_exception.dart';
import 'package:committee_manager/database/app_database.dart';
import 'package:committee_manager/di/service_locator.dart';
import 'package:committee_manager/models/committee_turn.dart';
import 'package:committee_manager/models/enums.dart';
import 'package:committee_manager/models/payment.dart';
import 'package:committee_manager/models/payment_schedule.dart';
import 'package:committee_manager/models/statistics.dart';
import 'package:committee_manager/repositories/interfaces/committee_repository.dart';
import 'package:committee_manager/repositories/interfaces/member_repository.dart';
import 'package:committee_manager/repositories/interfaces/payment_repository.dart';
import 'package:committee_manager/repositories/interfaces/schedule_repository.dart';
import 'package:committee_manager/repositories/interfaces/turn_repository.dart';
import 'package:committee_manager/services/committee_service.dart';
import 'package:committee_manager/services/payment_calculator.dart';
import 'package:committee_manager/services/payment_service.dart';
import 'package:committee_manager/services/schedule_service.dart';
import 'package:committee_manager/services/statistics_service.dart';
import 'package:committee_manager/services/turn_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The failure the sabotage raises. A distinct type makes the assertion read as
/// "the write blew up" rather than depending on which sqflite exception class
/// happens to be constructible in a given version.
class _InjectedWriteFailure implements Exception {
  const _InjectedWriteFailure();
}

/// Fails on the first write, so a test can prove a multi-write operation rolls
/// back completely instead of stopping half-done.
class _FailingTurnRepository implements TurnRepository {
  _FailingTurnRepository(this._inner);

  final TurnRepository _inner;

  @override
  Future<void> update(CommitteeTurn turn) async => throw const _InjectedWriteFailure();

  @override
  Future<List<CommitteeTurn>> getByCommittee(String committeeId) =>
      _inner.getByCommittee(committeeId);

  @override
  Future<CommitteeTurn?> getByNumber(String committeeId, int turnNumber) =>
      _inner.getByNumber(committeeId, turnNumber);

  @override
  Future<CommitteeTurn?> getActive(String committeeId) => _inner.getActive(committeeId);

  @override
  Future<CommitteeTurn?> getByMember(String memberId) => _inner.getByMember(memberId);

  @override
  Future<void> insertAll(List<CommitteeTurn> turns) => _inner.insertAll(turns);

  @override
  Future<void> updateCollected(String turnId, double collectedAmount) =>
      _inner.updateCollected(turnId, collectedAmount);

  @override
  Future<void> deleteByCommittee(String committeeId) => _inner.deleteByCommittee(committeeId);

  @override
  Future<int> countCompleted(String committeeId) => _inner.countCompleted(committeeId);

  @override
  Future<int> countAll() => _inner.countAll();

  @override
  Future<int> countCompletedAll() => _inner.countCompletedAll();

  @override
  Future<int> sumExpectedAll() => _inner.sumExpectedAll();

  @override
  Future<int> sumCollectedAll() => _inner.sumCollectedAll();
}

/// Edge cases a user will hit by accident: editing a committee after money has
/// moved, acting on rows that no longer exist, and building a one-person
/// committee.
///
/// The rule these all protect: a bad request must produce a **readable error**,
/// never a crash, and never a silently wrong number. In an app that holds other
/// people's money, "it showed the wrong total" is worse than "it refused".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late CommitteeService committees;
  late PaymentService payments;
  late TurnService turns;
  late StatisticsService stats;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ServiceLocator.instance.reset();
    db = AppDatabase(factory: databaseFactoryFfi, overridePath: inMemoryDatabasePath);
    await ServiceLocator.wire(databaseOverride: db);
    committees = ServiceLocator.instance.get<CommitteeService>();
    payments = ServiceLocator.instance.get<PaymentService>();
    turns = ServiceLocator.instance.get<TurnService>();
    stats = ServiceLocator.instance.get<StatisticsService>();
  });

  tearDown(() async => db.close());

  Future<String> newCommittee({
    int members = 3,
    double contribution = 1000,
    DateTime? startDate,
  }) async {
    final c = await committees.create(
      name: 'Committee ${DateTime.now().microsecondsSinceEpoch}',
      description: null,
      contributionAmount: contribution,
      frequency: PaymentFrequency.monthly,
      startDate: startDate ?? DateTime.now().subtract(const Duration(days: 10)),
      memberDrafts: <MemberDraft>[
        for (int i = 1; i <= members; i++) MemberDraft(name: 'Member $i'),
      ],
    );
    return c.id;
  }

  Future<List<Payment>> unpaid(String committeeId) async =>
      (await payments.forCommittee(committeeId)).where((Payment p) => !p.isPaid).toList();

  group('changing the amount', () {
    test('is refused once any payment has been recorded', () async {
      final String id = await newCommittee(members: 3, contribution: 1000);
      await payments.markPaid(paymentId: (await unpaid(id)).first.id);

      // Changing it now would make the history disagree with the agreement.
      await expectLater(
        committees.updateContribution(id: id, contributionAmount: 2000),
        throwsA(isA<BusinessRuleException>()),
      );

      // And the stored amount is untouched.
      final committee = await committees.getById(id);
      expect(committee.contributionAmount, 1000);
    });

    test('updates every generated row when nothing has been paid', () async {
      final String id = await newCommittee(members: 3, contribution: 1000);
      expect(await payments.forCommittee(id), hasLength(6), reason: '3 members x 3 periods, recipient skips');

      await committees.updateContribution(id: id, contributionAmount: 2500);

      final List<Payment> rows = await payments.forCommittee(id);
      expect(rows.every((Payment p) => p.amount == 2500), isTrue);
      expect(rows.fold<double>(0, (double s, Payment p) => s + p.amount), 6 * 2500);
    });

    test('the turn pool follows the new amount', () async {
      final String id = await newCommittee(members: 4, contribution: 1000);
      await committees.updateContribution(id: id, contributionAmount: 500);
      // pool = (4-1) members x 500, the other members fund the pot
      final committee = await committees.getById(id);
      final dashboard = await stats.forCommittee(committee.id);
      expect(dashboard.expectedPool, 1500);
    });

    test('zero and negative amounts are rejected', () async {
      final String id = await newCommittee();
      for (final double bad in <double>[0, -1, -0.01]) {
        await expectLater(
          committees.updateContribution(id: id, contributionAmount: bad),
          throwsA(isA<ValidationException>()),
          reason: '$bad should be refused',
        );
      }
    });

    test('a tiny amount is rejected as implausibly small', () async {
      final String id = await newCommittee();
      await expectLater(
        committees.updateContribution(id: id, contributionAmount: 0.0001),
        throwsA(isA<ValidationException>()),
      );
    });

    test('an absurd amount is rejected before anything is written', () async {
      final String id = await newCommittee(contribution: 1000);
      await expectLater(
        committees.updateContribution(
          id: id,
          contributionAmount: AppConstants.maxContributionAmount + 1,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect((await committees.getById(id)).contributionAmount, 1000);
      expect(
        (await payments.forCommittee(id)).every((Payment p) => p.amount == 1000),
        isTrue,
        reason: 'a rejected edit must not have rewritten any row',
      );
    });

    test('a failure part-way through leaves nothing half-written', () async {
      // Rewriting the amount touches the committee, its payment rows and its
      // turn expectations. Before they shared a transaction, a failure after the
      // first write left the committee advertising 2500 while every payment row
      // still said 1000 — a history that quietly stops adding up.
      final String id = await newCommittee(members: 3, contribution: 1000);
      final PaymentRepository paymentRows = ServiceLocator.instance.get<PaymentRepository>();
      final ScheduleService realSchedules = ServiceLocator.instance.get<ScheduleService>();
      final TurnService realTurns = ServiceLocator.instance.get<TurnService>();
      final PaymentCalculator calculator = ServiceLocator.instance.get<PaymentCalculator>();

      final CommitteeService sabotage = CommitteeService(
        committeeRepository: ServiceLocator.instance.get<CommitteeRepository>(),
        memberRepository: ServiceLocator.instance.get<MemberRepository>(),
        paymentRepository: paymentRows,
        scheduleRepository: ServiceLocator.instance.get<ScheduleRepository>(),
        // Turns are written last, so this stands in for any late failure.
        turnRepository: _FailingTurnRepository(ServiceLocator.instance.get<TurnRepository>()),
        scheduleService: realSchedules,
        turnService: realTurns,
        calculator: calculator,
        appDatabase: db,
      );

      // sqflite wraps whatever the body threw, so the original cause is what
      // identifies the injected failure.
      await expectLater(
        sabotage.updateContribution(id: id, contributionAmount: 2500),
        throwsA(
          predicate<Object>((Object e) => e.toString().contains('_InjectedWriteFailure')),
        ),
      );

      expect(
        (await committees.getById(id)).contributionAmount,
        1000,
        reason: 'the committee write must have been rolled back',
      );
      expect(
        (await payments.forCommittee(id)).every((Payment p) => p.amount == 1000),
        isTrue,
        reason: 'the payment rows must have been rolled back too',
      );
    });
  });

  group('acting on things that are gone', () {
    test('paying a payment that no longer exists fails readably', () async {
      await expectLater(
        payments.markPaid(paymentId: 'does-not-exist'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('fetching a payment that no longer exists fails readably', () async {
      await expectLater(
        payments.getById('does-not-exist'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('editing a committee that no longer exists fails readably', () async {
      await expectLater(
        committees.getById('does-not-exist'),
        throwsA(isA<NotFoundException>()),
      );
      await expectLater(
        committees.updateDetails(id: 'does-not-exist', name: 'New name'),
        throwsA(isA<NotFoundException>()),
      );
      await expectLater(
        committees.updateContribution(id: 'does-not-exist', contributionAmount: 500),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('paying a payment twice does not double-count the money', () async {
      final String id = await newCommittee(members: 2, contribution: 100);
      final String paymentId = (await unpaid(id)).first.id;

      await payments.markPaid(paymentId: paymentId);
      final double afterFirst = await payments.collectedIn(id);
      expect(afterFirst, 100);

      // The second attempt must not add another 100.
      try {
        await payments.markPaid(paymentId: paymentId);
      } on AppException {
        // Refusing outright is also fine.
      }
      expect(await payments.collectedIn(id), afterFirst);
      expect((await payments.getById(paymentId)).isPaid, isTrue);
    });

    test('undoing then re-paying a payment settles correctly', () async {
      final String id = await newCommittee(members: 2, contribution: 100);
      final String paymentId = (await unpaid(id)).first.id;

      await payments.markPaid(paymentId: paymentId);
      expect(await payments.collectedIn(id), 100);
      await payments.markUnpaid(paymentId);
      expect(await payments.collectedIn(id), 0);
      await payments.markPaid(paymentId: paymentId);
      expect(await payments.collectedIn(id), 100);
    });

    test('the total is never more than the committee is worth', () async {
      final String id = await newCommittee(members: 3, contribution: 1000);
      for (final Payment p in (await payments.forCommittee(id)).toList()) {
        await payments.markPaid(paymentId: p.id);
      }
      final committee = await committees.getById(id);
      final dashboard = await stats.forCommittee(committee.id);
      // 3 members x 3 periods x 1000 = 6000 collected (recipient skips their own
      // period, so only 2 rows per period), nothing outstanding.
      expect(dashboard.totalCollected, 6000);
      expect(dashboard.totalPending, 0);
      expect(dashboard.overdueCount, 0);
    });
  });

  group('unusual but legal committees', () {
    test('a solo committee is refused, because the member would pay themselves', () async {
      await expectLater(
        newCommittee(members: 1, contribution: 2500),
        throwsA(
          isA<ValidationException>().having(
            (ValidationException e) => e.fieldErrors,
            'fieldErrors',
            contains('members'),
          ),
        ),
      );
    });

    test('the smallest legal committee is two members and it completes', () async {
      final String id = await newCommittee(members: 2, contribution: 2500);
      final List<Payment> rows = await payments.forCommittee(id);
      expect(rows, hasLength(2), reason: '2 members x 2 periods, each paid by the other');

      // Period 1 settles, then period 2 settles and the committee is finished.
      for (final Payment p in rows.where((Payment p) => p.periodNumber == 1)) {
        await payments.markPaid(paymentId: p.id);
      }
      final midway = await turns.reconcile(id);
      expect(midway.completedTurns, 1);
      expect(midway.status, isNot(CommitteeStatus.completed));

      for (final Payment p in rows.where((Payment p) => p.periodNumber == 2)) {
        await payments.markPaid(paymentId: p.id);
      }
      final done = await turns.reconcile(id);
      expect(done.completedTurns, 2);
      expect(done.status, CommitteeStatus.completed);
    });

    test('the smallest committee reports a correct pool and pending total', () async {
      final String id = await newCommittee(members: 2, contribution: 1000);
      final dashboard = await stats.forCommittee(id);
      // Nothing paid yet: 2 rows of 1000 outstanding, pool is (2-1) x 1000.
      expect(dashboard.totalPending, 2000);
      expect(dashboard.expectedPool, 1000);
      expect(dashboard.paidCount, 0);
      expect(dashboard.pendingCount, 2);
    });

    test('paying everyone in a period advances exactly one turn', () async {
      final String id = await newCommittee(members: 4, contribution: 500);
      final committee = await committees.getById(id);

      await turns.reconcile(committee.id);
      // Period 1: the recipient does not pay, so three members fund the pot.
      for (final Payment p in (await payments.forCommittee(id))
          .where((Payment p) => p.periodNumber == 1)
          .toList()) {
        await payments.markPaid(paymentId: p.id);
      }
      final after = await turns.reconcile(id);
      expect(after.completedTurns, 1);
      expect(after.currentTurn, 2);
    });

    test('a large committee generates the full matrix', () async {
      final String id = await newCommittee(members: 30, contribution: 1000);
      // 30 members means 30 periods, and each period is funded by the other 29,
// so 30 x 29 rows (the recipient of each period skips their own row).
      expect(await payments.forCommittee(id), hasLength(870));
    });

    test('a large amount does not overflow the totals', () async {
      final String id = await newCommittee(members: 5, contribution: 10000000);
      for (final Payment p in (await payments.forCommittee(id)).toList()) {
        await payments.markPaid(paymentId: p.id);
      }
      final committee = await committees.getById(id);
      final dashboard = await stats.forCommittee(committee.id);
      // 5 members x 5 periods, each period funded by the other 4 = 20 x 10,000,000.
      expect(dashboard.totalCollected, 200000000);
      expect(dashboard.totalCollected.isFinite, isTrue);
    });
  });

  group('a committee that has fallen behind', () {
    test('the collection screen lands on the money actually owed, not today\'s month', () async {
      // Started six months ago but nobody has ever paid: the app is a long way
      // behind the calendar and period 1 is where all the overdue money is.
      final String id = await newCommittee(
        members: 3,
        contribution: 1000,
        startDate: DateTime.now().subtract(const Duration(days: 180)),
      );

      final PaymentSchedule landing = (await payments.defaultPeriod(
        id,
        await committees.getById(id),
      ))!;

      expect(
        landing.periodNumber,
        1,
        reason: 'the oldest unpaid period is the one the user needs to act on',
      );
    });

    test('once the backlog is cleared it moves forward to the next period owing', () async {
      final String id = await newCommittee(
        members: 3,
        contribution: 1000,
        startDate: DateTime.now().subtract(const Duration(days: 180)),
      );
      for (final Payment p in (await payments.forCommittee(id))
          .where((Payment p) => p.periodNumber == 1)
          .toList()) {
        await payments.markPaid(paymentId: p.id);
      }

      final PaymentSchedule landing = (await payments.defaultPeriod(
        id,
        await committees.getById(id),
      ))!;
      expect(landing.periodNumber, 2, reason: 'period 1 is settled, period 2 is now owed');
    });

    test('a fully paid committee still opens without error', () async {
      final String id = await newCommittee(
        members: 2,
        contribution: 1000,
        startDate: DateTime.now().subtract(const Duration(days: 180)),
      );
      for (final Payment p in await payments.forCommittee(id)) {
        await payments.markPaid(paymentId: p.id);
      }
      // Nothing is owed, so it must not crash or return a nonsense period.
      final PaymentSchedule? landing = await payments.defaultPeriod(
        id,
        await committees.getById(id),
      );
      expect(landing, isNotNull);
      expect(landing!.periodNumber, inInclusiveRange(1, 2));
    });

    test('the stats agree with the turn, and separately report being behind', () async {
      final String id = await newCommittee(
        members: 3,
        contribution: 1000,
        startDate: DateTime.now().subtract(const Duration(days: 180)),
      );
      final CommitteeStats behind = await stats.forCommittee(id);

      // The period we are really collecting is period 1, matching the recipient.
      expect(behind.currentPeriod, 1);
      expect(behind.currentRecipientName, isNotNull);
      // ...while the calendar is six months in, and the app now says so out loud
      // instead of quietly relabelling the committee as "period 6".
      expect(behind.expectedPeriod, greaterThan(behind.currentPeriod));
      expect(behind.isBehindSchedule, isTrue);
      expect(behind.periodsBehind, greaterThan(0));
    });
  });

  group('statistics stay honest over a full lifecycle', () {
    test('collecting, undoing and re-collecting nets out', () async {
      final String id = await newCommittee(members: 3, contribution: 1000);
      final committee = await committees.getById(id);
      expect((await stats.forCommittee(committee.id)).totalCollected, 0);

      final List<Payment> period1 = (await payments.forCommittee(id))
          .where((Payment p) => p.periodNumber == 1)
          .toList();
      for (final Payment p in period1) {
        await payments.markPaid(paymentId: p.id);
      }
      // 3 members: the recipient of period 1 does not pay it, so 2 x 1000.
      expect((await stats.forCommittee(id)).totalCollected, 2000);

      // Undo one of them: the total must come back down by exactly 1000.
      await payments.markUnpaid(period1.first.id);
      expect((await stats.forCommittee(id)).totalCollected, 1000);

      // And re-pay it.
      await payments.markPaid(paymentId: period1.first.id);
      expect((await stats.forCommittee(id)).totalCollected, 2000);
    });

    test('the dashboard never claims more money than was ever agreed', () async {
      final String id = await newCommittee(members: 3, contribution: 1000);
      // Throw a lot of state at it.
      final List<Payment> rows = await payments.forCommittee(id);
      await payments.markPaid(paymentId: rows[0].id);
      await payments.markPaid(paymentId: rows[1].id);
      await payments.markUnpaid(rows[0].id);
      await turns.reconcile(id);

      final committee = await committees.getById(id);
      final dashboard = await stats.forCommittee(committee.id);
      final double possible = committee.contributionAmount * rows.length;
      expect(dashboard.totalCollected, lessThanOrEqualTo(possible));
      expect(dashboard.totalCollected + dashboard.totalPending, closeTo(possible, 0.001));
    });
  });
}
