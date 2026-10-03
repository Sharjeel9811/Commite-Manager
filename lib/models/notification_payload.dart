import 'package:flutter/material.dart';

/// The kinds of reminder the app can raise.
///
/// An enum is used (instead of free strings) so the notification channel,
/// the icon and the wording can never drift apart.
enum AppNotificationType {
  paymentUpcoming('Upcoming payment', 'Payment reminder', Icons.payments_outlined),
  paymentDueToday('Payment due today', 'Payment due today', Icons.event_available),
  paymentOverdue('Payment overdue', 'Overdue payment', Icons.warning_amber_rounded),
  turnUpcoming('Upcoming committee turn', 'Turn reminder', Icons.emoji_events_outlined),
  myTurn('Your turn is coming up', 'Your turn', Icons.celebration_outlined),
  committeeComplete('Committee completed', 'Committee complete', Icons.verified),
  paymentReceived('Payment recorded', 'Payment received', Icons.check_circle_outline);

  const AppNotificationType(this.title, this.channelName, this.icon);

  final String title;
  final String channelName;
  final IconData icon;
}

/// A notification request, independent of any notification plugin.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.payload,
  });

  /// Stable numeric id — must be deterministic so a re-schedule replaces the
  /// previous one instead of creating duplicates.
  final int id;
  final AppNotificationType type;
  final String title;
  final String body;

  /// Opaque string used to deep-link when the user taps the notification
  /// (for example `committee:<id>`).
  final String? payload;

  @override
  String toString() => 'AppNotification($id, $type, "$title")';
}
