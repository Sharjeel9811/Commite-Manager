import 'package:sqflite/sqflite.dart' hide DatabaseException;

import '../../core/utils/logger.dart';
import '../../database/app_database.dart';
import '../../database/db_schema.dart';
import '../../models/committee_turn.dart';
import '../interfaces/turn_repository.dart';

/// SQLite implementation of [TurnRepository].
///
/// Holds no rotation logic at all — deciding *when* a turn completes is the job
/// of `TurnService`.
class SqliteTurnRepository implements TurnRepository {
  const SqliteTurnRepository(this._appDatabase);

  final AppDatabase _appDatabase;
  static const AppLogger _log = AppLogger('TurnRepo');

  @override
  Future<List<CommitteeTurn>> getByCommittee(String committeeId) =>
      _appDatabase.guardAsync('Could not load the turn order.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.turns,
          where: 'committee_id = ?',
          whereArgs: <Object?>[committeeId],
          orderBy: 'turn_number ASC',
        );
        return rows.map(CommitteeTurn.fromMap).toList(growable: false);
      });

  @override
  Future<CommitteeTurn?> getByNumber(String committeeId, int turnNumber) =>
      _appDatabase.guardAsync('Could not find that turn.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.turns,
          where: 'committee_id = ? AND turn_number = ?',
          whereArgs: <Object?>[committeeId, turnNumber],
          limit: 1,
        );
        return rows.isEmpty ? null : CommitteeTurn.fromMap(rows.first);
      });

  @override
  Future<CommitteeTurn?> getActive(String committeeId) =>
      _appDatabase.guardAsync('Could not find the current turn.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.turns,
          where: "committee_id = ? AND status = 'active'",
          whereArgs: <Object?>[committeeId],
          limit: 1,
        );
        return rows.isEmpty ? null : CommitteeTurn.fromMap(rows.first);
      });

  @override
  Future<CommitteeTurn?> getByMember(String memberId) =>
      _appDatabase.guardAsync('Could not find this member\'s turn.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.turns,
          where: 'member_id = ?',
          whereArgs: <Object?>[memberId],
          limit: 1,
        );
        return rows.isEmpty ? null : CommitteeTurn.fromMap(rows.first);
      });

  @override
  Future<void> insertAll(List<CommitteeTurn> turns) =>
      _appDatabase.guardAsync('Could not set up the turn order.', () async {
        if (turns.isEmpty) return;
        final DatabaseExecutor db = await _appDatabase.executor;
        final Batch batch = db.batch();
        for (final CommitteeTurn turn in turns) {
          batch.insert(DbSchema.turns, turn.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        await batch.commit(noResult: true);
        _log.info('Generated ${turns.length} turns');
      });

  @override
  Future<void> update(CommitteeTurn turn) =>
      _appDatabase.guardAsync('Could not update the turn.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final int rows = await db.update(
          DbSchema.turns,
          turn.copyWith(updatedAt: DateTime.now()).toMap(),
          where: 'id = ?',
          whereArgs: <Object?>[turn.id],
        );
        if (rows == 0) {
          throw StateError('Turn ${turn.id} not found while updating.');
        }
      });

  @override
  Future<void> updateCollected(String turnId, double collectedAmount) =>
      _appDatabase.guardAsync('Could not update the collected amount.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        await db.update(
          DbSchema.turns,
          <String, Object?>{
            'collected_amount': collectedAmount,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: <Object?>[turnId],
        );
      });

  @override
  Future<void> deleteByCommittee(String committeeId) => _appDatabase.guardAsync(
    'Could not clear the turn order.',
    () async {
      final DatabaseExecutor db = await _appDatabase.executor;
      await db.delete(DbSchema.turns, where: 'committee_id = ?', whereArgs: <Object?>[committeeId]);
    },
  );

  @override
  Future<int> countCompleted(String committeeId) => _count(
    "SELECT COUNT(*) AS c FROM ${DbSchema.turns} "
    "WHERE committee_id = ? AND status = 'completed'",
    <Object?>[committeeId],
  );

  @override
  Future<int> countAll() =>
      _count('SELECT COUNT(*) AS c FROM ${DbSchema.turns}', const <Object?>[]);

  @override
  Future<int> countCompletedAll() => _count(
    "SELECT COUNT(*) AS c FROM ${DbSchema.turns} WHERE status = 'completed'",
    const <Object?>[],
  );

  @override
  Future<int> sumExpectedAll() => _doubleCount(
    'SELECT IFNULL(SUM(expected_amount), 0) AS c FROM ${DbSchema.turns}',
    const <Object?>[],
  );

  @override
  Future<int> sumCollectedAll() => _doubleCount(
    'SELECT IFNULL(SUM(collected_amount), 0) AS c FROM ${DbSchema.turns}',
    const <Object?>[],
  );

  Future<int> _count(String sql, List<Object?> args) async {
    final List<Map<String, Object?>> rows = await _run(sql, args);
    return (rows.first['c'] as int?) ?? 0;
  }

  /// SQLite stores REAL as a double; the interface uses `int` to avoid exposing
  /// floating point noise in the sum, so we round to whole currency units.
  Future<int> _doubleCount(String sql, List<Object?> args) async {
    final List<Map<String, Object?>> rows = await _run(sql, args);
    return ((rows.first['c'] as num?) ?? 0).round();
  }

  Future<List<Map<String, Object?>>> _run(String sql, List<Object?> args) =>
      _appDatabase.guardAsync('Could not read turn totals.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        return db.rawQuery(sql, args);
      });
}
