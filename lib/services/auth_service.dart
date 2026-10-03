import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/utils/crypto_helper.dart';
import '../core/utils/logger.dart';
import '../core/utils/validators.dart';
import '../database/app_database.dart';
import '../models/app_user.dart';
import '../models/enums.dart';
import '../repositories/interfaces/user_repository.dart';
import 'implementations/supabase_service.dart';
import 'interfaces/biometric_service.dart';
import 'otp_service.dart';

/// Authentication policy: registration, PIN rules, lockout, unlock and recovery.
///
/// It orchestrates [UserRepository] (storage), [OtpService] (lockout recovery) and
/// [BiometricService] (device unlock) but implements none of their jobs — the
/// principle is "orchestrate, don't own".
class AuthService {
  const AuthService({
    required UserRepository userRepository,
    required OtpService otpService,
    required BiometricService biometricService,
    required AppDatabase database,
  }) : _users = userRepository,
       _otps = otpService,
       _biometrics = biometricService,
       _database = database;

  final UserRepository _users;
  final OtpService _otps;
  final BiometricService _biometrics;
  final AppDatabase _database;

  static const AppLogger _log = AppLogger('AuthService');

  // ------------------------------------------------------------- First launch

  Future<bool> hasAccount() => _users.exists();

  Future<AppUser?> currentUser() => _users.getPrimary();

  /// Creates the single local account with a hashed PIN.
  ///
  /// Registration is local and does not require email verification.
  /// [phoneNumber] and [email] are stored as contact and recovery details.
  Future<AppUser> register({
    required String fullName,
    String? phoneNumber,
    required String email,
    required String pin,
    required String confirmPin,
  }) async {
    final Map<String, String> errors = <String, String>{};

    void check(String? error, String field) {
      if (error != null) errors[field] = error;
    }

    check(
      Validators.requiredText(fullName, fieldName: 'Your name', minLength: 2),
      'name',
    );
    check(Validators.optionalPhoneNumber(phoneNumber), 'phone');
    check(Validators.email(email), 'email');
    check(Validators.pin(pin, isConfirmation: false), 'pin');
    check(Validators.pin(confirmPin, isConfirmation: true), 'confirm');

    if (errors.isEmpty && pin != confirmPin) {
      errors['confirm'] = 'The two PINs do not match';
    }
    if (errors.isNotEmpty) {
      throw ValidationException(
        'Please correct the highlighted fields.',
        fieldErrors: errors,
      );
    }

    if (await _users.exists()) {
      throw const DuplicateException(
        'An account already exists on this device.',
      );
    }

    // Email remains a required account detail because it is used for account
    // verification and lockout recovery.
    final String cleanPhone = (phoneNumber ?? '').trim();
    final String cleanEmail = email.trim();
    if (cleanEmail.isEmpty) {
      throw const ValidationException(
        'Enter an email address for account recovery.',
        fieldErrors: <String, String>{'email': 'Required'},
      );
    }

    final String salt = CryptoHelper.newSalt();
    final AppUser user = AppUser(
      id: CryptoHelper.newId(),
      fullName: fullName.trim(),
      phoneNumber: cleanPhone,
      email: cleanEmail,
      pinHash: await CryptoHelper.hashPinAsync(pin, salt),
      pinSalt: salt,
      pinLength: pin.trim().length,
      preferredChannel: OtpChannel.email,
      isVerified: false,
      otpVerified: false,
      biometricEnabled: false,
      role: UserRole.owner,
      createdAt: DateTime.now(),
    );
    await _users.insert(user);
    _log.info('Account created for ${user.fullName}');
    return user;
  }

  // ------------------------------------------------------------------ Unlock

