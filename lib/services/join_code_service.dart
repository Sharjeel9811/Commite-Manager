import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import '../core/utils/logger.dart';
import '../models/committee.dart';
import '../models/enums.dart';
import '../models/member.dart';

/// Manages committee join codes via the Vercel backend.
///
/// Flow:
///   Organiser: shareCommittee() → gets a 6-char code → shares it
///   Member:    joinWithCode()   → enters the code → gets committee data
class JoinCodeService {
  JoinCodeService({http.Client? client, String? baseUrl, String? apiKey, String? accessToken})
      : _client     = client ?? http.Client(),
        _baseUrl     = _norm(baseUrl ?? AppConfig.otpGatewayUrl),
        _apiKey      = apiKey ?? AppConfig.otpGatewayApiKey,
        _accessToken = accessToken ?? '';

  final http.Client _client;
  final String _baseUrl;
  final String _apiKey;
  String _accessToken;

  static const AppLogger _log = AppLogger('JoinCodeService');

  static String _norm(String url) =>
      url.trim().endsWith('/') ? url.trim().substring(0, url.trim().length - 1) : url.trim();

  /// Call this after the user verifies their OTP so all join-code calls are
  /// authenticated.
  void setAccessToken(String token) => _accessToken = token;

  Map<String, String> get _headers => <String, String>{
    'content-type': 'application/json',
    if (_apiKey.isNotEmpty) 'x-otp-key': _apiKey,
    if (_accessToken.isNotEmpty) 'authorization': 'Bearer $_accessToken',
  };

  /// Uploads committee data and returns a 6-character join code.
  Future<JoinCodeResult> shareCommittee({
    required Committee committee,
    required List<Member> members,
  }) async {
    if (_baseUrl.isEmpty) {
      return JoinCodeResult.failure('OTP gateway URL is not configured.');
    }
    try {
      final http.Response response = await _client
          .post(
            Uri.parse('$_baseUrl/api/committees/share'),
            headers: _headers,
            body: jsonEncode(<String, Object?>{
              'committee': committee.toMap(),
              'members':   members.map((Member m) => m.toMap()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, Object?> body =
            jsonDecode(response.body) as Map<String, Object?>;
        _log.info('Join code created: ${body['code']}');
        return JoinCodeResult.success(
          code:      body['code']! as String,
          expiresAt: DateTime.parse(body['expiresAt']! as String),
        );
      }
      return JoinCodeResult.failure(_errorFrom(response));
    } catch (e) {
      _log.error('shareCommittee failed', e);
      return JoinCodeResult.failure(
          'Could not create join code. Check your connection.');
    }
  }

  /// Fetches committee data using a join code entered by a member.
  Future<JoinResult> joinWithCode(String code) async {
    if (_baseUrl.isEmpty) {
      return JoinResult.failure('OTP gateway URL is not configured.');
    }
    final String clean = code.trim().toUpperCase();
    try {
      final http.Response response = await _client
          .get(
            Uri.parse('$_baseUrl/api/committees/join/$clean'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, Object?> body =
            jsonDecode(response.body) as Map<String, Object?>;
        final Committee committee =
            Committee.fromMap(body['committee']! as Map<String, Object?>);
        final List<Member> members = (body['members']! as List<Object?>)
            .map((Object? m) => Member.fromMap(m! as Map<String, Object?>))
            .toList();
        _log.info('Joined committee via code $clean');
        return JoinResult.success(committee: committee, members: members);
      }
      return JoinResult.failure(_errorFrom(response));
    } catch (e) {
      _log.error('joinWithCode failed', e);
      return JoinResult.failure(
          'Could not fetch committee. Check your connection.');
    }
  }

  String _errorFrom(http.Response r) {
    try {
      final Object? body = jsonDecode(r.body);
      if (body is Map<String, Object?> && body['error'] is String) {
        return body['error']! as String;
      }
    } on FormatException {
      // fall through
    }
    if (r.statusCode == 404) return 'Join code not found. Check the code and try again.';
    if (r.statusCode == 410) return 'This join code has expired. Ask the organiser for a new one.';
    if (r.statusCode == 401) return 'Not signed in. Please verify your email first.';
    return 'Something went wrong (${r.statusCode}). Please try again.';
  }
}

class JoinCodeResult {
  const JoinCodeResult._({this.code, this.expiresAt, this.error});

  factory JoinCodeResult.success({required String code, required DateTime expiresAt}) =>
      JoinCodeResult._(code: code, expiresAt: expiresAt);

  factory JoinCodeResult.failure(String error) => JoinCodeResult._(error: error);

  final String? code;
  final DateTime? expiresAt;
  final String? error;

  bool get isSuccess => error == null;
}

class JoinResult {
  const JoinResult._({this.committee, this.members, this.error});

  factory JoinResult.success({
    required Committee committee,
    required List<Member> members,
  }) => JoinResult._(committee: committee, members: members);

  factory JoinResult.failure(String error) => JoinResult._(error: error);

  final Committee? committee;
  final List<Member>? members;
  final String? error;

  bool get isSuccess => error == null;
}
