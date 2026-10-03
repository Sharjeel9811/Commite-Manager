import 'package:committee_manager/app.dart';
import 'package:committee_manager/database/app_database.dart';
import 'package:committee_manager/di/service_locator.dart';
import 'package:committee_manager/providers/auth_provider.dart';
import 'package:committee_manager/repositories/interfaces/settings_repository.dart';
import 'package:committee_manager/screens/auth/lock_screen.dart';
import 'package:committee_manager/screens/auth/register_screen.dart';
import 'package:committee_manager/screens/auth/verify_otp_screen.dart';
import 'package:committee_manager/services/auth_service.dart';
import 'package:committee_manager/widgets/auth_gate.dart';
import 'package:committee_manager/widgets/state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Tests that the app actually *boots*.
///
/// `flutter analyze` and the service tests both stay green while the app is
/// completely broken: a mistyped provider constructor, a service the composition
/// root never registered, or a `context.watch` of something absent. None of those
/// are compile errors, and all of them crash on the first frame on a real device.
///
/// So these tests wire the real [ServiceLocator] against a real in-memory database
/// and mount the real widget tree, exactly as `main()` does.
///
/// Note on the auth stage: the real `AuthProvider.bootstrap()` cannot be used
/// here. It awaits `local_auth`, which talks over a Pigeon channel that no unit
/// test can answer, so the future simply never completes. Overriding the `stage`
/// getter instead keeps these tests synchronous and deterministic, and the
/// provider's own behaviour is covered by the service tests.
/// An [AuthProvider] with a fixed stage and no platform dependencies.
class _StubbedAuthProvider extends AuthProvider {
  _StubbedAuthProvider(this._stage, AuthService authService, SettingsRepository settingsRepository)
    : super(authService: authService, settingsRepository: settingsRepository);

  final AuthStage _stage;

  @override
  AuthStage get stage => _stage;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = AppDatabase(factory: databaseFactoryFfi, overridePath: inMemoryDatabasePath);
    await ServiceLocator.wire(databaseOverride: db);
  });

  tearDown(() async {
    await db.close();
    ServiceLocator.instance.reset();
  });

  _StubbedAuthProvider stubbed(AuthStage stage) => _StubbedAuthProvider(
    stage,
    ServiceLocator.instance.get<AuthService>(),
    ServiceLocator.instance.get<SettingsRepository>(),
  );

  Future<void> pumpGate(WidgetTester tester, AuthProvider provider) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: provider,
        child: MaterialApp(
          home: AuthGate(child: const Scaffold(body: Text('THE-SHELL'))),
        ),
      ),
    );
    await tester.pump();
  }

  group('dependency injection', () {
    testWidgets('the full provider graph builds with no missing registration', (
      WidgetTester tester,
    ) async {
      // MultiProvider constructs every provider eagerly, so a service the
      // composition root forgot to register throws right here instead of on a
      // user's phone.
      await tester.pumpWidget(const CommitteeManagerApp());
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    test('the services the screens depend on are all resolvable', () {
      final ServiceLocator locator = ServiceLocator.instance;
      expect(() => locator.get<AuthService>(), returnsNormally);
      expect(() => locator.get<SettingsRepository>(), returnsNormally);
    });
  });

  group('AuthGate maps every stage to the right screen', () {
    testWidgets('loading shows a splash, never the dashboard or a form', (
      WidgetTester tester,
    ) async {
      await pumpGate(tester, stubbed(AuthStage.loading));

      expect(find.byType(SplashBody), findsOneWidget);
      expect(find.text('THE-SHELL'), findsNothing);
      expect(find.byType(RegisterScreen), findsNothing);
    });

    testWidgets('needsRegistration shows the register screen', (WidgetTester tester) async {
      await pumpGate(tester, stubbed(AuthStage.needsRegistration));

      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(find.text('THE-SHELL'), findsNothing);
    });

    testWidgets('needsOtp shows the verification screen', (WidgetTester tester) async {
      await pumpGate(tester, stubbed(AuthStage.needsOtp));

      expect(find.byType(VerifyOtpScreen), findsOneWidget);
      expect(find.text('THE-SHELL'), findsNothing);
    });

    testWidgets('locked shows the lock screen', (WidgetTester tester) async {
      await pumpGate(tester, stubbed(AuthStage.locked));

      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('THE-SHELL'), findsNothing);
    });

    testWidgets('authenticated reveals the protected content', (WidgetTester tester) async {
      await pumpGate(tester, stubbed(AuthStage.authenticated));

      expect(find.text('THE-SHELL'), findsOneWidget);
      expect(find.byType(RegisterScreen), findsNothing);
      expect(find.byType(LockScreen), findsNothing);
    });
  });
}
