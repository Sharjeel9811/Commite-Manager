import 'dart:math';

import 'package:committee_manager/core/utils/crypto_helper.dart';
import 'package:committee_manager/database/app_database.dart';
import 'package:committee_manager/di/service_locator.dart';
import 'package:committee_manager/models/app_user.dart';
import 'package:committee_manager/models/enums.dart';
import 'package:committee_manager/repositories/interfaces/user_repository.dart';
import 'package:committee_manager/services/interfaces/otp_sender.dart';
import 'package:committee_manager/services/otp_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Guards the rule that the verification code is **never** generated, stored or
/// seen by the app.
///
/// The original build displayed the code in a panel on the verify screen, which
/// meant holding the unlocked device was enough to register any number or email
/// address. The provider (Supabase Auth) now owns the whole code lifecycle:
/// `send` asks it to email one, `verify` asks it to check one back. Nothing in
/// this app can print, log or render a code, because a code never exists here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = AppDatabase(factory: databaseFactoryFfi, overridePath: inMemoryDatabasePath);
    await ServiceLocator.wire(databaseOverride: db);
  });

  tearDown(() async {
    await db.close();
    ServiceLocator.instance.reset();
  });

  UserRepository users() => ServiceLocator.instance.get<UserRepository>();

  Future<String> seedUser() async {
    final String salt = CryptoHelper.newSalt();
    await users().insert(
      AppUser(
        id: CryptoHelper.newId(),
        fullName: 'Ada Lovelace',
        phoneNumber: '+923001234567',
        email: 'ada@example.com',
        pinHash: CryptoHelper.hashSecret('5381', salt),
        pinSalt: salt,
        isVerified: false,
        biometricEnabled: false,
        createdAt: DateTime.now(),
      ),
    );
    return (await users().getPrimary())!.id;
  }

  OtpService serviceWith(OtpSender sender) => OtpService(
    otpRepository: ServiceLocator.instance.get<OtpRepository>(),
    userRepository: users(),
    sender: sender,
  );

  group('the app does not own the code', () {
    test('send never asks the provider for a code, and issue never sees one', () {
      // Compile-time assertions. If anyone ever re-adds `code` to the send
      // contract, `issue` to a sender, or makes the service return the code,
      // these assignments stop compiling.
      final Future<OtpDeliveryResult> Function({
        required String destination,
        required String purpose,
      })
      typedSend = _ProviderSender().send;

      final Future<void> Function({
        required String userId,
        required String destination,
        required OtpChannel channel,
        required String purpose,
      })
      typedIssue = serviceWith(_ProviderSender()).issue;

      expect(typedSend, isNotNull);
      expect(typedIssue, isNotNull);
    });

    test('the database stores an opaque marker, never anything verifiable', () async {
      final String userId = await seedUser();
      final _ProviderSender provider = _ProviderSender();

      await serviceWith(provider).issue(
        userId: userId,
        destination: 'ada@example.com',
        channel: OtpChannel.email,
        purpose: 'Account verification',
      );

      final String code = provider.lastCodeFor('ada@example.com')!;
      final rows = await (await db.executor).rawQuery('SELECT code_hash FROM otp_challenges');
      expect(rows, hasLength(1));

      final String hash = rows.first['code_hash']! as String;
      expect(hash, isNot(equals(code)));
      expect(hash, isNot(contains(code)));
      expect(hash.length, greaterThan(32), reason: 'salted + iterated, not a bare code');
    });
  });

  group('issue and verify through a provider-owned code', () {
    test('issue -> the provider emails a code -> verify accepts exactly that code', () async {
      final String userId = await seedUser();
      final _ProviderSender provider = _ProviderSender();
      final OtpService service = serviceWith(provider);

      await service.issue(
        userId: userId,
        destination: 'ada@example.com',
        channel: OtpChannel.email,
        purpose: 'Account verification',
      );

      expect(provider.sendCount, 1);
      final String? code = provider.lastCodeFor('ada@example.com');
      expect(code, hasLength(6));

      await expectLater(service.verify(userId: userId, code: '000000'), throwsA(isA<Exception>()));
      await service.verify(userId: userId, code: code!);
      expect(provider.verifyCount, 2);
    });

    test('a failed delivery throws instead of pretending it worked', () async {
      final String userId = await seedUser();

      await expectLater(
        serviceWith(
          _ProviderSender(failureOnSend: 'The verification service could not send the code.'),
        ).issue(
          userId: userId,
          destination: 'ada@example.com',
          channel: OtpChannel.email,
          purpose: 'Account verification',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('issuing a new code invalidates the previous one', () async {
      final String userId = await seedUser();
      final _ProviderSender provider = _ProviderSender();
      final OtpService service = serviceWith(provider);

      await service.issue(
        userId: userId,
        destination: 'ada@example.com',
        channel: OtpChannel.email,
        purpose: 'Account verification',
      );
      final String first = provider.lastCodeFor('ada@example.com')!;

      await service.issue(
        userId: userId,
        destination: 'ada@example.com',
        channel: OtpChannel.email,
        purpose: 'Account verification',
      );

      expect(provider.sendCount, 2);
      await expectLater(service.verify(userId: userId, code: first), throwsA(isA<Exception>()));
      await service.verify(userId: userId, code: provider.lastCodeFor('ada@example.com')!);
    });

    test('a consumed code cannot be replayed after a successful verify', () async {
      final String userId = await seedUser();
      final _ProviderSender provider = _ProviderSender();
      final OtpService service = serviceWith(provider);

      await service.issue(
        userId: userId,
        destination: 'ada@example.com',
        channel: OtpChannel.email,
        purpose: 'Account verification',
      );
      final String code = provider.lastCodeFor('ada@example.com')!;

      await service.verify(userId: userId, code: code);
      await expectLater(service.verify(userId: userId, code: code), throwsA(isA<Exception>()));
    });
  });
}

/// Stands in for Supabase Auth: it generates a code server-side when asked to
/// send, remembers it per destination, and checks submitted codes against it.
class _ProviderSender implements OtpSender {
  _ProviderSender({this.failureOnSend});

  final String? failureOnSend;

  final Map<String, String> _codes = <String, String>{};
  int sendCount = 0;
  int verifyCount = 0;

  String? lastCodeFor(String destination) => _codes[destination];

  static final Random _random = Random();

  @override
  String get deliveryDescription => 'email through the test provider';

  @override
  Future<OtpDeliveryResult> send({
    required String destination,
    required String purpose,
  }) async {
    sendCount++;
    final String? problem = failureOnSend;
    if (problem != null) return OtpDeliveryResult(success: false, error: problem);
    _codes[destination] = '${_random.nextInt(900000) + 100000}';
    return const OtpDeliveryResult(success: true);
  }

  @override
  Future<OtpVerificationResult> verify({
    required String destination,
    required String code,
  }) async {
    verifyCount++;
    final bool ok = _codes[destination] == code;
    if (!ok) {
      return const OtpVerificationResult(
        success: false,
        error: 'That code is not correct.',
      );
    }
    _codes.remove(destination); // one-time use, like a real OTP
    return const OtpVerificationResult(success: true);
  }
}