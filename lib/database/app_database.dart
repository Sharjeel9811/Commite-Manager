import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' hide DatabaseException;

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/utils/logger.dart';
import 'db_schema.dart';

/// Owns the SQLite connection and the schema lifecycle.
///
/// Repositories depend on this class **only** for a [Database] handle and a
/// transaction helper — no business rule lives here. That keeps this class at
/// exactly one responsibility: "talk to SQLite safely".
class AppDatabase {
  AppDatabase({DatabaseFactory? factory, this._overridePath})
    : _factory = factory ?? databaseFactory;

  static const AppLogger _log = AppLogger('AppDatabase');

  final DatabaseFactory _factory;
  final String? _overridePath;
  Database? _db;
  Completer<Database>? _opening;
  Transaction? _activeTransaction;

  /// The handle a repository should run its statement on.
  ///
  /// While a transaction is open this is the *transaction* itself, so every
  /// statement a repository issues — including a `batch()` — joins that
  /// transaction instead of racing it on a second connection. Outside a
  /// transaction it is simply the open database.
  ///
  /// Repositories therefore stay free of transaction plumbing (and of importing
  /// sqflite at all in their interfaces) while still being fully atomic.
  Future<DatabaseExecutor> get executor async => _activeTransaction ?? await database;

  /// Opens the database (idempotent, safe for concurrent callers).
  Future<Database> get database async {
    final Database? existing = _db;
    if (existing != null && existing.isOpen) return existing;

    // Two providers can ask for the database at the same time during startup;
    // the completer makes sure the file is only opened once.
    if (_opening != null) return _opening!.future;

    final Completer<Database> completer = Completer<Database>();
    _opening = completer;
    try {
      final Database opened = await _open();
      _db = opened;
      completer.complete(opened);
      return opened;
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      _log.error('Failed to open database', error, stackTrace);
      rethrow;
    } finally {
      _opening = null;
    }
  }

  Future<Database> _open() async {
    final String path =
        _overridePath ?? p.join(await _resolveDirectory(), AppConstants.databaseName);
    _log.info('Opening $path');
    return _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: AppConstants.databaseVersion,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<String> _resolveDirectory() async {
    // `getDatabasesPath()` returns the OS-approved location for databases.
    final String base = await _factory.getDatabasesPath();
    final String directory = p.join(base, AppConstants.databaseDirectoryName);
    await Directory(directory).create(recursive: true);
    return directory;
  }

  /// Foreign keys are OFF by default in SQLite — they must be switched on for
  /// every single connection, otherwise `ON DELETE CASCADE` silently does
  /// nothing and the data ends up inconsistent.
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    _log.info('Creating schema v$version');
    await db.transaction((Transaction txn) async {
      for (final String statement in DbSchema.createStatements) {
        await txn.execute(statement);
      }
    });
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Version 1 is the first public schema. Later versions append
    // `if (oldVersion < 2) { ... }` blocks here — this is the only method that
    // changes when the schema grows (Open/Closed in practice).
    _log.info('Migrating $oldVersion -> $newVersion');
    if (oldVersion < 1) {
      await _onCreate(db, newVersion);
    }
    if (oldVersion < 2) {
      // v2 records the PIN length so the lock screen can draw the right number
      // of dots. Each statement is independent, so one that has already been
      // applied (an interrupted upgrade) is skipped rather than failing.
      for (final String statement in DbSchema.upgrade1to2) {
        try {
          await db.execute(statement);
        } on DatabaseException catch (error) {
          _log.warn('Skipping "${_short(statement)}": ${error.message}');
        }
      }
    }
  }

  static String _short(String sql) =>
      sql.length <= 60 ? sql : '${sql.substring(0, 57)}...';

  /// Runs [action] inside a transaction.
  ///
  /// Multi-row writes (creating a committee writes committee + members +
  /// periods + payments + turns) always go through here: either **all** of the
  /// rows land, or none of them do.
  ///
  /// Re-entrant calls join the transaction that is already open instead of
  /// starting a second one, which is why services are free to compose each other
  /// without accidentally nesting transactions.
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    if (_activeTransaction != null) {
      return action(_activeTransaction!);
    }
    final Database db = await database;
    try {
      return await db.transaction<T>((Transaction txn) async {
        _activeTransaction = txn;
        try {
          return await action(txn);
        } finally {
          _activeTransaction = null;
        }
      });
    } on DatabaseException {
      rethrow;
    } catch (error) {
      _log.error('Transaction failed: $error');
      throw DatabaseException(
        'The database could not complete this operation. Nothing was saved.',
        details: error.toString(),
      );
    }
  }

  /// Wraps any unexpected driver error into a friendly [DatabaseException].
  T guard<T>(String userMessage, T Function() action) {
    try {
      return action();
    } on AppException {
      rethrow;
    } catch (error) {
      _log.error(userMessage, error);
      throw DatabaseException(userMessage, details: error.toString());
    }
  }

  Future<T> guardAsync<T>(String userMessage, Future<T> Function() action) async {
    try {
      return await action();
    } on AppException {
      rethrow;
    } catch (error) {
      _log.error(userMessage, error);
      throw DatabaseException(userMessage, details: error.toString());
    }
  }

  /// Closes the connection (used by tests and on logout).
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Deletes every table's rows. Used by "reset application data".
  Future<void> wipe() async {
    await transaction((Transaction txn) async {
      for (final String table in DbSchema.allTables) {
        await txn.delete(table);
      }
    });
  }
}
