import 'enums.dart';

/// The single local account that owns the data on this device.
///
/// No password is ever stored: only a salted, stretched hash produced by
/// `CryptoHelper`, plus a boolean telling us whether the account has completed
/// OTP verification.
class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.pinHash,
    required this.pinSalt,
    required this.isVerified,
    required this.biometricEnabled,
    required this.createdAt,
    this.phoneNumber,
    this.email,
    this.otpVerified = false,
    this.role = UserRole.owner,
    this.lastLoginAt,
    this.updatedAt,
    this.failedLoginAttempts = 0,
    this.lockedUntil,
    this.pinLength = 4,
    this.preferredChannel = OtpChannel.email,
  });

  final String id;
  final String fullName;
  final String? phoneNumber;
  final String? email;

  /// Salted + iterated SHA-256 of the PIN. The PIN itself is never persisted.
  final String pinHash;
  final String pinSalt;

  /// How many digits the PIN has, kept so the lock screen can draw exactly that
  /// many dots. Not a secret — it only tells an attacker the length.
  final int pinLength;

  /// True once the account has passed the registration + OTP flow.
  final bool isVerified;

  /// True once the phone/email has been proven with an OTP.
  final bool otpVerified;

  final bool biometricEnabled;
  final UserRole role;
  final int failedLoginAttempts;
  final DateTime? lockedUntil;
  final DateTime? lastLoginAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Where the user asked for their codes to be sent.
  ///
  /// Separate from [primaryChannel], which resolves this into something actually
  /// deliverable. Keeping the raw choice lets the UI show what they picked even
  /// if the other contact is later removed.
  final OtpChannel preferredChannel;

  /// Which channel the account is verified through.
  ///
  /// Always [OtpChannel.email]: the app has one delivery path, and the stored
  /// preference is only read back so that rows written when SMS still existed
  /// keep loading instead of failing the cast.
  OtpChannel get primaryChannel => OtpChannel.email;

  String get maskedPhone => _mask(phoneNumber);

  String get maskedEmail => _maskEmail(email);

  /// The destination the OTP is actually sent to.
  String get verificationTarget => email?.trim() ?? '';

  /// The address a code for [channel] would be delivered to, or `''` when this
  /// account has nothing usable on that channel.
  ///
  /// Where a code is sent. Email is the only channel, so this is the account's
  /// email address or the empty string when they have not supplied one.
  String targetFor(OtpChannel channel) => switch (channel) {
    OtpChannel.email => email?.trim() ?? '',
  };

  /// Every channel this account could actually receive a code on.
  List<OtpChannel> get availableChannels => <OtpChannel>[
    for (final OtpChannel channel in OtpChannel.values)
      if (targetFor(channel).isNotEmpty) channel,
  ];

  static String _mask(String? value) {
    final String raw = (value ?? '').trim();
    if (raw.isEmpty) return '-';
    if (raw.length <= 4) return '••••';
    return '${raw.substring(0, 2)}${'•' * (raw.length - 4)}${raw.substring(raw.length - 2)}';
  }

  static String _maskEmail(String? value) {
    final String raw = (value ?? '').trim();
    if (raw.isEmpty) return '-';
    final int at = raw.indexOf('@');
    if (at <= 0) return _mask(raw);
    final String name = raw.substring(0, at);
    final String domain = raw.substring(at);
    final String head = name.length <= 2 ? name[0] : name.substring(0, 2);
    return '$head${'•' * (name.length - 2 > 0 ? name.length - 2 : 1)}$domain';
  }

  bool isLockedOutAt(DateTime now) => lockedUntil != null && lockedUntil!.isAfter(now);

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'full_name': fullName,
    'phone_number': phoneNumber,
    'email': email,
    'pin_hash': pinHash,
    'pin_salt': pinSalt,
    'pin_length': pinLength,
    'preferred_otp_channel': preferredChannel.name,
    'is_verified': isVerified ? 1 : 0,
    'otp_verified': otpVerified ? 1 : 0,
    'biometric_enabled': biometricEnabled ? 1 : 0,
    'role': role.name,
    'failed_login_attempts': failedLoginAttempts,
    'locked_until': lockedUntil?.millisecondsSinceEpoch,
    'last_login_at': lastLoginAt?.millisecondsSinceEpoch,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': (updatedAt ?? createdAt).millisecondsSinceEpoch,
  };

  factory AppUser.fromMap(Map<String, Object?> map) => AppUser(
    id: _asString(map['id']) ?? '',
    fullName: _asString(map['full_name']) ?? '',
    phoneNumber: _asString(map['phone_number']),
    email: _asString(map['email']),
    pinHash: _asString(map['pin_hash']) ?? '',
    pinSalt: _asString(map['pin_salt']) ?? '',
    pinLength: (_asInt(map['pin_length']) ?? 4).clamp(1, 6),
    preferredChannel: OtpChannel.fromStorage(_asString(map['preferred_otp_channel'])),
    isVerified: (_asInt(map['is_verified']) ?? 0) == 1,
    otpVerified: (_asInt(map['otp_verified']) ?? 0) == 1,
    biometricEnabled: (_asInt(map['biometric_enabled']) ?? 0) == 1,
    role: UserRole.fromStorage(_asString(map['role'])),
    failedLoginAttempts: _asInt(map['failed_login_attempts']) ?? 0,
    lockedUntil: _asDate(map['locked_until']),
    lastLoginAt: _asDate(map['last_login_at']),
    createdAt: _asDate(map['created_at']) ?? DateTime.now(),
    updatedAt: _asDate(map['updated_at']),
  );

  /// SQLite is dynamically typed, so a column declared INTEGER can still hand
  /// back a String after a careless migration or a hand-edited row.
  ///
  /// A hard `as int` cast in `fromMap` would throw, and because this method is
  /// what loads the *only* account on the device, the user would be locked out
  /// of their own committee data with no way back. Coercing instead turns a
  /// schema mistake into a defaulted field rather than a bricked app.
  static int? _asInt(Object? value) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    final String v => int.tryParse(v),
    _ => null,
  };

  static String? _asString(Object? value) => switch (value) {
    final String v => v.isEmpty ? null : v,
    final num v => v.toString(),
    _ => null,
  };

  static DateTime? _asDate(Object? value) {
    final int? ms = _asInt(value);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  AppUser copyWith({
    String? fullName,
    String? phoneNumber,
    String? email,
    String? pinHash,
    String? pinSalt,
    int? pinLength,
    OtpChannel? preferredChannel,
    bool? isVerified,
    bool? otpVerified,
    bool? biometricEnabled,
    int? failedLoginAttempts,
    DateTime? lockedUntil,
    bool clearLock = false,
    DateTime? lastLoginAt,
    DateTime? updatedAt,
  }) => AppUser(
    id: id,
    fullName: fullName ?? this.fullName,
    phoneNumber: phoneNumber ?? this.phoneNumber,
    email: email ?? this.email,
    pinHash: pinHash ?? this.pinHash,
    pinSalt: pinSalt ?? this.pinSalt,
    pinLength: pinLength ?? this.pinLength,
    preferredChannel: preferredChannel ?? this.preferredChannel,
    isVerified: isVerified ?? this.isVerified,
    otpVerified: otpVerified ?? this.otpVerified,
    biometricEnabled: biometricEnabled ?? this.biometricEnabled,
    role: role,
    failedLoginAttempts: failedLoginAttempts ?? this.failedLoginAttempts,
    lockedUntil: clearLock ? null : (lockedUntil ?? this.lockedUntil),
    lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  @override
  bool operator ==(Object other) => identical(this, other) || (other is AppUser && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'AppUser($id, $fullName, verified=$isVerified)';
}
