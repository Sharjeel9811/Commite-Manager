import 'package:flutter/foundation.dart';

import '../core/errors/app_exception.dart';
import '../core/utils/logger.dart';
import '../models/statistics.dart';
import '../providers/committee_provider.dart' show AsyncValue;
import '../services/statistics_service.dart';

/// Read model for the statistics screen: headline totals plus a per-period
/// collection trend for the chart.
class StatisticsProvider extends ChangeNotifier {
  StatisticsProvider({required StatisticsService statisticsService})
    : _statistics = statisticsService;

  final StatisticsService _statistics;

  static const AppLogger _log = AppLogger('StatisticsProvider');

  AsyncValue<DashboardStats> _state = const AsyncValue<DashboardStats>.idle();
  AsyncValue<DashboardStats> get state => _state;

  DashboardStats? get stats => _state.data;

  List<double> _trend = const <double>[];
  List<double> get trend => _trend;

  List<String> _labels = const <String>[];
  List<String> get labels => _labels;

  double get trendTotal => _trend.fold<double>(0, (double a, double b) => a + b);

  double get trendPeak => _trend.isEmpty ? 0 : _trend.reduce((double a, double b) => a > b ? a : b);

  double get trendAverage => _trend.isEmpty ? 0 : trendTotal / _trend.length;

  Future<void> load() async {
    _state = _state.isReady
        ? AsyncValue<DashboardStats>.loading(previous: _state.data)
        : const AsyncValue<DashboardStats>.loading();
    notifyListeners();
    try {
      _state = AsyncValue<DashboardStats>.ready(await _statistics.dashboard());
      final ({List<double> values, List<String> labels}) series = await _statistics
          .collectionTrend();
      _trend = series.values;
      _labels = series.labels;
    } catch (error) {
      _log.error('Could not load statistics', error);
      _state = AsyncValue<DashboardStats>.failed(describeError(error));
    }
    notifyListeners();
  }
}
