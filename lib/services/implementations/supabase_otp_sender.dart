import '../../core/utils/logger.dart';
import '../interfaces/otp_sender.dart';
import 'supabase_service.dart';

/// [OtpSender] backed by Supabase Auth email OTP.
///
/// The provider generates the code, emails it, and checks it back in — the app
/// never sees, generates or stores the plaintext. This is the production
/// transport; there is deliberately no local HTTP gateway anymore.
class SupabaseOtpSender implements OtpSender {
  const SupabaseOtpSender();

  static const AppLogger _log = AppLogger('SupabaseOtpSender');

  @override
  String get deliveryDescription =>
      'Sent by email through Supabase (secure HTTPS)';

  @override
  Future<OtpDeliveryResult> send({
    required String destination,
    required String purpose,
  }) async {
    if (!SupabaseService.isConfigured) {
      _log.error('OTP send attempted with no Supabase configuration');
      return const OtpDeliveryResult(
        success: false,
        error: 'Email verification is not configured in this build. Contact the developer.',
      );
    }
    try {
      await SupabaseService.sendEmailOtp(destination);
      _log.info('OTP email accepted by Supabase for $destination');
      return const OtpDeliveryResult(success: true);
    } on Exception catch (error) {
      _log.error('Supabase OTP send failed', error);
      return OtpDeliveryResult(
        success: false,
        error: _friendlySendError(error),
      );
    }
  }

  @override
  Future<OtpVerificationResult> verify({
    required String destination,
    required String code,
  }) async {
    if (!SupabaseService.isConfigured) {
      return const OtpVerificationResult(
        success: false,
        error: 'Email verification is not configured in this build. Contact the developer.',
      );
    }
    try {
      await SupabaseService.verifyEmailOtp(email: destination, code: code);
      _log.info('OTP email verified by Supabase for $destination');
      return const OtpVerificationResult(success: true);
    } on Exception catch (error) {
      _log.error('Supabase OTP verification failed', error);
      return OtpVerificationResult(
        success: false,
        error: _friendlyVerifyError(error),
      );
    }
  }

  String _friendlySendError(Exception error) {
    if (error is SupabaseNotConfiguredException) return error.message;
    if (error.toString().contains('SupabaseNotConfiguredException')) {
      return 'Email verification is not configured in this build. Contact the developer.';
    }
    return 'Could not send the verification email. Please check your connection and try again.';
  }

  String _friendlyVerifyError(Exception error) {
    if (error is SupabaseNotConfiguredException) return error.message;
    if (error.toString().contains('SupabaseNotConfiguredException')) {
      return 'Email verification is not configured in this build. Contact the developer.';
    }
    // The exact text varies by provider SDK; a generic but true message beats
    // leaking internals.
    return 'That code was not accepted. It may be wrong or expired — request a new one.';
  }
}