import '../core/config/app_config.dart';
import '../core/utils/logger.dart';
import '../database/app_database.dart';
import '../models/app_settings.dart';
import '../repositories/implementations/shared_preferences_settings_repository.dart';
import '../repositories/implementations/sqlite_committee_repository.dart';
import '../repositories/implementations/sqlite_member_repository.dart';
import '../repositories/implementations/sqlite_otp_repository.dart';
import '../repositories/implementations/sqlite_payment_repository.dart';
import '../repositories/implementations/sqlite_schedule_repository.dart';
import '../repositories/implementations/sqlite_turn_repository.dart';
import '../repositories/implementations/sqlite_user_repository.dart';
import '../repositories/interfaces/committee_repository.dart';
import '../repositories/interfaces/member_repository.dart';
import '../repositories/interfaces/payment_repository.dart';
import '../repositories/interfaces/schedule_repository.dart';
import '../repositories/interfaces/settings_repository.dart';
import '../repositories/interfaces/turn_repository.dart';
import '../repositories/interfaces/user_repository.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/committee_service.dart';
import '../services/demo_data_service.dart';
import '../services/implementations/gateway_otp_sender.dart';
import '../services/implementations/local_biometric_service.dart';
import '../services/implementations/local_notification_service.dart';
import '../services/implementations/supabase_otp_sender.dart';
import '../services/implementations/supabase_service.dart';
import '../services/interfaces/biometric_service.dart';
import '../services/interfaces/notification_service.dart';
import '../services/interfaces/otp_sender.dart';
import '../services/member_service.dart';
import '../services/otp_service.dart';
import '../services/payment_calculator.dart';
import '../services/payment_service.dart';
import '../services/reminder_service.dart';
import '../services/schedule_service.dart';
import '../services/statistics_service.dart';
import '../services/turn_service.dart';

/// Composition root — the one place in the whole app that knows which concrete
/// implementation is used for each abstraction.
///
/// This is **Dependency Injection without a framework**: services receive their
/// collaborators through their constructors, and start-up is the only code that
/// ever names a concrete class. Because of that, a unit test can build a
/// `CommitteeService` with in-memory repositories in a few lines, and replacing
/// SQLite with another store would touch this file only.
class ServiceLocator {
  ServiceLocator._();

  static final ServiceLocator instance = ServiceLocator._();
  static const AppLogger _log = AppLogger('ServiceLocator');

  final Map<Type, Object> _registry = <Type, Object>{};

  bool get isInitialised => _registry.isNotEmpty;

  // ------------------------------------------------------------- Registration

  /// Registers [instance] under the interface type [T].
  void register<T extends Object>(T instance) => _registry[T] = instance;

  /// Resolves a dependency. Throws a clear, actionable error if wiring is
  /// missing, turning "null somewhere in the UI" into an obvious start-up bug.
  T get<T extends Object>() {
    final Object? instance = _registry[T];
    if (instance == null) {
      throw StateError(
        'Dependency "$T" was requested before it was registered. '
        'Call ServiceLocator.instance.wire() during start-up.',
      );
    }
    return instance as T;
  }

  /// Test seam: replace an already-registered dependency.
  void override<T extends Object>(T instance) => register<T>(instance);

  void reset() => _registry.clear();

  // ------------------------------------------------------------------ Wiring

  /// Builds the whole object graph into [instance]. Read it top to bottom:
  /// infrastructure, then repositories, then services. The order matters — which
  /// is exactly why manual DI stays readable at this size.
  static Future<ServiceLocator> wire({AppDatabase? databaseOverride}) async {
    final ServiceLocator locator = instance..reset();
    locator._buildInfrastructure(databaseOverride);
    await locator._buildRepositories();
    await locator._buildSettings();
    locator._buildCoreServices();
    await locator._buildOtpStack();
    locator._registerAuthServices();
    _log.info('Object graph ready');
    return locator;
  }

