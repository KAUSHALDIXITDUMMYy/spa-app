import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class ApiClient {
  ApiClient(this._auth);

  final FirebaseAuth _auth;

  Future<http.Response> get(String path) => _request('GET', path);

  Future<http.Response> post(String path, {Object? body}) =>
      _request('POST', path, body: body);

  /// Pre-login requests (e.g. pending-user migration) — no user token yet.
  Future<http.Response> postPublic(String path, {Object? body}) {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    return http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: body == null ? null : jsonEncode(body),
    );
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Object? body,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be signed in');
    }

    final idToken = await user.getIdToken();
    if (idToken == null) {
      throw Exception('Could not get auth token');
    }
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $idToken',
      'X-Id-Token': idToken,
    };
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');

    if (method == 'GET') {
      return http.get(uri, headers: headers);
    }
    return http.post(
      uri,
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    );
  }
}
