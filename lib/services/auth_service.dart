import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import 'api_client.dart';

class AuthService {
  AuthService(this._auth, this._api);

  final FirebaseAuth _auth;
  final ApiClient _api;

  static const _sessionKey = 'subscriber_session_id';

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<UserProfile?> getUserProfile(String uid, {int retry = 0}) async {
    try {
      final res = await _api.get('/api/auth/profile?uid=${Uri.encodeComponent(uid)}');
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final profile = json['profile'];
        if (profile is Map<String, dynamic>) {
          return UserProfile.fromMap(uid, profile);
        }
      }
      if (retry < 3) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return getUserProfile(uid, retry: retry + 1);
      }
      return null;
    } catch (_) {
      if (retry < 3) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return getUserProfile(uid, retry: retry + 1);
      }
      return null;
    }
  }

  Future<String?> signIn(String email, String password) async {
    final lower = email.trim().toLowerCase();

    // Pending-user migration runs server-side (Firestore is not readable from the client).
    try {
      await _api.postPublic(
        '/api/auth/login',
        body: {'email': lower, 'password': password},
      );
    } catch (_) {
      // Non-fatal — fall through to a normal sign-in attempt.
    }

    try {
      final cred =
          await _auth.signInWithEmailAndPassword(email: lower, password: password);
      final uid = cred.user!.uid;

      final profile = await getUserProfile(uid);
      if (profile == null) {
        await _auth.signOut();
        return 'Could not load profile. Check your connection and try again.';
      }

      if (profile.role == 'subscriber') {
        final prefs = await SharedPreferences.getInstance();
        final localSid = prefs.getString(_sessionKey);

        final res = await _api.post(
          '/api/auth/account',
          body: {
            'action': 'establishSession',
            'payload': {
              if (localSid != null) 'localSessionId': localSid,
            },
          },
        );
        final json = jsonDecode(res.body) as Map<String, dynamic>;

        if (res.statusCode == 200 && json['ok'] == false) {
          await _auth.signOut();
          return json['error'] as String? ??
              'This account is already active on another device. Sign out there or wait a few minutes.';
        }

        final sessionId = json['sessionId'] as String?;
        if (sessionId != null && sessionId.isNotEmpty) {
          await prefs.setString(_sessionKey, sessionId);
        }
      }

      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Sign in failed';
    } catch (e) {
      return 'Sign in failed: $e';
    }
  }

  Future<void> signOutCurrent() async {
    try {
      await _api.post(
        '/api/auth/account',
        body: {'action': 'clearSession', 'payload': {}},
      );
    } catch (_) {
      // Best-effort while we still have a token.
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    await _auth.signOut();
  }

  Future<void> acceptTerms(String uid) async {
    await _api.post(
      '/api/auth/account',
      body: {'action': 'acceptTerms', 'payload': {}},
    );
  }

  Future<void> heartbeatSession() async {
    try {
      await _api.post(
        '/api/auth/account',
        body: {'action': 'heartbeat', 'payload': {}},
      );
    } catch (_) {}
  }
}
