import 'package:sqflite/sqflite.dart' hide DatabaseException;

import '../../database/app_database.dart';
import '../../database/db_schema.dart';
import '../../models/otp_challenge.dart';
import '../interfaces/user_repository.dart';

/// SQLite implementation of [OtpRepository].
///
/// Separate class from the user repository on purpose: the OTP table has a
/// different lifecycle (insert, bump attempts, consume) and a different
/// security profile. Giving it its own repository means a bug in verification
/// can never be introduced by an unrelated change to the account code.
class SqliteOtpRepository implements OtpRepository {
  const SqliteOtpRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<String> insert(OtpChallenge challenge) =>
      _appDatabase.guardAsync('Could not create the verification code.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        await db.insert(
          DbSchema.otpChallenges,
          challenge.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        return challenge.id;
      });

  @override
  Future<OtpChallenge?> getLatestOpen(String userId) =>
      _appDatabase.guardAsync('Could not read the verification code.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.otpChallenges,
          where: 'user_id = ? AND consumed_at IS NULL',
          whereArgs: <Object?>[userId],
          orderBy: 'created_at DESC',
          limit: 1,
        );
        return rows.isEmpty ? null : OtpChallenge.fromMap(rows.first);
      });

  @override
  Future<void> incrementAttempts(String challengeId) =>
      _appDatabase.guardAsync('Could not record the attempt.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        await db.rawUpdate(
          'UPDATE ${DbSchema.otpChallenges} SET attempts = attempts + 1 WHERE id = ?',
          <Object?>[challengeId],
        );
      });

  @override
  Future<void> markConsumed(String challengeId, DateTime when) =>
      _appDatabase.guardAsync('Could not complete the verification.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        await db.update(
          DbSchema.otpChallenges,
          <String, Object?>{'consumed_at': when.millisecondsSinceEpoch},
          where: 'id = ?',
          whereArgs: <Object?>[challengeId],
        );
      });

  @override
  Future<void> invalidateAll(String userId) =>
      _appDatabase.guardAsync('Could not reset verification codes.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        await db.update(
          DbSchema.otpChallenges,
          <String, Object?>{'consumed_at': DateTime.now().millisecondsSinceEpoch},
          where: 'user_id = ? AND consumed_at IS NULL',
          whereArgs: <Object?>[userId],
        );
      });

  @override
  Future<int> countRecent(String userId, DateTime since) =>
      _appDatabase.guardAsync('Could not check the request rate.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM ${DbSchema.otpChallenges} '
          'WHERE user_id = ? AND created_at >= ?',
          <Object?>[userId, since.millisecondsSinceEpoch],
        );
        return Sqflite.firstIntValue(rows) ?? 0;
      });
}
