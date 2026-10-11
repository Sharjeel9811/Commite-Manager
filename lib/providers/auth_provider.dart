import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/utils/crypto_helper.dart';
import '../core/utils/logger.dart';
import '../models/app_settings.dart';
import '../models/app_user.dart';
import '../repositories/interfaces/settings_repository.dart';
import '../services/auth_service.dart';

/// Where the user is in the authentication journey.
enum AuthStage { loading, needsRegistration, needsOtp, needsPinReset, locked, authenticated }

/// The authentication state machine.
///
/// The provider contains no crypto, no SQL and no validation rules — it asks
/// [AuthService] to do those things and only remembers *what stage* the app is
/// in and *what* the user typed. That separation is what keeps this class small.
class AuthProvider extends ChangeNotifier {
  AuthProvider({
    required AuthService authService,
    required SettingsRepository settingsRepository,
  }) : _auth = authService,
       _settings = settingsRepository;

  final AuthService _auth;
  final SettingsRepository _settings;

  static const AppLogger _log = AppLogger('AuthProvider');

  AuthStage _stage = AuthStage.loading;
  AppUser? _user;
  String? _error;
  bool _busy = false;
  int _failedAttempts = 0;
  DateTime? _lockedUntil;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  AppSettings _preferences = const AppSettings();

  // ------------------------------------------------------------------ Getters

  AuthStage get stage => _stage;
  AppUser? get user => _user;
  String? get error => _error;
  bool get isBusy => _busy;
  bool get isAuthenticated => _stage == AuthStage.authenticated;
  int get failedAttempts => _failedAttempts;
  DateTime? get lockedUntil => _lockedUntil;
  bool get biometricAvailable => _biometricAvailable;
  bool get biometricEnabled => _biometricEnabled;
  AppSettings get preferences => _preferences;
  String get fullName => _user?.fullName ?? 'there';

  bool get isLockedOut =>
      _lockedUntil != null && _lockedUntil!.isAfter(DateTime.now());

  int get attemptsLeft => (AppConstants.maxPinAttempts - _failedAttempts)
      .clamp(0, AppConstants.maxPinAttempts)
      .toInt();

  // ------------------------------------------------------------------- Boot

  /// Decides the first screen: register, lock or go straight in.
  Future<void> bootstrap() async {
    _setBusy(true);
    try {
      _preferences = await _settings.load();
      _biometricAvailable = await _auth.isBiometricAvailable();

      if (!await _auth.hasAccount()) {
        _stage = AuthStage.needsRegistration;
        return;
      }

      final AppUser? user = await _auth.currentUser();
      _user = user;
      _biometricEnabled = user?.biometricEnabled ?? false;

      if (user == null) {
        _stage = AuthStage.needsRegistration;
        return;
      }
      if (!user.isVerified) {
        _stage = AuthStage.needsOtp;
        return;
      }
      if (user.isLockedOutAt(DateTime.now())) {
        _lockedUntil = user.lockedUntil;
        _failedAttempts = AppConstants.maxPinAttempts;
        _stage = AuthStage.locked;
        return;
      }
      _stage = AuthStage.locked;
    } catch (error) {
      _fail(error);
      _stage = AuthStage.needsRegistration;
    } finally {
      _setBusy(false);
    }
  }

  // ------------------------------------------------------------- Registration

