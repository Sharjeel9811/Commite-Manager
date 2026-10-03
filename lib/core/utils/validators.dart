import '../constants/app_constants.dart';

/// All input validation in one place.
///
/// Forms never contain their own regex: they ask this class. That is
/// Single Responsibility in action — the rules live in one testable place and
/// can be changed without touching a single widget.
class Validators {
  const Validators._();

  static final RegExp _phonePattern = RegExp(r'^\+?[0-9]{7,15}$');
  static final RegExp _digitsOnly = RegExp(r'[^0-9]');

  /// Anything that is not part of a number: a currency symbol, spaces, or
  /// thousands separators.
  static final RegExp _amountNoise = RegExp(r'[^0-9.]');

  /// Thousands separators, i.e. a comma or a dot followed by exactly three
  /// digits and then a digit boundary. The lookahead is what stops the decimal
  /// point in `10.50` from being treated as a grouping separator: there the
  /// group after the dot is two digits, not three.
  static final RegExp _groupingSeparator = RegExp(r'(?<=\d)[.,](?=\d{3}(?!\d))');

  /// Normalises money text into something [double.tryParse] understands.
  ///
  /// The previous implementation deleted every non-digit, which threw away the
  /// decimal point as well: `10.50` became `1050`, a silent 100x overcharge
  /// that mattered as soon as a 2-decimal currency (USD, GBP, EUR, AUD, AED)
  /// was selected. It also meant `-50` parsed as `50`, so a negative amount
  /// passed validation.
  static String _normalizeAmount(String? value) {
    var raw = (value ?? '').trim().replaceAll(_amountNoise, '');
    raw = raw.replaceAll(_groupingSeparator, '');
    // Collapse repeated separators that grouping removal may have left behind,
    // e.g. `1,,000`, and drop a leading/trailing dot that `10.` would create.
    while (raw.contains('..')) {
      raw = raw.replaceAll('..', '.');
    }
    if (raw.startsWith('.')) raw = raw.substring(1);
    if (raw.endsWith('.')) raw = raw.substring(0, raw.length - 1);
    return raw;
  }

  // ------------------------------------------------------------------ Generic

  static String? requiredText(
    String? value, {
    required String fieldName,
    int minLength = 1,
    int maxLength = 120,
  }) {
    final String trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return '$fieldName is required';
    if (trimmed.length < minLength) {
      return '$fieldName must be at least $minLength characters long';
    }
    if (trimmed.length > maxLength) {
      return '$fieldName must be at most $maxLength characters long';
    }
    return null;
  }

  // ---------------------------------------------------------------- Committee

  static String? committeeName(String? value) {
    final String? basic = requiredText(
      value,
      fieldName: 'Committee name',
      minLength: 3,
      maxLength: AppConstants.maxCommitteeNameLength,
    );
    if (basic != null) return basic;
    if (RegExp(r'^\d+$').hasMatch(value!.trim())) {
      return 'Committee name cannot be only numbers';
    }
    return null;
  }

  /// Accepts "10000", "10,000", "Rs 10,000" and "10000.50".
  ///
  /// A `-` is rejected outright rather than being stripped, so a negative
  /// contribution can never be saved.
  static String? contributionAmount(String? value) {
    final String typed = (value ?? '').trim();
    if (RegExp(r'-').hasMatch(typed)) return 'Amount cannot be negative';
    final String raw = _normalizeAmount(typed);
    if (raw.isEmpty) return 'Contribution amount is required';
    final double? parsed = double.tryParse(raw);
    if (parsed == null) return 'Enter a valid number';
    if (parsed < AppConstants.minContributionAmount) {
      return 'Amount must be greater than 0';
    }
    if (parsed > AppConstants.maxContributionAmount) {
      return 'That amount is unrealistically large';
    }
    return null;
  }

  static double parseAmount(String? value) =>
      double.tryParse(_normalizeAmount(value)) ?? 0;

  /// Compares two money amounts for "is this the same figure?".
  ///
  /// A bare `!=` on doubles is wrong here: the value goes through a decimal
  /// string on the way in and a `double` on the way out, so a round trip can
  /// land one ULP away and report a change the user never made. Half a paisa
  /// of tolerance is far below any amount anyone can enter and far above the
  /// representation error.
  static bool isSameAmount(double a, double b) => (a - b).abs() < 0.005;

