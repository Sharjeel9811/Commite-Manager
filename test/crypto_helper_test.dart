import 'package:committee_manager/core/utils/crypto_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the PIN credential handling.
///
/// A PIN is four to six digits, so it has almost no entropy by construction —
/// the whole defence is a slow, salted KDF plus a lockout. These tests pin the
/// algorithm down, including against published vectors, so a future refactor
/// cannot silently weaken it or invalidate stored hashes.
void main() {
  group('PBKDF2-HMAC-SHA256', () {
    // Published PBKDF2-HMAC-SHA256 test vectors (RFC 7914 / draft-josefs).
    const Map<String, String> vectors = <String, String>{
      'password|salt|1':
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      'password|salt|2':
          'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      'password|salt|4096':
          'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
    };

    test('matches the published vectors for a 32-byte key', () {
      // The private implementation is exercised through `hashPin`, whose output
      // is `pbkdf2_sha256$<rounds>$<hex>` — so the vector is checked by parsing.
      for (final MapEntry<String, String> entry in vectors.entries) {
        final List<String> parts = entry.key.split('|');
        final String stored = CryptoHelper.hashPin(
          parts[0],
          parts[1],
          iterations: int.parse(parts[2]),
        );
        expect(
          stored,
          '${CryptoHelper.pinHashPrefix}${parts[2]}\$${entry.value}',
          reason: 'vector ${entry.key}',
        );
      }
    });
  });

  group('hashPin', () {
    test('stores a self-describing, salted hash — never the PIN', () {
      final String hash = CryptoHelper.hashPin('5381', 'abcdef');

      expect(hash, startsWith(CryptoHelper.pinHashPrefix));
      expect(hash, isNot(contains('5381')));
      expect(hash.split(r'$'), hasLength(3));
    });

    test('the same PIN with a different salt gives an unrelated hash', () {
      expect(
        CryptoHelper.hashPin('5381', CryptoHelper.newSalt()),
        isNot(CryptoHelper.hashPin('5381', CryptoHelper.newSalt())),
      );
    });

    test('salts are 16 random bytes and differ every time', () {
      final String a = CryptoHelper.newSalt();
      final String b = CryptoHelper.newSalt();
      expect(a, hasLength(32), reason: '16 bytes, hex encoded');
      expect(a, isNot(b));
    });
  });

  group('verifyPin', () {
    test('accepts the right PIN and rejects a near miss', () {
      final String salt = CryptoHelper.newSalt();
      final String stored = CryptoHelper.hashPin('9274', salt);

      expect(CryptoHelper.verifyPin('9274', salt, stored), isTrue);
      expect(CryptoHelper.verifyPin('9275', salt, stored), isFalse);
      expect(CryptoHelper.verifyPin('', salt, stored), isFalse);
      expect(CryptoHelper.verifyPin('9274', CryptoHelper.newSalt(), stored), isFalse);
    });

    test('still accepts a hash written by an older build, and flags it for upgrade', () {
      // This is what a user upgrading the app actually has on disk.
      final String salt = CryptoHelper.newSalt();
      final String legacy = CryptoHelper.hashSecret(
        '5381',
        salt,
        rounds: CryptoHelper.kLegacyPinHashIterations,
      );

      expect(CryptoHelper.needsRehash(legacy), isTrue);
      expect(CryptoHelper.verifyPin('5381', salt, legacy), isTrue);
      expect(CryptoHelper.verifyPin('1111', salt, legacy), isFalse);
    });

    test('a modern hash is not flagged for upgrade', () {
      final String salt = CryptoHelper.newSalt();
      final String stored = CryptoHelper.hashPin('5381', salt);
      expect(CryptoHelper.needsRehash(stored), isFalse);
    });

    test('malformed or missing stored hashes are refused, never thrown on', () {
      expect(CryptoHelper.verifyPin('5381', 'salt', ''), isFalse);
      expect(CryptoHelper.verifyPin('5381', 'salt', r'pbkdf2_sha256$'), isFalse);
      expect(CryptoHelper.verifyPin('5381', 'salt', r'pbkdf2_sha256$abc$00'), isFalse);
      expect(CryptoHelper.verifyPin('5381', 'salt', r'pbkdf2_sha256$0$00'), isFalse);
    });
  });

  group('secureEquals', () {
    test('is value and length independent', () {
      expect(CryptoHelper.secureEquals('abc', 'abc'), isTrue);
      expect(CryptoHelper.secureEquals('abc', 'abd'), isFalse);
      expect(CryptoHelper.secureEquals('abc', 'abcd'), isFalse);
      expect(CryptoHelper.secureEquals(null, 'abc'), isFalse);
      expect(CryptoHelper.secureEquals('abc', null), isFalse);
    });
  });

  group('randomSecret', () {
    test('produces the requested length from the typo-free alphabet', () {
      final String secret = CryptoHelper.randomSecret(12);
      expect(secret, hasLength(12));
      expect(secret, matches(RegExp(r'^[A-Z2-9]+$')));
    });
  });
}
