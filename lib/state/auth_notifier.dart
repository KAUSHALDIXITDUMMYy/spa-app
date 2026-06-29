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

  Future<void> _onAuthUser(User? user) async {
    firebaseUser = user;
    _profilePoll?.cancel();
    _profilePoll = null;
    _subscriberHeartbeat?.cancel();
    _subscriberHeartbeat = null;

    if (user == null) {
      profile = null;
      loading = false;
      notifyListeners();
      return;
    }

    profile = await _authService.getUserProfile(user.uid);
    loading = false;
    notifyListeners();

    _profilePoll = Timer.periodic(const Duration(seconds: 15), (_) async {
      final u = firebaseUser;
      if (u == null) return;
      final next = await _authService.getUserProfile(u.uid);
      if (next == null) return;
      profile = next;
      if (next.role == 'subscriber' && !next.isActive) {
        await _authService.signOutCurrent();
      }
      notifyListeners();
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
