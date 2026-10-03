import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import '../../models/notification_payload.dart';
import '../interfaces/notification_service.dart';

/// The real implementation of [NotificationService], backed by
/// `flutter_local_notifications`.
///
/// All platform/plugin knowledge is confined to this file — the rest of the app
/// only ever sees the [NotificationService] interface.
class LocalNotificationService implements NotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  static const AppLogger _log = AppLogger('LocalNotifications');

  bool _initialised = false;
  void Function(String? payload)? _onTap;

  @override
  void onTap(void Function(String? payload) handler) => _onTap = handler;

  @override
  Future<void> initialize() async {
    if (_initialised) return;
    try {
      tzdata.initializeTimeZones();
      await _applyLocalTimeZone();

      const AndroidInitializationSettings android = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const DarwinInitializationSettings ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: _handleResponse,
      );

      _initialised = true;
      _log.info('Notification service ready');
    } catch (error, stackTrace) {
      // Notifications are a convenience: never let them stop the app booting.
      _log.error('Could not initialise notifications', error, stackTrace);
    }
  }

  Future<void> _applyLocalTimeZone() async {
    try {
      final Object info = await FlutterTimezone.getLocalTimezone();
      final String name = _extractIdentifier(info);
      tz.setLocalLocation(tz.getLocation(name));
      _log.info('Timezone set to $name');
    } catch (error) {
      _log.warn('Falling back to UTC timezone: $error');
      tz.setLocalLocation(tz.UTC);
    }
  }

  /// `flutter_timezone` returns a `TimezoneInfo` in v4 but a plain `String` in
  /// older versions; handle both without a cast error.
  String _extractIdentifier(Object info) {
    if (info is String) return info;
    try {
      final Object? identifier = (info as dynamic).identifier;
      if (identifier is String && identifier.isNotEmpty) return identifier;
    } on NoSuchMethodError {
      // fall through
    }
    return 'UTC';
  }

  void _handleResponse(NotificationResponse response) {
    final String? payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      _onTap?.call(payload);
    }
  }

  @override
  Future<String?> launchPayload() async {
    if (!_initialised) await initialize();
    if (!_initialised) return null;
    try {
      final NotificationAppLaunchDetails? details = await _plugin
          .getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      final String? payload = details.notificationResponse?.payload;
      return (payload == null || payload.isEmpty) ? null : payload;
    } catch (error) {
      _log.error('Could not read the launch notification payload', error);
      return null;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final AndroidFlutterLocalNotificationsPlugin? android = _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        final bool? granted = await android?.requestNotificationsPermission();
        final bool? exact = await android?.requestExactAlarmsPermission();
        if (granted == true && kDebugMode && exact == false) {
          _log.warn('Exact-alarm permission not granted; reminders may be approximate.');
        }
        return granted ?? true;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final IOSFlutterLocalNotificationsPlugin? ios = _plugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? true;
      }
    } catch (error) {
      _log.error('Permission request failed', error);
    }
    return true;
  }

  @override
  Future<bool> hasPermission() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final AndroidFlutterLocalNotificationsPlugin? android = _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        return await android?.areNotificationsEnabled() ?? true;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final IOSFlutterLocalNotificationsPlugin? ios = _plugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        return (await ios?.checkPermissions())?.isEnabled ?? true;
      }
    } catch (error) {
      _log.error('Permission check failed', error);
    }
    return true;
  }

  @override
  Future<void> show(AppNotification notification) async {
    if (!_initialised) await initialize();
    try {
      await _plugin.show(
        notification.id,
        notification.title,
        notification.body,
        _details(notification.type),
        payload: notification.payload,
      );
    } catch (error, stackTrace) {
      _log.error('Could not show notification', error, stackTrace);
    }
  }

  @override
  Future<void> schedule(AppNotification notification, DateTime at) async {
    if (!_initialised) await initialize();
    try {
      final tz.TZDateTime when = tz.TZDateTime.from(at, tz.local);
      if (when.isBefore(tz.TZDateTime.now(tz.local))) {
        // Never schedule in the past — show it immediately instead.
        await show(notification);
        return;
      }
      await _plugin.zonedSchedule(
        notification.id,
        notification.title,
        notification.body,
        when,
        _details(notification.type),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: notification.payload,
        matchDateTimeComponents: null,
      );
    } catch (error, stackTrace) {
      _log.error('Could not schedule notification', error, stackTrace);
    }
  }

  @override
  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (error) {
      _log.error('Could not cancel $id', error);
    }
  }

  @override
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (error) {
      _log.error('Could not cancel all notifications', error);
    }
  }

  @override
  Future<List<int>> pendingIds() async {
    try {
      final List<PendingNotificationRequest> pending = await _plugin.pendingNotificationRequests();
      return pending.map((PendingNotificationRequest p) => p.id).toList(growable: false);
    } catch (error) {
      _log.error('Could not list pending notifications', error);
      return const <int>[];
    }
  }

  /// Builds the platform-specific details object for a notification type.
  NotificationDetails _details(AppNotificationType type) {
    final bool urgent =
        type == AppNotificationType.paymentOverdue || type == AppNotificationType.paymentDueToday;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId(type),
        type.channelName,
        channelDescription: AppConstants.notificationChannelDescription,
        importance: urgent ? Importance.max : Importance.high,
        priority: urgent ? Priority.max : Priority.high,
        styleInformation: BigTextStyleInformation(type.title),
        category: AndroidNotificationCategory.reminder,
        color: const Color(0xFF4F46E5),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  String _channelId(AppNotificationType type) =>
      '${AppConstants.notificationChannelId}_${type.name}';
}
