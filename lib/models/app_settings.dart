import 'enums.dart';

/// Small, strongly-typed key/value store for user preferences.
///
/// Preferences are *not* financial data, so they live in `SharedPreferences`
/// rather than in SQLite. They are still reached through a repository
/// interface, so the storage engine can be swapped without touching a widget.
class AppSettings {
  const AppSettings({
    this.themePreference = AppThemePreference.system,
    this.notificationsEnabled = true,
    this.dailyReminderHour = 9,
    this.currencyCode = 'PKR',
    this.currencySymbol = 'Rs',
    this.currencyDecimals = 0,
    this.lockEnabled = true,
    this.lockTimeoutMinutes = 5,
    this.hasSeenWelcome = false,
    this.sampleDataLoaded = false,
    this.language = AppLanguage.english,
  });

  final AppThemePreference themePreference;
  final bool notificationsEnabled;
  final int dailyReminderHour;
  final String currencyCode;
  final String currencySymbol;
  final int currencyDecimals;
  final bool lockEnabled;
  final int lockTimeoutMinutes;
  final bool hasSeenWelcome;
  final bool sampleDataLoaded;
  final AppLanguage language;

  AppSettings copyWith({
    AppThemePreference? themePreference,
    bool? notificationsEnabled,
    int? dailyReminderHour,
    String? currencyCode,
    String? currencySymbol,
    int? currencyDecimals,
    bool? lockEnabled,
    int? lockTimeoutMinutes,
    bool? hasSeenWelcome,
    bool? sampleDataLoaded,
    AppLanguage? language,
  }) => AppSettings(
    themePreference: themePreference ?? this.themePreference,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    dailyReminderHour: dailyReminderHour ?? this.dailyReminderHour,
    currencyCode: currencyCode ?? this.currencyCode,
    currencySymbol: currencySymbol ?? this.currencySymbol,
    currencyDecimals: currencyDecimals ?? this.currencyDecimals,
    lockEnabled: lockEnabled ?? this.lockEnabled,
    lockTimeoutMinutes: lockTimeoutMinutes ?? this.lockTimeoutMinutes,
    hasSeenWelcome: hasSeenWelcome ?? this.hasSeenWelcome,
    sampleDataLoaded: sampleDataLoaded ?? this.sampleDataLoaded,
    language: language ?? this.language,
  );
}
