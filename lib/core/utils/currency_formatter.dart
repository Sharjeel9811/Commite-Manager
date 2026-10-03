import 'package:intl/intl.dart';

import '../constants/app_constants.dart';

/// Formats money consistently everywhere in the UI.
///
/// The currency is configurable because the same project is demonstrated with
/// both PKR and other currencies; changing it happens in one place only.
class CurrencyFormatter {
  const CurrencyFormatter._();

  static String _symbol = AppConstants.defaultCurrencySymbol;
  static String _code = AppConstants.defaultCurrencyCode;
  static int _decimals = AppConstants.currencyDecimalDigits;

  static String get symbol => _symbol;
  static String get code => _code;

  static void configure({required String symbol, required String code, int? decimals}) {
    _symbol = symbol;
    _code = code;
    if (decimals != null) _decimals = decimals;
  }

  /// `Rs 100,000` (no decimals, which is what people expect for round amounts).
  static String format(num amount) =>
      NumberFormat.currency(symbol: '$_symbol ', decimalDigits: _decimals).format(amount);

  /// `Rs 1,00,000` style is locale specific; this keeps grouping simple.
  static String formatCompact(num amount) {
    final double value = amount.toDouble();
    if (value.abs() >= 1000000) {
      return '$_symbol ${(value / 1000000).toStringAsFixed(value.abs() >= 10000000 ? 0 : 1)}M';
    }
    if (value.abs() >= 1000) {
      return '$_symbol ${(value / 1000).toStringAsFixed(value.abs() >= 100000 ? 0 : 1)}K';
    }
    return format(value);
  }

  /// `+ Rs 5,000` / `- Rs 5,000`
  static String formatSigned(num amount) {
    final String sign = amount < 0 ? '-' : '+';
    return '$sign ${format(amount.abs())}';
  }
}
