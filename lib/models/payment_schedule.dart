/// A single collection period ("October 2026", "Week of 12 Oct").
///
/// One row per period. It carries the label and the due date that every
/// member's [Payment] in that period points at, so the due date exists in
/// exactly one place.
class PaymentSchedule {
  const PaymentSchedule({
    required this.id,
    required this.committeeId,
    required this.periodNumber,
    required this.label,
    required this.startDate,
    required this.dueDate,
    this.isClosed = false,
  });

  final String id;
  final String committeeId;

  /// 1-based period index.
  final int periodNumber;

  /// e.g. "October 2026".
  final String label;
  final DateTime startDate;
  final DateTime dueDate;

  /// A period is closed once its turn has been handed over.
  final bool isClosed;

  bool get isDueNow =>
      !isClosed && !dueDate.isAfter(DateTime.now()) && _isSameDay(dueDate, DateTime.now());

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'committee_id': committeeId,
    'period_number': periodNumber,
    'label': label,
    'start_date': startDate.millisecondsSinceEpoch,
    'due_date': dueDate.millisecondsSinceEpoch,
    'is_closed': isClosed ? 1 : 0,
  };

  factory PaymentSchedule.fromMap(Map<String, Object?> map) => PaymentSchedule(
    id: map['id']! as String,
    committeeId: map['committee_id']! as String,
    periodNumber: map['period_number']! as int,
    label: map['label']! as String,
    startDate: DateTime.fromMillisecondsSinceEpoch(map['start_date']! as int),
    dueDate: DateTime.fromMillisecondsSinceEpoch(map['due_date']! as int),
    isClosed: (map['is_closed'] as int? ?? 0) == 1,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PaymentSchedule && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PaymentSchedule($committeeId, #$periodNumber, $label)';
}
