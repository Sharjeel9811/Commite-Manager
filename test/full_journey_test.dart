import 'dart:math';

import 'package:committee_manager/core/constants/app_constants.dart';
import 'package:committee_manager/core/errors/app_exception.dart';
import 'package:committee_manager/database/app_database.dart';
import 'package:committee_manager/di/service_locator.dart';
import 'package:committee_manager/models/app_user.dart';
import 'package:committee_manager/models/committee.dart';
import 'package:committee_manager/models/enums.dart';
import 'package:committee_manager/models/payment.dart';
import 'package:committee_manager/providers/auth_provider.dart';
import 'package:committee_manager/providers/history_provider.dart';
import 'package:committee_manager/providers/statistics_provider.dart';
import 'package:committee_manager/repositories/interfaces/user_repository.dart';
import 'package:committee_manager/services/auth_service.dart';
import 'package:committee_manager/services/committee_service.dart';
import 'package:committee_manager/services/interfaces/otp_sender.dart';
import 'package:committee_manager/services/otp_service.dart';
import 'package:committee_manager/services/payment_service.dart';
import 'package:committee_manager/services/statistics_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Drives the **whole app** the way a person does, against the real object
/// graph, the real SQLite database and the real services.
///
/// The unit tests elsewhere each cover one area. This file exists because the
/// bugs that actually reach a user are the ones that only show up *between*
/// areas:
///
///  * the lock screen asked for a code it had never sent, so a locked-out user
///    could never get back in;
///  * a 4-digit PIN was drawn against six dots, which reads as "the app wants
///    six digits";
///  * a delivery failure was swallowed, leaving the account silently unusable.
///
/// The only thing doubled is the verification provider, because a real one is a
/// server. This double plays the inbox the user would be reading while keeping
/// the code server-side, exactly like Supabase does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String pin = '5381';
  const String phone = '+923001234567';
  const String email = 'ada@example.com';
  late AppDatabase db;
  late _Inbox inbox;
  late AuthService auth;
  late UserRepository users;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ServiceLocator.instance.reset();
    db = AppDatabase(factory: databaseFactoryFfi, overridePath: inMemoryDatabasePath);
    await ServiceLocator.wire(databaseOverride: db);

    inbox = _Inbox();
    ServiceLocator.instance
      ..override<OtpSender>(inbox)
      // OtpService and AuthService captured the sender at wiring time, so
      // they have to be rebuilt around the inbox. Everything else is untouched.
      ..register<OtpService>(
        OtpService(
          otpRepository: ServiceLocator.instance.get<OtpRepository>(),
          userRepository: ServiceLocator.instance.get<UserRepository>(),
          sender: inbox,
        ),
      )
      ..register<AuthService>(
        AuthService(
          userRepository: ServiceLocator.instance.get<UserRepository>(),
          otpService: ServiceLocator.instance.get<OtpService>(),
          biometricService: ServiceLocator.instance.get(),
          database: ServiceLocator.instance.get(),
        ),
      );

    auth = ServiceLocator.instance.get<AuthService>();
    users = ServiceLocator.instance.get<UserRepository>();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> registerAndVerify({String pinToUse = pin}) async {
    await auth.register(
      fullName: 'Ada Lovelace',
      phoneNumber: phone,
      email: email,
      pin: pinToUse,
      confirmPin: pinToUse,
    );
    await auth.sendVerificationCode();
    await auth.verifyAccount(inbox.lastCode);
  }

  group('the journey a person actually takes', () {
    test('register -> receive a code -> verify -> committee -> payment -> '
        'lock out -> recover with a genuinely sent code', () async {
      final CommitteeService committees = ServiceLocator.instance.get<CommitteeService>();
      final PaymentService payments = ServiceLocator.instance.get<PaymentService>();

      // ---- 1. Register with a 4-digit PIN ---------------------------------
      await auth.register(
        fullName: 'Ada Lovelace',
        phoneNumber: phone,
        email: email,
        pin: pin,
        confirmPin: pin,
      );
      expect(inbox.sent, isEmpty, reason: 'registering on its own must not send anything');

      // The length is recorded so the lock screen never claims 6 when it is 4.
      final AppUser registered = (await users.getPrimary())!;
      expect(registered.pinLength, 4);
      expect(registered.pinLength, lessThanOrEqualTo(AppConstants.maxPinLength));
      expect(registered.otpVerified, isTrue, reason: 'registration no longer requires OTP');
      expect(registered.isVerified, isTrue, reason: 'registration completes locally');

      // ---- 2. Ask for the code and receive it for real --------------------
      await auth.sendVerificationCode();
      expect(inbox.sent, hasLength(1), reason: 'the code must actually be delivered');
      expect(inbox.lastCode, hasLength(AppConstants.otpLength));
      expect(inbox.lastDestination, email, reason: 'codes are delivered by email');

      // ---- 3. Verify it ----------------------------------------------------
      await auth.verifyAccount(inbox.lastCode);
      final AppUser verified = (await users.getPrimary())!;
      expect(verified.otpVerified, isTrue);
      expect(verified.isVerified, isTrue);

      // ---- 4. Build a committee -------------------------------------------
      final Committee committee = await committees.create(
        name: 'Bicycle Fund',
        description: 'Three members, one cycle each',
        contributionAmount: 10000,
        frequency: PaymentFrequency.monthly,
        startDate: DateTime.now().subtract(const Duration(days: 30)),
        memberDrafts: <MemberDraft>[
          const MemberDraft(name: 'Ada Lovelace', phoneNumber: phone),
          const MemberDraft(name: 'Alan Turing', phoneNumber: '+923002234567'),
          const MemberDraft(name: 'Grace Hopper', phoneNumber: '+923003234567'),
        ],
      );
      expect(committee.memberCount, 3);
      expect(committee.durationPeriods, 3);

      // ---- 5. Record a payment --------------------------------------------
      final List<Payment> due = (await payments.forCommittee(committee.id))
          .where((Payment p) => !p.isPaid)
          .toList();
      expect(due, isNotEmpty, reason: 'creating a committee schedules its payments');

      await payments.markPaid(paymentId: due.first.id);
      expect(
        (await payments.getById(due.first.id)).isPaid,
        isTrue,
        reason: 'a marked payment must stay paid',
      );

      // ---- 6. Fail the PIN on purpose until the app locks itself -----------
      for (int attempt = 0; attempt < AppConstants.maxPinAttempts; attempt++) {
        await expectLater(
          auth.unlockWithPin('0000'),
          throwsA(isA<AuthException>()),
          reason: 'a wrong PIN must never unlock',
        );
      }
      final AppUser locked = (await users.getPrimary())!;
      expect(
        locked.isLockedOutAt(DateTime.now()),
        isTrue,
        reason: 'the app must lock itself after the allowed attempts',
      );

      // ---- 7. The correct PIN is refused *while* the lock is active -------
      await expectLater(
        auth.unlockWithPin(pin),
        throwsA(
          isA<AuthException>().having(
            (AuthException e) => e.message,
            'message',
            contains('Too many incorrect attempts'),
          ),
        ),
        reason: 'the lockout must be real, not cosmetic',
      );

      // ---- 8. Recovery. This is the path that was broken: the old lock
      //     screen prompted for a code and never sent one, so `recoverWithOtp`
      //     found no challenge and the user was locked out permanently.
      await auth.sendVerificationCode();
      expect(inbox.sent, hasLength(2), reason: 'recovery must send a real code');

      final AppUser recovered = await auth.recoverWithOtp(inbox.lastCode);
      expect(recovered, isNotNull);
      final AppUser free = (await users.getPrimary())!;
      expect(free.isLockedOutAt(DateTime.now()), isFalse, reason: 'recovery must clear the lock');
      expect(free.failedLoginAttempts, 0);

      // ---- 9. The original 4-digit PIN still opens the app -----------------
      expect(await auth.unlockWithPin(pin), isNotNull);
    });

    test('a wrong recovery code is refused and does not unlock', () async {
      await registerAndVerify();
      for (int i = 0; i < AppConstants.maxPinAttempts; i++) {
        await expectLater(auth.unlockWithPin('0000'), throwsA(isA<AuthException>()));
      }
      await auth.sendVerificationCode();

      await expectLater(auth.recoverWithOtp('000000'), throwsA(isA<AuthException>()));
      expect(
        (await users.getPrimary())!.isLockedOutAt(DateTime.now()),
        isTrue,
        reason: 'a bad code must not open the app',
      );
    });

    test('a recovery delivery outage is reported, never swallowed', () async {
      await auth.register(
        fullName: 'Ada Lovelace',
        phoneNumber: phone,
        email: email,
        pin: pin,
        confirmPin: pin,
      );

      inbox.failure = 'Could not reach the gateway on this computer.';
      await expectLater(auth.sendVerificationCode(), throwsA(isA<AuthException>()));

      // Registration is local, but recovery still reports delivery failures.
      final AppUser user = (await users.getPrimary())!;
      expect(user.otpVerified, isTrue);
      expect(user.isVerified, isTrue);
    });

    test('changing the PIN keeps the recorded length and retires the old PIN', () async {
      await registerAndVerify();

      await auth.changePin(currentPin: pin, newPin: '9274', confirmPin: '9274');
      expect((await users.getPrimary())!.pinLength, 4);
      expect(await auth.unlockWithPin('9274'), isNotNull);

      for (int i = 0; i < AppConstants.maxPinAttempts; i++) {
        await expectLater(auth.unlockWithPin(pin), throwsA(isA<AuthException>()));
      }
    });

    test('a 6-digit PIN is honoured too, and is not confused with the 6-digit code', () async {
      await registerAndVerify(pinToUse: '927413');
      final AppUser user = (await users.getPrimary())!;
      expect(user.pinLength, 6);

      // The 6-digit OTP is never accepted as the PIN.
      await expectLater(auth.unlockWithPin(inbox.lastCode), throwsA(isA<AuthException>()));
      expect(await auth.unlockWithPin('927413'), isNotNull);
    });
    test('deleting the account wipes every local row and reopens registration', () async {
      // Google Play requires a way to delete an account; this is it.
      await registerAndVerify();
      final CommitteeService committees = ServiceLocator.instance.get<CommitteeService>();
      await committees.create(
        name: 'Water Fund',
        description: null,
        contributionAmount: 10000,
        frequency: PaymentFrequency.monthly,
        startDate: DateTime.now().subtract(const Duration(days: 30)),
        memberDrafts: <MemberDraft>[
          const MemberDraft(name: 'Ada Lovelace'),
          const MemberDraft(name: 'Alan Turing'),
        ],
      );
      expect(await committees.getAll(), isNotEmpty);

      await auth.deleteAccount();

      expect(await auth.hasAccount(), isFalse, reason: 'the account must be gone');
      expect(await committees.getAll(), isEmpty, reason: 'committees must be gone too');
      expect(
        await users.getPrimary(),
        isNull,
        reason: 'no half-deleted user row may remain',
      );
      final List<Map<String, Object?>> tables = await (await db.executor).rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );
      for (final Map<String, Object?> row in tables) {
        final List<Map<String, Object?>> counted = await (await db.executor).rawQuery(
          'SELECT COUNT(*) AS c FROM ${row['name']}',
        );
        expect(counted.first['c'], 0, reason: 'table ${row['name']} must be empty after deletion');
      }
    });

    test('a locked-out user gets back in with a real code sent to their email', () async {
      // The recovery path that matters: no phone number, no provider, no
      // alternatives to fall back on - just one channel and it has to work.
      await registerAndVerify();
      for (int i = 0; i < AppConstants.maxPinAttempts; i++) {
        await expectLater(auth.unlockWithPin('0000'), throwsA(isA<AuthException>()));
      }
      expect((await users.getPrimary())!.isLockedOutAt(DateTime.now()), isTrue);

      await auth.sendVerificationCode();
      expect(inbox.lastChannel, OtpChannel.email);
      expect(inbox.lastDestination, email);

      expect(await auth.recoverWithOtp(inbox.lastCode), isNotNull);
      expect((await users.getPrimary())!.isLockedOutAt(DateTime.now()), isFalse);
    });

    test('registering without an email is refused, because there is no way in', () async {
      // Email is the only channel, so an account without one could never
      // receive a code. Better to say so at signup than to strand the user
      // behind a lock screen they cannot open.
      await expectLater(
        auth.register(
          fullName: 'Ada Lovelace',
          phoneNumber: phone,
          email: '',
          pin: pin,
          confirmPin: pin,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(await auth.hasAccount(), isFalse, reason: 'no half-made account may survive');
    });

    test('registering with no phone number at all is fine', () async {
      // The phone number is now just a contact detail, so it must be optional.
      await auth.register(
        fullName: 'Ada Lovelace',
        phoneNumber: null,
        email: email,
        pin: pin,
        confirmPin: pin,
      );
      final AppUser user = (await users.getPrimary())!;
      expect(user.phoneNumber, isNull);
      expect(user.availableChannels, <OtpChannel>[OtpChannel.email]);

      await auth.sendVerificationCode();
      expect(inbox.lastDestination, email);
      await auth.verifyAccount(inbox.lastCode);
      expect((await users.getPrimary())!.isVerified, isTrue);
    });

    test('a phone number on file is never used to deliver a code', () async {
      // Having both contacts on file used to mean a choice. Now the number is
      // contact information only, and must never receive anything.
      await auth.register(
        fullName: 'Ada Lovelace',
        phoneNumber: phone,
        email: email,
        pin: pin,
        confirmPin: pin,
      );
      expect((await users.getPrimary())!.preferredChannel, OtpChannel.email);

      await auth.sendVerificationCode();
      expect(inbox.lastChannel, OtpChannel.email);
      expect(inbox.lastDestination, email);
      expect(inbox.lastDestination, isNot(phone));

      // And every later send, including a resend, keeps using the email.
      await auth.sendVerificationCode();
      expect(inbox.lastChannel, OtpChannel.email);
      expect(inbox.lastDestination, email);
    });

    test('the email-only rule survives a restart', () async {
      await auth.register(
        fullName: 'Ada Lovelace',
        phoneNumber: phone,
        email: email,
        pin: pin,
        confirmPin: pin,
      );
      await auth.sendVerificationCode();
      await auth.verifyAccount(inbox.lastCode);

      // A brand new provider, as if the app had been closed and reopened.
      final AuthProvider reopened = AuthProvider(
        authService: auth,
        settingsRepository: ServiceLocator.instance.get(),
      );
      expect(reopened.user, isNull, reason: 'nothing is known until it bootstraps');
      await reopened.bootstrap();
      expect(reopened.user?.primaryChannel, OtpChannel.email);
      expect(reopened.user?.verificationTarget, email);
    });

    test('an account saved with a legacy SMS preference still reads back as email', () async {
      // Rows written before SMS was removed store 'sms'. They have to keep
      // loading, and they must not resurrect a channel that no longer exists.
      await auth.register(
        fullName: 'Ada Lovelace',
        phoneNumber: phone,
        email: email,
        pin: pin,
        confirmPin: pin,
      );
      await (await db.database).update(
        'users',
        <String, Object?>{'preferred_otp_channel': 'sms'},
      );

      final AppUser user = (await users.getPrimary())!;
      expect(user.preferredChannel, OtpChannel.email);
      expect(user.primaryChannel, OtpChannel.email);
      expect(user.verificationTarget, email);
    });
  });

  group('the screens read the same truth as the database', () {
    test('history and the dashboard reflect a real payment', () async {
      final CommitteeService committees = ServiceLocator.instance.get<CommitteeService>();
      final PaymentService payments = ServiceLocator.instance.get<PaymentService>();
      final StatisticsService statistics = ServiceLocator.instance.get<StatisticsService>();

      final Committee committee = await committees.create(
        name: 'School Fees',
        description: null,
        contributionAmount: 5000,
        frequency: PaymentFrequency.monthly,
        startDate: DateTime.now().subtract(const Duration(days: 60)),
        memberDrafts: <MemberDraft>[
          const MemberDraft(name: 'Ada Lovelace'),
          const MemberDraft(name: 'Alan Turing'),
        ],
      );
      final List<Payment> due = (await payments.forCommittee(committee.id))
          .where((Payment p) => !p.isPaid)
          .toList();
      await payments.markPaid(paymentId: due.first.id);

      final HistoryProvider history = HistoryProvider(statisticsService: statistics);
      await history.load();
      expect(history.all, isNotEmpty, reason: 'a paid row must reach the history screen');

      final StatisticsProvider dashboard = StatisticsProvider(statisticsService: statistics);
      await dashboard.load();
      expect(dashboard.stats, isNotNull);
      expect(dashboard.stats!.totalCollected, greaterThan(0));
      expect(dashboard.stats!.activeCommittees, greaterThan(0));
      expect(dashboard.stats!.totalMembers, 2);
    });
  });
}