  static String? memberCount(String? value, {required int currentCount}) {
    final int? parsed = int.tryParse((value ?? '').trim());
    if (parsed == null) return 'Enter a valid number of members';
    if (parsed < AppConstants.minCommitteeMembers) {
      return 'A committee needs at least ${AppConstants.minCommitteeMembers} members';
    }
    if (parsed > AppConstants.maxCommitteeMembers) {
      return 'Maximum ${AppConstants.maxCommitteeMembers} members supported';
    }
    if (currentCount > 0 && parsed < currentCount) {
      return 'Cannot be less than the $currentCount members already added';
    }
    return null;
  }

  /// In a classic committee every member contributes once and receives once,
  /// therefore the number of periods must equal the number of members.
  static String? duration(String? value, {required int memberCount}) {
    final int? parsed = int.tryParse((value ?? '').trim());
    if (parsed == null) return 'Duration is required';
    if (parsed < AppConstants.minCommitteeMembers) {
      return 'Duration must be at least ${AppConstants.minCommitteeMembers} periods';
    }
    if (parsed != memberCount) {
      return 'Duration must equal the number of members ($memberCount)';
    }
    return null;
  }

  // ------------------------------------------------------------------- Member

  static String? memberName(String? value) => requiredText(
    value,
    fieldName: 'Member name',
    minLength: 2,
    maxLength: AppConstants.maxMemberNameLength,
  );

  /// Very deliberately permissive: 7 to 15 digits with an optional `+`.
  /// It rejects letters and rejects obviously broken lengths, which is the
  /// right trade-off for a local, offline application.
  static String? phoneNumber(String? value, {bool required = false}) {
    final String raw = (value ?? '').replaceAll(RegExp(r'[\s\-()]'), '').trim();
    if (raw.isEmpty) return required ? 'Phone number is required' : null;
    if (!_phonePattern.hasMatch(raw)) {
      return 'Enter a valid phone number (7-15 digits)';
    }
    return null;
  }

  /// A phone number the user may legitimately leave blank.
  ///
  /// Kept as a separate name so call sites read honestly: the account's phone
  /// number is an optional contact detail now that codes arrive by email, and
  /// the silent-null return of [phoneNumber] is easy to forget is optional.
  static String? optionalPhoneNumber(String? value) => phoneNumber(value);

  static String? email(String? value, {bool required = false}) {
    final String raw = (value ?? '').trim();
    if (raw.isEmpty) return required ? 'Email is required' : null;
    final RegExp pattern = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
    if (!pattern.hasMatch(raw)) return 'Enter a valid email address';
    return null;
  }

  // --------------------------------------------------------------------- Auth

  static String? pin(String? value, {required bool isConfirmation}) {
    final String raw = (value ?? '').trim();
    if (raw.isEmpty) {
      return isConfirmation ? 'Please confirm your PIN' : 'Please enter a PIN';
    }
    // `_digitsOnly` is `[^0-9]`, so it *matching* means a non-digit is present.
    if (_digitsOnly.hasMatch(raw) || raw != value) {
      return 'PIN must contain digits only';
    }
    if (raw.length < AppConstants.minPinLength || raw.length > AppConstants.maxPinLength) {
      return 'PIN must be ${AppConstants.minPinLength}-${AppConstants.maxPinLength} digits';
    }
    if (RegExp(r'^(\d)\1+$').hasMatch(raw)) {
      return 'PIN cannot be the same digit repeated';
    }
    var hasAscendingRun = true;
    for (int i = 1; i < raw.length; i++) {
      if (int.parse(raw[i]) != int.parse(raw[i - 1]) + 1) {
        hasAscendingRun = false;
        break;
      }
    }
    if (hasAscendingRun) return 'PIN is too predictable';
    return null;
  }

  static String? otp(String? value) {
    final String raw = (value ?? '').replaceAll(' ', '').trim();
    if (raw.isEmpty) return 'Enter the verification code';
    if (raw.length != AppConstants.otpLength) {
      return 'Code must be ${AppConstants.otpLength} digits';
    }
    if (_digitsOnly.hasMatch(raw)) return 'Code must contain digits only';
    return null;
  }

  // -------------------------------------------------------------- Date picker

  /// Guard used before any date is accepted into the domain.
  static String? startDate(DateTime? value) {
    if (value == null) return 'Start date is required';
    final DateTime start = DateTime(value.year, value.month, value.day);
    if (start.isBefore(DateTime.now().subtract(const Duration(days: 365)))) {
      return 'Start date cannot be more than a year in the past';
    }
    return null;
  }
}