  /// Verifies a PIN.
  ///
  /// Every failure increments a counter; after [AppConstants.maxPinAttempts]
  /// the account is locked for [AppConstants.pinLockout]. The counter lives in
  /// the database, so closing the app does not reset it.
  Future<AppUser> unlockWithPin(String pin) async {
    final AppUser? user = await _users.getPrimary();
    if (user == null) {
      throw const AuthException(
        'No account has been set up on this device yet.',
      );
    }

    final DateTime now = DateTime.now();
    if (user.isLockedOutAt(now)) {
      throw AuthException(
        'Too many incorrect attempts. Try again in '
        '${_minutesUntil(user.lockedUntil!)} minute(s).',
        lockoutUntil: user.lockedUntil,
      );
    }

    if (!await CryptoHelper.verifyPinAsync(pin, user.pinSalt, user.pinHash)) {
      final int attempts = user.failedLoginAttempts + 1;
      final bool shouldLock = attempts >= AppConstants.maxPinAttempts;
      final AppUser updated = user.copyWith(
        failedLoginAttempts: shouldLock ? 0 : attempts,
        lockedUntil: shouldLock ? now.add(AppConstants.pinLockout) : null,
        clearLock: !shouldLock,
      );
      await _users.update(updated);
      _log.warn('Failed PIN attempt #$attempts for ${user.id}');
      if (shouldLock) {
        throw AuthException(
          'Too many incorrect attempts. The app is locked for '
          '${AppConstants.pinLockout.inMinutes} minutes.',
          lockoutUntil: updated.lockedUntil,
        );
      }
      final int left = AppConstants.maxPinAttempts - attempts;
      throw AuthException(
        'Incorrect PIN. $left attempt${left == 1 ? '' : 's'} left.',
      );
    }

    AppUser unlocked = user.copyWith(
      failedLoginAttempts: 0,
      clearLock: true,
      lastLoginAt: now,
    );

    // Transparent upgrade: a PIN stored by an older build keeps working, and the
    // first correct unlock rewrites it with the current KDF and a fresh salt.
    if (CryptoHelper.needsRehash(user.pinHash)) {
      final String salt = CryptoHelper.newSalt();
      unlocked = unlocked.copyWith(
        pinSalt: salt,
        pinHash: await CryptoHelper.hashPinAsync(pin, salt),
      );
      _log.info('Re-hashed a legacy PIN with PBKDF2');
    }

    await _users.update(unlocked);
    _log.info('Unlocked with PIN');
    return unlocked;
  }

  /// Unlocks using the device fingerprint / face.
  Future<AppUser> unlockWithBiometrics() async {
    final AppUser? user = await _users.getPrimary();
    if (user == null) {
      throw const AuthException(
        'No account has been set up on this device yet.',
      );
    }
    if (user.isLockedOutAt(DateTime.now())) {
      throw AuthException(
        'The app is temporarily locked. Try again in '
        '${_minutesUntil(user.lockedUntil!)} minute(s).',
        lockoutUntil: user.lockedUntil,
      );
    }
    final bool ok = await _biometrics.authenticate(
      reason: 'Unlock ${user.fullName}\'s committees',
    );
    if (!ok) {
      throw const AuthException('Biometric check was not successful.');
    }
    final AppUser unlocked = user.copyWith(
      failedLoginAttempts: 0,
      clearLock: true,
      lastLoginAt: DateTime.now(),
    );
    await _users.update(unlocked);
    return unlocked;
  }

  // ------------------------------------------------------------ PIN / profile

  /// Changes the PIN. The current PIN must be known, so nobody can hijack the
  /// app by simply opening it.
  Future<void> changePin({
    required String currentPin,
    required String newPin,
    required String confirmPin,
  }) async {
    final AppUser? user = await _users.getPrimary();
    if (user == null) throw const AuthException('No account found.');

    if (!await CryptoHelper.verifyPinAsync(
      currentPin,
      user.pinSalt,
      user.pinHash,
    )) {
      throw const AuthException('Your current PIN is not correct.');
    }

    final String? newError = Validators.pin(newPin, isConfirmation: false);
    final String? confirmError = Validators.pin(
      confirmPin,
      isConfirmation: true,
    );
    if (newError != null) throw ValidationException(newError);
    if (confirmError != null) throw ValidationException(confirmError);
    if (newPin != confirmPin) {
      throw const ValidationException('The two PINs do not match.');
    }
    if (newPin == currentPin) {
      throw const ValidationException(
        'The new PIN must be different from the old one.',
      );
    }

    final String salt = CryptoHelper.newSalt();
    await _users.update(
      user.copyWith(
        pinSalt: salt,
        pinHash: await CryptoHelper.hashPinAsync(newPin, salt),
        pinLength: newPin.trim().length,
        failedLoginAttempts: 0,
        clearLock: true,
      ),
    );
    await _otps.invalidateAll(user.id);
    _log.info('PIN changed');
  }

