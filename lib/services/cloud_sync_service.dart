import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import '../database/app_database.dart';

class CloudSyncService {
  CloudSyncService(this._database, {http.Client? client}) : _client = client ?? http.Client();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _tokenKey = 'cloud.sync.access_token';
  final AppDatabase _database;
  final http.Client _client;

  Uri get _pushUri => Uri.parse('${AppConfig.otpGatewayUrl}/api/sync/push');
  Uri get _pullUri => Uri.parse('${AppConfig.otpGatewayUrl}/api/sync/pull');

  Future<void> saveAccessToken(String token) => _storage.write(key: _tokenKey, value: token);

  Future<String?> _token() => _storage.read(key: _tokenKey);

  Future<bool> push() async {
    final String? token = await _token();
    if (token == null || token.isEmpty || !AppConfig.otpGatewayConfigured) return false;
    final response = await _client.post(
      _pushUri,
      headers: <String, String>{
        'content-type': 'application/json',
        'authorization': 'Bearer $token',
      },
      body: jsonEncode(<String, Object?>{'data': await _database.exportCloudData()}),
    );
    if (response.statusCode != 200) {
      throw StateError('Cloud backup failed (${response.statusCode}).');
    }
    return true;
  }

  Future<bool> pull() async {
    final String? token = await _token();
    if (token == null || token.isEmpty || !AppConfig.otpGatewayConfigured) return false;
    final response = await _client.get(_pullUri, headers: <String, String>{'authorization': 'Bearer $token'});
    if (response.statusCode != 200) {
      throw StateError('Cloud restore failed (${response.statusCode}).');
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic> && decoded['data'] is Map<String, dynamic>) {
      await _database.replaceCloudData(decoded['data'] as Map<String, dynamic>);
    }
    return true;
  }
}
