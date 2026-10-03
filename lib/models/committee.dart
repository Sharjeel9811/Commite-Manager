import 'enums.dart';

/// A committee (also called a "Bachat Committee" or "Committee").
///
/// This class is a **pure data holder**. It knows how to describe itself and
/// how to convert to/from a database row, but it performs **no** business
/// decisions — that is the job of `CommitteeService` and `PaymentCalculator`.
class Committee {
  const Committee({
    required this.id,
    required this.name,
    required this.contributionAmount,
    required this.frequency,
    required this.startDate,
    required this.durationPeriods,
    required this.memberCount,
    required this.currentTurn,
    required this.completedTurns,
    required this.status,
    required this.createdAt,
    this.description,
    this.updatedAt,
    this.isDemo = false,
  });

  final String id;
  final String name;
  final String? description;

  /// Money every member pays in one period.
  final double contributionAmount;

  final PaymentFrequency frequency;
  final DateTime startDate;

  /// How many collection periods this committee runs for.
  final int durationPeriods;

  /// How many members share the pool.
  final int memberCount;

  /// 1-based index of the turn currently collecting the pool.
  final int currentTurn;

  /// How many members have already received their turn.
  final int completedTurns;

  final CommitteeStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Demo rows are visually separated from real user data.
  final bool isDemo;

  // ------------------------------------------------------------- Derived data

  /// The full amount one member receives on their turn.
  ///
  /// Every period, the member who is collecting that period's pot does not pay
  /// into it — the pot is made of the other `memberCount - 1` members'
  /// contributions (9 x 10,000 = 90,000 for a 10-member committee).
  double get totalPoolPerTurn => contributionAmount * (memberCount <= 1 ? 0 : memberCount - 1);

  /// Total money that will pass through the committee over its whole life.
  ///
  /// Each member pays in every period except the one they collect, so
  /// `(memberCount - 1) x durationPeriods x contributionAmount`
  /// (9 x 10 periods x 10,000 = 900,000 for a 10-member committee).
  double get expectedTotalCollection =>
      contributionAmount * (memberCount <= 1 ? 0 : memberCount - 1) * durationPeriods;

  DateTime get firstDueDate => frequency.dueDateForPeriod(1, startDate);

  DateTime get lastDueDate => frequency.dueDateForPeriod(durationPeriods, startDate);

  int get remainingTurns => (durationPeriods - completedTurns).clamp(0, durationPeriods);

  /// 0.0 - 100.0 progress through the committee's life.
  double get progressPercent => durationPeriods == 0 ? 0 : (completedTurns / durationPeriods) * 100;

  bool get isActive => status == CommitteeStatus.active;

  bool get isCompleted => status == CommitteeStatus.completed;

  /// A committee may only be structurally edited while it has not started.
  bool get isEditable =>
      completedTurns == 0 && (status == CommitteeStatus.draft || status == CommitteeStatus.active);

  // ------------------------------------------------------------ (de)serialise

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'name': name,
    'description': description,
    'contribution_amount': contributionAmount,
    'frequency': frequency.storageKey,
    'start_date': startDate.millisecondsSinceEpoch,
    'duration_periods': durationPeriods,
    'member_count': memberCount,
    'current_turn': currentTurn,
    'completed_turns': completedTurns,
    'status': status.name,
    'is_demo': isDemo ? 1 : 0,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': (updatedAt ?? createdAt).millisecondsSinceEpoch,
  };

  factory Committee.fromMap(Map<String, Object?> map) => Committee(
    id: map['id']! as String,
    name: map['name']! as String,
    description: map['description'] as String?,
    contributionAmount: (map['contribution_amount']! as num).toDouble(),
    frequency: PaymentFrequency.fromStorage(map['frequency'] as String?),
    startDate: DateTime.fromMillisecondsSinceEpoch(map['start_date']! as int),
    durationPeriods: map['duration_periods']! as int,
    memberCount: map['member_count']! as int,
    currentTurn: map['current_turn']! as int,
    completedTurns: map['completed_turns']! as int,
    status: CommitteeStatus.fromStorage(map['status'] as String?),
    isDemo: (map['is_demo'] as int? ?? 0) == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
    updatedAt: map['updated_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(map['updated_at']! as int),
  );

  Committee copyWith({
    String? name,
    String? description,
    double? contributionAmount,
    PaymentFrequency? frequency,
    DateTime? startDate,
    int? durationPeriods,
    int? memberCount,
    int? currentTurn,
    int? completedTurns,
    CommitteeStatus? status,
    DateTime? updatedAt,
    bool? isDemo,
  }) => Committee(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    contributionAmount: contributionAmount ?? this.contributionAmount,
    frequency: frequency ?? this.frequency,
    startDate: startDate ?? this.startDate,
    durationPeriods: durationPeriods ?? this.durationPeriods,
    memberCount: memberCount ?? this.memberCount,
    currentTurn: currentTurn ?? this.currentTurn,
    completedTurns: completedTurns ?? this.completedTurns,
    status: status ?? this.status,
    isDemo: isDemo ?? this.isDemo,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Committee && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Committee($id, $name, Rs$contributionAmount/${frequency.name})';
}
