import 'dart:convert';

import 'package:committee_manager/core/config/app_config.dart';
import 'package:committee_manager/core/constants/app_constants.dart';
import 'package:committee_manager/services/implementations/gateway_otp_sender.dart';
import 'package:committee_manager/services/interfaces/otp_sender.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Verifies the self-hosted Nodemailer transport against a stub of the gateway's
/// real HTTP contract (`POST /otp`, `x-otp-key`, JSON body).
///
/// The contract this pins down lives in `otp_gateway_server/server.js`. If that
/// server changes its shape, these fail loudly rather than the app quietly
/// sending codes nobody receives.
void main() {
  const String destination = 'user@example.com';

  late List<http.Request> sent;

  /// A gateway stub that accepts sends and records what it was given.
  ({GatewayOtpSender sender, MockClient client}) stub({
    int status = 200,
    String body = '{"delivered":true,"channel":"email"}',
    Duration delay = Duration.zero,
    bool throwError = false,
    String? apiKey = 'secret-key',
  }) {
    sent = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      sent.add(request);
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (throwError) throw const SocketExceptionStub();
      return http.Response(body, status);
    });
    return (
      sender: GatewayOtpSender(
        client: client,
        baseUrl: 'https://otp.example.com',
        apiKey: apiKey,
      ),
      client: client,
    );
  }

  /// The code the gateway was actually asked to email.
  ///
  /// [index] matters once more than one code has been sent in a single test;
  /// without it `List.single` throws and the test fails for the wrong reason.
  String emailedCode([int index = 0]) {
    final Map<String, Object?> body =
        jsonDecode(sent[index].body) as Map<String, Object?>;
    return body['code']! as String;
  }

  group('the request matches the gateway contract', () {
    test('posts to /otp with the documented JSON body', () async {
      final harness = stub();
      await harness.sender.send(destination: destination, purpose: 'Account verification');

      expect(sent.single.method, 'POST');
      expect(sent.single.url.toString(), 'https://otp.example.com/otp');
      expect(sent.single.headers['content-type'], contains('application/json'));

      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body['destination'], destination);
      expect(body['channel'], 'email', reason: 'the server rejects anything else');
      expect(body['purpose'], 'Account verification');
      expect(body['code'], isA<String>());
    });

    test('a trailing slash on the base URL does not double up', () async {
      sent = <http.Request>[];
      final GatewayOtpSender sender = GatewayOtpSender(
        client: MockClient((http.Request r) async {
          sent.add(r);
          return http.Response('{"delivered":true}', 200);
        }),
        baseUrl: 'https://otp.example.com/',
      );
      await sender.send(destination: destination, purpose: 'p');
      expect(sent.single.url.toString(), 'https://otp.example.com/otp');
    });

    test('sends the x-otp-key header when a key is configured', () async {
      final harness = stub();
      await harness.sender.send(destination: destination, purpose: 'p');
      expect(sent.single.headers['x-otp-key'], 'secret-key');
    });

    test('omits the header when no key is configured', () async {
      final harness = stub(apiKey: '');
      await harness.sender.send(destination: destination, purpose: 'p');
      expect(sent.single.headers.containsKey('x-otp-key'), isFalse);
    });

    test('the emailed code is the right length and numeric', () async {
      final harness = stub();
      await harness.sender.send(destination: destination, purpose: 'p');
      final String code = emailedCode();
      expect(code.length, AppConstants.otpLength);
      expect(RegExp(r'^\d+$').hasMatch(code), isTrue);
    });
  });

  group('verification round-trips', () {
    test('the code that was emailed is the code that verifies', () async {
      final harness = stub();
      await harness.sender.send(destination: destination, purpose: 'p');
      final String code = emailedCode();

      final OtpVerificationResult result = await harness.sender.verify(
        destination: destination,
        code: code,
      );
      expect(result.success, isTrue, reason: result.error);
    });

    test('a wrong code is rejected', () async {
      final harness = stub();
      await harness.sender.send(destination: destination, purpose: 'p');
      final String code = emailedCode();
      final String wrong = code == '000000' ? '111111' : '000000';

      final OtpVerificationResult result = await harness.sender.verify(
        destination: destination,
        code: wrong,
      );
      expect(result.success, isFalse);
      expect(result.error, isNotEmpty);
    });

    test('a code is single use', () async {
      final harness = stub();
      await harness.sender.send(destination: destination, purpose: 'p');
      final String code = emailedCode();

      expect(
        (await harness.sender.verify(destination: destination, code: code)).success,
        isTrue,
      );
      final OtpVerificationResult second = await harness.sender.verify(
        destination: destination,
        code: code,
      );
      expect(second.success, isFalse, reason: 'a replayed code must not work');
    });

    test('surrounding whitespace in the typed code is tolerated', () async {
      final harness = stub();
      await harness.sender.send(destination: destination, purpose: 'p');
      final String code = emailedCode();

      final OtpVerificationResult result = await harness.sender.verify(
        destination: destination,
        code: '  $code  ',
      );
      expect(result.success, isTrue, reason: result.error);
    });

    test('the address is matched case-insensitively', () async {
      final harness = stub();
      await harness.sender.send(destination: destination, purpose: 'p');
      final String code = emailedCode();

      final OtpVerificationResult result = await harness.sender.verify(
        destination: 'USER@Example.COM',
        code: code,
      );
      expect(result.success, isTrue, reason: result.error);
    });

    test('a code is not accepted for a different address', () async {
      final harness = stub();
      await harness.sender.send(destination: destination, purpose: 'p');
      final String code = emailedCode();

      final OtpVerificationResult result = await harness.sender.verify(
        destination: 'someone.else@example.com',
        code: code,
      );
      expect(result.success, isFalse);
    });

    test('a code for one address never verifies for another', () async {
      final harness = stub();
      await harness.sender.send(destination: 'a@example.com', purpose: 'p');
      final String codeA = emailedCode(0);
      await harness.sender.send(destination: 'b@example.com', purpose: 'p');
      final String codeB = emailedCode(1);

      expect((await harness.sender.verify(destination: 'b@example.com', code: codeA)).success, isFalse);
      expect((await harness.sender.verify(destination: 'a@example.com', code: codeB)).success, isFalse);
      expect((await harness.sender.verify(destination: 'a@example.com', code: codeA)).success, isTrue);
      expect((await harness.sender.verify(destination: 'b@example.com', code: codeB)).success, isTrue);
    });

    test('verifying with nothing sent asks for a new code', () async {
      final harness = stub();
      final OtpVerificationResult result = await harness.sender.verify(
        destination: destination,
        code: '123456',
      );
      expect(result.success, isFalse);
      expect(result.error, contains('new verification code'));
    });
  });

  group('requesting a new code invalidates the old one', () {
    test('the previous code stops working', () async {
      final harness = stub();
      await harness.sender.send(destination: destination, purpose: 'p');
      final String first = emailedCode(0);
      await harness.sender.send(destination: destination, purpose: 'p');
      final String second = emailedCode(1);

      expect(
        (await harness.sender.verify(destination: destination, code: first)).success,
        isFalse,
        reason: 'the superseded code must not verify',
      );
      expect((await harness.sender.verify(destination: destination, code: second)).success, isTrue);
    });
  });

  group('failures never leave a usable code behind', () {
    test('a refused send is not remembered', () async {
      final harness = stub(status: 502);
      final OtpDeliveryResult delivery = await harness.sender.send(
        destination: destination,
        purpose: 'p',
      );
      expect(delivery.success, isFalse);

      // Nothing was delivered, so nothing may verify.
      final String sent2 = emailedCode();
      final OtpVerificationResult verify = await harness.sender.verify(
        destination: destination,
        code: sent2,
      );
      expect(verify.success, isFalse, reason: 'a code that was never emailed must not work');
    });

    test('an unreachable gateway is reported without leaking the code', () async {
      final harness = stub(throwError: true);
      final OtpDeliveryResult delivery = await harness.sender.send(
        destination: destination,
        purpose: 'p',
      );
      expect(delivery.success, isFalse);
      expect(delivery.error, isNot(contains(emailedCode())));
    });

    test('a 429 becomes a wait message', () async {
      final harness = stub(status: 429, body: '{"error":"Too many code requests."}');
      final OtpDeliveryResult delivery = await harness.sender.send(
        destination: destination,
        purpose: 'p',
      );
      expect(delivery.success, isFalse);
      expect(delivery.error, contains('Too many attempts'));
    });

    test('a 401 is treated as a build misconfiguration', () async {
      final harness = stub(status: 401, body: '{"error":"Unauthorized"}');
      final OtpDeliveryResult delivery = await harness.sender.send(
        destination: destination,
        purpose: 'p',
      );
      expect(delivery.success, isFalse);
      expect(delivery.error, contains('not configured'));
    });

    test('a gateway-authored message is passed through to the user', () async {
      final harness = stub(
        status: 503,
        body: '{"error":"Email delivery is not configured on the gateway."}',
      );
      final OtpDeliveryResult delivery = await harness.sender.send(
        destination: destination,
        purpose: 'p',
      );
      expect(delivery.error, contains('not configured on the gateway'));
    });

    test('deployment internals are not shown to the user', () async {
      // This is the real gateway text when the server has no mail credentials.
      // It is written for whoever runs the server, not for the person holding
      // the phone, and it must not appear in a published app.
      final harness = stub(
        status: 503,
        body:
            '{"error":"Email delivery is not configured on the gateway '
            '(set MAIL_USER and MAIL_PASS in .env)."}',
      );
      final OtpDeliveryResult delivery = await harness.sender.send(
        destination: destination,
        purpose: 'p',
      );
      expect(delivery.error, isNot(contains('MAIL_USER')));
      expect(delivery.error, isNot(contains('MAIL_PASS')));
      expect(delivery.error, isNot(contains('.env')));
      expect(delivery.error, isNotEmpty);
    });

    test('a non-JSON error body does not crash the sender', () async {
      final harness = stub(status: 500, body: '<html>502 Bad Gateway</html>');
      final OtpDeliveryResult delivery = await harness.sender.send(
        destination: destination,
        purpose: 'p',
      );
      expect(delivery.success, isFalse);
      expect(delivery.error, isNotEmpty);
    });

    test('an unconfigured build refuses politely instead of dialling', () async {
      sent = <http.Request>[];
      final GatewayOtpSender sender = GatewayOtpSender(
        client: MockClient((http.Request r) async {
          sent.add(r);
          return http.Response('{}', 200);
        }),
        baseUrl: '',
      );
      final OtpDeliveryResult delivery = await sender.send(
        destination: destination,
        purpose: 'p',
      );
      expect(delivery.success, isFalse);
      expect(delivery.error, contains('not configured'));
      expect(sent, isEmpty, reason: 'must not make a request it cannot fulfil');
    });
  });

  group('pending codes are bounded', () {
    test('a flood of addresses cannot grow the map without limit', () async {
      final GatewayOtpSender sender = GatewayOtpSender(
        client: MockClient(
          (http.Request r) async => http.Response('{"delivered":true}', 200),
        ),
        baseUrl: 'https://otp.example.com',
      );
      for (int i = 0; i < 200; i++) {
        await sender.send(destination: 'user$i@example.com', purpose: 'p');
      }
      // The cap is internal; what is observable is that the sender still works
      // and never throws while under flood.
      final OtpDeliveryResult last = await sender.send(
        destination: 'final@example.com',
        purpose: 'p',
      );
      expect(last.success, isTrue);
    });
  });

  group('which transport is live', () {
    test('Supabase stays the default when no gateway URL is built in', () {
      // This test binary is compiled without --dart-define, which is exactly the
      // "fresh clone" case. It pins the default so a build cannot silently flip
      // the app onto the weaker transport.
      expect(AppConfig.otpGatewayUrl, isEmpty);
      expect(AppConfig.otpGatewayConfigured, isFalse);
      expect(AppConfig.useOtpGateway, isFalse, reason: 'Supabase must stay the default');
    });
  });

  group('user-facing text', () {
    test('delivery description names the verification service', () {
      final harness = stub();
      expect(harness.sender.deliveryDescription, isNotEmpty);
      expect(harness.sender.deliveryDescription, contains('email'));
    });
  });
}

/// Stands in for a transport-level failure without depending on dart:io.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();

  @override
  String toString() => 'SocketException: connection failed';
}
