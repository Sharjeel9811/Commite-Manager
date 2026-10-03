import 'package:committee_manager/core/constants/app_constants.dart';
import 'package:committee_manager/core/constants/app_routes.dart';
import 'package:committee_manager/database/app_database.dart';
import 'package:committee_manager/di/service_locator.dart';
import 'package:committee_manager/models/app_settings.dart';
import 'package:committee_manager/models/enums.dart';
import 'package:committee_manager/models/notification_payload.dart';
import 'package:committee_manager/providers/auth_provider.dart';
import 'package:committee_manager/providers/settings_provider.dart';
import 'package:committee_manager/providers/theme_provider.dart';
import 'package:committee_manager/repositories/interfaces/settings_repository.dart';
import 'package:committee_manager/services/auth_service.dart';
import 'package:committee_manager/services/demo_data_service.dart';
import 'package:committee_manager/services/interfaces/notification_service.dart';
import 'package:committee_manager/services/reminder_service.dart';
import 'package:committee_manager/widgets/app_session_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers the two behaviours that only exist above [MaterialApp]: the session
/// timer and the notification deep link.
///
/// Both were previously absent, which is the kind of gap that stays invisible
/// to `flutter analyze` — the code simply was not there, and the app booted
/// happily while leaking a session and swallowing every notification tap.
class _StubbedAuthProvider extends AuthProvider {
  _StubbedAuthProvider(
    AuthService authService,
    SettingsRepository settingsRepository, {
    required AppSettings prefs,
  }) : _preferences = prefs,
       super(authService: authService, settingsRepository: settingsRepository);

  AppSettings _preferences;

  @override
  AppSettings get preferences => _preferences;

  @override
  void applySecurityPreferences(AppSettings settings) {
    _preferences = settings;
    notifyListeners();
  }

  /// How many times the guard asked to lock. `AuthProvider.lock()` is real, but
  /// it awaits nothing, so the count is enough to assert the decision.
  int lockCalls = 0;
  bool _locked = false;

  @override
  bool get isAuthenticated => !_locked;

  @override
  AuthStage get stage => _locked ? AuthStage.locked : AuthStage.authenticated;

  /// Simulates the moment a fresh sign-in completes.
  void signIn() {
    _locked = false;
    notifyListeners();
  }

  @override
  Future<void> lock() async {
    lockCalls++;
    if (preferences.lockEnabled) _locked = true;
  }
}

/// A [NotificationService] that only records what the app did with it.
class _FakeNotificationService implements NotificationService {
  _FakeNotificationService({this.launchedWith});

  /// What a cold start from a notification would report.
  final String? launchedWith;

  void Function(String? payload)? handler;

  @override
  void onTap(void Function(String? payload) handler) => this.handler = handler;

  @override
  Future<String?> launchPayload() async => launchedWith;

  /// Simulates the user tapping a notification while the app is running.
  void tap(String? payload) => handler?.call(payload);

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> show(AppNotification notification) async {}

  @override
  Future<void> schedule(AppNotification notification, DateTime at) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<List<int>> pendingIds() async => const <int>[];
}

