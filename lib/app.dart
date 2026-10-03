import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'core/constants/app_constants.dart';
import 'core/constants/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'di/service_locator.dart';
import 'providers/auth_provider.dart';
import 'providers/committee_detail_provider.dart';
import 'providers/committee_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/history_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/payment_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/statistics_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/auth/lock_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/verify_otp_screen.dart';
import 'screens/committees/committee_details_screen.dart';
import 'screens/committees/committees_screen.dart';
import 'screens/committees/create_committee_screen.dart';
import 'screens/history/history_screen.dart';
import 'screens/members/members_screen.dart';
import 'screens/payments/payments_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/shell/app_shell.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/statistics/statistics_screen.dart';
import 'widgets/app_session_guard.dart';
import 'widgets/state_views.dart';

/// The root of the widget tree.
///
/// It is deliberately tiny: it wires [MultiProvider], hands routing to
/// [AppRouter] and watches the auth stage. It contains no business logic, which
/// is what lets a test mount a single screen without starting the whole app.
class CommitteeManagerApp extends StatelessWidget {
  const CommitteeManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ServiceLocator locator = ServiceLocator.instance;

    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(settingsRepository: locator.get()),
        ),
        ChangeNotifierProvider<LocaleProvider>(
          create: (_) => LocaleProvider(settingsRepository: locator.get())..load(),
        ),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) =>
              AuthProvider(authService: locator.get(), settingsRepository: locator.get())
                ..bootstrap(),
        ),
        ChangeNotifierProvider<CommitteeProvider>(
          create: (_) =>
              CommitteeProvider(committeeService: locator.get(), reminderService: locator.get())
                ..load(),
        ),
        ChangeNotifierProvider<CommitteeDetailProvider>(
          create: (_) => CommitteeDetailProvider(
            committeeService: locator.get(),
            memberService: locator.get(),
            statisticsService: locator.get(),
            reminderService: locator.get(),
          ),
        ),
        ChangeNotifierProvider<PaymentProvider>(
          create: (_) =>
              PaymentProvider(paymentService: locator.get(), reminderService: locator.get()),
        ),
        ChangeNotifierProvider<DashboardProvider>(
          create: (_) =>
              DashboardProvider(statisticsService: locator.get(), committeeService: locator.get())
                ..load()
                ..listenToPaymentChanges(),
        ),
        ChangeNotifierProvider<SettingsProvider>(
          create: (BuildContext context) => SettingsProvider(
            settingsRepository: locator.get(),
            reminderService: locator.get(),
            notificationService: locator.get(),
            demoDataService: locator.get(),
            authService: locator.get(),
            themeProvider: context.read<ThemeProvider>(),
            authProvider: context.read<AuthProvider>(),
          )..load(),
        ),
        ChangeNotifierProvider<HistoryProvider>(
          create: (_) => HistoryProvider(statisticsService: locator.get())..load(),
        ),
        ChangeNotifierProvider<StatisticsProvider>(
          create: (_) => StatisticsProvider(statisticsService: locator.get())..load(),
        ),
      ],
      child: Consumer2<ThemeProvider, LocaleProvider>(
        builder: (BuildContext context, ThemeProvider theme, LocaleProvider locale, _) {
          return AppSessionGuard(
            builder: (GlobalKey<NavigatorState> navigatorKey) => MaterialApp(
              title: AppConstants.appName,
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: theme.themeMode,
              // Locale drives both the language and RTL/LTR text direction.
              locale: locale.locale,
              supportedLocales: const <Locale>[
                Locale('en'),
                Locale('ur'),
              ],
              // Flutter's built-in widgets (date pickers, text fields, tooltips)
              // also need to know the locale so they can flip their own layouts.
              localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
                _FallbackMaterialLocalizationsDelegate(),
                _FallbackWidgetsLocalizationsDelegate(),
                _FallbackCupertinoLocalizationsDelegate(),
              ],
              initialRoute: AppRoutes.splash,
              navigatorKey: navigatorKey,
              onGenerateRoute: AppRouter.onGenerateRoute,
            ),
          );
        },
      ),
    );
  }
}

/// Central route table.
///
/// [onGenerateRoute] is a single pure function: route name in, screen out. That
/// keeps navigation in one file instead of scattering `pushNamed` strings and
/// `MaterialPageRoute`s across twenty screens.
class AppRouter {
  const AppRouter._();

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final String? name = settings.name;

    return switch (name) {
      AppRoutes.splash => _page(settings, const SplashScreen()),
      AppRoutes.register => _page(settings, const RegisterScreen()),
      AppRoutes.verifyOtp => _page(settings, const VerifyOtpScreen()),
      AppRoutes.lock => _page(settings, const LockScreen()),
      AppRoutes.dashboard => _page(settings, const AppShell()),
      AppRoutes.committees => _page(settings, const CommitteesScreen()),
      AppRoutes.createCommittee => _page(settings, const CreateCommitteeScreen()),
      AppRoutes.committeeDetails => _page(
        settings,
        CommitteeDetailsScreen(committeeId: settings.arguments! as String),
      ),
      AppRoutes.members => _page(
        settings,
        MembersScreen(committeeId: settings.arguments! as String),
      ),
      AppRoutes.payments => _page(
        settings,
        PaymentsScreen(committeeId: settings.arguments! as String),
      ),
      AppRoutes.history => _page(settings, const HistoryScreen()),
      AppRoutes.statistics => _page(settings, const StatisticsScreen()),
      AppRoutes.settings => _page(settings, const SettingsScreen()),
      _ => _page(settings, const Scaffold(body: ErrorState(message: 'That page does not exist.'))),
    };
  }

  static MaterialPageRoute<dynamic> _page(RouteSettings settings, Widget child) =>
      MaterialPageRoute<dynamic>(settings: settings, builder: (_) => child);
}

// ---------------------------------------------------------------------------
// Minimal localisation delegates so Material/Widgets/Cupertino built-in
// widgets (date pickers, text fields, directional icons) respect the chosen
// locale without pulling in the full flutter_localizations package.
// ---------------------------------------------------------------------------

class _FallbackMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _FallbackMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      DefaultMaterialLocalizations.load(locale);

  @override
  bool shouldReload(_FallbackMaterialLocalizationsDelegate old) => false;
}

class _FallbackWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const _FallbackWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      DefaultWidgetsLocalizations.load(locale);

  @override
  bool shouldReload(_FallbackWidgetsLocalizationsDelegate old) => false;
}

class _FallbackCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _FallbackCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      DefaultCupertinoLocalizations.load(locale);

  @override
  bool shouldReload(_FallbackCupertinoLocalizationsDelegate old) => false;
}
