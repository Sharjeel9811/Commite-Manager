import 'enums.dart';

/// A pending one-time-password challenge.
///
/// The **plaintext code is never stored** — only its salted hash, exactly like
/// a password. Even if somebody copies the database file, they cannot read the
/// codes that were sent.
class OtpChallenge {
  const OtpChallenge({
    required this.id,
    required this.userId,
    required this.channel,
    required this.destination,
    required this.codeHash,
    required this.salt,
    required this.expiresAt,
    required this.maxAttempts,
    required this.createdAt,
    this.attempts = 0,
    this.consumedAt,
  });

  final String id;
  final String userId;
  final OtpChannel channel;

  /// The phone number or email the code was sent to.
  final String destination;

  /// Salted hash of the code, not the code itself.
  final String codeHash;

  /// The salt used to derive [codeHash]; needed to re-hash on verification.
  final String salt;

  final DateTime expiresAt;
  final int attempts;
  final int maxAttempts;
  final DateTime createdAt;
  final DateTime? consumedAt;

  bool get isConsumed => consumedAt != null;

  bool isExpiredAt(DateTime now) => now.isAfter(expiresAt);

  int get attemptsLeft => (maxAttempts - attempts).clamp(0, maxAttempts);

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'user_id': userId,
    'channel': channel.name,
    'destination': destination,
    'code_hash': codeHash,
    'salt': salt,
    'expires_at': expiresAt.millisecondsSinceEpoch,
    'attempts': attempts,
    'max_attempts': maxAttempts,
    'consumed_at': consumedAt?.millisecondsSinceEpoch,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory OtpChallenge.fromMap(Map<String, Object?> map) => OtpChallenge(
    id: map['id']! as String,
    userId: map['user_id']! as String,
    channel: OtpChannel.fromStorage(map['channel'] as String?),
    destination: map['destination']! as String,
    codeHash: map['code_hash']! as String,
    salt: map['salt']! as String,
    expiresAt: DateTime.fromMillisecondsSinceEpoch(map['expires_at']! as int),
    attempts: map['attempts'] as int? ?? 0,
    maxAttempts: map['max_attempts'] as int? ?? 5,
    consumedAt: map['consumed_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(map['consumed_at']! as int),
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is OtpChallenge && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