  void _buildInfrastructure(AppDatabase? override) {
    register<AppDatabase>(override ?? AppDatabase());
    final CloudSyncService cloudSync = CloudSyncService(get<AppDatabase>());
    register<CloudSyncService>(cloudSync);
    get<AppDatabase>().onDataChanged = cloudSync.push;
    register<PaymentCalculator>(const PaymentCalculator());
    final LocalNotificationService notifications = LocalNotificationService();
    register<LocalNotificationService>(notifications);
    register<NotificationService>(notifications);
    register<BiometricService>(LocalBiometricService());
  }

  Future<void> _buildRepositories() async {
    final AppDatabase db = get<AppDatabase>();

    final SqliteCommitteeRepository committees = SqliteCommitteeRepository(db);
    final SqliteMemberRepository members = SqliteMemberRepository(db);
    final SqlitePaymentRepository payments = SqlitePaymentRepository(db);
    final SqliteScheduleRepository schedules = SqliteScheduleRepository(db);
    final SqliteTurnRepository turns = SqliteTurnRepository(db);
    final SqliteUserRepository users = SqliteUserRepository(db);
    final SqliteOtpRepository otps = SqliteOtpRepository(db);
    final SharedPreferencesSettingsRepository settings = SharedPreferencesSettingsRepository();

    // Registered twice on purpose: once under the interface the application
    // depends on, once under the concrete type for the rare screen that needs
    // an implementation-specific helper.
    register<CommitteeRepository>(committees);
    register<SqliteCommitteeRepository>(committees);
    register<MemberRepository>(members);
    register<SqliteMemberRepository>(members);
    register<PaymentRepository>(payments);
    register<SqlitePaymentRepository>(payments);
    register<ScheduleRepository>(schedules);
    register<SqliteScheduleRepository>(schedules);
    register<TurnRepository>(turns);
    register<SqliteTurnRepository>(turns);
    register<UserRepository>(users);
    register<OtpRepository>(otps);
    register<SqliteUserRepository>(users);
    register<SqliteOtpRepository>(otps);
    register<SettingsRepository>(settings);
    register<SharedPreferencesSettingsRepository>(settings);

    _log.info('Repositories registered');
  }

  Future<void> _buildSettings() async {
    final AppSettings settings = await get<SettingsRepository>().load();
    register<AppSettings>(settings);
    _log.info('Settings loaded (theme=${settings.themePreference.name})');
  }

  void _buildCoreServices() {
    final AppDatabase db = get<AppDatabase>();
    final PaymentCalculator calculator = get<PaymentCalculator>();

    final ScheduleService scheduleService = ScheduleService(
      committeeRepository: get<CommitteeRepository>(),
      memberRepository: get<MemberRepository>(),
      scheduleRepository: get<ScheduleRepository>(),
      turnRepository: get<TurnRepository>(),
      paymentRepository: get<PaymentRepository>(),
      calculator: calculator,
      appDatabase: db,
    );

    final TurnService turnService = TurnService(
      committeeRepository: get<CommitteeRepository>(),
      memberRepository: get<MemberRepository>(),
      turnRepository: get<TurnRepository>(),
      paymentRepository: get<PaymentRepository>(),
      scheduleRepository: get<ScheduleRepository>(),
      appDatabase: db,
    );

    register<ScheduleService>(scheduleService);
    register<TurnService>(turnService);

    register<CommitteeService>(
      CommitteeService(
        committeeRepository: get<CommitteeRepository>(),
        memberRepository: get<MemberRepository>(),
        paymentRepository: get<PaymentRepository>(),
        scheduleRepository: get<ScheduleRepository>(),
        turnRepository: get<TurnRepository>(),
        scheduleService: scheduleService,
        turnService: turnService,
        calculator: calculator,
        appDatabase: db,
      ),
    );

    register<MemberService>(
      MemberService(
        memberRepository: get<MemberRepository>(),
        committeeRepository: get<CommitteeRepository>(),
        paymentRepository: get<PaymentRepository>(),
        scheduleService: scheduleService,
        appDatabase: db,
      ),
    );

    register<PaymentService>(
      PaymentService(
        paymentRepository: get<PaymentRepository>(),
        committeeRepository: get<CommitteeRepository>(),
        memberRepository: get<MemberRepository>(),
        scheduleRepository: get<ScheduleRepository>(),
        turnService: turnService,
        calculator: calculator,
        appDatabase: db,
      ),
    );

    register<ReminderService>(
      ReminderService(
        notificationService: get<NotificationService>(),
        committeeRepository: get<CommitteeRepository>(),
        paymentRepository: get<PaymentRepository>(),
        turnRepository: get<TurnRepository>(),
        calculator: calculator,
      ),
    );

    register<StatisticsService>(
      StatisticsService(
        committeeRepository: get<CommitteeRepository>(),
        memberRepository: get<MemberRepository>(),
        paymentRepository: get<PaymentRepository>(),
        turnRepository: get<TurnRepository>(),
        calculator: calculator,
      ),
    );

    register<DemoDataService>(
      DemoDataService(
        committeeService: get<CommitteeService>(),
        paymentService: get<PaymentService>(),
        reminderService: get<ReminderService>(),
      ),
    );
  }

