import 'package:sqflite/sqflite.dart' hide DatabaseException;

import '../../core/utils/logger.dart';
import '../../database/app_database.dart';
import '../../database/db_schema.dart';
import '../../models/payment_schedule.dart';
import '../interfaces/schedule_repository.dart';

/// SQLite implementation of [ScheduleRepository].
class SqliteScheduleRepository implements ScheduleRepository {
  const SqliteScheduleRepository(this._appDatabase);

  final AppDatabase _appDatabase;
  static const AppLogger _log = AppLogger('ScheduleRepo');

  @override
  Future<List<PaymentSchedule>> getByCommittee(String committeeId) =>
      _appDatabase.guardAsync('Could not load the collection periods.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.schedules,
          where: 'committee_id = ?',
          whereArgs: <Object?>[committeeId],
          orderBy: 'period_number ASC',
        );
        return rows.map(PaymentSchedule.fromMap).toList(growable: false);
      });

  @override
  Future<PaymentSchedule?> getByPeriod(String committeeId, int periodNumber) =>
      _appDatabase.guardAsync('Could not find that period.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.schedules,
          where: 'committee_id = ? AND period_number = ?',
          whereArgs: <Object?>[committeeId, periodNumber],
          limit: 1,
        );
        return rows.isEmpty ? null : PaymentSchedule.fromMap(rows.first);
      });

  @override
  Future<PaymentSchedule?> getById(String id) =>
      _appDatabase.guardAsync('Could not find that period.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.schedules,
          where: 'id = ?',
          whereArgs: <Object?>[id],
          limit: 1,
        );
        return rows.isEmpty ? null : PaymentSchedule.fromMap(rows.first);
      });

  @override
  Future<void> insertAll(List<PaymentSchedule> schedules) =>
      _appDatabase.guardAsync('Could not build the collection schedule.', () async {
        if (schedules.isEmpty) return;
        final DatabaseExecutor db = await _appDatabase.executor;
        final Batch batch = db.batch();
        for (final PaymentSchedule schedule in schedules) {
          batch.insert(
            DbSchema.schedules,
            schedule.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        await batch.commit(noResult: true);
        _log.info('Generated ${schedules.length} periods');
      });

  @override
  Future<void> closePeriod(String scheduleId) => _setClosed(scheduleId, true);

  @override
  Future<void> reopenPeriod(String scheduleId) => _setClosed(scheduleId, false);

  Future<void> _setClosed(String scheduleId, bool closed) =>
      _appDatabase.guardAsync('Could not update the period.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final int rows = await db.update(
          DbSchema.schedules,
          <String, Object?>{'is_closed': closed ? 1 : 0},
          where: 'id = ?',
          whereArgs: <Object?>[scheduleId],
        );
        if (rows == 0) {
          throw StateError('Schedule $scheduleId not found while closing.');
        }
      });

  @override
  Future<PaymentSchedule?> getNextOpen(String committeeId, DateTime asOf) =>
      _appDatabase.guardAsync('Could not find the current period.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.schedules,
          where: 'committee_id = ? AND is_closed = 0',
          whereArgs: <Object?>[committeeId],
          orderBy: 'period_number ASC',
        );
        for (final Map<String, Object?> row in rows) {
          final PaymentSchedule schedule = PaymentSchedule.fromMap(row);
          if (!schedule.dueDate.isBefore(asOf)) return schedule;
        }
        return rows.isEmpty ? null : PaymentSchedule.fromMap(rows.first);
      });

  @override
  Future<void> deleteByCommittee(String committeeId) =>
      _appDatabase.guardAsync('Could not clear periods.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        await db.delete(
          DbSchema.schedules,
          where: 'committee_id = ?',
          whereArgs: <Object?>[committeeId],
        );
      });

  @override
  Future<int> countByCommittee(String committeeId) =>
      _appDatabase.guardAsync('Could not count periods.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM ${DbSchema.schedules} WHERE committee_id = ?',
          <Object?>[committeeId],
        );
        return Sqflite.firstIntValue(rows) ?? 0;
      });
}
