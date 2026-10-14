import 'package:committee_manager/di/service_locator.dart';
import 'package:committee_manager/database/app_database.dart';
import 'package:committee_manager/database/db_schema.dart';
import 'package:committee_manager/models/enums.dart';
import 'package:committee_manager/services/committee_service.dart';
import 'package:committee_manager/services/payment_service.dart';
import 'package:committee_manager/services/report_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ServiceLocator.instance.reset();
    db = AppDatabase(
      factory: databaseFactoryFfi,
      overridePath: inMemoryDatabasePath,
    );
    await ServiceLocator.wire(databaseOverride: db);
  });

  tearDown(() => db.close());

  test('generates a complete PDF for a fourteen-member committee', () async {
    final CommitteeService committees = ServiceLocator.instance
        .get<CommitteeService>();
    final ReportService reports = ServiceLocator.instance.get<ReportService>();

    final committee = await committees.create(
      name: 'Fourteen Member Report',
      description: 'Large roster report test',
      contributionAmount: 1000,
      frequency: PaymentFrequency.monthly,
      startDate: DateTime(2026, 1, 31),
      memberDrafts: <MemberDraft>[
        for (int i = 1; i <= 14; i++) MemberDraft(name: 'Member $i'),
      ],
    );

    final bytes = await reports.buildPdfBytes(
      bundle: await committees.loadBundle(committee.id),
    );

    expect(bytes, isNotEmpty);
    expect(bytes.sublist(0, 5), <int>[37, 80, 68, 70, 45]);
  });

  test(
    'generates payment history for all rows in a fourteen-member committee',
    () async {
      final CommitteeService committees = ServiceLocator.instance
          .get<CommitteeService>();
      final PaymentService payments = ServiceLocator.instance
          .get<PaymentService>();
      final ReportService reports = ServiceLocator.instance
          .get<ReportService>();

      final committee = await committees.create(
        name: 'Fourteen Member Paid Report',
        description: null,
        contributionAmount: 1000,
        frequency: PaymentFrequency.daily,
        startDate: DateTime(2026, 1, 1),
        memberDrafts: <MemberDraft>[
          for (int i = 1; i <= 14; i++) MemberDraft(name: 'Member $i'),
        ],
      );
      for (final payment in await payments.forCommittee(committee.id)) {
        await payments.markPaid(paymentId: payment.id);
      }

      final bytes = await reports.buildPdfBytes(
        bundle: await committees.loadBundle(committee.id),
      );
      expect(bytes, isNotEmpty);
    },
  );

  test('generates a complete PDF for a thirty-member committee', () async {
    final CommitteeService committees = ServiceLocator.instance
        .get<CommitteeService>();
    final ReportService reports = ServiceLocator.instance.get<ReportService>();

    final committee = await committees.create(
      name: 'Thirty Member Report',
      description: 'Very large roster report test',
      contributionAmount: 1000,
      frequency: PaymentFrequency.daily,
      startDate: DateTime(2026, 1, 1),
      memberDrafts: <MemberDraft>[
        for (int i = 1; i <= 30; i++) MemberDraft(name: 'Member $i'),
      ],
    );
    final committeePayments = await (await db.database).query(
      DbSchema.payments,
      where: 'committee_id = ?',
      whereArgs: <Object?>[committee.id],
    );
    expect(committeePayments, hasLength(30 * 29));
    await db.transaction<void>((txn) async {
      await txn.update(
        DbSchema.payments,
        <String, Object?>{
          'status': 'paid',
          'paid_date': DateTime(2026, 1, 2).millisecondsSinceEpoch,
        },
        where: 'committee_id = ?',
        whereArgs: <Object?>[committee.id],
      );
    });

    final bytes = await reports.buildPdfBytes(
      bundle: await committees.loadBundle(committee.id),
    );

    expect(bytes, isNotEmpty);
    expect(bytes.sublist(0, 5), <int>[37, 80, 68, 70, 45]);
  });
}
