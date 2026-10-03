import 'package:flutter/foundation.dart';

import '../core/errors/app_exception.dart';
import '../core/utils/logger.dart';
import '../models/committee.dart';
import '../models/enums.dart';
import '../services/committee_service.dart';
import '../services/reminder_service.dart';

/// Generic "idle / loading / ready / failed" wrapper.
///
/// Every provider in this project reuses it, which is why there is no repeated
/// `bool isLoading, String? error` triple scattered across the state layer.
enum LoadState { idle, loading, ready, failed }

class AsyncValue<T> {
  const AsyncValue({this.state = LoadState.idle, this.data, this.error});

  const AsyncValue.idle() : this(state: LoadState.idle);
  const AsyncValue.loading({T? previous}) : this(state: LoadState.loading, data: previous);
  const AsyncValue.ready(T value) : this(state: LoadState.ready, data: value);
  const AsyncValue.failed(String message) : this(state: LoadState.failed, error: message);

  final LoadState state;
  final T? data;
  final String? error;

  bool get isLoading => state == LoadState.loading;
  bool get isReady => state == LoadState.ready;
  bool get hasError => state == LoadState.failed;
  bool get isEmpty => data == null;

  T get valueOrThrow => data as T;

  AsyncValue<R> map<R>(R Function(T value) transform) {
    final T? current = data;
    if (current == null) return AsyncValue<R>(state: state, error: error);
    return AsyncValue<R>(state: state, data: transform(current), error: error);
  }
}

/// Owns the committee list, the search box and the status filter.
class CommitteeProvider extends ChangeNotifier {
  CommitteeProvider({
    required CommitteeService committeeService,
    required ReminderService reminderService,
  }) : _committees = committeeService,
       _reminders = reminderService;

  final CommitteeService _committees;
  final ReminderService _reminders;

  static const AppLogger _log = AppLogger('CommitteeProvider');

  AsyncValue<List<Committee>> _state = const AsyncValue<List<Committee>>.idle();
  AsyncValue<List<Committee>> get state => _state;

  List<Committee> get items => _state.data ?? const <Committee>[];

  String _query = '';
  String get query => _query;

  CommitteeStatus? _statusFilter;
  CommitteeStatus? get statusFilter => _statusFilter;

  bool get isSearching => _query.trim().isNotEmpty;

  bool _mutating = false;
  bool get isMutating => _mutating;

  int get totalCount => items.length;

  int get activeCount => items.where((Committee c) => c.status == CommitteeStatus.active).length;

  int get completedCount =>
      items.where((Committee c) => c.status == CommitteeStatus.completed).length;

  /// Loads the list, honouring the active search text and status filter.
  Future<void> load() async {
    _state = _state.isReady
        ? AsyncValue<List<Committee>>.loading(previous: _state.data)
        : const AsyncValue<List<Committee>>.loading();
    notifyListeners();
    try {
      final List<Committee> result = _statusFilter == null
          ? await _committees.filterByStatus(null)
          : await _committees.filterByStatus(_statusFilter);
      _state = AsyncValue<List<Committee>>.ready(_applyQuery(result));
    } catch (error) {
      _log.error('Could not load committees', error);
      _state = AsyncValue<List<Committee>>.failed(describeError(error));
    }
    notifyListeners();
  }

  /// Filters the already-loaded list without another database round trip.
  void search(String value) {
    _query = value;
    final List<Committee>? current = _state.data;
    if (current != null) {
      _state = AsyncValue<List<Committee>>.ready(_applyQuery(current));
    }
    notifyListeners();
  }

  Future<void> setStatusFilter(CommitteeStatus? status) async {
    if (_statusFilter == status) return;
    _statusFilter = status;
    await load();
  }

  Future<Committee> create({
    required String name,
    String? description,
    required double contributionAmount,
    required PaymentFrequency frequency,
    required DateTime startDate,
    required List<MemberDraft> memberDrafts,
  }) async {
    _mutating = true;
    notifyListeners();
    try {
      final Committee created = await _committees.create(
        name: name,
        description: description,
        contributionAmount: contributionAmount,
        frequency: frequency,
        startDate: startDate,
        memberDrafts: memberDrafts,
        isDemo: false,
      );
      await _reminders.rescheduleAll();
      await load();
      return created;
    } finally {
      _mutating = false;
      notifyListeners();
    }
  }

  Future<Committee> rename(String id, String name, String? description) async {
    final Committee updated = await _committees.updateDetails(
      id: id,
      name: name,
      description: description,
    );
    await load();
    return updated;
  }

  Future<Committee> changeAmount(String id, double amount) async {
    final Committee updated = await _committees.updateContribution(
      id: id,
      contributionAmount: amount,
    );
    await load();
    return updated;
  }

  Future<Committee> changeStatus(String id, CommitteeStatus status) async {
    final Committee updated = await _committees.setStatus(id, status);
    await load();
    return updated;
  }

  Future<void> delete(String id) async {
    _mutating = true;
    notifyListeners();
    try {
      await _committees.delete(id);
      await _reminders.rescheduleAll();
      await load();
    } finally {
      _mutating = false;
      notifyListeners();
    }
  }

  Future<CommitteeBundle> bundleOf(String id) => _committees.loadBundle(id);

  Future<Committee> byId(String id) => _committees.getById(id);

  List<Committee> _applyQuery(List<Committee> source) {
    final String term = _query.trim().toLowerCase();
    if (term.isEmpty) return source;
    return source
        .where(
          (Committee c) =>
              c.name.toLowerCase().contains(term) ||
              (c.description ?? '').toLowerCase().contains(term),
        )
        .toList(growable: false);
  }
}