/// A stand-in destination so a pushed deep link is observable without mounting a
/// screen that would need the whole database.
class _LandingPage extends StatelessWidget {
  const _LandingPage();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('THE-COMMITTEE'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FakeNotificationService notifications;

  const String committeeId = 'committee-1';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = AppDatabase(factory: databaseFactoryFfi, overridePath: inMemoryDatabasePath);
    await ServiceLocator.wire(databaseOverride: db);
    notifications = _FakeNotificationService();
    ServiceLocator.instance.override<NotificationService>(notifications);
  });

  tearDown(() async {
    await db.close();
    ServiceLocator.instance.reset();
  });

  final ServiceLocator locator = ServiceLocator.instance;

  _StubbedAuthProvider authWith({AppSettings? prefs}) => _StubbedAuthProvider(
    locator.get<AuthService>(),
    locator.get<SettingsRepository>(),
    prefs: prefs ?? const AppSettings(),
  );

  /// Mounts the guard around a real `MaterialApp`, exactly as `app.dart` does.
  ///
  /// [clock] is injected so the idle window can be tested: the guard measures
  /// elapsed time with the wall clock, which `tester.pump` cannot advance.
  ///
  /// `pumpGuardWith` mounts a caller-supplied provider, so a test can drive the
  /// auth state after the guard has already wired itself up.
  Future<void> pumpGuardWith(
    WidgetTester tester, {
    required _StubbedAuthProvider auth,
    String initialRoute = AppRoutes.dashboard,
    _TestClock? clock,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: AppSessionGuard(
          now: clock == null ? null : () => clock.now,
          builder:
              (GlobalKey<NavigatorState> key) => MaterialApp(
                navigatorKey: key,
                initialRoute: initialRoute,
                onGenerateRoute: (RouteSettings settings) => MaterialPageRoute<void>(
                  settings: settings,
                  builder: (_) =>
                      settings.name == AppRoutes.committeeDetails
                      ? _LandingPage()
                      : const Scaffold(body: Text('THE-HOME')),
                ),
              ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<_StubbedAuthProvider> pumpGuard(
    WidgetTester tester, {
    AppSettings? prefs,
    String initialRoute = AppRoutes.dashboard,
    _TestClock? clock,
  }) async {
    final _StubbedAuthProvider auth = authWith(prefs: prefs);
    await pumpGuardWith(tester, auth: auth, initialRoute: initialRoute, clock: clock);
    return auth;
  }

  group('notification deep links', () {
    testWidgets('a tap on a signed-in session opens the committee', (WidgetTester tester) async {
      await pumpGuard(tester);

      notifications.tap('committee:$committeeId');
      await tester.pumpAndSettle();

      expect(find.text('THE-COMMITTEE'), findsOneWidget);
      expect(find.text('THE-HOME'), findsNothing);
    });

    testWidgets('a tap while locked waits instead of pushing over the lock screen', (
      WidgetTester tester,
    ) async {
      // `lockEnabled: false` means the stub cannot represent a locked app, so
      // the locked case is reached the way a real user reaches it: the app locks
      // itself, then the tap arrives.
      final _StubbedAuthProvider auth = await pumpGuard(tester);
      expect(notifications.handler, isNotNull);

      await auth.lock();
      notifications.tap('committee:$committeeId');
      await tester.pumpAndSettle();

      expect(find.text('THE-HOME'), findsOneWidget, reason: 'nothing may be pushed while locked');
    });

    testWidgets('a cold start from a notification opens the committee once in', (
      WidgetTester tester,
    ) async {
      notifications = _FakeNotificationService(launchedWith: 'committee:$committeeId');
      locator.override<NotificationService>(notifications);

      await pumpGuard(tester);
      // The launch payload is read in a post-frame callback and pushed in a
      // second one, so the tree needs a couple of turns to settle.
      await tester.pumpAndSettle();

      expect(find.text('THE-COMMITTEE'), findsOneWidget);
    });

    testWidgets('an unrecognised payload is ignored rather than crashing', (
      WidgetTester tester,
    ) async {
      await pumpGuard(tester);

      notifications.tap('committee:');
      notifications.tap('something-else');
      notifications.tap(null);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('THE-HOME'), findsOneWidget);
    });
  });

  group('the session locks itself', () {
    testWidgets('going to the background past the timeout locks on resume', (
      WidgetTester tester,
    ) async {
      // Android suspends timers while backgrounded, so the guard compares
      // wall-clock timestamps rather than counting down.
      final _TestClock clock = _TestClock();
      final _StubbedAuthProvider auth = await pumpGuard(tester, clock: clock);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock.advance(AppConstants.sessionIdleTimeout + const Duration(seconds: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(auth.lockCalls, 1);
    });

    testWidgets('a short trip to the notification shade does not lock', (
      WidgetTester tester,
    ) async {
      final _TestClock clock = _TestClock();
      final _StubbedAuthProvider auth = await pumpGuard(tester, clock: clock);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock.advance(const Duration(seconds: 20));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(auth.lockCalls, 0);
    });

    testWidgets('a second pause does not extend the time already served', (
      WidgetTester tester,
    ) async {
      // The notification shade and a rotation both pause the app. If a second
      // pause reset the clock, repeatedly glancing at the shade would keep the
      // app unlocked forever.
      final _TestClock clock = _TestClock();
      final _StubbedAuthProvider auth = await pumpGuard(tester, clock: clock);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock.advance(const Duration(minutes: 4));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(auth.lockCalls, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock.advance(const Duration(minutes: 4));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(auth.lockCalls, 1);
    });

    testWidgets('interaction postpones the lock', (WidgetTester tester) async {
      final _TestClock clock = _TestClock();
      final _StubbedAuthProvider auth = await pumpGuard(tester, clock: clock);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock.advance(const Duration(minutes: 4));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // Four minutes is most of the window, so without a touch the app would
      // already be locked.
      expect(auth.lockCalls, 0);

      // A touch counts as activity, so the window starts again from here. The
      // timer that enforces it runs on the framework's clock, so it is `pump`
      // that has to move it, while `clock` moves the elapsed-time comparison.
      await tester.tap(find.text('THE-HOME'));
      await tester.pump();
      // The touch reset the window, so a full window has to pass again before
      // the app locks even though four minutes had already gone by.
      clock.advance(const Duration(minutes: 4));
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();

      expect(auth.lockCalls, 0, reason: 'the touch restarted the five-minute window');

      clock.advance(const Duration(seconds: 1));
      await tester.pump(const Duration(minutes: 4));
      await tester.pumpAndSettle();

      expect(auth.lockCalls, 1);
    });

    testWidgets('a locked app is never locked a second time', (WidgetTester tester) async {
      final _TestClock clock = _TestClock();
      final _StubbedAuthProvider auth = await pumpGuard(tester, clock: clock);

      await auth.lock();
      final int before = auth.lockCalls;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock.advance(AppConstants.sessionIdleTimeout * 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(auth.lockCalls, before);
    });
  });

  group('the user\'s lock window is respected', () {
    testWidgets('a longer chosen window keeps the app open past the default', (
      WidgetTester tester,
    ) async {
      final _TestClock clock = _TestClock();
      final _StubbedAuthProvider auth = await pumpGuard(
        tester,
        prefs: const AppSettings(lockTimeoutMinutes: 30),
        clock: clock,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock.advance(const Duration(minutes: 10));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(auth.lockCalls, 0, reason: '10 minutes is well inside the chosen 30');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock.advance(const Duration(minutes: 31));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(auth.lockCalls, 1);
    });

    test('the offered options all sit inside the settings model', () {
      // Guards against a picker option that `AppSettings` cannot represent.
      for (final int minutes in <int>[1, 2, 5, 10, 15, 30]) {
        expect(const AppSettings().copyWith(lockTimeoutMinutes: minutes).lockTimeoutMinutes, minutes);
      }
    });
  });

  group('the theme switch reaches the app', () {
    // Guards a regression that survived `flutter analyze` happily: the Settings
    // screen wrote the preference to the repository while `MaterialApp` watched
    // a *different* provider, so choosing a theme appeared to do nothing until
    // the app was restarted.
    test('choosing a theme applies immediately and survives a restart', () async {
      final _InMemorySettings repository = _InMemorySettings();
      final ThemeProvider theme = ThemeProvider(settingsRepository: repository);
      final SettingsProvider settings = SettingsProvider(
        settingsRepository: repository,
        reminderService: locator.get<ReminderService>(),
        notificationService: _FakeNotificationService(),
        demoDataService: locator.get<DemoDataService>(),
        authService: locator.get<AuthService>(),
        themeProvider: theme,
      );
      await settings.load();

      expect(theme.themeMode, ThemeMode.system);

      await settings.setTheme(AppThemePreference.dark);
      expect(theme.themeMode, ThemeMode.dark, reason: 'the switch must apply immediately');

      await settings.setTheme(AppThemePreference.light);
      expect(theme.themeMode, ThemeMode.light);

      // And the next launch has to come up in the chosen theme, not the default.
      final ThemeProvider relaunched = ThemeProvider(settingsRepository: repository);
      await relaunched.load();
      expect(relaunched.themeMode, ThemeMode.light);
    });

    test('loading preferences restores the saved theme before the first frame', () async {
      final _InMemorySettings repository = _InMemorySettings();
      await repository.save(const AppSettings(themePreference: AppThemePreference.dark));

      final ThemeProvider theme = ThemeProvider(settingsRepository: repository);
      final SettingsProvider settings = SettingsProvider(
        settingsRepository: repository,
        reminderService: locator.get<ReminderService>(),
        notificationService: _FakeNotificationService(),
        demoDataService: locator.get<DemoDataService>(),
        authService: locator.get<AuthService>(),
        themeProvider: theme,
      );
      await settings.load();

      expect(theme.themeMode, ThemeMode.dark);
    });
  });

  group('security settings reach the running session', () {
    // The same class of bug as the theme one, in the security direction:
    // `SettingsProvider` persisted the choice while `AuthProvider` kept the copy
    // it loaded at bootstrap, so a PIN switched on in Settings did not lock the
    // app until it was restarted — the opposite of what the user asked for.
    test('enabling the PIN takes effect without a restart', () async {
      final _InMemorySettings repository = _InMemorySettings();
      await repository.save(const AppSettings(lockEnabled: false));
      final _StubbedAuthProvider auth = _StubbedAuthProvider(
        locator.get<AuthService>(),
        repository,
        prefs: const AppSettings(lockEnabled: false),
      );
      final SettingsProvider settings = SettingsProvider(
        settingsRepository: repository,
        reminderService: locator.get<ReminderService>(),
        notificationService: _FakeNotificationService(),
        demoDataService: locator.get<DemoDataService>(),
        authService: locator.get<AuthService>(),
        authProvider: auth,
      );
      await settings.load();

      expect(auth.preferences.lockEnabled, isFalse);

      await settings.setLockEnabled(true);
      expect(auth.preferences.lockEnabled, isTrue, reason: 'must not need a restart');
    });

    test('a new lock timeout is adopted immediately', () async {
      final _InMemorySettings repository = _InMemorySettings();
      final _StubbedAuthProvider auth = _StubbedAuthProvider(
        locator.get<AuthService>(),
        repository,
        prefs: const AppSettings(lockTimeoutMinutes: 5),
      );
      final SettingsProvider settings = SettingsProvider(
        settingsRepository: repository,
        reminderService: locator.get<ReminderService>(),
        notificationService: _FakeNotificationService(),
        demoDataService: locator.get<DemoDataService>(),
        authService: locator.get<AuthService>(),
        authProvider: auth,
      );
      await settings.load();

      await settings.setLockTimeout(30);
      expect(auth.preferences.lockTimeoutMinutes, 30);
    });

    test('a PIN enabled just before a crash is active on the next run', () async {
      final _InMemorySettings repository = _InMemorySettings();
      await repository.save(const AppSettings(lockEnabled: true, lockTimeoutMinutes: 15));

      final _StubbedAuthProvider auth = _StubbedAuthProvider(
        locator.get<AuthService>(),
        repository,
        prefs: const AppSettings(),
      );
      final SettingsProvider settings = SettingsProvider(
        settingsRepository: repository,
        reminderService: locator.get<ReminderService>(),
        notificationService: _FakeNotificationService(),
        demoDataService: locator.get<DemoDataService>(),
        authService: locator.get<AuthService>(),
        authProvider: auth,
      );
      await settings.load();

      expect(auth.preferences.lockEnabled, isTrue);
      expect(auth.preferences.lockTimeoutMinutes, 15);
    });
  });

  group('a new session is guarded immediately', () {
    // The timer used to be armed only by a tap or a resume, so a user who
    // signed in and put the phone down without touching the screen again was
    // never locked.
    testWidgets('signing in starts the idle window without further interaction', (
      WidgetTester tester,
    ) async {
      final _TestClock clock = _TestClock();
      final _StubbedAuthProvider auth = _StubbedAuthProvider(
        locator.get<AuthService>(),
        _InMemorySettings(),
        prefs: const AppSettings(lockEnabled: true, lockTimeoutMinutes: 5),
      );
      await pumpGuardWith(tester, auth: auth, clock: clock);

      auth.signIn();
      await tester.pumpAndSettle();

      // No tap, no backgrounding, no further interaction of any kind.
      clock.advance(const Duration(minutes: 6));
      await tester.pumpAndSettle(const Duration(minutes: 6));
      expect(auth.lockCalls, 1, reason: 'idle time must count from the sign-in');
    });
  });
}

/// A clock the test moves by hand.
///
/// The session timer deliberately reads the wall clock, because Android suspends
/// timers while the app is backgrounded and a countdown would stop dead. Real
/// time is not something `tester.pump` can advance, so it is replaced here.
class _TestClock {
  DateTime now = DateTime(2026, 1, 1, 9);

  void advance(Duration by) => now = now.add(by);
}

class _InMemorySettings implements SettingsRepository {
  AppSettings _settings = const AppSettings();

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async => _settings = settings;

  @override
  Future<void> reset() async => _settings = const AppSettings();
}
