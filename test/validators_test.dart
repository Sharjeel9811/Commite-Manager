import 'package:committee_manager/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the form validators.
///
/// Every one of these asserts on a *valid* input returning `null`. That is the
/// direction that matters most and the direction that is easiest to get wrong:
/// an inverted predicate rejects everything, which looks fine in code review and
/// makes the feature completely unusable at runtime. (The PIN check really was
/// inverted once - `_digitsOnly` is `[^0-9]`, so a match means a bad character is
/// present - and no other test caught it.)
void main() {
  group('Validators.pin', () {
    test('accepts an ordinary 4-digit PIN', () {
      expect(Validators.pin('4827', isConfirmation: false), isNull);
    });

    test('accepts a 6-digit PIN', () {
      expect(Validators.pin('926415', isConfirmation: false), isNull);
    });

    test('rejects letters', () {
      expect(Validators.pin('48a7', isConfirmation: false), 'PIN must contain digits only');
    });

    test('rejects symbols and spaces', () {
      expect(Validators.pin('48 7', isConfirmation: false), 'PIN must contain digits only');
      expect(Validators.pin('48-7', isConfirmation: false), 'PIN must contain digits only');
    });

    test('rejects a PIN that is too short', () {
      expect(Validators.pin('482', isConfirmation: false), isNotNull);
    });

    test('rejects a PIN that is too long', () {
      expect(Validators.pin('48271935', isConfirmation: false), isNotNull);
    });

    test('rejects a single repeated digit', () {
      expect(Validators.pin('1111', isConfirmation: false), isNotNull);
    });

    test('rejects an ascending run as predictable', () {
      expect(Validators.pin('1234', isConfirmation: false), isNotNull);
    });

    test('asks for a confirmation only when it is the confirm field', () {
      expect(Validators.pin('', isConfirmation: false), 'Please enter a PIN');
      expect(Validators.pin('', isConfirmation: true), 'Please confirm your PIN');
    });
  });

  group('Validators.otp', () {
    test('accepts a six-digit code', () {
      expect(Validators.otp('483920'), isNull);
    });

    test('tolerates spaces from a pasted code', () {
      expect(Validators.otp('483 920'), isNull);
    });

    test('rejects a code of the wrong length', () {
      expect(Validators.otp('48392'), isNotNull);
    });

    test('rejects letters', () {
      expect(Validators.otp('48392a'), 'Code must contain digits only');
    });

    test('rejects an empty code', () {
      expect(Validators.otp(''), isNotNull);
    });
  });

  group('Validators.phoneNumber', () {
    test('accepts an international number', () {
      expect(Validators.phoneNumber('+923001234567'), isNull);
    });

    test('accepts a local number and ignores formatting', () {
      expect(Validators.phoneNumber('0300 1234567'), isNull);
      expect(Validators.phoneNumber('(0300) 123-4567'), isNull);
    });

    test('rejects letters and absurd lengths', () {
      expect(Validators.phoneNumber('call me'), isNotNull);
      expect(Validators.phoneNumber('12345'), isNotNull);
    });

    test('treats an empty value as optional unless required', () {
      expect(Validators.phoneNumber(''), isNull);
      expect(Validators.phoneNumber('', required: true), 'Phone number is required');
    });
  });

  group('Validators.email', () {
    test('accepts an ordinary address', () {
      expect(Validators.email('ada@example.com'), isNull);
    });

    test('rejects a malformed address', () {
      expect(Validators.email('ada@example'), isNotNull);
      expect(Validators.email('ada@'), isNotNull);
    });
  });

  group('Validators.memberName', () {
    test('accepts a normal name', () {
      expect(Validators.memberName('Ada Lovelace'), isNull);
    });

    test('rejects a name that is too short', () {
      expect(Validators.memberName('A'), isNotNull);
    });
  });
}