  Future<void> updateProfile({
    required String fullName,
    String? phoneNumber,
    String? email,
  }) async {
    final AppUser? user = await _users.getPrimary();
    if (user == null) throw const AuthException('No account found.');

    final Map<String, String> errors = <String, String>{};
    final String? nameError = Validators.requiredText(
      fullName,
      fieldName: 'Your name',
      minLength: 2,
    );
    final String? phoneError = Validators.optionalPhoneNumber(phoneNumber);
    // Email is the only channel, so it is as required here as at registration:
    // clearing it would leave a locked-out account with no way to get a code.
    final String? emailError = Validators.email(email, required: true);
    if (nameError != null) errors['name'] = nameError;
    if (phoneError != null) errors['phone'] = phoneError;
    if (emailError != null) errors['email'] = emailError;
    if (errors.isNotEmpty) {
      throw ValidationException(
        'Please correct the highlighted fields.',
        fieldErrors: errors,
      );
    }

    await _users.update(
      user.copyWith(
        fullName: fullName.trim(),
        phoneNumber: phoneNumber?.trim(),
        email: email?.trim(),
      ),
    );
  }

  Future<bool> isBiometricAvailable() => _biometrics.isAvailable();

  Future<List<String>> biometricTypes() => _biometrics.availableTypes();

  Future<void> setBiometricEnabled(bool enabled) async {
    final AppUser? user = await _users.getPrimary();
    if (user == null) throw const AuthException('No account found.');
    if (enabled && !await _biometrics.isAvailable()) {
      throw const CapabilityException(
        'No fingerprint or face unlock is set up on this device.',
      );
    }
    await _users.update(user.copyWith(biometricEnabled: enabled));
  }

  /// Asks the provider to send (or re-send) the verification code to the
  /// account's email address. The code itself never comes back to this process.
  Future<void> sendVerificationCode({String? purpose}) async {
    final AppUser? user = await _users.getPrimary();
    if (user == null) throw const AuthException('No account found.');

    final String destination = user.targetFor(OtpChannel.email);
    if (destination.isEmpty) {
      throw const AuthException('No email address is saved for this account.');
    }

    await _otps.issue(
      userId: user.id,
      destination: destination,
      channel: OtpChannel.email,
      purpose: purpose ?? 'Account verification',
    );
  }

  /// Verifies the code and, if the PIN is still correct, unlocks the app.
  /// This is the *recovery* path used after a lockout.
  Future<AppUser> recoverWithOtp(String code) async {
    final AppUser? user = await _users.getPrimary();
    if (user == null) throw const AuthException('No account found.');
    await _otps.verify(userId: user.id, code: code);
    final AppUser recovered = user.copyWith(
      failedLoginAttempts: 0,
      clearLock: true,
      lastLoginAt: DateTime.now(),
    );
    await _users.update(recovered);
    _log.info('App unlocked through OTP recovery');
    return recovered;
  }

  /// Confirms ownership of the registered destination.
  ///
  /// The [code] is handed to the provider, which checks it, *before* the account
  /// is marked as verified. Marking first and checking later would let anyone skip
  /// verification entirely, which is the classic broken-OTP bug.
  Future<AppUser> verifyAccount(String code) async {
    final AppUser? user = await _users.getPrimary();
    if (user == null) throw const AuthException('No account found.');
    await _otps.verify(userId: user.id, code: code);
    await _otps.markAccountVerified(user.id);
    _log.info('Account verified for ${user.id}');
    return (await _users.getById(user.id))!;
  }

  /// Where codes are really sent, for display in Settings.
  String get otpDeliveryDescription => _otps.deliveryDescription;

  /// Permanently deletes the account and every byte of local data.
  ///
  /// Reaches the two places a person's identity lives:
  ///  1. the provider session is revoked (Supabase), and
  ///  2. every SQLite row — users, challenges, committees, members, payments,
  ///     schedules, turns — is wiped from the device.
  ///
  /// Preferences in `SharedPreferences` are intentionally not touched here;
  /// the caller resets those so a fresh install experience is available.
  Future<void> deleteAccount() async {
    await SupabaseService.deleteIdentity();
    await _database.wipe();
    _log.info('Account and all local data deleted');
  }

  int _minutesUntil(DateTime moment) {
    final int minutes = moment.difference(DateTime.now()).inMinutes + 1;
    return minutes < 1 ? 1 : minutes;
  }
}
