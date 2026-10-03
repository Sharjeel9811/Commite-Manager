import '../../models/app_settings.dart';

/// Persistence contract for user preferences.
///
/// A test double or a future "sync settings to the cloud" implementation can
/// replace this without any screen noticing.
abstract interface class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
  Future<void> reset();
}
