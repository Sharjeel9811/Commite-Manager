import 'enums.dart';

/// One turn of the collection order: "who receives the pool, and when".
///
/// The turn table is what makes the rotation explicit and auditable. A member
/// can never receive twice because `UNIQUE(committee_id, turn_number)` plus a
/// `UNIQUE` check on `member_id` inside a turn makes it impossible.
class CommitteeTurn {
  const CommitteeTurn({
    required this.id,
    required this.committeeId,
    required this.turnNumber,
    required this.memberId,
    required this.periodNumber,
    required this.expectedAmount,
    required this.dueDate,
    required this.status,
    required this.createdAt,
    this.collectedAmount = 0,
    this.completedAt,
    this.updatedAt,
  });

  final String id;
  final String committeeId;

  /// 1-based rotation position.
  final int turnNumber;
  final String memberId;

  /// The period whose collection funds this turn.
  final int periodNumber;

  /// How much this member will receive.
  final double expectedAmount;

  /// How much has actually been collected for this turn.
  final double collectedAmount;

  final DateTime dueDate;
  final TurnStatus status;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get isCompleted => status.isClosed;

  bool get isActive => status == TurnStatus.active;

  bool get isUpcoming => status == TurnStatus.upcoming;

  /// True once the whole pool for this turn has been collected.
  bool get isFullyFunded => expectedAmount <= 0 || collectedAmount >= expectedAmount;

  double get shortfall => (expectedAmount - collectedAmount).clamp(0, double.infinity);

  double get progressPercent =>
      expectedAmount <= 0 ? 0 : (collectedAmount / expectedAmount).clamp(0, 1) * 100;

  CommitteeTurn copyWith({
    double? collectedAmount,
    TurnStatus? status,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? updatedAt,
  }) => CommitteeTurn(
    id: id,
    committeeId: committeeId,
    turnNumber: turnNumber,
    memberId: memberId,
    periodNumber: periodNumber,
    expectedAmount: expectedAmount,
    collectedAmount: collectedAmount ?? this.collectedAmount,
    dueDate: dueDate,
    status: status ?? this.status,
    completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'committee_id': committeeId,
    'turn_number': turnNumber,
    'member_id': memberId,
    'period_number': periodNumber,
    'expected_amount': expectedAmount,
    'collected_amount': collectedAmount,
    'due_date': dueDate.millisecondsSinceEpoch,
    'status': status.name,
    'completed_at': completedAt?.millisecondsSinceEpoch,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': (updatedAt ?? createdAt).millisecondsSinceEpoch,
  };

  factory CommitteeTurn.fromMap(Map<String, Object?> map) => CommitteeTurn(
    id: map['id']! as String,
    committeeId: map['committee_id']! as String,
    turnNumber: map['turn_number']! as int,
    memberId: map['member_id']! as String,
    periodNumber: map['period_number']! as int,
    expectedAmount: (map['expected_amount']! as num).toDouble(),
    collectedAmount: (map['collected_amount'] as num? ?? 0).toDouble(),
    dueDate: DateTime.fromMillisecondsSinceEpoch(map['due_date']! as int),
    status: TurnStatus.fromStorage(map['status'] as String?),
    completedAt: map['completed_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(map['completed_at']! as int),
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
    updatedAt: map['updated_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(map['updated_at']! as int),
  );

  /// Used when the agreed contribution changes before any money is recorded.
  CommitteeTurn copyWithExpected(double newExpected) => CommitteeTurn(
    id: id,
    committeeId: committeeId,
    turnNumber: turnNumber,
    memberId: memberId,
    periodNumber: periodNumber,
    expectedAmount: newExpected,
    collectedAmount: collectedAmount,
    dueDate: dueDate,
    status: status,
    completedAt: completedAt,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is CommitteeTurn && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'CommitteeTurn(turn $turnNumber, member=$memberId, ${status.name})';
}
