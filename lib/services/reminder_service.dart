import '../core/utils/app_date_utils.dart';
import '../core/utils/currency_formatter.dart';
import '../core/utils/logger.dart';
import '../models/committee.dart';
import '../models/committee_turn.dart';
import '../models/enums.dart';
import '../models/notification_payload.dart';
import '../models/payment.dart';
import '../models/payment_schedule.dart';
import '../repositories/interfaces/committee_repository.dart';
import '../repositories/interfaces/payment_repository.dart';
import '../repositories/interfaces/turn_repository.dart';
import 'interfaces/notification_service.dart';
import 'payment_calculator.dart';

/// Decides *which* reminders to raise and asks [NotificationService] to raise
/// them. It never touches the notification plugin itself — that is the
/// implementation's job (Single Responsibility + Dependency Inversion).
class ReminderService {
  const ReminderService({
    required NotificationService notificationService,
    required CommitteeRepository committeeRepository,
    required PaymentRepository paymentRepository,
    required TurnRepository turnRepository,
    required PaymentCalculator calculator,
  }) : _notifications = notificationService,
       _committees = committeeRepository,
       _payments = paymentRepository,
       _turns = turnRepository,
       _calculator = calculator;

  final NotificationService _notifications;
  final CommitteeRepository _committees;
  final PaymentRepository _payments;
  final TurnRepository _turns;
  final PaymentCalculator _calculator;

  static const AppLogger _log = AppLogger('ReminderService');

  /// Rebuilds every reminder for the whole app. Called at start-up and after
  /// any payment is recorded, so the schedule always matches the data.
  Future<void> rescheduleAll({int reminderHour = 9}) async {
    try {
      await _notifications.initialize();
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
    }
  }

  /// Builds the reminders for one committee:
  ///  * the day before a due date,
  ///  * on the due date itself,
  ///  * the day after, if money is still missing (overdue),
  ///  * a few days before the next recipient's turn.
  Future<void> scheduleForCommittee(
    Committee committee, {
    int reminderHour = 9,
  }) async {
    if (committee.status == CommitteeStatus.completed) return;

    final List<Payment> payments = await _payments.getByCommittee(committee.id);
    final List<PaymentSchedule> periods = await _scheduleOf(committee);
    final List<CommitteeTurn> turns = await _turns.getByCommittee(committee.id);

    int scheduled = 0;
    for (final PaymentSchedule period in periods) {
      if (period.isClosed) continue;

      final List<Payment> inPeriod = payments
          .where((Payment p) => p.periodNumber == period.periodNumber)
          .toList();
      final int pending = _calculator.pendingCount(inPeriod);
      if (pending == 0) continue;

      final double outstanding = _calculator.pendingInPeriod(inPeriod);
      final String periodLabel = period.label;

      // 1 day before
      final DateTime dayBefore = _atHour(
        AppDateUtils.addDays(period.dueDate, -1),
        reminderHour,
      );
      await _notifications.schedule(
        AppNotification(
          id: _paymentId('pre', committee.id, period.periodNumber),
          type: AppNotificationType.paymentUpcoming,
          title: 'Payment due tomorrow',
          body:
              '${committee.name} • $periodLabel: ${_currency(outstanding)} '
              'pending from $pending member${pending == 1 ? '' : 's'}.',
          payload: 'committee:${committee.id}',
        ),
        dayBefore,
      );

      // On the day
      final DateTime dueDay = _atHour(period.dueDate, reminderHour);
      await _notifications.schedule(
        AppNotification(
          id: _paymentId('due', committee.id, period.periodNumber),
          type: AppNotificationType.paymentDueToday,
          title: 'Payment due today',
          body:
              '${committee.name} • $periodLabel: collect ${_currency(outstanding)} '
              'from $pending member${pending == 1 ? '' : 's'}.',
          payload: 'committee:${committee.id}',
        ),
        dueDay,
      );

      // Overdue follow-up
      final DateTime overdueDay = _atHour(
        AppDateUtils.addDays(period.dueDate, 1),
        reminderHour,
      );
      await _notifications.schedule(
        AppNotification(
          id: _paymentId('over', committee.id, period.periodNumber),
          type: AppNotificationType.paymentOverdue,
          title: 'Payment overdue',
          body:
              '${committee.name} • $periodLabel: ${_currency(outstanding)} '
              'still outstanding from $pending member${pending == 1 ? '' : 's'}.',
          payload: 'committee:${committee.id}',
        ),
        overdueDay,
      );
      scheduled += 3;
    }

    // Upcoming turn
    for (final CommitteeTurn turn in turns) {
      if (turn.isCompleted) continue;
      if (turn.status == TurnStatus.upcoming &&
          turn.turnNumber > committee.currentTurn + 1) {
        continue; // only remind about the immediate next turn
      }
      final DateTime remindOn = _atHour(
        AppDateUtils.addDays(turn.dueDate, -3),
        reminderHour,
      );
      final bool isMyTurn = turn.turnNumber == committee.currentTurn;
      await _notifications.schedule(
        AppNotification(
          id: _turnId(committee.id, turn.turnNumber),
          type: isMyTurn
              ? AppNotificationType.myTurn
              : AppNotificationType.turnUpcoming,
          title: isMyTurn
              ? 'Your committee turn is coming up'
              : 'Next committee turn',
          body:
              '${committee.name}: turn ${turn.turnNumber} is due on '
              '${AppDateUtils.formatCompact(turn.dueDate)} — pool ${_currency(turn.expectedAmount)}.',
          payload: 'committee:${committee.id}',
        ),
        remindOn,
      );
      scheduled++;
      break; // one upcoming-turn reminder per committee is enough
    }

    _log.info('${committee.name}: $scheduled reminder(s) scheduled');
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

  int _turnId(String committeeId, int turn) =>
      LocalNotificationId.forKey('turn:$committeeId:$turn');
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
