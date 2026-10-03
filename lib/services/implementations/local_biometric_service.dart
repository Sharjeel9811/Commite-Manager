import 'package:local_auth/local_auth.dart';

import '../../core/utils/logger.dart';
import '../interfaces/biometric_service.dart';

/// [BiometricService] backed by the OS biometric prompt.
class LocalBiometricService implements BiometricService {
  LocalBiometricService({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;
  static const AppLogger _log = AppLogger('BiometricService');

  @override
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (error) {
      _log.error('Biometric availability check failed', error);
      return false;
    }
  }

  @override
  Future<List<String>> availableTypes() async {
    try {
      final List<BiometricType> types = await _auth.getAvailableBiometrics();
      return types
          .map(
            (BiometricType type) => switch (type) {
              BiometricType.fingerprint => 'Fingerprint',
              BiometricType.face => 'Face',
              BiometricType.iris => 'Iris',
              BiometricType.strong => 'Strong biometric',
              BiometricType.weak => 'Weak biometric',
            },
          )
          .toList(growable: false);
    } catch (error) {
      _log.error('Could not read biometric types', error);
      return const <String>[];
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (error) {
      _log.error('Biometric prompt failed', error);
      return false;
    }
  }
}
