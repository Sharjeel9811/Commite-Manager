import '../core/utils/currency_formatter.dart';
import '../core/utils/logger.dart';
import '../models/committee.dart';
import '../models/enums.dart';
import '../models/notification_payload.dart';
import '../models/payment.dart';
import '../models/payment_schedule.dart';
import '../repositories/interfaces/committee_repository.dart';
import '../repositories/interfaces/payment_repository.dart';
import 'interfaces/notification_service.dart';
import 'payment_calculator.dart';

/// Decides *which* reminders to raise and asks [NotificationService] to raise
/// them. It never touches the notification plugin itself — that is the
/// implementation's job (Single Responsibility + Dependency Inversion).
class ReminderService {
  ReminderService({
    required NotificationService notificationService,
    required CommitteeRepository committeeRepository,
    required PaymentRepository paymentRepository,
    required PaymentCalculator calculator,
  }) : _notifications = notificationService,
       _committees = committeeRepository,
       _payments = paymentRepository,
       _calculator = calculator;

  final NotificationService _notifications;
  final CommitteeRepository _committees;
  final PaymentRepository _payments;
  final PaymentCalculator _calculator;

  static const AppLogger _log = AppLogger('ReminderService');

  /// Rebuilds every reminder for the whole app. Called at start-up and after
  /// any payment is recorded, so the schedule always matches the data.
  ///
  /// Guards against concurrent calls — if a reschedule is already running,
  /// the second call is silently dropped. This prevents the payment screen
  /// (which calls reschedule after every tap) from stacking up identical work.
  bool _rescheduling = false;

  Future<void> rescheduleAll({int reminderHour = 9}) async {
    if (_rescheduling) return; // drop concurrent duplicates
    _rescheduling = true;
    try {
      // initialize() is called once at app start by the notification service
      // itself. Calling it again here re-registers the response handler on
      // some Android versions and causes duplicate notification delivery.
      // Do NOT call initialize() here.
      await _notifications.cancelAll();
      final List<Committee> committees = await _committees.getAll();
      for (final Committee committee in committees) {
        if (committee.status == CommitteeStatus.archived) continue;
        await scheduleForCommittee(committee, reminderHour: reminderHour);
      }
      _log.info('Reminders rebuilt');
    } catch (error) {
      // A reminder failure must never interrupt a payment.
      _log.error('Could not rebuild reminders', error);
    } finally {
      _rescheduling = false;
    }
  }

  /// Builds one reminder for the earliest period that still has unpaid money.
  ///
  /// Limiting this to the next actionable period prevents a four-member
  /// committee from creating four future notifications at once.
  Future<void> scheduleForCommittee(
    Committee committee, {
    int reminderHour = 9,
  }) async {
    if (committee.status == CommitteeStatus.completed) return;

    final List<Payment> payments = await _payments.getByCommittee(committee.id);
    final List<PaymentSchedule> periods = await _scheduleOf(committee);
    for (final PaymentSchedule period in periods) {
      if (period.isClosed) continue;

      final List<Payment> inPeriod = payments
          .where((Payment p) => p.periodNumber == period.periodNumber)
          .toList();
      final int pending = _calculator.pendingCount(inPeriod);
      if (pending == 0) continue;

      final double outstanding = _calculator.pendingInPeriod(inPeriod);
      final String periodLabel = period.label;

      // One reminder per open period prevents the pre-due, due, overdue, and
      // turn reminders from appearing as duplicate notifications for one item.
      DateTime dueDay = _atHour(period.dueDate, reminderHour);
      // A reschedule happens after every payment write. Scheduling an already
      // elapsed due date as "now" would show the same reminder again after
      // each write, which looks like duplicate notifications to the user.
      if (dueDay.isBefore(DateTime.now())) {
        final DateTime tomorrow = DateTime.now().add(const Duration(days: 1));
        dueDay = _atHour(tomorrow, reminderHour);
      }
      await _notifications.schedule(
        AppNotification(
          id: _paymentId('due', committee.id, period.periodNumber),
          type: AppNotificationType.paymentUpcoming,
          title: 'Payment reminder',
          body:
              '${committee.name} • $periodLabel: ${_currency(outstanding)} '
              'from $pending member${pending == 1 ? '' : 's'}.',
          payload: 'committee:${committee.id}',
        ),
        dueDay,
      );
      _log.info('${committee.name}: 1 reminder scheduled');
      return;
    }

    _log.info('${committee.name}: no unpaid period reminder needed');
  }

  Future<List<PaymentSchedule>> _scheduleOf(Committee committee) async {
    // The schedule is derived from the committee definition, so it can be built
    // without another repository dependency.
    return _calculator.buildSchedule(committee);
  }

  DateTime _atHour(DateTime day, int hour) =>
      DateTime(day.year, day.month, day.day, hour, 0);

  String _currency(double amount) => CurrencyFormatter.format(amount);

  int _paymentId(String prefix, String committeeId, int period) =>
      LocalNotificationId.forKey('$prefix:$committeeId:$period');
}

/// Deterministic notification ids, kept in the domain layer so both the
/// scheduler and the settings screen agree on them.
class LocalNotificationId {
  const LocalNotificationId._();

  static int forKey(String key) {
    int hash = 0x811c9dc5;
    for (final int unit in key.codeUnits) {
      hash = (hash ^ unit) & 0xFFFFFFFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final int value = hash & 0x7FFFFFFF;
    return value == 0 ? 1 : value;
  }
}
