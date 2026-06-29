import 'dart:convert';

import 'api_client.dart';
import 'agora_live_service.dart';

class AgoraTokenResult {
  const AgoraTokenResult({
    required this.token,
    required this.uid,
    required this.appId,
  });

  final String token;
  final int uid;
  final String appId;
}

/// Fetches Agora RTC tokens from the SPA backend (same as web `/api/agora/token`).
class AgoraTokenService {
  AgoraTokenService(this._api);

  final ApiClient _api;

  Future<AgoraTokenResult> fetchToken({
    required String channelName,
    required LiveRole role,
    String? streamSessionId,
    int? uid,
  }) async {
    final body = <String, dynamic>{
      'channelName': channelName,
      'role': role == LiveRole.publisher ? 'publisher' : 'audience',
      if (streamSessionId != null && streamSessionId.isNotEmpty)
        'streamSessionId': streamSessionId,
      if (uid != null && uid > 0) 'uid': uid,
    };

    final res = await _api.post('/api/agora/token', body: body);
    Map<String, dynamic> json;
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Invalid Agora token response (${res.statusCode})');
    }

    if (res.statusCode != 200) {
      final msg = json['error'];
      throw Exception(msg is String && msg.isNotEmpty
          ? msg
          : 'Failed to fetch Agora token (${res.statusCode})');
    }

    final token = json['token'];
    final appId = json['appId'];
    final agoraUid = json['uid'];
    if (token is! String ||
        token.isEmpty ||
        appId is! String ||
        appId.isEmpty ||
        agoraUid is! num) {
      throw Exception('Agora token response missing token, uid, or appId');
    }

    return AgoraTokenResult(
      token: token,
      uid: agoraUid.toInt(),
      appId: appId,
    );
  }
}
