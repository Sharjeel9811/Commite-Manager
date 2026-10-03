import 'package:flutter/foundation.dart';

import '../core/errors/app_exception.dart';
import '../core/utils/app_date_utils.dart';
import '../core/utils/logger.dart';
import '../models/committee.dart';
import '../models/statistics.dart';
import '../services/committee_service.dart';
import '../services/statistics_service.dart';
import 'committee_provider.dart' show AsyncValue;
import 'payment_provider.dart';

/// The dashboard's read model.
///
/// It is deliberately *separate* from [CommitteeProvider]: the dashboard needs
/// aggregated numbers (pending counts, pool totals, next deadline) while the
/// committees tab needs a list. One giant "AppProvider" holding both would
/// rebuild half the UI on every keystroke in a search box.
class DashboardProvider extends ChangeNotifier {
  DashboardProvider({
    required StatisticsService statisticsService,
    required CommitteeService committeeService,
  }) : _statistics = statisticsService,
       _committees = committeeService;

  final StatisticsService _statistics;
  final CommitteeService _committees;

  static const AppLogger _log = AppLogger('DashboardProvider');

  AsyncValue<DashboardStats> _state = const AsyncValue<DashboardStats>.idle();
  AsyncValue<DashboardStats> get state => _state;

  DashboardStats? get stats => _state.data;

  List<Committee> _activeCommittees = const <Committee>[];
  List<Committee> get activeCommittees => _activeCommittees;

  UpcomingDeadline? _deadline;
  UpcomingDeadline? get deadline => _deadline;

  /// Computed from the clock instead of stored, so it can never drift.
  bool get isMorning {
    final int hour = DateTime.now().hour;
    return hour >= 5 && hour < 12;
  }

  void Function(String)? _busListener;

  Future<void> load() async {
    _state = _state.isReady
        ? AsyncValue<DashboardStats>.loading(previous: _state.data)
        : const AsyncValue<DashboardStats>.loading();
    notifyListeners();
    try {
      _state = AsyncValue<DashboardStats>.ready(await _statistics.dashboard());
      _activeCommittees = (await _committees.activeCommittees()).take(3).toList(growable: false);
      _deadline = await _committees.nextDeadline();
    } catch (error) {
      _log.error('Could not load the dashboard', error);
      _state = AsyncValue<DashboardStats>.failed(describeError(error));
    }
    notifyListeners();
  }

  /// Subscribes to the payment bus so the dashboard is never stale.
  void listenToPaymentChanges() {
    if (_busListener != null) return;
    _busListener = (String _) => load();
    PaymentChangeBus.instance.subscribe(_busListener!);
  }

  @override
  void dispose() {
    final void Function(String)? listener = _busListener;
    if (listener != null) {
      PaymentChangeBus.instance.unsubscribe(listener);
      _busListener = null;
    }
    super.dispose();
  }

  // ------------------------------------------------------------- Convenience

  String get greeting {
    if (isMorning) return 'Good morning';
    if (DateTime.now().hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get deadlineHeadline {
    final UpcomingDeadline? d = _deadline;
    if (d == null) return 'Nothing due';
    if (d.isOverdue) return 'Overdue';
    if (d.isToday) return 'Due today';
    return AppDateUtils.relativeDueText(d.period.dueDate, asOf: d.now);
  }

  String get deadlineSubtitle {
    final UpcomingDeadline? d = _deadline;
    if (d == null) return 'All committees are up to date';
    return '${d.committee.name} • ${d.period.label}';
  }

  String get deadlineDateLabel {
    final UpcomingDeadline? d = _deadline;
    if (d == null) return '';
    return AppDateUtils.formatCompact(d.period.dueDate);
  }
}
