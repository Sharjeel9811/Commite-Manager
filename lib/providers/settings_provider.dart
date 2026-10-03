import 'package:flutter/foundation.dart';

import '../core/errors/app_exception.dart';
import '../core/utils/currency_formatter.dart';
import '../core/utils/logger.dart';
import '../models/app_settings.dart';
import '../models/enums.dart';
import '../repositories/interfaces/settings_repository.dart';
import '../services/auth_service.dart';
import '../services/demo_data_service.dart';
import '../services/interfaces/notification_service.dart';
import '../services/reminder_service.dart';
import 'auth_provider.dart';
import 'theme_provider.dart';

/// Preferences + notification control.
///
/// Note what it does *not* do: it never computes money and never queries
/// committees. It only persists choices and asks [ReminderService] to rebuild
/// the schedule when the notification switch changes.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider({
    required SettingsRepository settingsRepository,
    required ReminderService reminderService,
    required NotificationService notificationService,
    required DemoDataService demoDataService,
    required AuthService authService,
    ThemeProvider? themeProvider,
    AuthProvider? authProvider,
  }) : _settings = settingsRepository,
       _reminders = reminderService,
       _notifications = notificationService,
       _demo = demoDataService,
       _auth = authService,
       _theme = themeProvider,
       _authProvider = authProvider;

  final SettingsRepository _settings;
  final ReminderService _reminders;
  final NotificationService _notifications;
  final DemoDataService _demo;
  final AuthService _auth;

  /// The app's theme is owned by [ThemeProvider] (that is what `MaterialApp`
  /// watches). Holding a reference is what makes the switch in Settings take
  /// effect immediately instead of only after the next launch.
  final ThemeProvider? _theme;

  /// `AuthProvider` holds its own copy of the preferences, loaded once at
  /// bootstrap. Security settings are forwarded so that turning the PIN on, or
  /// changing the idle timeout, takes effect in the current session instead of
  /// only after a restart.
  final AuthProvider? _authProvider;

  static const AppLogger _log = AppLogger('SettingsProvider');

  AppSettings _preferences = const AppSettings();
  AppSettings get preferences => _preferences;

  bool _notificationsAllowed = true;
  bool get notificationsAllowed => _notificationsAllowed;

  bool _busy = false;
  bool get isBusy => _busy;

  int _scheduledCount = 0;
  int get scheduledCount => _scheduledCount;

  /// How verification codes reach the user, for display in Settings.
  String get otpDeliveryDescription => _auth.otpDeliveryDescription;

  Future<void> load() async {
    _preferences = await _settings.load();
    // Keep the live theme in step with what was just read from disk, so a
    // restart restores the chosen appearance before the first frame.
    _theme?.applySettings(_preferences);
    // Same for security: a PIN enabled just before the process died must still
    // be active on the next run.
    _authProvider?.applySecurityPreferences(_preferences);
    _applyCurrency();
    await _refreshPermission();
    notifyListeners();
  }

  // ------------------------------------------------------------------ Theme

  Future<void> setTheme(AppThemePreference preference) async {
    _preferences = _preferences.copyWith(themePreference: preference);
    notifyListeners();
    // `MaterialApp` reads `ThemeProvider`, so the change has to travel through
    // it. It also persists, so the write is not repeated here.
    final ThemeProvider? theme = _theme;
    if (theme != null) {
      await theme.setPreference(preference);
      return;
    }
    await _settings.save(_preferences);
  }

  // ------------------------------------------------------------ Notifications

  Future<void> setNotificationsEnabled(bool value) async {
    _preferences = _preferences.copyWith(notificationsEnabled: value);
    notifyListeners();
    await _settings.save(_preferences);
    if (value) {
      await _notifications.requestPermission();
      await _reminders.rescheduleAll();
    } else {
      await _notifications.cancelAll();
      _scheduledCount = 0;
    }
    notifyListeners();
  }

  Future<void> setReminderHour(int hour) async {
    _preferences = _preferences.copyWith(dailyReminderHour: hour);
    notifyListeners();
    await _settings.save(_preferences);
    await _reminders.rescheduleAll();
  }

  Future<void> refreshScheduledCount() async {
    _scheduledCount = (await _notifications.pendingIds()).length;
    notifyListeners();
  }

  // --------------------------------------------------------------- Security

  /// Pushes the current preferences into `AuthProvider` and persists them.
  ///
  /// Enabling the PIN has to reach the running session, otherwise
  /// `AuthProvider.lock()` keeps reading the bootstrap value and does nothing
  /// until the app is restarted.
  Future<void> _applySecurity() async {
    _authProvider?.applySecurityPreferences(_preferences);
    await _settings.save(_preferences);
  }

  Future<void> setLockEnabled(bool value) async {
    _preferences = _preferences.copyWith(lockEnabled: value);
    notifyListeners();
    await _applySecurity();
  }

  Future<void> setLockTimeout(int minutes) async {
    _preferences = _preferences.copyWith(lockTimeoutMinutes: minutes);
    notifyListeners();
    await _applySecurity();
  }

  // --------------------------------------------------------------- Currency

  Future<void> setCurrency({required String code, required String symbol, int? decimals}) async {
    _preferences = _preferences.copyWith(
      currencyCode: code,
      currencySymbol: symbol,
      currencyDecimals: decimals,
    );
    _applyCurrency();
    notifyListeners();
    await _settings.save(_preferences);
  }

  // -------------------------------------------------------------- Welcome

  Future<void> markWelcomeSeen() async {
    if (_preferences.hasSeenWelcome) return;
    _preferences = _preferences.copyWith(hasSeenWelcome: true);
    await _settings.save(_preferences);
    notifyListeners();
  }

  // ------------------------------------------------------------- Sample data

  Future<String?> loadSampleData() async {
    _busy = true;
    notifyListeners();
    try {
      final int created = await _demo.loadSampleCommittees();
      _preferences = _preferences.copyWith(sampleDataLoaded: true);
      await _settings.save(_preferences);
      return '$created sample committee(s) added.';
    } catch (error) {
      _log.error('Could not load sample data', error);
      return describeError(error);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<String?> removeSampleData() async {
    _busy = true;
    notifyListeners();
    try {
      final int removed = await _demo.removeSampleCommittees();
      _preferences = _preferences.copyWith(sampleDataLoaded: false);
      await _settings.save(_preferences);
      return removed == 0
          ? 'There was no sample data to remove.'
          : '$removed sample committee(s) removed.';
    } catch (error) {
      _log.error('Could not remove sample data', error);
      return describeError(error);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  bool get hasSampleData => _preferences.sampleDataLoaded;

  /// Wipes every committee — only reachable behind a typed confirmation.
  Future<String?> eraseAllCommittees() async {
    _busy = true;
    notifyListeners();
    try {
      await _demo.removeEverything();
      return 'All committees were deleted.';
    } catch (error) {
      _log.error('Could not erase committees', error);
      return describeError(error);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> resetPreferences() async {
    await _settings.reset();
    _preferences = const AppSettings();
    _applyCurrency();
    notifyListeners();
  }

  // ------------------------------------------------------------------ Helpers

  void _applyCurrency() => CurrencyFormatter.configure(
    symbol: _preferences.currencySymbol,
    code: _preferences.currencyCode,
    decimals: _preferences.currencyDecimals,
  );

  Future<void> _refreshPermission() async {
    _notificationsAllowed = await _notifications.hasPermission();
  }

  @override
  void dispose() {
    _notifications.cancelAll();
    super.dispose();
  }
}
