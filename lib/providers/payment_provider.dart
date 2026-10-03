import 'package:flutter/foundation.dart';

import '../core/errors/app_exception.dart';
import '../core/utils/logger.dart';
import '../models/enums.dart';
import '../services/payment_service.dart';
import '../services/reminder_service.dart';

/// State for the payments screen: which period, which filter, which rows.
///
/// Like every provider it holds state only — the actual "mark as paid" rule
/// lives in [PaymentService] and is executed inside a database transaction.
class PaymentProvider extends ChangeNotifier {
  PaymentProvider({
    required PaymentService paymentService,
    required ReminderService reminderService,
  }) : _payments = paymentService,
       _reminders = reminderService;

  final PaymentService _payments;
  final ReminderService _reminders;

  static const AppLogger _log = AppLogger('PaymentProvider');

  String? _committeeId;
  int _period = 1;
  PaymentFilter _filter = PaymentFilter.all;
  String _query = '';
  List<PaymentRow> _rows = const <PaymentRow>[];
  bool _loading = false;
  String? _error;
  final Set<String> _pendingIds = <String>{};

  // ------------------------------------------------------------------ Getters

  List<PaymentRow> get rows => _rows;
  bool get isLoading => _loading;
  String? get error => _error;
  int get period => _period;
  PaymentFilter get filter => _filter;
  String get query => _query;
  String? get committeeId => _committeeId;

  int get paidCount => _rows.where((PaymentRow r) => r.isPaid).length;

  int get pendingCount => _rows.where((PaymentRow r) => !r.isPaid).length;

  int get overdueCount => _rows.where((PaymentRow r) => r.isOverdue).length;

  double get totalAmount => _rows.fold<double>(0, (double sum, PaymentRow r) => sum + r.amount);

  double get collectedAmount => _rows
      .where((PaymentRow r) => r.isPaid)
      .fold<double>(0, (double s, PaymentRow r) => s + r.amount);

  double get outstandingAmount => _rows
      .where((PaymentRow r) => !r.isPaid)
      .fold<double>(0, (double s, PaymentRow r) => s + r.amount);

  double get completionPercent => _rows.isEmpty ? 0 : (paidCount / _rows.length) * 100;

  /// True while a specific row is being written, so only that row shows a
  /// spinner instead of blocking the whole list.
  bool isBusy(String paymentId) => _pendingIds.contains(paymentId);

  bool get allPaid => _rows.isNotEmpty && paidCount == _rows.length;

  bool get canMarkAllPaid => _rows.isNotEmpty && pendingCount > 0;

  // ------------------------------------------------------------------ Loading

  Future<void> open({required String committeeId, required int period}) async {
    _committeeId = committeeId;
    _period = period;
    await _load();
  }

  Future<void> changePeriod(int period) async {
    if (_period == period) return;
    _period = period;
    _filter = PaymentFilter.all;
    await _load();
  }

  Future<void> changeFilter(PaymentFilter value) async {
    if (_filter == value) return;
    _filter = value;
    notifyListeners();
    await _load(keepScrollSafe: true);
  }

  void search(String value) {
    _query = value;
    notifyListeners();
  }

  List<PaymentRow> get visibleRows {
    final String term = _query.trim().toLowerCase();
    if (term.isEmpty) return _rows;
    return _rows
        .where((PaymentRow r) => r.memberName.toLowerCase().contains(term))
        .toList(growable: false);
  }

  Future<void> refresh() => _load();

  Future<void> _load({bool keepScrollSafe = false}) async {
    final String? id = _committeeId;
    if (id == null) return;
    _loading = true;
    _error = null;
    if (!keepScrollSafe) notifyListeners();
    try {
      _rows = await _payments.rowsForPeriod(id, _period, _filter);
    } catch (error) {
      _log.error('Could not load payments for period $_period', error);
      _error = describeError(error);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // --------------------------------------------------------------- Mutations

  /// Marks one row as paid and rebuilds the row list.
  Future<String?> markPaid(String paymentId, {PaymentMethod? method, String? notes}) async {
    final String? id = _committeeId;
    if (id == null) return 'No committee is open.';
    _pendingIds.add(paymentId);
    notifyListeners();
    try {
      await _payments.markPaid(paymentId: paymentId, method: method, notes: notes);
      await _refreshAfterPayment(id);
      return null;
    } catch (error) {
      _log.error('Could not mark payment', error);
      return describeError(error);
    } finally {
      _pendingIds.remove(paymentId);
      notifyListeners();
    }
  }

  /// Undoes a payment; the turn it funded re-opens automatically.
  Future<String?> markUnpaid(String paymentId) async {
    final String? id = _committeeId;
    if (id == null) return 'No committee is open.';
    _pendingIds.add(paymentId);
    notifyListeners();
    try {
      await _payments.markUnpaid(paymentId);
      await _refreshAfterPayment(id);
      return null;
    } catch (error) {
      _log.error('Could not undo payment', error);
      return describeError(error);
    } finally {
      _pendingIds.remove(paymentId);
      notifyListeners();
    }
  }

  /// "Everyone paid" shortcut.
  Future<String?> markWholePeriodPaid({PaymentMethod? method}) async {
    final String? id = _committeeId;
    if (id == null) return 'No committee is open.';
    _loading = true;
    notifyListeners();
    try {
      final int count = await _payments.markPeriodPaid(
        committeeId: id,
        periodNumber: _period,
        method: method,
      );
      await _refreshAfterPayment(id);
      return count == 0 ? 'Everyone in this period was already marked as paid.' : null;
    } catch (error) {
      _log.error('Could not mark period paid', error);
      return describeError(error);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// After any write: reload rows, rebuild reminders, and let the rest of the
  /// app know something changed.
  Future<void> _refreshAfterPayment(String committeeId) async {
    await _load(keepScrollSafe: true);
    await _reminders.rescheduleAll();
    PaymentChangeBus.instance.notifyChanged(committeeId);
  }
}

/// A tiny event bus so the dashboard, committee list and details screen all
/// refresh after a payment is recorded somewhere else.
///
/// It exists because Provider's dependency graph is one-directional; a payment
/// made on the payments screen must invalidate the dashboard. Using a bus keeps
/// providers from having to know about each other (they stay loosely coupled,
/// which is the "D" in DIP applied to state).
class PaymentChangeBus {
  PaymentChangeBus._();

  static final PaymentChangeBus instance = PaymentChangeBus._();

  final List<void Function(String committeeId)> _listeners = <void Function(String)>[];

  void subscribe(void Function(String committeeId) listener) => _listeners.add(listener);

  void unsubscribe(void Function(String committeeId) listener) => _listeners.remove(listener);

  void notifyChanged(String committeeId) {
    for (final void Function(String) listener in List<void Function(String)>.of(_listeners)) {
      listener(committeeId);
    }
  }
}
