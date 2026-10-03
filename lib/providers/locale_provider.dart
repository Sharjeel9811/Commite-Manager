import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/enums.dart';
import '../repositories/interfaces/settings_repository.dart';

/// Owns the language / locale decision for the whole app.
///
/// Mirrors [ThemeProvider] in structure: it reads the persisted value once at
/// bootstrap, exposes a single [locale] getter that [MaterialApp] watches, and
/// writes back to [SettingsRepository] whenever the user switches language.
///
/// Keeping locale in its own provider (rather than folding it into
/// [SettingsProvider]) means [MaterialApp] can `Consumer<LocaleProvider>` and
/// rebuild only when the locale changes — heavy providers like
/// [CommitteeProvider] are not disturbed.
class LocaleProvider extends ChangeNotifier {
  LocaleProvider({required SettingsRepository settingsRepository})
      : _settings = settingsRepository;

  final SettingsRepository _settings;

  AppLanguage _language = AppLanguage.english;

  /// The [Locale] that [MaterialApp.locale] should use.
  Locale get locale => Locale(_language.code);

  /// The active language, for the Settings UI.
  AppLanguage get language => _language;

  /// Whether the current language is right-to-left (Urdu).
  bool get isRtl => _language == AppLanguage.urdu;

  /// Called once by [ServiceLocator] / bootstrap before the first frame.
  Future<void> load() async {
    final AppSettings settings = await _settings.load();
    _language = settings.language;
    notifyListeners();
  }

  /// Switches language, persists the choice, and notifies the widget tree so
  /// [MaterialApp] rebuilds with the new locale immediately.
  Future<void> setLanguage(AppLanguage language) async {
    if (_language == language) return;
    _language = language;
    notifyListeners();
    // Read → patch → write so we never overwrite unrelated settings fields.
    final AppSettings current = await _settings.load();
    await _settings.save(current.copyWith(language: language));
  }

  /// Called by [SettingsProvider.applySecurityPreferences] equivalent — lets
  /// the settings screen push a language change without going through load().
  void applySettings(AppSettings settings) {
    if (_language == settings.language) return;
    _language = settings.language;
    notifyListeners();
  }
}
