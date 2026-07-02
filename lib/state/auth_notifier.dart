import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';

class AuthNotifier extends ChangeNotifier {
  AuthNotifier(this._authService) {
    _authSub = _authService.authStateChanges().listen(_onAuthUser);
  }

  final AuthService _authService;

  late final StreamSubscription<User?> _authSub;
  Timer? _profilePoll;
  Timer? _subscriberHeartbeat;

  User? firebaseUser;
  UserProfile? profile;
  bool loading = true;

  /// Tracks whether a profile load is in progress to avoid double-triggers.
  bool _loadingProfile = false;

  Future<void> _onAuthUser(User? user) async {
    firebaseUser = user;
    _profilePoll?.cancel();
    _profilePoll = null;
    _subscriberHeartbeat?.cancel();
    _subscriberHeartbeat = null;

    if (user == null) {
      profile = null;
      loading = false;
      _loadingProfile = false;
      notifyListeners();
      return;
    }

    await _loadProfile(user);
  }

  Future<void> _loadProfile(User user) async {
    if (_loadingProfile) return;
    _loadingProfile = true;
    loading = true;
    notifyListeners();

    try {
      // Give Firebase Auth a moment to settle token state after sign-in.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final fetched = await _authService.getUserProfile(user.uid);
      if (fetched != null) {
        profile = fetched;
      } else {
        // Profile fetch failed — keep any stale profile rather than nulling it out,
        // so the UI doesn't get stuck. Will retry on next poll tick.
        if (kDebugMode) {
          debugPrint('[AuthNotifier] getUserProfile returned null — will retry on poll');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthNotifier] getUserProfile threw: $e');
      }
    } finally {
      loading = false;
      _loadingProfile = false;
      notifyListeners();
    }

    _profilePoll = Timer.periodic(const Duration(seconds: 15), (_) async {
      final u = firebaseUser;
      if (u == null) return;
      try {
        final next = await _authService.getUserProfile(u.uid);
        if (next == null) return;
        profile = next;
        if (next.role == 'subscriber' && !next.isActive) {
          await _authService.signOutCurrent();
        }
        notifyListeners();
      } catch (_) {
        // Swallow poll errors — don't disrupt UI state.
      }
    });

    _subscriberHeartbeat = Timer.periodic(const Duration(minutes: 3), (_) async {
      final p = profile;
      final u = firebaseUser;
      if (u == null || p == null || p.role != 'subscriber') return;
      await _authService.heartbeatSession();
    });
  }

  Future<String?> signIn(String email, String password) {
    return _authService.signIn(email, password);
  }

  Future<void> signOut() => _authService.signOutCurrent();

  Future<void> acceptTerms() async {
    final u = firebaseUser;
    if (u == null) return;
    await _authService.acceptTerms(u.uid);
    profile = await _authService.getUserProfile(u.uid);
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub.cancel();
    _profilePoll?.cancel();
    _subscriberHeartbeat?.cancel();
    super.dispose();
  }
}
