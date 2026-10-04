import 'package:shared_preferences/shared_preferences.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/logger.dart';
import '../../models/app_settings.dart';
import '../../models/enums.dart';
import '../interfaces/settings_repository.dart';

/// [SettingsRepository] backed by `SharedPreferences`.
///
/// This is a second, concrete implementation of the same abstraction the app
/// uses for financial data — a live demonstration of Liskov Substitution: the
/// providers cannot tell which one they were given.
class SharedPreferencesSettingsRepository implements SettingsRepository {
  SharedPreferences? _prefs;
  Future<void> _saveQueue = Future<void>.value();

  static const AppLogger _log = AppLogger('SettingsRepo');

  static const String _keyTheme = 'settings.theme';
  static const String _keyNotifications = 'settings.notifications';
  static const String _keyReminderHour = 'settings.reminder_hour';
  static const String _keyCurrencyCode = 'settings.currency_code';
  static const String _keyCurrencySymbol = 'settings.currency_symbol';
  static const String _keyCurrencyDecimals = 'settings.currency_decimals';
  static const String _keyLockEnabled = 'settings.lock_enabled';
  static const String _keyLockTimeout = 'settings.lock_timeout';
  static const String _keyWelcome = 'settings.seen_welcome';
  static const String _keySampleData = 'settings.sample_data';
  static const String _keyLanguage = 'settings.language';

  Future<SharedPreferences> get _instance async =>
      _prefs ??= await SharedPreferences.getInstance();

  @override
  Future<AppSettings> load() =>
      _guard('Could not load your preferences.', () async {
        final SharedPreferences prefs = await _instance;
        return AppSettings(
          themePreference: AppThemePreference.fromStorage(
            prefs.getString(_keyTheme),
          ),
          notificationsEnabled: prefs.getBool(_keyNotifications) ?? true,
          dailyReminderHour: prefs.getInt(_keyReminderHour) ?? 9,
          currencyCode: prefs.getString(_keyCurrencyCode) ?? 'PKR',
          currencySymbol: prefs.getString(_keyCurrencySymbol) ?? 'Rs',
          currencyDecimals: prefs.getInt(_keyCurrencyDecimals) ?? 0,
          lockEnabled: prefs.getBool(_keyLockEnabled) ?? true,
          lockTimeoutMinutes: prefs.getInt(_keyLockTimeout) ?? 5,
          hasSeenWelcome: prefs.getBool(_keyWelcome) ?? false,
          sampleDataLoaded: prefs.getBool(_keySampleData) ?? false,
          language: AppLanguage.fromStorage(prefs.getString(_keyLanguage)),
        );
      });

  @override
  Future<void> save(AppSettings settings) {
    final Future<void> operation = _saveQueue.then<void>(
      (_) => _guard('Could not save your preferences.', () async {
        final SharedPreferences prefs = await _instance;
        await Future.wait(<Future<bool>>[
          prefs.setString(_keyTheme, settings.themePreference.name),
          prefs.setBool(_keyNotifications, settings.notificationsEnabled),
          prefs.setInt(_keyReminderHour, settings.dailyReminderHour),
          prefs.setString(_keyCurrencyCode, settings.currencyCode),
          prefs.setString(_keyCurrencySymbol, settings.currencySymbol),
          prefs.setInt(_keyCurrencyDecimals, settings.currencyDecimals),
          prefs.setBool(_keyLockEnabled, settings.lockEnabled),
          prefs.setInt(_keyLockTimeout, settings.lockTimeoutMinutes),
          prefs.setBool(_keyWelcome, settings.hasSeenWelcome),
          prefs.setBool(_keySampleData, settings.sampleDataLoaded),
          prefs.setString(_keyLanguage, settings.language.code),
        ]);
        _log.info('Settings saved');
      }),
    );
    _saveQueue = operation.catchError((Object _) {});
    return operation;
  }

  @override
  Future<void> reset() => _guard('Could not reset your preferences.', () async {
    final SharedPreferences prefs = await _instance;
    for (final String key in <String>[
      _keyTheme,
      _keyNotifications,
      _keyReminderHour,
      _keyCurrencyCode,
      _keyCurrencySymbol,
      _keyCurrencyDecimals,
      _keyLockEnabled,
      _keyLockTimeout,
      _keyWelcome,
      _keySampleData,
      _keyLanguage,
    ]) {
      await prefs.remove(key);
    }
  });

  /// Same "never leak a driver error to the user" policy as the SQLite repos.
  Future<T> _guard<T>(String message, Future<T> Function() action) async {
    try {
      return await action();
    } on AppException {
      rethrow;
    } catch (error) {
      _log.error(message, error);
      throw DatabaseException(message, details: error.toString());
    }
  }
}
