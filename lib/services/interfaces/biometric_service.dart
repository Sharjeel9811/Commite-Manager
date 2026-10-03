/// Device capability check for fingerprint / face unlock.
///
/// Abstracted for the same reason as [NotificationService]: the app depends on
/// the *capability*, not on `local_auth`.
abstract interface class BiometricService {
  /// True when the device has usable biometrics AND the app is allowed to use them.
  Future<bool> isAvailable();

  /// Human readable list of the enrolled modalities ("Fingerprint", "Face").
  Future<List<String>> availableTypes();

  /// Shows the system prompt.
  ///
  /// Returns true only when authentication succeeded. Never throws for a normal
  /// user cancel — the caller simply shows "authentication failed".
  Future<bool> authenticate({required String reason});
}
