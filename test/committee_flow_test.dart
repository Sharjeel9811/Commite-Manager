import 'package:committee_manager/database/app_database.dart';
import 'package:committee_manager/di/service_locator.dart';
import 'package:committee_manager/models/committee.dart';
import 'package:committee_manager/models/committee_turn.dart';
import 'package:committee_manager/models/enums.dart';
import 'package:committee_manager/models/member.dart';
import 'package:committee_manager/models/payment.dart';
import 'package:committee_manager/models/payment_schedule.dart';
import 'package:committee_manager/models/statistics.dart';
import 'package:committee_manager/repositories/interfaces/member_repository.dart';
import 'package:committee_manager/repositories/interfaces/payment_repository.dart';
import 'package:committee_manager/repositories/interfaces/schedule_repository.dart';
import 'package:committee_manager/repositories/interfaces/turn_repository.dart';
import 'package:committee_manager/services/committee_service.dart';
import 'package:committee_manager/services/member_service.dart';
import 'package:committee_manager/services/payment_service.dart';
import 'package:committee_manager/services/statistics_service.dart';
import 'package:committee_manager/services/turn_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// End-to-end tests for the money rules, running against a real in-memory
/// SQLite database.
///
/// The services are built by the real [ServiceLocator] against the real SQLite
/// repositories — only the database location is swapped. That means these tests
/// exercise the foreign keys, CHECK constraints and UNIQUE indexes exactly as
/// the shipping app does, which is the only way to catch the class of bug that
/// "works" against mocks.
void main() {
  // The settings repository talks to platform channels, so the binding has to
  // exist even though these tests never touch the UI layer.
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  late AppDatabase db;
  late ServiceLocator locator;
  late CommitteeService committees;
  late MemberService members;
  late PaymentService payments;
  late TurnService turns;
  late TurnRepository turnRepo;
  late PaymentRepository paymentRepo;
  late ScheduleRepository scheduleRepo;
  late MemberRepository memberRepo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase(factory: databaseFactoryFfi, overridePath: inMemoryDatabasePath);
    locator = await ServiceLocator.wire(databaseOverride: db);
    committees = locator.get<CommitteeService>();
    members = locator.get<MemberService>();
    payments = locator.get<PaymentService>();
    turns = locator.get<TurnService>();
    turnRepo = locator.get<TurnRepository>();
    paymentRepo = locator.get<PaymentRepository>();
    scheduleRepo = locator.get<ScheduleRepository>();
    memberRepo = locator.get<MemberRepository>();
  });

  tearDown(() async {
    await db.close();
    ServiceLocator.instance.reset();
  });

  Future<Committee> createCommittee({
    required String name,
    int memberCount = 4,
    PaymentFrequency frequency = PaymentFrequency.monthly,
    int startMonthsAgo = 0,
  }) {
    final DateTime start = DateTime.now().subtract(Duration(days: 30 * startMonthsAgo));
    return committees.create(
      name: name,
      description: 'Test committee',
      contributionAmount: 1000,
      frequency: frequency,
      startDate: start,
      memberDrafts: <MemberDraft>[
        for (int i = 1; i <= memberCount; i++) MemberDraft(name: 'Member $i'),
      ],
    );
  }

  group('committee creation', () {
    test('persists the committee, its members, periods, turns and payments', () async {
      final Committee committee = await createCommittee(name: 'Family Committee', memberCount: 4);

      final Committee stored = await committees.getById(committee.id);
      expect(stored.name, 'Family Committee', reason: 'the committee header must be written');

      final List<Member> roster = await memberRepo.getByCommittee(committee.id);
      expect(roster, hasLength(4));

      final List<PaymentSchedule> periods = await scheduleRepo.getByCommittee(committee.id);
      expect(periods, hasLength(4), reason: 'one period per member in a classic committee');

      final List<CommitteeTurn> rotation = await turnRepo.getByCommittee(committee.id);
      expect(rotation, hasLength(4));
      expect(rotation.map((CommitteeTurn t) => t.turnNumber).toList()..sort(), <int>[1, 2, 3, 4]);

      final List<Payment> all = await paymentRepo.getByCommittee(committee.id);
      expect(all, hasLength(12), reason: 'each of 4 periods is paid by the other 3 members');
    });

    test('duration always equals the member count', () async {
      final Committee committee = await createCommittee(name: 'Duration Rule', memberCount: 5);
      expect(committee.durationPeriods, 5);
      expect(committee.memberCount, 5);
    });

    test('rejects a committee with too few members', () async {
      await expectLater(
        committees.create(
          name: 'Too Small',
          description: null,
          contributionAmount: 500,
          frequency: PaymentFrequency.monthly,
          startDate: DateTime.now(),
          memberDrafts: const <MemberDraft>[MemberDraft(name: 'Solo')],
        ),
        throwsA(isA<Object>()),
      );
    });

    test('rejects a duplicate committee name', () async {
      await createCommittee(name: 'Duplicated Name');
      await expectLater(createCommittee(name: 'Duplicated Name'), throwsA(isA<Object>()));
    });
  });

  group('collection and rotation', () {
    test('paying everyone in period 1 releases the first turn', () async {
      final Committee committee = await createCommittee(name: 'Rotation One', memberCount: 4);

      final List<Payment> periodOne = await paymentRepo.getByPeriod(committee.id, 1);
      expect(periodOne, hasLength(3), reason: 'the recipient of period 1 does not pay it');
      expect(periodOne.every((Payment p) => !p.isPaid), isTrue);

      for (final Payment payment in periodOne) {
        await payments.markPaid(paymentId: payment.id);
      }

      final CommitteeTurn? first = await turnRepo.getByNumber(committee.id, 1);
      expect(first, isNotNull);
      expect(first!.isCompleted, isTrue, reason: 'a full period must release the turn');
      expect(first.completedAt, isNotNull);

      final CommitteeTurn? second = await turnRepo.getByNumber(committee.id, 2);
      expect(second!.status, TurnStatus.active, reason: 'the rotation must advance by one');
    });

    test('an incomplete period leaves the turn untouched', () async {
      final Committee committee = await createCommittee(name: 'Partial Pay', memberCount: 4);
      final List<Payment> periodOne = await paymentRepo.getByPeriod(committee.id, 1);

      for (final Payment payment in periodOne.take(2)) {
        await payments.markPaid(paymentId: payment.id);
      }

      final CommitteeTurn? first = await turnRepo.getByNumber(committee.id, 1);
      expect(first!.isCompleted, isFalse, reason: '2 of 3 paid is still not a full period');
    });

    test('marking a payment paid twice is refused', () async {
      final Committee committee = await createCommittee(name: 'No Double Pay', memberCount: 4);
      final Payment payment = (await paymentRepo.getByPeriod(committee.id, 1)).first;

      await payments.markPaid(paymentId: payment.id);
      await expectLater(payments.markPaid(paymentId: payment.id), throwsA(isA<Object>()));
    });

    test('undoing a payment re-opens the turn it had released', () async {
      final Committee committee = await createCommittee(name: 'Undo', memberCount: 3);
      final List<Payment> periodOne = await paymentRepo.getByPeriod(committee.id, 1);
      for (final Payment payment in periodOne) {
        await payments.markPaid(paymentId: payment.id);
      }
      expect((await turnRepo.getByNumber(committee.id, 1))!.isCompleted, isTrue);

      await payments.markUnpaid(periodOne.last.id);

      expect((await turnRepo.getByNumber(committee.id, 1))!.isCompleted, isFalse);
    });

    test('closing the whole committee marks every turn completed', () async {
      final Committee committee = await createCommittee(name: 'Full Run', memberCount: 3);
      for (int period = 1; period <= 3; period++) {
        final List<Payment> rows = await paymentRepo.getByPeriod(committee.id, period);
        for (final Payment payment in rows) {
          await payments.markPaid(paymentId: payment.id);
        }
      }

      final Committee updated = await committees.getById(committee.id);
      expect(updated.status, CommitteeStatus.completed);
      expect(updated.completedTurns, 3);

      final List<CommitteeTurn> rotation = await turnRepo.getByCommittee(committee.id);
      expect(rotation.every((CommitteeTurn t) => t.isCompleted), isTrue);
    });
  });

  group('roster changes', () {
    test('a member can be added and the committee grows by one period', () async {
      final Committee committee = await createCommittee(name: 'Growing', memberCount: 3);
      await members.add(committeeId: committee.id, name: 'Late Arrival');

      final Committee updated = await committees.getById(committee.id);
      expect(updated.memberCount, 4);
      expect(updated.durationPeriods, 4);
      expect(await scheduleRepo.getByCommittee(committee.id), hasLength(4));
      expect(await paymentRepo.getByCommittee(committee.id), hasLength(12));
    });

    test('a member can be removed and the committee shrinks', () async {
      final Committee committee = await createCommittee(name: 'Shrinking', memberCount: 4);
      final List<Member> roster = await memberRepo.getByCommittee(committee.id);
      await members.remove(roster.last.id);

      final Committee updated = await committees.getById(committee.id);
      expect(updated.memberCount, 3);
      expect(await scheduleRepo.getByCommittee(committee.id), hasLength(3));
      expect(await paymentRepo.getByCommittee(committee.id), hasLength(6));
    });

    test('reordering the rotation respects the UNIQUE turn constraint', () async {
      final Committee committee = await createCommittee(name: 'Reorder Swap', memberCount: 4);
      final List<Member> roster = await memberRepo.getByCommittee(committee.id);

      // A pure swap of turn 1 and turn 2 is the case a naive sequential UPDATE
      // cannot handle, because the first write would collide with the second.
      final List<Member> swapped = <Member>[roster[1], roster[0], roster[2], roster[3]];
      await members.reorderTurns(committee.id, swapped);

      final List<Member> after = await memberRepo.getByCommittee(committee.id);
      expect(after.map((Member m) => m.id).toList(), <String>[
        roster[1].id,
        roster[0].id,
        roster[2].id,
        roster[3].id,
      ]);
      expect(after.map((Member m) => m.turnNumber).toList(), <int>[1, 2, 3, 4]);
    });

    test('reordering a full reverse keeps every turn number unique', () async {
      final Committee committee = await createCommittee(name: 'Reorder Reverse', memberCount: 5);
      final List<Member> roster = await memberRepo.getByCommittee(committee.id);
      await members.reorderTurns(committee.id, roster.reversed.toList());

      final List<Member> after = await memberRepo.getByCommittee(committee.id);
      expect(after.map((Member m) => m.turnNumber).toList(), <int>[1, 2, 3, 4, 5]);
      expect(after.first.id, roster.last.id);
    });

    test('the roster is frozen once a payment exists', () async {
      final Committee committee = await createCommittee(name: 'Frozen', memberCount: 4);
      final Payment payment = (await paymentRepo.getByPeriod(committee.id, 1)).first;
      await payments.markPaid(paymentId: payment.id);

      await expectLater(
        members.add(committeeId: committee.id, name: 'Too Late'),
        throwsA(isA<Object>()),
      );
      await expectLater(
        members.remove((await memberRepo.getByCommittee(committee.id)).first.id),
        throwsA(isA<Object>()),
      );
    });
  });

  group('queries', () {
    test('the active recipient is the first uncompleted turn', () async {
      final Committee committee = await createCommittee(name: 'Recipient', memberCount: 4);
      final ({Member? member, int turnNumber, double expectedAmount}) before = await turns
          .currentRecipient(committee.id);
      expect(before.turnNumber, 1);
      expect(before.member?.name, 'Member 1');

      for (final Payment payment in await paymentRepo.getByPeriod(committee.id, 1)) {
        await payments.markPaid(paymentId: payment.id);
      }

      final ({Member? member, int turnNumber, double expectedAmount}) after = await turns
          .currentRecipient(committee.id);
      expect(after.turnNumber, 2);
      expect(after.member?.name, 'Member 2');
    });
    test('statistics add up for a brand new committee', () async {
      final Committee committee = await createCommittee(name: 'Stats', memberCount: 4);
      final CommitteeStats stats = await locator.get<StatisticsService>().forCommittee(
        committee.id,
      );

      expect(stats.totalMembers, 4);
      expect(stats.totalTurns, 4);
      expect(stats.completedTurns, 0);
      expect(stats.paidCount, 0);
      expect(stats.pendingCount, 12);
      expect(stats.totalCollected, 0);

      // Per-turn pot is (memberCount - 1) x contribution: the recipient does not
      // pay into their own pot...
      expect(stats.expectedPool, 3000);
      // ...while the money still to be collected over the committee's whole life
      // is every member x every period, minus the recipient's own skip.
      expect(stats.totalPending, 12000);
    });

    test('collecting money moves the statistics', () async {
      final Committee committee = await createCommittee(name: 'Stats After Pay', memberCount: 4);
      for (final Payment payment in await paymentRepo.getByPeriod(committee.id, 1)) {
        await payments.markPaid(paymentId: payment.id);
      }

      final CommitteeStats stats = await locator.get<StatisticsService>().forCommittee(
        committee.id,
      );
      expect(stats.paidCount, 3);
      expect(stats.totalCollected, 3000);
      expect(stats.completedTurns, 1);
      expect(stats.currentRecipientName, 'Member 2');
    });
  });
}
