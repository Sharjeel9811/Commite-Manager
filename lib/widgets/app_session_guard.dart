import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/app_routes.dart';
import '../core/utils/logger.dart';
import '../di/service_locator.dart';
import '../providers/auth_provider.dart';
import '../services/interfaces/notification_service.dart';

/// Owns the two decisions that cannot live inside a screen: how long an
/// authenticated session survives, and where a notification tap should land.
///
/// It sits above [MaterialApp] because both need a navigator and a lifecycle
/// hook, neither of which a pushed route owns.
class AppSessionGuard extends StatefulWidget {
  const AppSessionGuard({required this.builder, this.now, super.key});

  /// Receives the navigator key the guarded [MaterialApp] must use, so a
  /// notification deep link can be pushed from inside the guard.
  final Widget Function(GlobalKey<NavigatorState> navigatorKey) builder;

  /// Reads the wall clock. Exists because the idle window has to be measured
  /// with real time (Android suspends timers while backgrounded) and real time
  /// is not something a widget test can advance. Production leaves it alone.
  final DateTime Function()? now;

  @override
  State<AppSessionGuard> createState() => _AppSessionGuardState();
}

class _AppSessionGuardState extends State<AppSessionGuard> with WidgetsBindingObserver {
  static const AppLogger _log = AppLogger('SessionGuard');

  /// The payload format `ReminderService` schedules: `committee:<id>`.
  static const String _committeePrefix = 'committee:';

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  AuthProvider? _auth;
  bool _wired = false;
  Timer? _idleTimer;
  late DateTime _lastActivity;
  DateTime? _backgroundedAt;

  /// A tap that arrived while the app was locked, replayed once the user is in.
  String? _pendingCommitteeId;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _lastActivity = _now;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;

    final AuthProvider auth = context.read<AuthProvider>();
    _auth = auth;
    auth.addListener(_onAuthChanged);

    final ServiceLocator locator = ServiceLocator.instance;
    if (locator.isInitialised) {
      locator.get<NotificationService>().onTap(_onNotificationTap);
    }

    // A cold start from a notification reports its payload through launch
    // details rather than the tap callback, so it is asked for once the first
    // frame is up and a navigator exists.
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeLaunchPayload());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth?.removeListener(_onAuthChanged);
    _idleTimer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------ Session

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // A second pause (notification shade, rotation) must not reset the clock.
        _backgroundedAt ??= _now;
        _idleTimer?.cancel();
        _idleTimer = null;
      case AppLifecycleState.resumed:
        final DateTime? since = _backgroundedAt;
        _backgroundedAt = null;
        // Android suspends timers while backgrounded, so time away has to be
        // measured with a wall clock rather than a countdown.
        if (since != null && _now.difference(since) >= _idleTimeout) {
          _lock();
          return;
        }
        _restartIdleTimer();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _markActive() {
    _lastActivity = _now;
    _restartIdleTimer();
  }

  /// The user's own chosen window, falling back to the app default.
  ///
  /// Read on demand rather than cached: the guard is not a `ChangeNotifier`
  /// listener for the sake of one number, and a setting changed in Settings
  /// takes effect on the next interaction without a restart.
  Duration get _idleTimeout {
    final int? minutes = _auth?.preferences.lockTimeoutMinutes;
    if (minutes == null || minutes <= 0) return AppConstants.sessionIdleTimeout;
    return Duration(minutes: minutes);
  }

  /// Arms one timer for the remaining idle time. A single timer rather than a
  /// repeating one, so an active app is not woken up every few seconds for
  /// nothing.
  void _restartIdleTimer() {
    _idleTimer?.cancel();
    if (!(_auth?.isAuthenticated ?? false)) return;
    final Duration timeout = _idleTimeout;
    final Duration elapsed = _now.difference(_lastActivity);
    if (elapsed >= timeout) {
      _lock();
      return;
    }
    _idleTimer = Timer(timeout - elapsed, () {
      if (mounted) _lock();
    });
  }

  void _lock() {
    _idleTimer?.cancel();
    _idleTimer = null;
    final AuthProvider? auth = _auth;
    // Only an open session can be closed. Without this, returning to the app
    // after the lock screen itself had gone to the background would try to lock
    // a second time, and the "stayed locked" case would look like a fresh event.
    if (auth == null || !auth.isAuthenticated) return;
    unawaited(auth.lock());
  }

  // ------------------------------------------------------------ Notifications

  Future<void> _consumeLaunchPayload() async {
    final ServiceLocator locator = ServiceLocator.instance;
    if (!locator.isInitialised) return;
    final String? payload = await locator.get<NotificationService>().launchPayload();
    if (!mounted || payload == null) return;
    _log.info('App launched from a notification tap');
    _onNotificationTap(payload);
  }

  void _onNotificationTap(String? payload) {
    final String? committeeId = _committeeIdOf(payload);
    if (committeeId == null) {
      _log.warn('Ignoring a notification with an unrecognised payload');
      return;
    }
    // A tap while the app is locked must not push a screen over the lock screen,
    // so the intent is held until the user is actually signed in.
    if (!(_auth?.isAuthenticated ?? false)) {
      _pendingCommitteeId = committeeId;
      return;
    }
    _openCommittee(committeeId);
  }

  void _onAuthChanged() {
    final AuthProvider? auth = _auth;
    if (auth == null) return;

    // A session that has just opened must start its idle window immediately.
    // The timer is otherwise only armed by a tap or a resume, so a user who
    // signed in and then put the phone down without touching the screen would
    // never be locked.
    if (auth.isAuthenticated && _idleTimer == null && _backgroundedAt == null) {
      _lastActivity = _now;
      _restartIdleTimer();
    }

    final String? pending = _pendingCommitteeId;
    if (pending == null || !auth.isAuthenticated) return;
    _pendingCommitteeId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openCommittee(pending);
    });
  }

  String? _committeeIdOf(String? payload) {
    if (payload == null || !payload.startsWith(_committeePrefix)) return null;
    final String id = payload.substring(_committeePrefix.length);
    return id.isEmpty ? null : id;
  }

  void _openCommittee(String committeeId) {
    final NavigatorState? navigator = _navigatorKey.currentState;
    if (navigator == null) {
      _log.warn('No navigator available yet; deep link dropped');
      return;
    }
    navigator.pushNamed(AppRoutes.committeeDetails, arguments: committeeId);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Any deliberate touch counts as activity, so a user reading a long screen
      // is not locked out mid-task.
      onPointerDown: (_) => _markActive(),
      child: widget.builder(_navigatorKey),
    );
  }
}
