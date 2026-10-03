import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

/// Generates and hashes the secrets used by the authentication layer.
///
/// Keeping hashing here (instead of inside the auth service) means the auth
/// service stays focused on *policy*, while this class owns *crypto mechanics*.
class CryptoHelper {
  const CryptoHelper._();

  static const Uuid _uuid = Uuid();
  static final Random _random = Random.secure();

  /// RFC-4122 v4 identifier, used for every primary key in the database.
  static String newId() => _uuid.v4();

  /// A cryptographically strong random string of [length] characters.
  static String randomSecret(int length) {
    const String alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I to avoid typos
    return List<String>.generate(length, (_) => alphabet[_random.nextInt(alphabet.length)]).join();
  }

  /// A numeric one-time password of [length] digits (000000 - 999999).
  static String numericOtp(int length) {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < length; i++) {
      buffer.write(_random.nextInt(10));
    }
    return buffer.toString();
  }

  /// A fresh random salt, hex encoded.
  static String newSalt({int bytes = 16}) {
    final List<int> data = List<int>.generate(bytes, (_) => _random.nextInt(256));
    return _toHex(data);
  }

  /// Iterated salted SHA-256, used only for the challenge marker stored with an
  /// OTP row.
  ///
  /// A plain `sha256(secret)` would be trivially reversed with a rainbow table,
  /// so the value is stretched with many rounds. PINs use [hashPin] below, which
  /// is a standard, memory-hard-adjacent KDF instead of a hand-rolled loop.
  static String hashSecret(String secret, String salt, {int rounds = 25000}) {
    String digest = sha256.convert(utf8Bytes('$salt::$secret')).toString();
    for (int i = 0; i < rounds; i++) {
      digest = sha256.convert(utf8Bytes('$digest::$salt')).toString();
    }
    return digest;
  }

  /// Marker for [isLegacyPinHash] — the prefix of every modern PIN hash.
  static const String pinHashPrefix = r'pbkdf2_sha256$';

  /// Hashes a PIN with PBKDF2-HMAC-SHA256.
  ///
  /// PBKDF2 is what OWASP recommends for low-entropy secrets such as a 4-6 digit
  /// PIN: a high iteration count makes every guess expensive, and the 16-byte
  /// random salt means two users with the same PIN get unrelated hashes and a
  /// precomputed table is useless.
  ///
  /// The result is stored self-describing — `pbkdf2_sha256$<iterations>$<hex>` —
  /// so the cost can be raised later without invalidating anyone's PIN.
  static String hashPin(
    String pin,
    String salt, {
    int iterations = kPinHashIterations,
  }) {
    final String derived = _pbkdf2Sha256(
      password: pin,
      salt: salt,
      iterations: iterations,
      keyLength: 32,
    );
    return '$pinHashPrefix$iterations\$$derived';
  }

  /// Computes [hashPin] on a background isolate; see [hashSecretAsync].
  static Future<String> hashPinAsync(
    String pin,
    String salt, {
    int iterations = kPinHashIterations,
  }) {
    return Isolate.run(() => hashPin(pin, salt, iterations: iterations));
  }

  /// Verifies a PIN against a stored hash of any supported vintage.
  ///
  /// Understands both the current PBKDF2 format and the original iterated
  /// SHA-256 rows written by older builds, so an existing user's PIN keeps
  /// working after an update. [needsRehash] reports which case applied, which
  /// lets the caller quietly upgrade the stored hash on the next successful
  /// unlock.
  static bool verifyPin(
    String pin,
    String salt,
    String storedHash, {
    int legacyRounds = kLegacyPinHashIterations,
  }) {
    if (storedHash.startsWith(pinHashPrefix)) {
      final List<String> parts = storedHash.split(r'$');
      if (parts.length != 3) return false;
      final int? iterations = int.tryParse(parts[1]);
      if (iterations == null || iterations <= 0) return false;
      return secureEquals(hashPin(pin, salt, iterations: iterations), storedHash);
    }
    return secureEquals(hashSecret(pin, salt, rounds: legacyRounds), storedHash);
  }

  /// Computes [verifyPin] on a background isolate; see [hashSecretAsync].
  static Future<bool> verifyPinAsync(
    String pin,
    String salt,
    String storedHash, {
    int legacyRounds = kLegacyPinHashIterations,
  }) {
    return Isolate.run(
      () => verifyPin(pin, salt, storedHash, legacyRounds: legacyRounds),
    );
  }

  /// True when [storedHash] uses the old hand-rolled scheme and should be
  /// replaced with PBKDF2 the next time the correct PIN is presented.
  static bool needsRehash(String storedHash) => !storedHash.startsWith(pinHashPrefix);

  /// Iteration count for new PIN hashes.
  static const int kPinHashIterations = 210000;

  /// The iteration count that produced every hash written before PBKDF2.
  static const int kLegacyPinHashIterations = 25000;

  /// PBKDF2-HMAC-SHA256 (RFC 8018) over UTF-8 inputs, hex encoded.
  ///
  /// Implemented here on top of the audited `crypto` HMAC primitive so the app
  /// takes on no extra dependency for one well-specified algorithm. Verified
  /// against the RFC test vectors in `test/crypto_helper_test.dart`.
  static String _pbkdf2Sha256({
    required String password,
    required String salt,
    required int iterations,
    required int keyLength,
  }) {
    final List<int> passwordBytes = utf8.encode(password);
    final List<int> saltBytes = utf8.encode(salt);
    final Hmac hmac = Hmac(sha256, passwordBytes);

    final List<int> derived = <int>[];
    int block = 1;
    while (derived.length < keyLength) {
      // U1 = PRF(P, S || INT_32_BE(i))
      final List<int> seed = <int>[...saltBytes, ..._int32BigEndian(block)];
      List<int> u = hmac.convert(seed).bytes;
      final List<int> accumulator = List<int>.of(u);
      for (int round = 1; round < iterations; round++) {
        u = hmac.convert(u).bytes;
        for (int i = 0; i < accumulator.length; i++) {
          accumulator[i] ^= u[i];
        }
      }
      derived.addAll(accumulator);
      block++;
    }
    return _toHex(derived.sublist(0, keyLength));
  }

  static List<int> _int32BigEndian(int value) => <int>[
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ];

  /// Length-independent, value-independent comparison.
  ///
  /// Comparing the two hashes character by character with a *running* total
  /// prevents an attacker from learning the correct prefix by timing the
  /// comparison.
  static bool secureEquals(String? a, String? b) {
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// UTF-8 bytes of [value].
  ///
  /// `codeUnits` (UTF-16) would mangle any character outside the Latin-1 range,
  /// so every hash input goes through a real UTF-8 encoder.
  static List<int> utf8Bytes(String value) => utf8.encode(value);

  static String _toHex(List<int> bytes) {
    final StringBuffer buffer = StringBuffer();
    for (final int byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
