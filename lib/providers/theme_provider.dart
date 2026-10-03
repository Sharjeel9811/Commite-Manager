import 'package:flutter/material.dart';

import '../core/utils/logger.dart';
import '../models/app_settings.dart';
import '../models/enums.dart';
import '../repositories/interfaces/settings_repository.dart';

/// Owns the light/dark theme decision.
///
/// A provider is a *state holder* — it never talks to SQLite and never formats
/// money. It asks [SettingsRepository], which is an interface, and exposes
/// plain getters to the widget tree.
class ThemeProvider extends ChangeNotifier {
  ThemeProvider({required SettingsRepository settingsRepository}) : _settings = settingsRepository {
    _settings = settingsRepository;
  }

  SettingsRepository _settings;
  AppSettings _preferences = const AppSettings();

  static const AppLogger _log = AppLogger('ThemeProvider');

  AppSettings get preferences => _preferences;

  ThemeMode get themeMode => _preferences.themePreference.themeMode;

  AppThemePreference get preference => _preferences.themePreference;

  bool get isDark => themeMode == ThemeMode.dark;

  Future<void> load() async {
    _preferences = await _settings.load();
    notifyListeners();
  }

  Future<void> setPreference(AppThemePreference value) async {
    _preferences = _preferences.copyWith(themePreference: value);
    notifyListeners();
    await _settings.save(_preferences);
  }

  /// Flips between light and dark, leaving "follow system" behind.
  Future<void> toggleDark() async {
    final bool currentlyDark = themeMode == ThemeMode.dark;
    await setPreference(currentlyDark ? AppThemePreference.light : AppThemePreference.dark);
  }

  /// Called by the settings screen when the repository itself is swapped.
  void useRepository(SettingsRepository repository) {
    _settings = repository;
  }

  /// Exposed so `AppBootstrap` can push a freshly loaded [AppSettings] in.
  void applySettings(AppSettings settings) {
    _preferences = settings;
    notifyListeners();
  }

  void handleError(Object error) {
    _log.error('Theme operation failed', error);
  }
}
