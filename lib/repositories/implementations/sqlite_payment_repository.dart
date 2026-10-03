import 'package:sqflite/sqflite.dart' hide DatabaseException;

import '../../core/errors/app_exception.dart';
import '../../core/utils/logger.dart';
import '../../database/app_database.dart';
import '../../database/db_schema.dart';
import '../../models/payment.dart';
import '../interfaces/payment_repository.dart';

/// SQLite implementation of [PaymentRepository].
///
/// The duplicate-payment rule is enforced in **two** places:
///  1. here, with an explicit check that returns a friendly message, and
///  2. in the schema, with `UNIQUE (committee_id, member_id, period_number)`.
/// Layer 2 is the one that actually guarantees correctness under concurrency.
class SqlitePaymentRepository implements PaymentRepository {
  const SqlitePaymentRepository(this._appDatabase);

  final AppDatabase _appDatabase;
  static const AppLogger _log = AppLogger('PaymentRepo');

  @override
  Future<List<Payment>> getByCommittee(String committeeId) =>
      _appDatabase.guardAsync('Could not load the payments.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.payments,
          where: 'committee_id = ?',
          whereArgs: <Object?>[committeeId],
          orderBy: 'period_number ASC, member_id ASC',
        );
        return rows.map(Payment.fromMap).toList(growable: false);
      });

  @override
  Future<List<Payment>> getByPeriod(String committeeId, int periodNumber) =>
      _appDatabase.guardAsync('Could not load this period.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.payments,
          where: 'committee_id = ? AND period_number = ?',
          whereArgs: <Object?>[committeeId, periodNumber],
        );
        return rows.map(Payment.fromMap).toList(growable: false);
      });

  @override
  Future<List<Payment>> getByMember(String memberId) =>
      _appDatabase.guardAsync('Could not load this member\'s history.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.payments,
          where: 'member_id = ?',
          whereArgs: <Object?>[memberId],
          orderBy: 'period_number ASC',
        );
        return rows.map(Payment.fromMap).toList(growable: false);
      });

  @override
  Future<Payment?> getById(String id) =>
      _appDatabase.guardAsync('Could not load the payment.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.payments,
          where: 'id = ?',
          whereArgs: <Object?>[id],
          limit: 1,
        );
        return rows.isEmpty ? null : Payment.fromMap(rows.first);
      });

  @override
  Future<Payment?> find(String committeeId, String memberId, int periodNumber) =>
      _appDatabase.guardAsync('Could not look up the payment.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final List<Map<String, Object?>> rows = await db.query(
          DbSchema.payments,
          where: 'committee_id = ? AND member_id = ? AND period_number = ?',
          whereArgs: <Object?>[committeeId, memberId, periodNumber],
          limit: 1,
        );
        return rows.isEmpty ? null : Payment.fromMap(rows.first);
      });

  @override
  Future<String> insert(Payment payment) =>
      _appDatabase.guardAsync('Could not record the payment.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        try {
          await db.insert(
            DbSchema.payments,
            payment.toMap(),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        } on DatabaseException catch (error) {
          throw _translate(error, payment);
        }
        return payment.id;
      });

  @override
  Future<void> insertAll(List<Payment> payments) =>
      _appDatabase.guardAsync('Could not set up the payment schedule.', () async {
        if (payments.isEmpty) return;
        final DatabaseExecutor db = await _appDatabase.executor;
        final Batch batch = db.batch();
        for (final Payment payment in payments) {
          // `ignore` makes generation idempotent: re-running the generator can
          // never create a duplicate or crash the app.
          batch.insert(
            DbSchema.payments,
            payment.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        await batch.commit(noResult: true);
        _log.info('Generated ${payments.length} payment rows');
      });

  @override
  Future<void> update(Payment payment) =>
      _appDatabase.guardAsync('Could not save the payment.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final int rows = await db.update(
          DbSchema.payments,
          payment.toMap(),
          where: 'id = ?',
          whereArgs: <Object?>[payment.id],
        );
        if (rows == 0) throw const NotFoundException('This payment record no longer exists.');
      });

  @override
  Future<void> markPaid(String paymentId, DateTime paidAt, {String? method, String? notes}) =>
      _appDatabase.guardAsync('Could not mark the payment as paid.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final int rows = await db.update(
          DbSchema.payments,
          <String, Object?>{
            'status': 'paid',
            'paid_date': paidAt.millisecondsSinceEpoch,
            'method': method,
            'notes': notes,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ? AND status = ?',
          whereArgs: <Object?>[paymentId, 'pending'],
        );
        if (rows == 0) {
          throw const DuplicateException(
            'This payment has already been recorded. Undo it first if you need to change it.',
          );
        }
      });

  @override
  Future<void> markUnpaid(String paymentId) =>
      _appDatabase.guardAsync('Could not undo the payment.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        final int rows = await db.update(
          DbSchema.payments,
          <String, Object?>{
            'status': 'pending',
            'paid_date': null,
            'method': null,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: <Object?>[paymentId],
        );
        if (rows == 0) throw const NotFoundException('This payment record no longer exists.');
      });

  @override
  Future<void> deleteById(String id) =>
      _appDatabase.guardAsync('Could not delete the payment.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        await db.delete(DbSchema.payments, where: 'id = ?', whereArgs: <Object?>[id]);
      });

  @override
  Future<void> deleteByCommittee(String committeeId) =>
      _appDatabase.guardAsync('Could not delete payments.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        await db.delete(
          DbSchema.payments,
          where: 'committee_id = ?',
          whereArgs: <Object?>[committeeId],
        );
      });

  // ------------------------------------------------------------------ Totals

  @override
  Future<double> sumPaid(String committeeId) => _sum(
    committeeId,
    "SELECT IFNULL(SUM(amount), 0) AS t FROM ${DbSchema.payments} "
    "WHERE committee_id = ? AND status = 'paid'",
  );

  @override
  Future<double> sumPending(String committeeId) => _sum(
    committeeId,
    "SELECT IFNULL(SUM(amount), 0) AS t FROM ${DbSchema.payments} "
    "WHERE committee_id = ? AND status = 'pending'",
  );

  @override
  Future<double> sumPaidAll() =>
      _sumAll("SELECT IFNULL(SUM(amount), 0) AS t FROM ${DbSchema.payments} WHERE status = 'paid'");

  @override
  Future<int> countPaid(String committeeId) => _count(
    "SELECT COUNT(*) AS c FROM ${DbSchema.payments} WHERE committee_id = ? AND status = 'paid'",
    <Object?>[committeeId],
  );

  @override
  Future<int> countPending(String committeeId) => _count(
    "SELECT COUNT(*) AS c FROM ${DbSchema.payments} WHERE committee_id = ? AND status = 'pending'",
    <Object?>[committeeId],
  );

  @override
  Future<int> countOverdue(String committeeId, DateTime asOf) => _count(
    "SELECT COUNT(*) AS c FROM ${DbSchema.payments} "
    "WHERE committee_id = ? AND status = 'pending' AND due_date < ?",
    <Object?>[committeeId, asOf.millisecondsSinceEpoch],
  );

  @override
  Future<int> countPaidInPeriod(String committeeId, int periodNumber) => _count(
    'SELECT COUNT(*) AS c FROM ${DbSchema.payments} '
    "WHERE committee_id = ? AND period_number = ? AND status = 'paid'",
    <Object?>[committeeId, periodNumber],
  );

  @override
  Future<int> countPendingInPeriod(String committeeId, int periodNumber) => _count(
    'SELECT COUNT(*) AS c FROM ${DbSchema.payments} '
    "WHERE committee_id = ? AND period_number = ? AND status = 'pending'",
    <Object?>[committeeId, periodNumber],
  );

  @override
  Future<double> sumPaidInPeriod(String committeeId, int periodNumber) => _sum(
    committeeId,
    'SELECT IFNULL(SUM(amount), 0) AS t FROM ${DbSchema.payments} '
    "WHERE committee_id = ? AND period_number = ? AND status = 'paid'",
    extraArgs: <Object?>[periodNumber],
  );

  @override
  Future<int> countByPeriod(String committeeId, int periodNumber) => _count(
    'SELECT COUNT(*) AS c FROM ${DbSchema.payments} WHERE committee_id = ? AND period_number = ?',
    <Object?>[committeeId, periodNumber],
  );

  @override
  Future<int> countAll() =>
      _count('SELECT COUNT(*) AS c FROM ${DbSchema.payments}', const <Object?>[]);
  @override
  Future<int> countPendingAll() => _count(
    "SELECT COUNT(*) AS c FROM ${DbSchema.payments} WHERE status = 'pending'",
    const <Object?>[],
  );

  @override
  Future<int> countOverdueAll(DateTime asOf) => _count(
    "SELECT COUNT(*) AS c FROM ${DbSchema.payments} "
    "WHERE status = 'pending' AND due_date < ?",
    <Object?>[asOf.millisecondsSinceEpoch],
  );

  @override
  Future<List<({int periodNumber, double total, DateTime dueDate})>> collectionByPeriod(
    String committeeId,
  ) => _collectionByPeriod(
    'SELECT period_number AS p, IFNULL(SUM(amount), 0) AS t, MIN(due_date) AS d '
    "FROM ${DbSchema.payments} WHERE committee_id = ? AND status = 'paid' "
    'GROUP BY period_number ORDER BY period_number ASC',
    <Object?>[committeeId],
  );

  @override
  Future<List<({int periodNumber, double total, DateTime dueDate})>> collectionByPeriodAll() =>
      _collectionByPeriod(
        'SELECT period_number AS p, IFNULL(SUM(amount), 0) AS t, MIN(due_date) AS d '
        "FROM ${DbSchema.payments} WHERE status = 'paid' "
        'GROUP BY committee_id, period_number ORDER BY d ASC',
        const <Object?>[],
      );

  // ----------------------------------------------------------------- Helpers

  Future<double> _sum(
    String committeeId,
    String sql, {
    List<Object?> extraArgs = const <Object?>[],
  }) async {
    final List<Map<String, Object?>> rows = await _run(sql, <Object?>[committeeId, ...extraArgs]);
    return ((rows.first['t'] as num?) ?? 0).toDouble();
  }

  Future<double> _sumAll(String sql) async {
    final List<Map<String, Object?>> rows = await _run(sql, const <Object?>[]);
    return ((rows.first['t'] as num?) ?? 0).toDouble();
  }

  Future<int> _count(String sql, List<Object?> args) async {
    final List<Map<String, Object?>> rows = await _run(sql, args);
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<List<({int periodNumber, double total, DateTime dueDate})>> _collectionByPeriod(
    String sql,
    List<Object?> args,
  ) async {
    final List<Map<String, Object?>> rows = await _run(sql, args);
    return rows
        .map(
          (Map<String, Object?> row) => (
            periodNumber: row['p']! as int,
            total: ((row['t'] as num?) ?? 0).toDouble(),
            dueDate: DateTime.fromMillisecondsSinceEpoch(row['d']! as int),
          ),
        )
        .toList(growable: false);
  }

  Future<List<Map<String, Object?>>> _run(String sql, List<Object?> args) =>
      _appDatabase.guardAsync('Could not read the payment totals.', () async {
        final DatabaseExecutor db = await _appDatabase.executor;
        return db.rawQuery(sql, args);
      });

  AppException _translate(DatabaseException error, Payment payment) {
    final String text = error.toString().toLowerCase();
    if (text.contains('unique')) {
      return const DuplicateException(
        'A payment for this member and period has already been recorded.',
      );
    }
    if (text.contains('foreign key')) {
      return const ValidationException('This payment refers to a record that no longer exists.');
    }
    return DatabaseException('Could not record the payment.', details: error.toString());
  }
}
