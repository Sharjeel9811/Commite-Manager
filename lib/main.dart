import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/utils/logger.dart';
import 'di/service_locator.dart';
import 'screens/splash/splash_screen.dart';
import 'widgets/state_views.dart';

/// Entry point.
///
/// Deliberately thin. It does exactly three things — bind the framework, build
/// the object graph, run the app. Everything else is behind [CommitteeManagerApp]
/// so the whole application can be mounted inside a test without any of this
/// side-effecting start-up code.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A crash anywhere is worth a log line; the logger is already dependency-free
  // so this is safe to install before anything else can fail.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    AppLogger('Bootstrap').error('Uncaught framework error', details.exception);
  };

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    // Building the graph also creates the database schema, so it is awaited
    // before the first frame to avoid a "database not ready" race in a screen.
    await ServiceLocator.wire();
  } catch (error, stack) {
    AppLogger('Bootstrap').error('Could not start the app', error, stack);
    runApp(const _StartupFailureApp());
    return;
  }

  runApp(const CommitteeManagerApp());
}

/// Shown only when the database itself cannot be opened — the one failure the
/// user could not have prevented and the app cannot work around.
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF4F46E5)),
      home: const Scaffold(
        body: ErrorState(
          message:
              'The local database could not be opened. Restart the app; if this keeps '
              'happening, reinstall it.',
        ),
      ),
    );
  }
}

/// Re-exported so a smoke test can mount the real widget tree.
const Widget kSplashScreen = SplashScreen();