  /// Wires the OTP transport.
  ///
  /// Priority order:
  ///
  ///  1. **Supabase Auth** (default for production / Play Store builds) —
  ///     Supabase generates, emails and checks the code entirely server-side.
  ///     The device never sees the plaintext. Works from anywhere in the world
  ///     with an internet connection. Selected when `SUPABASE_URL` and
  ///     `SUPABASE_ANON_KEY` are supplied at build time (which they always are
  ///     in a Play Store release build).
  ///
  ///  2. **Self-hosted gateway** (developer / on-prem opt-in) — a local
  ///     Nodemailer server that the app POSTs the code to. Only reachable on
  ///     the same network as the server. Selected by setting `OTP_GATEWAY_URL`
  ///     at build time. Never use this for a public Play Store release — users
  ///     outside your LAN will never receive a code.
  ///
  ///  3. **No transport configured** — both `SUPABASE_URL` and
  ///     `OTP_GATEWAY_URL` are empty. `SupabaseOtpSender` is still registered
  ///     and will return a clear "not configured" error at send time so the
  ///     developer knows exactly what is missing, rather than a null-pointer.
  Future<void> _buildOtpStack() async {
    if (AppConfig.useOtpGateway) {
      // Developer / on-prem path. Requires the Node.js server to be reachable.
      register<OtpSender>(GatewayOtpSender());
      _log.info('OTP sender: self-hosted Nodemailer gateway (${AppConfig.otpGatewayUrl})');
    } else {
      // Production path — initialize Supabase eagerly so the client is ready
      // before the first frame reaches the verify screen.
      if (AppConfig.supabaseConfigured) {
        await SupabaseService.ensureInitialized();
        _log.info('OTP sender: Supabase Auth (initialized)');
      } else {
        _log.warn(
          'OTP sender: Supabase Auth selected but SUPABASE_URL / SUPABASE_ANON_KEY are '
          'not set. Rebuild with --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
        );
      }
      register<OtpSender>(const SupabaseOtpSender());
    }
    register<OtpService>(
      OtpService(
        otpRepository: get<OtpRepository>(),
        userRepository: get<UserRepository>(),
        sender: get<OtpSender>(),
      ),
    );
  }

  void _registerAuthServices() {
    register<AuthService>(
      AuthService(
        userRepository: get<UserRepository>(),
        otpService: get<OtpService>(),
        biometricService: get<BiometricService>(),
        database: get<AppDatabase>(),
        cloudSync: get<CloudSyncService>(),
      ),
    );
  }
}
