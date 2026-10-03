import 'package:committee_manager/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the money parser.
///
/// [Validators] used to strip *every* non-digit before parsing, so the decimal
/// point was deleted along with the separators. Typing `10.50` therefore stored
/// `1050` — a silent 100x overcharge. The app offers 2-decimal currencies
/// (USD, GBP, EUR, AUD, AED), so this was reachable in normal use.
void main() {
  group('Validators.parseAmount', () {
    test('keeps the decimal point instead of deleting it', () {
      expect(Validators.parseAmount('10.50'), 10.5);
      expect(Validators.parseAmount('0.01'), 0.01);
      expect(Validators.parseAmount('1234.56'), 1234.56);
    });

    test('treats grouping separators as noise, not as decimals', () {
      expect(Validators.parseAmount('10,000'), 10000);
      expect(Validators.parseAmount('1,00,000'), 100000);
      expect(Validators.parseAmount('Rs 10,000'), 10000);
    });

    test('tolerates a currency prefix and surrounding space', () {
      expect(Validators.parseAmount('  \$ 1,234.56 '), 1234.56);
    });

    test('returns 0 for input that is not a number at all', () {
      expect(Validators.parseAmount(null), 0);
      expect(Validators.parseAmount(''), 0);
      expect(Validators.parseAmount('abc'), 0);
    });
  });

  group('Validators.contributionAmount', () {
    test('accepts an amount with two decimal places', () {
      expect(Validators.contributionAmount('10.50'), isNull);
      expect(Validators.contributionAmount('1234.56'), isNull);
    });

    test('rejects a value above the maximum rather than mangling it', () {
      expect(Validators.contributionAmount('999999999.99'), isNotNull);
    });

    test('rejects zero and negatives', () {
      expect(Validators.contributionAmount('0'), isNotNull);
      expect(Validators.contributionAmount('-50'), isNotNull);
    });

    test('rejects values below the minimum', () {
      expect(Validators.contributionAmount('0.4'), isNotNull);
    });

    test('accepts the smallest allowed contribution', () {
      expect(Validators.contributionAmount('1'), isNull);
    });
  });
}