  Future<bool> register({
    required String fullName,
    String? phoneNumber,
    required String email,
    required String pin,
    required String confirmPin,
  }) async {
    _setBusy(true);
    _error = null;
    try {
      _user = await _auth.register(
        fullName: fullName,
        phoneNumber: phoneNumber,
        email: email,
        pin: pin,
        confirmPin: confirmPin,
      );
      _stage = AuthStage.needsOtp;
      return true;
    } on ValidationException catch (error) {
      _error = error.message;
      rethrow;
    } catch (error) {
      _fail(error);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  // -------------------------------------------------------------------- OTP

  /// Sends a verification code during **initial registration** flow.
  /// Sets stage to [AuthStage.needsOtp] so AuthGate shows the verify screen.
  Future<bool> sendOtp() async {
    _setBusy(true);
    _error = null;
    try {
      await _auth.sendVerificationCode();
      _stage = AuthStage.needsOtp;
      return true;
    } catch (error) {
      _fail(error);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  /// Sends a verification code during **PIN recovery** flow.
  /// Does NOT change stage — the recovery dialog stays open,
  /// no second VerifyOtpScreen is shown on top.
  Future<bool> sendOtpForRecovery() async {
    _setBusy(true);
    _error = null;
    try {
      await _auth.sendVerificationCode();
      return true;
    } catch (error) {
      _fail(error);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  /// Verifies the code and signs the user in.
  Future<bool> verifyOtp(String code) async {
    _setBusy(true);
    _error = null;
    try {
      _user = await _auth.verifyAccount(code);
      _stage = AuthStage.authenticated;
      return true;
    } on AuthException catch (error) {
      _error = error.message;
      return false;
    } catch (error) {
      _fail(error);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  // ------------------------------------------------------------------ Unlock

  Future<bool> unlock(String pin) async {
    _setBusy(true);
    _error = null;
    try {
      _user = await _auth.unlockWithPin(pin);
      _failedAttempts = 0;
      _lockedUntil = null;
      _biometricEnabled = _user!.biometricEnabled;
      _stage = AuthStage.authenticated;
      return true;
    } on AuthException catch (error) {
      _error = error.message;
      _failedAttempts++;
      if (error.isLockedOut) {
        _lockedUntil = error.lockoutUntil;
        _stage = AuthStage.locked;
      }
      return false;
    } catch (error) {
      _fail(error);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<bool> unlockWithBiometrics() async {
    _setBusy(true);
    _error = null;
    try {
      _user = await _auth.unlockWithBiometrics();
      _failedAttempts = 0;
      _lockedUntil = null;
      // Only move to authenticated if currently locked.
      // When called from Settings (already authenticated) keep current stage.
      if (_stage == AuthStage.locked) {
        _stage = AuthStage.authenticated;
      }
      return true;
    } on AuthException catch (error) {
      _error = error.message;
      return false;
    } catch (error) {
      _fail(error);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  /// Lockout recovery: proves the phone/email code, then moves to PIN reset.
  /// Stage becomes [AuthStage.needsPinReset] so AuthGate shows a full-screen
  /// "Set new PIN" page — not another OTP screen.
  Future<bool> recoverWithOtp(String code) async {
    _setBusy(true);
    _error = null;
    try {
      _user = await _auth.recoverWithOtp(code);
      _failedAttempts = 0;
      _lockedUntil = null;
      // Move to the dedicated PIN-reset stage.
      _stage = AuthStage.needsPinReset;
      return true;
    } on AuthException catch (error) {
      _error = error.message;
      return false;
    } catch (error) {
      _fail(error);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  /// Completes the PIN-reset flow: saves the new PIN then unlocks the app.
  Future<bool> completePinReset(String newPin, String confirmPin) async {
    _setBusy(true);
    _error = null;
    try {
      await _auth.changePin(
        currentPin: '',   // allowed because OTP recovery already verified identity
        newPin: newPin,
        confirmPin: confirmPin,
      );
      _user = await _auth.currentUser();
      _stage = AuthStage.authenticated;
      return true;
    } on AppException catch (error) {
      _error = error.message;
      return false;
    } catch (error) {
      _fail(error);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> lock({bool force = false}) async {
    if (_stage != AuthStage.authenticated) return;
    // When called from "Lock now" button (force=true), lock regardless of
    // the lockEnabled preference. The preference only controls *automatic*
    // locking on idle/background — the user tapping the button is always
    // an explicit intent to lock.
    if (!force && !_preferences.lockEnabled) return;
    _stage = AuthStage.locked;
    _error = null;
    _safeNotify();
  }

  /// Adopts security preferences changed elsewhere in the running session.
  ///
  /// [SettingsProvider] writes `lockEnabled` and `lockTimeoutMinutes` to shared
  /// storage, but this provider keeps its own copy loaded at bootstrap. Without
  /// this call a PIN enabled in Settings would keep the app unlocked for the
  /// rest of the process, and a change to the timeout would be ignored until the
  /// next launch. The listener is not notified: locking is a security decision,
  /// not a settings change, and notifying here would rebuild the auth screen.
  void applySecurityPreferences(AppSettings settings) {
    _preferences = settings;
  }

  // ---------------------------------------------------------------- Security

  Future<bool> setBiometricEnabled(bool value) async {
    _setBusy(true);
    try {
      await _auth.setBiometricEnabled(value);
      _user = await _auth.currentUser();
      _biometricEnabled = value;
      return true;
    } catch (error) {
      _fail(error);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<bool> changePin({
    required String currentPin,
    required String newPin,
    required String confirmPin,
  }) async {
    _setBusy(true);
    _error = null;
    try {
      await _auth.changePin(
        currentPin: currentPin,
        newPin: newPin,
        confirmPin: confirmPin,
      );
      return true;
    } on AppException catch (error) {
      _error = error.message;
      return false;
    } catch (error) {
      _fail(error);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<bool> updateProfile({
    required String fullName,
    String? phoneNumber,
    String? email,
  }) async {
    _setBusy(true);
    _error = null;
    try {
      await _auth.updateProfile(
        fullName: fullName,
        phoneNumber: phoneNumber,
        email: email,
      );
      _user = await _auth.currentUser();
      return true;
    } on ValidationException catch (error) {
      _error = error.message;
      rethrow;
    } catch (error) {
      _fail(error);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  /// Saves the replacement PIN after OTP recovery and completes authentication.
  Future<bool> resetToNewPin(String newPin, String confirmPin) async {
    _setBusy(true);
    _error = null;
    try {
      await _auth.resetPinAfterRecovery(
        newPin: newPin,
        confirmPin: confirmPin,
      );
      _user = await _auth.currentUser();
      _failedAttempts = 0;
      _lockedUntil = null;
      _stage = AuthStage.authenticated;
      return true;
    } on AppException catch (error) {
      _error = error.message;
      return false;
    } catch (error) {
      _fail(error);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    _safeNotify();
  }

  /// Deletes the account and all local data, then returns to registration.
  ///
  /// Local state is reset in the same breath as the wipe, so no screen can keep
  /// showing a name, a PIN length or a stage that no longer exists.
  Future<bool> deleteAccount() async {
    _setBusy(true);
    try {
      await _auth.deleteAccount();
      _user = null;
      _failedAttempts = 0;
      _lockedUntil = null;
      _biometricEnabled = false;
      _error = null;
      _stage = AuthStage.needsRegistration;
      return true;
    } catch (error) {
      _fail(error);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  // ------------------------------------------------------------------ Helpers

  /// True once the widget tree has torn this provider down.
  ///
  /// `bootstrap()` and the auth calls are async and cannot be cancelled, so their
  /// continuations can land after the provider has been disposed — for example
  /// when the splash screen is replaced while the initial database check is still
  /// in flight. Notifying a disposed `ChangeNotifier` throws, so every state
  /// change goes through [_safeNotify] instead.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _setBusy(bool value) {
    _busy = value;
    _safeNotify();
  }

  void _fail(Object error) {
    _log.error('Authentication failed', error);
    _error = describeError(error);
  }
}

/// A random, printable recovery phrase the user can write down.
///
/// Useful in a viva to explain "what happens if the user forgets the PIN".
String generateRecoveryPhrase() => CryptoHelper.randomSecret(12);
