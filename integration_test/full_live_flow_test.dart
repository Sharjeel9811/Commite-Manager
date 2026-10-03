import 'package:committee_manager/core/constants/app_constants.dart';
import 'package:committee_manager/main.dart' as app;
import 'package:committee_manager/screens/auth/verify_otp_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

/// A real, end-to-end verification on a real Android runtime:
///
///   1. Boots the real app (real SQLite, real composition root).
///   2. Fills the registration form and taps "Create account".
///   3. The real [GatewayOtpSender] mints a code and POSTs it to the real
///      Nodemailer gateway (reached through the adb reverse tunnel at
///      127.0.0.1:4000).
///   4. The gateway emails it and, because LOG_CODES=true in this verification
///      run, also writes the code to its log.
///   5. This test fetches that log (via LOGSERVE at 127.0.0.1:4101, also reverse
///      tunnelled) — the same role a human reading their inbox plays.
///   6. Enters the code into the OTP boxes and verifies.
///   7. Expects the authenticated dashboard.
///
/// This is the closest automation can get to the real sign-up without owning the
/// mailbox: the code is genuinely delivered to the gateway and read from the
/// gateway's own record of it, not injected by the Flutter process.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const Duration timeout = Duration(seconds: 240);

  Future<String> fetchCode() async {
    final http.Response response = await http
        .get(Uri.parse('http://127.0.0.1:4101/log'))
        .timeout(const Duration(seconds: 10));
    final List<String> codes = RegExp(
      r'development only - the code was (\d{4,10})',
    ).allMatches(response.body).map((RegExpMatch m) => m.group(1)!).toList();
    if (codes.isEmpty) {
      throw StateError('no code in gateway log yet');
    }
    return codes.last;
  }

  /// Pumps frames until [finder] matches or [timeout] passes.
  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    required String what,
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('timed out waiting for $what');
  }

  testWidgets('real gateway: register -> emailed code -> verify -> dashboard', (
    WidgetTester tester,
  ) async {
    await app.main();

    // Splash resolves to registration on a fresh install.
    await pumpUntil(
      tester,
      find.text('Create your account'),
      what: 'the registration screen',
    );

    // Fill the real registration form.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full name'),
      'Integration Verifier',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone number (optional)'),
      '03001234567',
    );
    const String email = 'committeeverify.dev@gmail.com';
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email address'),
      email,
    );
    await tester.enterText(find.widgetWithText(TextFormField, '4–6 digit PIN'), '1234');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm PIN'),
      '1234',
    );

    await tester.pump();
    // The on-screen keyboard covers the button's coordinates, so a physical tap
    // can land on the IME instead. The confirm-PIN field submits on the done
    // action (_submit), which is the same code path as the button — use it.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // "Create account" finishes locally, then the screen swaps to Verify OTP
    // and [GatewayOtpSender] POSTs the code to the real gateway.
    await pumpUntil(
      tester,
      find.text('Verify your account'),
      what: 'the OTP verification screen',
    );

    // Pull the code back from the gateway's log and enter it like a user would.
    String code = '';
    final DateTime fetchDeadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(fetchDeadline)) {
      try {
        code = await fetchCode();
        break;
      } catch (_) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }
    expect(code.length, AppConstants.otpLength, reason: 'a real 6-digit code');

    // The OtpInput is one TextField per digit.
    final Finder otpBoxes = find.descendant(
      of: find.byType(OtpInput),
      matching: find.byType(TextField),
    );
    expect(otpBoxes, findsNWidgets(AppConstants.otpLength));
    for (int i = 0; i < code.length; i++) {
      await tester.enterText(otpBoxes.at(i), code[i]);
      await tester.pump();
    }

    // The final digit auto-submits, so there is no button to press; the code is
    // verified as soon as the code is complete.
    await tester.pump(const Duration(milliseconds: 200));

    // On success AuthGate swaps the shell in: the dashboard (Home tab) shows.
    await pumpUntil(
      tester,
      find.text('Committees'),
      what: 'the dashboard bottom bar',
    );

    expect(tester.takeException(), isNull, reason: 'no framework error on the way in');
  });
}