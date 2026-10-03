import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../screens/auth/lock_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/verify_otp_screen.dart';
import 'state_views.dart';

/// Keeps the private app behind the auth screens.
///
/// It is used *inline* (not as a pushed route) so that losing authentication —
/// the app being backgrounded and returning, or the user tapping "Lock" — is
/// handled by the same widget that handled first launch. There is exactly one
/// place that decides "which auth screen is showing right now", which is what
/// stops a stale dashboard from ever being visible to a locked-out user.
class AuthGate extends StatelessWidget {
  const AuthGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AuthStage stage = context.select<AuthProvider, AuthStage>((AuthProvider p) => p.stage);

    return switch (stage) {
      AuthStage.authenticated => child,
      AuthStage.loading => const Scaffold(body: SplashBody()),
      AuthStage.needsRegistration => const RegisterScreen(),
      AuthStage.needsOtp => const VerifyOtpScreen(),
      AuthStage.locked => const LockScreen(),
    };
  }
}
