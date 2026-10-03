/// The outcome of "we tried to have a code delivered".
class OtpDeliveryResult {
  const OtpDeliveryResult({required this.success, this.error});

  final bool success;

  /// A safe, user-facing explanation shown when [success] is false. It must not
  /// contain a provider's raw error, because those can echo back credentials.
  final String? error;
}

/// The outcome of "we asked the provider to check a submitted code".
class OtpVerificationResult {
  const OtpVerificationResult({required this.success, this.error});

  final bool success;

  /// Safe, user-facing text when [success] is false.
  final String? error;
}

/// Delivers and verifies one-time passwords.
///
/// The provider owns the code: `send` asks the provider to email a code to
/// [destination], and `verify` asks the provider whether the submitted code is
/// the one it sent. The plaintext code is *never* generated, produced or seen
/// by the app, so a code cannot be read out of the device or shown on screen.
///
/// ### Liskov Substitution / Dependency Inversion
/// [OtpService] depends on **this interface only**, so pointing the app at a
/// different provider (Supabase Auth today, another service tomorrow, a test
/// double in unit tests) never requires editing the auth flow.
abstract interface class OtpSender {
  /// Human readable description of where codes end up, shown in Settings.
  String get deliveryDescription;

  /// Asks the provider to send a verification code to [destination].
  Future<OtpDeliveryResult> send({
    required String destination,
    required String purpose,
  });

  /// Asks the provider whether [code] matches the one sent to [destination].
  Future<OtpVerificationResult> verify({
    required String destination,
    required String code,
  });
}