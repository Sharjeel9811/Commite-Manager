import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../screens/auth/lock_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/reset_pin_screen.dart';
import '../screens/auth/verify_otp_screen.dart';
import 'state_views.dart';

/// Keeps the private app behind the auth screens.
class AuthGate extends StatelessWidget {
  const AuthGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AuthStage stage =
        context.select<AuthProvider, AuthStage>((AuthProvider p) => p.stage);

    return switch (stage) {
      AuthStage.authenticated      => child,
      AuthStage.loading            => const Scaffold(body: SplashBody()),
      AuthStage.needsRegistration  => const RegisterScreen(),
      AuthStage.needsOtp           => const VerifyOtpScreen(),
      AuthStage.needsPinReset      => const ResetPinScreen(),
      AuthStage.locked             => const LockScreen(),
    };
  }
}
