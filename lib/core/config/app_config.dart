/// Values that differ per environment and must be decided at **build** time.
///
/// ## How build-time injection works
///
/// Every value here comes from `--dart-define=KEY=VALUE` passed to
/// `flutter build` or `flutter run`.  Nothing is hard-coded in source, so
/// secrets never appear in the git repository.
///
/// ### Play Store / production build (uses Supabase Auth for OTP)
/// ```powershell
/// flutter build appbundle --release `
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co `
///   --dart-define=SUPABASE_ANON_KEY=eyJ...
/// ```
///
/// ### Production build with self-hosted gateway (Render.com)
/// ```powershell
/// flutter build appbundle --release `
///   --dart-define=OTP_GATEWAY_URL=https://committee-manager-otp.onrender.com `
///   --dart-define=OTP_GATEWAY_API_KEY=your-api-key
/// ```
///
/// ### Local development (gateway on your PC)
/// ```powershell
/// flutter run `
///   --dart-define=OTP_GATEWAY_URL=http://10.0.2.2:4000 `
///   --dart-define=OTP_GATEWAY_API_KEY=
/// ```
/// (10.0.2.2 is the Android emulator's alias for localhost.
///  For a real phone on the same LAN use your PC's LAN IP — development only.)
///
/// Nothing in this file is a private credential.
class AppConfig {
  const AppConfig._();

  // ─────────────────────────────────────────────────────────────── Supabase
  /// Supabase project URL, injected at build time.
  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL');

  /// Supabase public anon key, injected at build time.
  /// This is a *public* key — safe to ship in an APK.
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// True when a Supabase project has been wired in at build time.
  static bool get supabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  // ──────────────────────────────────────────────── Self-hosted OTP gateway
  /// Base URL of the production gateway, e.g.
  /// `https://committee-manager-otp.onrender.com`
  ///
  /// For local development you can temporarily pass
  /// `--dart-define=OTP_GATEWAY_URL=http://10.0.2.2:4000`
  /// but NEVER ship a build with a LAN/localhost URL to the Play Store.
  static const String otpGatewayUrl =
      String.fromEnvironment('OTP_GATEWAY_URL');

  /// Shared secret sent in `x-otp-key`.  Safe to ship in the APK because its
  /// blast radius is "someone can spam your OTP email endpoint" — not "someone
  /// can read user data".  Rotate it if you publish a build you regret.
  static const String otpGatewayApiKey =
      String.fromEnvironment('OTP_GATEWAY_API_KEY');

  /// True when the self-hosted gateway URL has been supplied at build time.
  static bool get otpGatewayConfigured =>
      otpGatewayUrl.trim().isNotEmpty;

  /// Whether to use the self-hosted gateway transport.
  ///
  /// Priority:  gateway  >  Supabase Auth  >  neither (shows config error).
  static bool get useOtpGateway => otpGatewayConfigured;
}
