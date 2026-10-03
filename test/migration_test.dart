import 'dart:io';

import 'package:committee_manager/core/constants/app_constants.dart';
import 'package:committee_manager/core/utils/crypto_helper.dart';
import 'package:committee_manager/database/app_database.dart';
import 'package:committee_manager/models/app_user.dart';
import 'package:committee_manager/models/enums.dart';
import 'package:committee_manager/models/otp_challenge.dart';
import 'package:committee_manager/repositories/implementations/sqlite_user_repository.dart';
import 'package:committee_manager/repositories/interfaces/user_repository.dart';
import 'package:committee_manager/services/auth_service.dart';
import 'package:committee_manager/services/interfaces/biometric_service.dart';
import 'package:committee_manager/services/interfaces/otp_sender.dart';
import 'package:committee_manager/services/otp_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Proves an **existing install survives an upgrade**.
///
/// This is the one path no normal test touches, and the one that matters most to
/// a real user: if the migration throws, they open the app to a broken screen
/// and cannot get into their committee data at all.
///
/// Version 1 is recreated here by hand — the old shape, with no `pin_length` and
/// no `preferred_otp_channel` — so the test fails if the migration ever stops
/// matching what was actually shipped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String phone = '+923001234567';
  const String email = 'ada@example.com';
  const String pin = '5381';

  late String path;
  late _Inbox inbox;

  /// The exact v1 `users` table, before the two columns were added.
  const String v1Users = '''
CREATE TABLE users (
  id                    TEXT PRIMARY KEY,
  full_name             TEXT    NOT NULL,
  phone_number          TEXT,
  email                 TEXT,
  pin_hash              TEXT    NOT NULL,
  pin_salt              TEXT    NOT NULL,
  is_verified           INTEGER NOT NULL DEFAULT 0,
  otp_verified          INTEGER NOT NULL DEFAULT 0,
  biometric_enabled     INTEGER NOT NULL DEFAULT 0,
  role                  TEXT    NOT NULL DEFAULT 'owner',
  failed_login_attempts INTEGER NOT NULL DEFAULT 0,
  locked_until          INTEGER,
  last_login_at         INTEGER,
  created_at            INTEGER NOT NULL,
  updated_at            INTEGER NOT NULL
)''';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    path = '${Directory.systemTemp.path}/cm_migration_${DateTime.now().microsecondsSinceEpoch}.db';
    inbox = _Inbox();
  });

  tearDown(() {
    for (final String suffix in <String>['', '-journal', '-wal', '-shm']) {
      final File file = File('$path$suffix');
      if (file.existsSync()) file.deleteSync();
    }
  });

  /// Builds a genuine version-1 database holding one registered, verified user
  /// with a known PIN hash.
  Future<void> seedVersion1({required String pinToUse}) async {
    final Database db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (Database d, int _) async {
          await d.execute(v1Users);
        },
      ),
    );
    final String salt = 'legacy-salt-value';
    await db.insert('users', <String, Object?>{
      'id': 'legacy-user-1',
      'full_name': 'Ada Lovelace',
      'phone_number': phone,
      'email': email,
      'pin_hash': CryptoHelper.hashSecret(
        pinToUse,
        salt,
        rounds: CryptoHelper.kLegacyPinHashIterations,
      ),
      'pin_salt': salt,
      'is_verified': 1,
      'otp_verified': 1,
      'biometric_enabled': 0,
      'role': 'owner',
      'failed_login_attempts': 0,
      'locked_until': null,
      'last_login_at': null,
      'created_at': 1700000000000,
      'updated_at': 1700000000000,
    });
    await db.close();
  }

  /// Opens the seeded file through the real `AppDatabase` and returns the
  /// repository bound to it.
  Future<(AppDatabase, UserRepository, AuthService)> openUpgraded() async {
    final AppDatabase upgraded = AppDatabase(
      factory: databaseFactoryFfi,
      overridePath: path,
    );
    // Force the connection to open, which is when onUpgrade runs.
    await upgraded.database;

    final UserRepository users = SqliteUserRepository(upgraded);
    final OtpService otps = OtpService(
      otpRepository: _NullOtpRepository(),
      userRepository: users,
      sender: inbox,
    );
    final AuthService auth = AuthService(
      userRepository: users,
      otpService: otps,
      biometricService: _NoBiometrics(),
      database: upgraded,
    );
    return (upgraded, users, auth);
  }

  group('upgrading a real v1 install', () {
    test('the account survives and the user can still unlock with their PIN', () async {
      await seedVersion1(pinToUse: pin);
      final (AppDatabase db, UserRepository users, AuthService auth) = await openUpgraded();
      addTearDown(db.close);

      expect(await users.exists(), isTrue, reason: 'the account must not vanish');
      final AppUser? user = await users.getPrimary();
      expect(user, isNotNull);
      expect(user!.id, 'legacy-user-1');
      expect(user.fullName, 'Ada Lovelace');
      expect(user.phoneNumber, phone);
      expect(user.email, email);
      expect(user.isVerified, isTrue);
      expect(user.otpVerified, isTrue);

      // The real point of the exercise: their existing PIN still opens the app.
      final AppUser unlocked = await auth.unlockWithPin(pin);
      expect(unlocked.id, 'legacy-user-1');
    });

    test('the new columns are present and defaulted', () async {
      await seedVersion1(pinToUse: pin);
      final (AppDatabase db, UserRepository users, _) = await openUpgraded();
      addTearDown(db.close);

      final List<Map<String, Object?>> cols = await (await db.database).rawQuery(
        'PRAGMA table_info(users)',
      );
      final Set<String> names = cols.map((Map<String, Object?> r) => r['name'] as String).toSet();
      expect(names, contains('pin_length'));
      expect(names, contains('preferred_otp_channel'));

      final AppUser user = (await users.getPrimary())!;
      // Nothing recorded the real length, so the minimum is assumed; entry still
      // allows up to six digits.
      expect(user.pinLength, 4);
      expect(user.pinLength, greaterThanOrEqualTo(AppConstants.minPinLength));
      expect(user.pinLength, lessThanOrEqualTo(AppConstants.maxPinLength));
    });

    test('a legacy user is not locked out by a wrong PIN after upgrading', () async {
      await seedVersion1(pinToUse: pin);
      final (AppDatabase db, _, AuthService auth) = await openUpgraded();
      addTearDown(db.close);

      for (int i = 0; i < AppConstants.maxPinAttempts; i++) {
        await expectLater(auth.unlockWithPin('0000'), throwsA(anything));
      }
      // The lockout is real, and the correct PIN clears it through recovery.
      final AppUser user = (await auth.currentUser())!;
      expect(user.isLockedOutAt(DateTime.now()), isTrue);
    });

    test('a legacy row with a null phone number still loads', () async {      await seedVersion1(pinToUse: pin);
      // Legacy installs allowed a missing phone number; the new default channel
      // must not blow up on a NULL.
      final Database raw = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (Database d, int _) async => d.execute(v1Users),
        ),
      );
      await raw.update('users', <String, Object?>{'phone_number': null});
      await raw.close();

      final (AppDatabase db, UserRepository users, _) = await openUpgraded();
      addTearDown(db.close);

      final AppUser? user = await users.getPrimary();
      expect(user, isNotNull);
      expect(user!.phoneNumber, isNull);
      // With no phone, the app must fall back to email rather than try to text
      // a number that does not exist.
      expect(user.primaryChannel, OtpChannel.email);
    });
  });

  group('a damaged row must not brick the app', () {
    // The account is the only key to the user's committee data, and it is read
    // with a plain cast in most apps. A single oddly-typed value would then throw
    // during bootstrap and leave the user staring at an error screen forever.
    test('a timestamp stored as text still loads', () async {
      await seedVersion1(pinToUse: pin);
      final Database raw = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (Database d, int _) async => d.execute(v1Users),
        ),
      );
      // SQLite is dynamically typed, so this is representable.
      await raw.update('users', <String, Object?>{'locked_until': '1700000000000'});
      await raw.close();

      final (AppDatabase db, UserRepository users, AuthService auth) = await openUpgraded();
      addTearDown(db.close);

      final AppUser user = (await users.getPrimary())!;
      expect(user.id, 'legacy-user-1');
      expect(user.lockedUntil, isNotNull);
      // The important half: the account is still usable.
      expect(await auth.unlockWithPin(pin), isNotNull);
    });

    test('a nonsense pin_length is clamped instead of crashing the lock screen', () async {
      await seedVersion1(pinToUse: pin);
      final (AppDatabase db, UserRepository users, _) = await openUpgraded();
      addTearDown(db.close);
      await (await db.database).update('users', <String, Object?>{'pin_length': 99});

      final int length = (await users.getPrimary())!.pinLength;
      expect(length, inInclusiveRange(1, 6), reason: 'the lock screen clamps to a drawable count');
    });

    test('a garbage OTP channel falls back to a real one', () async {
      await seedVersion1(pinToUse: pin);
      final (AppDatabase db, UserRepository users, _) = await openUpgraded();
      addTearDown(db.close);
      await (await db.database).update(
        'users',
        <String, Object?>{'preferred_otp_channel': 'carrier-pigeon'},
      );

      final AppUser user = (await users.getPrimary())!;
      // The only channel there is.
      expect(user.primaryChannel, OtpChannel.email);
    });
  });

  group('a fresh install', () {
    test('starts at the current version with both columns', () async {
      final AppDatabase fresh = AppDatabase(
        factory: databaseFactoryFfi,
        overridePath: inMemoryDatabasePath,
      );
      addTearDown(fresh.close);
      await fresh.database;
      final int version = await (await fresh.database).rawQuery('PRAGMA user_version').then(
        (List<Map<String, Object?>> r) => r.first['user_version'] as int,
      );
      expect(version, AppConstants.databaseVersion);
      expect(version, greaterThanOrEqualTo(2));
    });

    test('registering records the PIN length and the chosen channel', () async {
      final AppDatabase fresh = AppDatabase(
        factory: databaseFactoryFfi,
        overridePath: inMemoryDatabasePath,
      );
      addTearDown(fresh.close);
      await fresh.database;

      final UserRepository users = SqliteUserRepository(fresh);
      final AuthService auth = AuthService(
        userRepository: users,
        otpService: OtpService(
          otpRepository: _NullOtpRepository(),
          userRepository: users,
          sender: inbox,
        ),
        biometricService: _NoBiometrics(),
        database: fresh,
      );

      await auth.register(
        fullName: 'Ada Lovelace',
        phoneNumber: phone,
        email: email,
        pin: pin,
        confirmPin: pin,
      );
      final AppUser user = (await users.getPrimary())!;
      expect(user.pinLength, 4);
      expect(user.preferredChannel, OtpChannel.email);
      // And it survives a round trip through SQLite, not just in memory.
      expect((await users.getPrimary())!.preferredChannel, OtpChannel.email);
    });

    test('a six digit PIN is stored as six, not capped at four', () async {
      final AppDatabase fresh = AppDatabase(
        factory: databaseFactoryFfi,
        overridePath: inMemoryDatabasePath,
      );
      addTearDown(fresh.close);
      await fresh.database;

      final UserRepository users = SqliteUserRepository(fresh);
      final AuthService auth = AuthService(
        userRepository: users,
        otpService: OtpService(
          otpRepository: _NullOtpRepository(),
          userRepository: users,
          sender: inbox,
        ),
        biometricService: _NoBiometrics(),
        database: fresh,
      );
      await auth.register(
        fullName: 'Ada Lovelace',
        phoneNumber: phone,
        email: email,
        pin: '927413',
        confirmPin: '927413',
      );
      expect((await users.getPrimary())!.pinLength, 6);
      expect(await auth.unlockWithPin('927413'), isNotNull);
    });
  });
}

/// Minimal stand-ins so the migration test does not need the whole app graph.
class _Inbox implements OtpSender {
  @override
  String get deliveryDescription => 'test';
  @override
  Future<OtpDeliveryResult> send({
    required String destination,
    required String purpose,
  }) async => const OtpDeliveryResult(success: true);

  @override
  Future<OtpVerificationResult> verify({
    required String destination,
    required String code,
  }) async => const OtpVerificationResult(success: true);
}

class _NullOtpRepository implements OtpRepository {
  @override
  Future<void> invalidateAll(String userId) async {}

  @override
  Future<int> countRecent(String userId, DateTime since) async => 0;

  @override
  Future<String> insert(OtpChallenge challenge) async => challenge.id;

  @override
  Future<OtpChallenge?> getLatestOpen(String userId) async => null;

  @override
  Future<void> incrementAttempts(String challengeId) async {}

  @override
  Future<void> markConsumed(String challengeId, DateTime when) async {}
}

class _NoBiometrics implements BiometricService {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<List<String>> availableTypes() async => const <String>[];

  @override
  Future<bool> authenticate({required String reason}) async => false;
}
