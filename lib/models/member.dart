import 'enums.dart';

/// A person inside a committee.
///
/// A member does **not** know anything about payments or turns; that keeps the
/// model free of navigation loops and makes it trivially unit-testable.
class Member {
  const Member({
    required this.id,
    required this.committeeId,
    required this.name,
    required this.turnNumber,
    required this.isActive,
    required this.createdAt,
    this.phoneNumber,
    this.address,
    this.notes,
    this.role = MemberRole.member,
    this.isDemo = false,
    this.updatedAt,
  });

  final String id;
  final String committeeId;
  final String name;
  final String? phoneNumber;
  final String? address;
  final String? notes;

  /// 1-based position in the collection order.
  final int turnNumber;

  final MemberRole role;
  final bool isActive;
  final bool isDemo;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Up to two letters for an avatar, e.g. "Ali Raza" -> "AR".
  String get initials {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final String first = parts.first;
      return (first.isEmpty ? '?' : first[0]).toUpperCase();
    }
    return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
  }

  bool get isOrganizer => role == MemberRole.organizer;

  // ------------------------------------------------------------ (de)serialise

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'committee_id': committeeId,
    'name': name,
    'phone_number': phoneNumber,
    'address': address,
    'notes': notes,
    'turn_number': turnNumber,
    'role': role.name,
    'is_active': isActive ? 1 : 0,
    'is_demo': isDemo ? 1 : 0,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': (updatedAt ?? createdAt).millisecondsSinceEpoch,
  };

  factory Member.fromMap(Map<String, Object?> map) => Member(
    id: map['id']! as String,
    committeeId: map['committee_id']! as String,
    name: map['name']! as String,
    phoneNumber: map['phone_number'] as String?,
    address: map['address'] as String?,
    notes: map['notes'] as String?,
    turnNumber: map['turn_number']! as int,
    role: MemberRole.fromStorage(map['role'] as String?),
    isActive: (map['is_active'] as int? ?? 1) == 1,
    isDemo: (map['is_demo'] as int? ?? 0) == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
    updatedAt: map['updated_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(map['updated_at']! as int),
  );

  Member copyWith({
    String? name,
    String? phoneNumber,
    String? address,
    String? notes,
    int? turnNumber,
    MemberRole? role,
    bool? isActive,
    DateTime? updatedAt,
  }) => Member(
    id: id,
    committeeId: committeeId,
    name: name ?? this.name,
    phoneNumber: phoneNumber ?? this.phoneNumber,
    address: address ?? this.address,
    notes: notes ?? this.notes,
    turnNumber: turnNumber ?? this.turnNumber,
    role: role ?? this.role,
    isActive: isActive ?? this.isActive,
    isDemo: isDemo,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  @override
  bool operator ==(Object other) => identical(this, other) || (other is Member && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Member($name, turn $turnNumber)';
}
