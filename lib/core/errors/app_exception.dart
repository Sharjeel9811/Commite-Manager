/// Custom exception hierarchy.
///
/// Every failure that can reach the UI is represented by one of these types, so
/// a widget never has to read a raw SQLite message. Each exception carries a
/// *user friendly* [message] and an optional technical [details] field that is
/// only logged, never displayed.
library;

/// Base class for every error raised by the domain / data layers.
sealed class AppException implements Exception {
  const AppException(this.message, {this.details});

  /// Safe to show to the user.
  final String message;

  /// Technical information, only written to the debug console.
  final String? details;

  @override
  String toString() => '$runtimeType: $message${details == null ? '' : ' ($details)'}';
}

/// The user typed something invalid.
class ValidationException extends AppException {
  const ValidationException(super.message, {super.details, this.fieldErrors = const {}});

  /// Optional per-field messages, keyed by field name.
  final Map<String, String> fieldErrors;
}

/// A business rule was violated (e.g. trying to pay twice).
class BusinessRuleException extends AppException {
  const BusinessRuleException(super.message, {super.details});
}

/// A record was requested but does not exist.
class NotFoundException extends AppException {
  const NotFoundException(super.message, {super.details});
}

/// A unique constraint / duplicate would be created.
class DuplicateException extends AppException {
  const DuplicateException(super.message, {super.details});
}

/// The database or a plugin failed.
class DatabaseException extends AppException {
  const DatabaseException(super.message, {super.details});
}

/// Authentication / authorisation failed.
class AuthException extends AppException {
  const AuthException(super.message, {super.details, this.lockoutUntil});

  /// Set when the user is temporarily locked out after too many failures.
  final DateTime? lockoutUntil;

  bool get isLockedOut => lockoutUntil != null && lockoutUntil!.isAfter(DateTime.now());
}

/// A required device capability (biometrics, notifications) is unavailable.
class CapabilityException extends AppException {
  const CapabilityException(super.message, {super.details});
}

/// Turns any thrown object into a message that is safe to display.
///
/// [ValidationException] is matched first on purpose: it extends
/// [AppException], so testing the parent first would swallow the per-field
/// messages a form needs in order to highlight the offending input.
String describeError(Object error) {
  if (error is ValidationException) {
    final Map<String, String> fields = error.fieldErrors;
    if (fields.isNotEmpty) return fields.values.first;
    return error.message;
  }
  if (error is AppException) return error.message;
  return 'Something went wrong. Please try again.';
}
