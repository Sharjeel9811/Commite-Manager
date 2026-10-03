import 'package:sqflite/sqflite.dart' hide DatabaseException;

import '../../core/errors/app_exception.dart';
import '../../core/utils/logger.dart';
import '../../database/app_database.dart';
import '../../database/db_schema.dart';
import '../../models/committee.dart';
import '../interfaces/committee_repository.dart';

/// SQLite implementation of [CommitteeRepository].
///
/// **Liskov Substitution:** wherever the application asks for a
/// `CommitteeRepository` it gets *this* class, but the rest of the code has no
/// idea that SQLite is involved — swap in an in-memory repository and nothing
/// above this layer changes.
class SqliteCommitteeRepository implements CommitteeRepository {
  const SqliteCommitteeRepository(this._appDatabase);

  final AppDatabase _appDatabase;
  static const AppLogger _log = AppLogger('CommitteeRepo');

  @override
  Future<List<Committee>> getAll() =>
      _appDatabase.guardAsync('Could not load your committees.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.committees,
          orderBy: 'created_at DESC',
        );
        return rows.map(Committee.fromMap).toList(growable: false);
      });

  @override
  Future<List<Committee>> getByStatus(String status) =>
      _appDatabase.guardAsync('Could not filter committees.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.committees,
          where: 'status = ?',
          whereArgs: <Object?>[status],
          orderBy: 'created_at DESC',
        );
        return rows.map(Committee.fromMap).toList(growable: false);
      });

  @override
  Future<List<Committee>> search(String query) =>
      _appDatabase.guardAsync('Could not search committees.', () async {
        final String term = query.trim();
        if (term.isEmpty) return <Committee>[];
        final DatabaseExecutor db = await _appDatabase.executor;
        // `?` placeholders: the user's text can never become part of the SQL.
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.committees,
          where: 'name LIKE ? OR IFNULL(description, \'\') LIKE ?',
          whereArgs: <Object?>['%$term%', '%$term%'],
          orderBy: 'created_at DESC',
        );
        return rows.map(Committee.fromMap).toList(growable: false);
      });

  @override
  Future<Committee?> getById(String id) =>
      _appDatabase.guardAsync('Could not open the committee.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.committees,
          where: 'id = ?',
          whereArgs: <Object?>[id],
          limit: 1,
        );
        return rows.isEmpty ? null : Committee.fromMap(rows.first);
      });

  @override
  Future<String> insert(Committee committee) =>
      _appDatabase.guardAsync('Could not create the committee.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        try {
          await db.insert(
            DbSchema.committees,
            committee.toMap(),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        } on DatabaseException catch (error) {
          if (error.toString().toLowerCase().contains('unique')) {
            throw DuplicateException(
              'A committee called "${committee.name}" already exists. '
              'Please choose a different name.',
              details: error.toString(),
            );
          }
          rethrow;
        }
        _log.info('Inserted committee ${committee.id}');
        return committee.id;
      });

  @override
  Future<void> update(Committee committee) =>
      _appDatabase.guardAsync('Could not save your changes.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final int rows = await db.update(
          DbSchema.committees,
          committee.copyWith(updatedAt: DateTime.now()).toMap(),
          where: 'id = ?',
          whereArgs: <Object?>[committee.id],
        );
        if (rows == 0) throw const NotFoundException('This committee no longer exists.');
      });

  @override
  Future<void> delete(String id) =>
      _appDatabase.guardAsync('Could not delete the committee.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        // ON DELETE CASCADE removes members, periods, payments and turns.
        final int rows = await db.delete(
          DbSchema.committees,
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
        if (rows == 0) throw const NotFoundException('This committee no longer exists.');
      });

  @override
  Future<int> count() => _appDatabase.guardAsync('Could not count committees.', () async {
    final DatabaseExecutor db = await _appDatabase.executor;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${DbSchema.committees}',
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  });

  @override
  Future<void> deleteAll() => _appDatabase.guardAsync('Could not remove committees.', () async {
    final DatabaseExecutor db = await _appDatabase.executor;
    await db.delete(DbSchema.committees);
  });
}
