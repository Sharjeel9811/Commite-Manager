import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/utils/crypto_helper.dart';
import '../core/utils/logger.dart';
import '../models/app_user.dart';
import '../models/enums.dart';
import '../models/otp_challenge.dart';
import '../repositories/interfaces/user_repository.dart';
import 'interfaces/otp_sender.dart';

/// The complete OTP lifecycle: **issue → track attempt → verify → expire**.
///
/// The *code itself* lives entirely with the [OtpSender]'s provider (Supabase
/// Auth): `issue` asks the provider to email a code, and `verify` asks the
/// provider whether the submitted code is the one it sent. This file keeps the
/// local bookkeeping that gives the user a good experience — rate limiting,
/// expiry, attempt counting, and invalidating old codes as soon as a new one is
/// requested.
class OtpService {
  OtpService({
    required OtpRepository otpRepository,
    required UserRepository userRepository,
    required OtpSender sender,
  }) : _otps = otpRepository,
       _users = userRepository,
       _sender = sender;

  final OtpRepository _otps;
  final UserRepository _users;
  final OtpSender _sender;
  String? _lastAccessToken;

  String? get lastAccessToken => _lastAccessToken;

  static const AppLogger _log = AppLogger('OtpService');

  /// Asks the provider to email a fresh code and records a local challenge.
  ///
  /// Rate limiting: at most 3 requests per 5 minutes per account, and any older
  /// open challenge is invalidated so only the newest code can be used.
  Future<void> issue({
    required String userId,
    required String destination,
    required OtpChannel channel,
    required String purpose,
  }) async {
    if (destination.trim().isEmpty) {
      throw const ValidationException(
        'Add an email address before requesting a code.',
      );
    }

    final DateTime now = DateTime.now();
    final int recent = await _otps.countRecent(userId, now.subtract(const Duration(minutes: 5)));
    if (recent >= 3) {
      throw const AuthException(
        'Too many codes requested. Please wait a few minutes and try again.',
      );
    }

    await _otps.invalidateAll(userId);

    final OtpChallenge challenge = OtpChallenge(
      id: CryptoHelper.newId(),
      userId: userId,
      channel: channel,
      destination: destination.trim(),
      // The code is never known to this process. This is an opaque marker so the
      // row is attributable and tamper-evident; it is deliberately not the code.
      codeHash: CryptoHelper.hashSecret(CryptoHelper.newId(), CryptoHelper.newSalt()),
      salt: CryptoHelper.newSalt(),
      expiresAt: now.add(AppConstants.otpValidity),
      maxAttempts: AppConstants.otpMaxAttempts,
      createdAt: now,
    );
    await _otps.insert(challenge);

    final OtpDeliveryResult delivery = await _sender.send(
      destination: challenge.destination,
      purpose: purpose,
    );

    if (!delivery.success) {
      await _otps.markConsumed(challenge.id, now);
      throw AuthException(delivery.error ?? 'The verification code could not be sent.');
    }

    _log.info('OTP requested for $userId via ${channel.name}');
  }

  /// Asks the provider to check a submitted code against the newest challenge.
  ///
  /// Codes expire after 5 minutes and allow 5 attempts. A new code invalidates
  /// the previous one, so brute forcing is impractical.
  Future<void> verify({required String userId, required String code}) async {
    final OtpChallenge? challenge = await _otps.getLatestOpen(userId);
    if (challenge == null) {
      throw const AuthException('Request a new verification code to continue.');
    }
    if (challenge.isConsumed) {
      throw const AuthException('That code has already been used.');
    }
    if (challenge.isExpiredAt(DateTime.now())) {
      await _otps.markConsumed(challenge.id, DateTime.now());
      throw const AuthException('That code has expired. Request a new one.');
    }
    if (challenge.attempts >= challenge.maxAttempts) {
      throw const AuthException('Too many incorrect attempts. Request a new code.');
    }

    final OtpVerificationResult result = await _sender.verify(
      destination: challenge.destination,
      code: code.trim(),
    );

    if (!result.success) {
      await _otps.incrementAttempts(challenge.id);
      final int left = challenge.attemptsLeft - 1;
      throw AuthException(
        left <= 0
            ? '${result.error ?? 'That code is not correct.'} No attempts are left — request a new code.'
            : '${result.error ?? 'That code is not correct.'} $left attempt${left == 1 ? '' : 's'} left.',
      );
    }

    _lastAccessToken = result.accessToken;
    await _otps.markConsumed(challenge.id, DateTime.now());
    _log.info('OTP verified for $userId');
  }

  /// Marks the account as verified.
  Future<void> markAccountVerified(String userId) async {
    final AppUser? user = await _users.getById(userId);
    if (user == null) {
      throw const NotFoundException('Your account could not be found.');
    }
    await _users.update(user.copyWith(otpVerified: true, isVerified: true));
  }

  /// Wipes every open challenge (used when the PIN changes).
  Future<void> invalidateAll(String userId) => _otps.invalidateAll(userId);

  String get deliveryDescription => _sender.deliveryDescription;
}