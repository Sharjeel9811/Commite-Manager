import 'package:sqflite/sqflite.dart' hide DatabaseException;

import '../../core/errors/app_exception.dart';
import '../../core/utils/logger.dart';
import '../../database/app_database.dart';
import '../../database/db_schema.dart';
import '../../models/app_user.dart';
import '../interfaces/user_repository.dart';

/// SQLite implementation of [UserRepository].
///
/// The account table is small and is always loaded as a whole row, so there is
/// no benefit in splitting single-column queries into separate methods.
class SqliteUserRepository implements UserRepository {
  const SqliteUserRepository(this._appDatabase);

  final AppDatabase _appDatabase;
  static const AppLogger _log = AppLogger('UserRepo');

  @override
  Future<AppUser?> getPrimary() =>
      _appDatabase.guardAsync('Could not load your account.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.users,
          orderBy: 'created_at ASC',
          limit: 1,
        );
        return rows.isEmpty ? null : AppUser.fromMap(rows.first);
      });

  @override
  Future<AppUser?> getById(String id) =>
      _appDatabase.guardAsync('Could not load your account.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.users,
          where: 'id = ?',
          whereArgs: <Object?>[id],
          limit: 1,
        );
        return rows.isEmpty ? null : AppUser.fromMap(rows.first);
      });

  @override
  Future<String> insert(AppUser user) =>
      _appDatabase.guardAsync('Could not create your account.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        await db.insert(DbSchema.users, user.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
        _log.info('Created account ${user.id}');
        return user.id;
      });

  @override
  Future<void> update(AppUser user) =>
      _appDatabase.guardAsync('Could not save your account.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final int rows = await db.update(
          DbSchema.users,
          user.copyWith(updatedAt: DateTime.now()).toMap(),
          where: 'id = ?',
          whereArgs: <Object?>[user.id],
        );
        if (rows == 0) throw const NotFoundException('Your account no longer exists.');
      });

  @override
  Future<void> delete(String id) =>
      _appDatabase.guardAsync('Could not remove the account.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        await db.delete(DbSchema.users, where: 'id = ?', whereArgs: <Object?>[id]);
      });

  @override
  Future<bool> exists() => _appDatabase.guardAsync('Could not check your account.', () async {
    final DatabaseExecutor db = await _appDatabase.executor;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${DbSchema.users}',
    );
    return (Sqflite.firstIntValue(rows) ?? 0) > 0;
  });
}