/// Stands in for the verification provider by keeping what it "emails", so a
/// test can play the part of the inbox the user would be reading. The code is
/// generated inside the double, never in the app.
class _Inbox implements OtpSender {
  final List<String> sent = <String>[];
  String? failure;
  String lastDestination = '';
  OtpChannel lastChannel = OtpChannel.email;

  static final Random _random = Random();

  String get lastCode => sent.last;

  @override
  String get deliveryDescription => 'test inbox';

  @override
  Future<OtpDeliveryResult> send({
    required String destination,
    required String purpose,
  }) async {
    final String? problem = failure;
    if (problem != null) return OtpDeliveryResult(success: false, error: problem);
    lastDestination = destination;
    lastChannel = OtpChannel.email;
    sent.add('${_random.nextInt(900000) + 100000}');
    return const OtpDeliveryResult(success: true);
  }

  @override
  Future<OtpVerificationResult> verify({
    required String destination,
    required String code,
  }) async {
    final String? problem = failure;
    if (problem != null) return OtpVerificationResult(success: false, error: problem);
    final bool ok = sent.isNotEmpty &&
        code == sent.last &&
        destination == lastDestination;
    if (!ok) {
      return const OtpVerificationResult(
        success: false,
        error: 'That code is not correct.',
      );
    }
    return const OtpVerificationResult(success: true);
  }
}
