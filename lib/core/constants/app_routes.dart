/// Every named route in the application.
///
/// Using constants instead of raw strings means a typo becomes a compile error
/// rather than a runtime "route not found" crash.
class AppRoutes {
  const AppRoutes._();

  // Public / auth
  static const String splash = '/';
  static const String lock = '/lock';
  static const String register = '/register';
  static const String createPin = '/create-pin';
  static const String verifyOtp = '/verify-otp';

  // Private app
  static const String dashboard = '/dashboard';
  static const String committees = '/committees';
  static const String createCommittee = '/committees/create';
  static const String committeeDetails = '/committees/details';
  static const String editCommittee = '/committees/edit';

  static const String members = '/members';
  static const String addMember = '/members/add';
  static const String memberDetails = '/members/details';
  static const String memberForm = '/members/form';
  static const String reorderTurns = '/members/reorder';

  static const String payments = '/payments';
  static const String periodDetails = '/payments/period';

  static const String history = '/history';
  static const String statistics = '/statistics';
  static const String settings = '/settings';
  static const String security = '/settings/security';
  static const String notificationsSettings = '/settings/notifications';
}
