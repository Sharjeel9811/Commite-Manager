import '../core/constants/app_constants.dart';
import '../core/utils/app_date_utils.dart';
import 'enums.dart';

/// One member's obligation for one period.
///
/// A row is created when the committee is created (member x period) and is
/// flipped to `paid` when money is received, so a committee can never contain
/// a payment record that nobody has even heard of.
///
/// A database-level `UNIQUE(committee_id, member_id, period_number)` constraint
/// plus [status] make double payment physically impossible.
class Payment {
  const Payment({
    required this.id,
    required this.committeeId,
    required this.scheduleId,
    required this.memberId,
    required this.periodNumber,
    required this.amount,
    required this.dueDate,
    required this.status,
    required this.createdAt,
    this.paidDate,
    this.method,
    this.notes,
    this.updatedAt,
  });

  final String id;
  final String committeeId;
  final String scheduleId;
  final String memberId;

  /// 1-based period index; the column used for grouping and reporting.
  final int periodNumber;

  final double amount;
  final DateTime dueDate;
  final DateTime? paidDate;
  final PaymentStatus status;
  final PaymentMethod? method;
  final String? notes;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get isPaid => status.isPaid;

  /// "Overdue" is never stored — it is always derived from the due date, so it
  /// can never go stale if the clock or the due date changes.
  bool get isOverdue => !isPaid && AppDateUtils.isPast(dueDate);

  bool get isDueToday => !isPaid && AppDateUtils.isToday(dueDate);

  /// Days still to go before the money is expected (may be 0 or negative once
  /// the date passes — see [daysOverdue] for the clamped late count).
  int get daysUntilDue => AppDateUtils.daysBetween(DateTime.now(), dueDate);

  /// Days the payment is late, never negative for a not-yet-due row.
  int get daysOverdue => isPaid ? 0 : AppDateUtils.daysLate(dueDate);

  /// Unpaid and inside the shared due-soon window (today through today+N).
  bool get isDueSoon => !isPaid && AppDateUtils.isDueSoon(dueDate);

  /// Late long enough to deserve escalation past plain "overdue" (see
  /// [AppConstants.severelyOverdueDays]). Drives the stronger row colour and
  /// lets a busy collector see at a glance which debts need chasing first.
  bool get isSeverelyOverdue =>
      !isPaid && daysOverdue >= AppConstants.severelyOverdueDays;

  /// The most serious overdue label for a chip: "Overdue" for a fresh debt,
  /// "Overdue 12 days" for one that is getting old, and
  /// "Severely overdue" past the escalation threshold.
  String get overdueLabel {
    if (!isOverdue) return '';
    if (isSeverelyOverdue) return 'Severely overdue ($daysOverdue days)';
    return 'Overdue $daysOverdue ${daysOverdue == 1 ? 'day' : 'days'}';
  }

  /// Status used by the UI chips and the filter bar.
  PaymentStatus get effectiveStatus {
    if (isPaid) return PaymentStatus.paid;
    if (isOverdue) return PaymentStatus.pending;
    return status;
  }

  /// Label that distinguishes "Pending" from "Overdue".
  String get displayStatusLabel => isOverdue ? 'Overdue' : status.label;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'committee_id': committeeId,
    'schedule_id': scheduleId,
    'member_id': memberId,
    'period_number': periodNumber,
    'amount': amount,
    'due_date': dueDate.millisecondsSinceEpoch,
    'paid_date': paidDate?.millisecondsSinceEpoch,
    'status': status.name,
    'method': method?.name,
    'notes': notes,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': (updatedAt ?? createdAt).millisecondsSinceEpoch,
  };

  factory Payment.fromMap(Map<String, Object?> map) => Payment(
    id: map['id']! as String,
    committeeId: map['committee_id']! as String,
    scheduleId: map['schedule_id']! as String,
    memberId: map['member_id']! as String,
    periodNumber: map['period_number']! as int,
    amount: (map['amount']! as num).toDouble(),
    dueDate: DateTime.fromMillisecondsSinceEpoch(map['due_date']! as int),
    paidDate: map['paid_date'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(map['paid_date']! as int),
    status: PaymentStatus.fromStorage(map['status'] as String?),
    method: PaymentMethod.fromStorage(map['method'] as String?),
    notes: map['notes'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
    updatedAt: map['updated_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(map['updated_at']! as int),
  );

  Payment copyWith({
    PaymentStatus? status,
    DateTime? paidDate,
    bool clearPaidDate = false,
    PaymentMethod? method,
    bool clearMethod = false,
    String? notes,
    DateTime? updatedAt,
  }) => Payment(
    id: id,
    committeeId: committeeId,
    scheduleId: scheduleId,
    memberId: memberId,
    periodNumber: periodNumber,
    amount: amount,
    dueDate: dueDate,
    paidDate: clearPaidDate ? null : (paidDate ?? this.paidDate),
    status: status ?? this.status,
    method: clearMethod ? null : (method ?? this.method),
    notes: notes ?? this.notes,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  /// Used when the agreed contribution changes before any money is recorded.
  Payment copyWithAmount(double newAmount) => Payment(
    id: id,
    committeeId: committeeId,
    scheduleId: scheduleId,
    memberId: memberId,
    periodNumber: periodNumber,
    amount: newAmount,
    dueDate: dueDate,
    paidDate: paidDate,
    status: status,
    method: method,
    notes: notes,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  @override
  bool operator ==(Object other) => identical(this, other) || (other is Payment && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Payment($committeeId, member=$memberId, period=$periodNumber, ${status.name})';
}
