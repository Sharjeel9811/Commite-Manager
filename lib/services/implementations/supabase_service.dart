import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/config/app_config.dart';
import '../../core/utils/logger.dart';

/// A [sb.LocalStorage] that keeps the Supabase session inside the OS
/// keystore-backed secure storage instead of plaintext SharedPreferences.
class SecureSupabaseStorage extends sb.LocalStorage {
  SecureSupabaseStorage();

  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: false,
    ),
  );

  static const String _sessionKey = 'supabase.session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => (await _secure.read(key: _sessionKey))?.isNotEmpty ?? false;

  @override
  Future<String?> accessToken() => _secure.read(key: _sessionKey);

  @override
  Future<void> removePersistedSession() => _secure.delete(key: _sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _secure.write(key: _sessionKey, value: persistSessionString);
}

/// Throws when Supabase is used but never configured at build time.
class SupabaseNotConfiguredException implements Exception {
  const SupabaseNotConfiguredException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Owns the one Supabase client and the people-facing auth flows it performs.
///
/// The app's committee data stays in local SQLite; Supabase is used to prove
/// that the person registering owns the email address they typed. Keeping every
/// call behind this class means the rest of the app never imports `supabase_flutter`
/// directly, so swapping providers later touches exactly one file.
class SupabaseService {
  const SupabaseService._();

  static const AppLogger _log = AppLogger('SupabaseService');

  /// Whether a valid build-time configuration exists.
  static bool get isConfigured => AppConfig.supabaseConfigured;

  /// Initialises the shared client. Safe to call once from the app's start-up
  /// path; subsequent calls are a no-op because `Supabase.initialize` skips
  /// re-initialisation internally. Deliberately not invoked during unit tests,
  /// which run without `--dart-define` values and use fake senders.
  ///
  /// Must be called during [main] / [ServiceLocator.wire] **before** any OTP
  /// send or verify attempt, so that the Supabase client is ready by the time
  /// the first frame lands on the verify screen.
  static Future<void> ensureInitialized() async {
    if (!isConfigured) {
      throw const SupabaseNotConfiguredException(
        'This build has no Supabase project configured. '
        'Rebuild with --dart-define=SUPABASE_URL=https://xxxx.supabase.co '
        '--dart-define=SUPABASE_ANON_KEY=your-public-anon-key',
      );
    }
    // Supabase.initialize is idempotent — calling it a second time is a no-op,
    // so it is safe to call unconditionally during every start-up path.
    await sb.Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
      authOptions: sb.FlutterAuthClientOptions(
        localStorage: SecureSupabaseStorage(),
        detectSessionInUri: false,
      ),
    );
  }

  static sb.SupabaseClient get _client => sb.Supabase.instance.client;

  /// Sends the 6-digit email verification code to [email]. The code is
  /// generated and sent entirely on Supabase's side.
  static Future<void> sendEmailOtp(String email) async {
    await ensureInitialized();
    _log.info('Email OTP requested for $email');
    await _client.auth.signInWithOtp(email: email);
  }

  /// Asks Supabase whether [code] is the code it emailed to [email].
  ///
  /// On success the provider returns a session, which is persisted into secure
  /// storage by the [SecureSupabaseStorage] above. The session is not used to
  /// gate local app access — the PIN does that — but it is the identity that a
  /// future synchronising server would trust.
  static Future<void> verifyEmailOtp({
    required String email,
    required String code,
  }) async {
    await ensureInitialized();
    _log.info('Email OTP verification requested for $email');
    await _client.auth.verifyOTP(
      email: email,
      token: code,
      type: sb.OtpType.email,
    );
  }

  /// Ends the provider session when a user deletes their account.
  ///
  /// The app's own data (SQLite + preferences) is wiped by the caller; this is
  /// the provider-side half. `signOut` with a global scope revokes the refresh
  /// token so a copied session cannot be re-hydrated. The verification identity
  /// itself cannot be removed from the client — that can only be done with the
  /// server secret key from a trusted backend, which the app must never hold.
  static Future<void> deleteIdentity() async {
    if (!isConfigured) return;
    await ensureInitialized();
    try {
      await _client.auth.signOut(scope: sb.SignOutScope.global);
    } on Exception catch (error) {
      // No session is a normal case here (e.g. verification-only account).
      _log.info('Sign-out during deletion had nothing to revoke (ignored): $error');
    }
  }

  /// Maps a Supabase [sb.AuthException] to a safe, user-facing sentence.
  static String friendlyMessage(sb.AuthException error, {required String action}) {
    final String code = error.code ?? '';
    final String lower = '${error.message} $code';
    if (lower.contains('email address') && lower.contains('invalid')) {
      return 'That email address was not accepted. Please check it and try again.';
    }
    if (code == 'rate_limit' ||
        lower.contains('rate limit') ||
        lower.contains('too many')) {
      return 'Too many attempts. Please wait a minute and try again.';
    }
    if (lower.contains('expired') || lower.contains('invalid token') || code == 'otp_expired') {
      return 'That code is not valid or has expired. Request a new code.';
    }
    if (lower.contains('network') || lower.contains('failed to fetch')) {
      return 'Could not reach the verification service. Check your connection and try again.';
    }
    // No raw internals; the fallback is deliberately generic.
    return 'The verification service could not $action right now. Please try again.';
  }
}