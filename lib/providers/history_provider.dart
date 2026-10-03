import 'package:flutter/foundation.dart';

import '../core/errors/app_exception.dart';
import '../core/utils/logger.dart';
import '../models/statistics.dart';
import '../providers/committee_provider.dart' show AsyncValue;
import '../services/statistics_service.dart';

/// State for the history screen: every period across every committee, newest
/// first, with a committee filter.
///
/// Like the dashboard this is its own read model rather than an extension of
/// [CommitteeProvider] — history needs different aggregates, and mixing them
/// would mean loading a table nobody on that screen looks at.
class HistoryProvider extends ChangeNotifier {
  HistoryProvider({required StatisticsService statisticsService}) : _statistics = statisticsService;

  final StatisticsService _statistics;

  static const AppLogger _log = AppLogger('HistoryProvider');

  AsyncValue<List<PeriodCollection>> _state = const AsyncValue<List<PeriodCollection>>.idle();
  AsyncValue<List<PeriodCollection>> get state => _state;

  List<PeriodCollection> _all = const <PeriodCollection>[];
  List<PeriodCollection> get all => _all;

  String? _committeeFilter;
  String? get committeeFilter => _committeeFilter;

  /// The distinct committees present in the loaded history, for the filter chips.
  List<String> get committeeNames {
    final List<String> names =
        _all.map((PeriodCollection p) => p.committeeName).toSet().toList(growable: false)..sort();
    return names;
  }

  List<PeriodCollection> get visible => _committeeFilter == null
      ? _all
      : _all
            .where((PeriodCollection p) => p.committeeName == _committeeFilter)
            .toList(growable: false);

  /// Closed periods grouped under their committee, ready to render as sections.
  Map<String, List<PeriodCollection>> get grouped {
    final Map<String, List<PeriodCollection>> map = <String, List<PeriodCollection>>{};
    for (final PeriodCollection period in visible) {
      map.putIfAbsent(period.committeeName, () => <PeriodCollection>[]).add(period);
    }
    return map;
  }

  int get completedTurns => _all.where((PeriodCollection p) => p.isClosed).length;

  Future<void> load() async {
    _state = _state.isReady
        ? AsyncValue<List<PeriodCollection>>.loading(previous: _state.data)
        : const AsyncValue<List<PeriodCollection>>.loading();
    notifyListeners();
    try {
      _all = await _statistics.allHistory();
      _state = AsyncValue<List<PeriodCollection>>.ready(_all);
    } catch (error) {
      _log.error('Could not load history', error);
      _state = AsyncValue<List<PeriodCollection>>.failed(describeError(error));
    }
    notifyListeners();
  }

  void filterBy(String? committeeName) {
    if (_committeeFilter == committeeName) return;
    _committeeFilter = committeeName;
    notifyListeners();
  }
}
