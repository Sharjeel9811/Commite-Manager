import 'package:sqflite/sqflite.dart' hide DatabaseException;

import '../../core/errors/app_exception.dart';
import '../../core/utils/logger.dart';
import '../../database/app_database.dart';
import '../../database/db_schema.dart';
import '../../models/member.dart';
import '../interfaces/member_repository.dart';

/// SQLite implementation of [MemberRepository].
///
/// All statements are parameterised; no string interpolation of user input into
/// SQL ever happens (SQL-injection safety).
class SqliteMemberRepository implements MemberRepository {
  const SqliteMemberRepository(this._appDatabase);

  final AppDatabase _appDatabase;
  static const AppLogger _log = AppLogger('MemberRepo');

  @override
  Future<List<Member>> getByCommittee(String committeeId) =>
      _appDatabase.guardAsync('Could not load the members.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.members,
          where: 'committee_id = ?',
          whereArgs: <Object?>[committeeId],
          orderBy: 'turn_number ASC',
        );
        return rows.map(Member.fromMap).toList(growable: false);
      });

  @override
  Future<Member?> getById(String id) =>
      _appDatabase.guardAsync('Could not open the member.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.members,
          where: 'id = ?',
          whereArgs: <Object?>[id],
          limit: 1,
        );
        return rows.isEmpty ? null : Member.fromMap(rows.first);
      });

  @override
  Future<Member?> getByTurn(String committeeId, int turnNumber) =>
      _appDatabase.guardAsync('Could not find the member for that turn.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.members,
          where: 'committee_id = ? AND turn_number = ?',
          whereArgs: <Object?>[committeeId, turnNumber],
          limit: 1,
        );
        return rows.isEmpty ? null : Member.fromMap(rows.first);
      });

  @override
  Future<String> insert(Member member) =>
      _appDatabase.guardAsync('Could not add the member.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        try {
          await db.insert(
            DbSchema.members,
            member.toMap(),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        } on DatabaseException catch (error) {
          throw _translate(error, member);
        }
        return member.id;
      });

  @override
  Future<void> update(Member member) =>
      _appDatabase.guardAsync('Could not save the member.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        try {
          final int rows = await db.update(
            DbSchema.members,
            member.copyWith(updatedAt: DateTime.now()).toMap(),
            where: 'id = ?',
            whereArgs: <Object?>[member.id],
          );
          if (rows == 0) throw const NotFoundException('This member no longer exists.');
        } on DatabaseException catch (error) {
          throw _translate(error, member);
        }
      });

  @override
  Future<void> delete(String id) => _appDatabase.guardAsync(
    'Could not remove the member.',
    () async {
      final DatabaseExecutor db = await _appDatabase.executor;
      // Payments/turns of this member cascade away as well.
      final int rows = await db.delete(DbSchema.members, where: 'id = ?', whereArgs: <Object?>[id]);
      if (rows == 0) throw const NotFoundException('This member no longer exists.');
    },
  );

  @override
  Future<int> countByCommittee(String committeeId) =>
      _appDatabase.guardAsync('Could not count members.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM ${DbSchema.members} WHERE committee_id = ?',
          <Object?>[committeeId],
        );
        return Sqflite.firstIntValue(rows) ?? 0;
      });

  @override
  Future<int> nextTurnNumber(String committeeId) =>
      _appDatabase.guardAsync('Could not work out the next turn.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.rawQuery(
          'SELECT IFNULL(MAX(turn_number), 0) AS m FROM ${DbSchema.members} WHERE committee_id = ?',
          <Object?>[committeeId],
        );
        return ((rows.first['m'] as int?) ?? 0) + 1;
      });

  @override
  Future<void> insertAll(List<Member> members) =>
      _appDatabase.guardAsync('Could not add the members.', () async {
        if (members.isEmpty) return;
        final DatabaseExecutor db = await _appDatabase.executor;
        final Batch batch = db.batch();
        for (final Member member in members) {
          batch.insert(DbSchema.members, member.toMap());
        }
        await batch.commit(noResult: true);
        _log.info('Inserted ${members.length} members');
      });

  @override
  Future<void> reorder(String committeeId, List<String> orderedMemberIds) =>
      _appDatabase.guardAsync('Could not change the turn order.', () async {
        if (orderedMemberIds.isEmpty) return;
        final DatabaseExecutor db = await _appDatabase.executor;

        // Two-phase update, needed because of UNIQUE(committee_id, turn_number).
        //
        // Phase 1 parks every row far outside the range of any legal turn number
        // so no intermediate state can collide. A *negative* park is not an
        // option here: the schema has `CHECK (turn_number > 0)` and SQLite
        // applies CHECK constraints per row on every single UPDATE, so a
        // negative intermediate value is rejected immediately.
        final int parkOffset = 1000000;
        await db.rawUpdate(
          'UPDATE ${DbSchema.members} SET turn_number = turn_number + ? WHERE committee_id = ?',
          <Object?>[parkOffset, committeeId],
        );

        // Phase 2 writes the final 1..N numbers, which cannot collide with the
        // parked values because they are all above [parkOffset].
        final Batch batch = db.batch();
        final int now = DateTime.now().millisecondsSinceEpoch;
        for (int index = 0; index < orderedMemberIds.length; index++) {
          batch.update(
            DbSchema.members,
            <String, Object?>{'turn_number': index + 1, 'updated_at': now},
            where: 'id = ? AND committee_id = ?',
            whereArgs: <Object?>[orderedMemberIds[index], committeeId],
          );
        }
        await batch.commit(noResult: true);
      });

  @override
  Future<void> deleteByCommittee(String committeeId) =>
      _appDatabase.guardAsync('Could not remove members.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        await db.delete(
          DbSchema.members,
          where: 'committee_id = ?',
          whereArgs: <Object?>[committeeId],
        );
      });

  /// Turns a raw SQLite constraint failure into a message a human can act on.
  AppException _translate(DatabaseException error, Member member) {
    final String text = error.toString().toLowerCase();
    if (text.contains('unique')) {
      return DuplicateException(
        'Turn number ${member.turnNumber} is already taken in this committee.',
        details: error.toString(),
      );
    }
    return DatabaseException('Could not save the member.', details: error.toString());
  }
}
