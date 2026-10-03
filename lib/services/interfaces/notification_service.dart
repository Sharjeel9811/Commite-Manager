import '../../models/notification_payload.dart';

/// Abstraction over "remind the user something".
///
/// ### Liskov Substitution
/// The app only ever talks to this interface. Today the only implementation is
/// `LocalNotificationService`; a `PushNotificationService` or a
/// `SilentNotificationService` (unit tests) can be dropped in without changing
/// a single call site — that is the whole point of the abstraction.
///
/// ### Interface Segregation
/// This interface is deliberately small. Anything that only needs to *show* an
/// error toast implements `AppNotifier` instead, not this.
abstract interface class NotificationService {
  /// Prepares channels and asks the OS for permission. Safe to call repeatedly.
  Future<void> initialize();

  /// Asks the operating system for permission (Android 13+ runtime prompt).
  Future<bool> requestPermission();

  Future<bool> hasPermission();

  /// Shows a notification right now.
  Future<void> show(AppNotification notification);

  /// Schedules a notification for a future moment.
  Future<void> schedule(AppNotification notification, DateTime at);

  /// Cancels one scheduled notification.
  Future<void> cancel(int id);

  /// Cancels everything this app scheduled.
  Future<void> cancelAll();

  /// Identifiers currently scheduled — used by the settings screen.
  Future<List<int>> pendingIds();

  /// Registers the handler invoked when the user taps one of our
  /// notifications. The payload is the opaque string the notification was
  /// scheduled with (for example `committee:<id>`), or `null` when the
  /// notification carried none.
  void onTap(void Function(String? payload) handler);

  /// The payload of the notification that *launched* the app, if the app was
  /// cold-started by a tap. Returns `null` on a normal launch. Callers must
  /// tolerate a null answer even on platforms that cannot report it.
  Future<String?> launchPayload();
}

/// A tiny, UI-facing notifier so screens never import
/// `flutter_local_notifications` directly.
abstract interface class AppNotifier {
  void success(String message);
  void error(String message);
  void info(String message);
}
