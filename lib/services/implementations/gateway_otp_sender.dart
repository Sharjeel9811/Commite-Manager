import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/utils/logger.dart';
import '../interfaces/otp_sender.dart';

/// [OtpSender] backed by the self-hosted Node.js / Express / Nodemailer
/// gateway running on Render.com (or any public HTTPS host).
///
/// ### Endpoints used
///   POST /api/auth/send-otp    — request a new OTP email
///   POST /api/auth/verify-otp  — verify a submitted OTP
///
/// ### Security model
/// The OTP is generated and hashed on the server. The plaintext code travels
/// only inside the email Nodemailer sends; it is never in any API response.
/// Verification is also server-side, so a rooted phone cannot read or bypass
/// the code.
///
/// The `x-otp-key` header carries a shared secret baked into the APK at build
/// time via `--dart-define=OTP_GATEWAY_API_KEY=...`.  Its blast radius is
/// "someone can spam the send endpoint" — no user data is accessible through
/// this key.
class GatewayOtpSender implements OtpSender {
  GatewayOtpSender({
    http.Client? client,
    String? baseUrl,
    String? apiKey,
  })  : _client  = client  ?? http.Client(),
        _baseUrl = _normaliseBase(baseUrl ?? AppConfig.otpGatewayUrl),
        _apiKey  = apiKey  ?? AppConfig.otpGatewayApiKey;

  final http.Client _client;
  final String _baseUrl;
  final String _apiKey;

  static const AppLogger _log = AppLogger('GatewayOtpSender');

  @override
  String get deliveryDescription =>
      'Sent by email through the Committee Manager cloud gateway (HTTPS)';

  // ─────────────────────────────────────────────── URL helpers

  static String _normaliseBase(String url) {
    final String trimmed = url.trim();
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  Uri get _sendEndpoint   => Uri.parse('$_baseUrl/api/auth/send-otp');
  Uri get _verifyEndpoint => Uri.parse('$_baseUrl/api/auth/verify-otp');

  Map<String, String> get _headers => <String, String>{
    'content-type': 'application/json',
    if (_apiKey.isNotEmpty) 'x-otp-key': _apiKey,
  };

  // ─────────────────────────────────────────────── OtpSender interface

  @override
  Future<OtpDeliveryResult> send({
    required String destination,
    required String purpose,
  }) async {
    if (_baseUrl.isEmpty) {
      return const OtpDeliveryResult(
        success: false,
        error: 'The OTP gateway URL is not configured. '
            'Rebuild with --dart-define=OTP_GATEWAY_URL=https://...',
      );
    }

    try {
      final http.Response response = await _client
          .post(
            _sendEndpoint,
            headers: _headers,
            body: jsonEncode(<String, String>{'email': destination}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200 || response.statusCode == 201) {
        _log.info('OTP send accepted by gateway for ${_mask(destination)}');
        return const OtpDeliveryResult(success: true);
      }

      return OtpDeliveryResult(
        success: false,
        error: _friendlyError(response),
      );
    } on TimeoutException {
      _log.error('Gateway send timed out for ${_mask(destination)}');
      return const OtpDeliveryResult(
        success: false,
        error: 'The verification service did not respond. Please try again.',
      );
    } on Exception catch (e) {
      _log.error('Gateway send failed', e);
      return const OtpDeliveryResult(
        success: false,
        error: 'Could not reach the verification service. Check your connection.',
      );
    }
  }

  @override
  Future<OtpVerificationResult> verify({
    required String destination,
    required String code,
  }) async {
    if (_baseUrl.isEmpty) {
      return const OtpVerificationResult(
        success: false,
        error: 'The OTP gateway URL is not configured.',
      );
    }

    try {
      final http.Response response = await _client
          .post(
            _verifyEndpoint,
            headers: _headers,
            body: jsonEncode(<String, String>{
              'email': destination,
              'otp':   code.trim(),
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        _log.info('OTP verified by gateway for ${_mask(destination)}');
        final Object? decoded = jsonDecode(response.body);
        final String? token = decoded is Map<String, Object?> ? decoded['accessToken'] as String? : null;
        return OtpVerificationResult(success: true, accessToken: token);
      }

      return OtpVerificationResult(
        success: false,
        error: _friendlyError(response),
      );
    } on TimeoutException {
      _log.error('Gateway verify timed out for ${_mask(destination)}');
      return const OtpVerificationResult(
        success: false,
        error: 'The verification service did not respond. Please try again.',
      );
    } on Exception catch (e) {
      _log.error('Gateway verify failed', e);
      return const OtpVerificationResult(
        success: false,
        error: 'Could not reach the verification service. Check your connection.',
      );
    }
  }

  // ─────────────────────────────────────────────── Helpers

  /// Extracts a safe user-facing message from the server response.
  /// Raw provider errors (SMTP auth, etc.) are never exposed to the UI.
  String _friendlyError(http.Response response) {
    if (response.statusCode == 429) {
      return 'Too many attempts. Please wait a minute and try again.';
    }
    if (response.statusCode == 401) {
      return 'The verification service is not configured correctly. '
          'Contact the developer.';
    }
    try {
      final Object? body = jsonDecode(response.body);
      if (body is Map<String, Object?>) {
        final Object? msg = body['error'];
        if (msg is String && msg.isNotEmpty && !_looksInternal(msg)) {
          return msg;
        }
      }
    } on FormatException {
      // Non-JSON — fall through
    }
    return 'The verification code could not be sent. Please try again.';
  }

  /// Heuristic: suppress any message that looks like a deployment/config error.
  bool _looksInternal(String message) => RegExp(
    r'\.env|\bMAIL_[A-Z_]+|\bSMTP_[A-Z_]+|\bOTP_SECRET\b|process\.env|ECONNREFUSED',
  ).hasMatch(message);

  String _mask(String email) {
    final int at = email.indexOf('@');
    if (at <= 0) return '***';
    final String name = email.substring(0, at);
    final String head = name.substring(0, name.length < 2 ? name.length : 2);
    return '$head***${email.substring(at)}';
  }
}
