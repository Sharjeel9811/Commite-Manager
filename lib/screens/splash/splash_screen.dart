import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/state_views.dart';

/// The first screen. It exists for one reason: the database has to be opened and
/// the auth stage resolved before any other screen can safely assume a schema
/// exists.
///
/// It deliberately *replaces* itself rather than pushing, so the user can never
/// swipe back into a half-initialised app.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
  }

  Future<void> _decide() async {
    if (!mounted) return;
    final AuthProvider auth = context.read<AuthProvider>();
    if (auth.stage == AuthStage.loading) {
      await auth.bootstrap();
    }
    if (!mounted) return;
    // Always hand over to the shell. `AuthGate` inside it decides whether the
    // dashboard, the lock screen or registration is shown, so there is only one
    // place in the app that maps an auth stage to a screen.
    Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SplashBody());
  }
}
