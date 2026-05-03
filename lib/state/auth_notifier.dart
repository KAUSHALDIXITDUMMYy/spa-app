import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';

class AuthNotifier extends ChangeNotifier {
  AuthNotifier(this._authService, this._db) {
    _authSub = _authService.authStateChanges().listen(_onAuthUser);
  }

  final AuthService _authService;
  final FirebaseFirestore _db;

  late final StreamSubscription<User?> _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;
  Timer? _subscriberHeartbeat;

  User? firebaseUser;
  UserProfile? profile;
  bool loading = true;

  Future<void> _onAuthUser(User? user) async {
    firebaseUser = user;
    await _profileSub?.cancel();
    _profileSub = null;
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

    _profileSub = _db.collection('users').doc(user.uid).snapshots().listen((snap) {
      if (!snap.exists) return;
      final next = UserProfile.fromMap(user.uid, snap.data()!);
      profile = next;
      if (next.role == 'subscriber' && !next.isActive) {
        _authService.signOutCurrent();
      }
      notifyListeners();
    });

    _subscriberHeartbeat = Timer.periodic(const Duration(minutes: 3), (_) async {
      final p = profile;
      final u = firebaseUser;
      if (u == null || p == null || p.role != 'subscriber') return;
      try {
        await _db.collection('users').doc(u.uid).update({
          'lastLoginAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
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
  }

  @override
  void dispose() {
    _authSub.cancel();
    _profileSub?.cancel();
    _subscriberHeartbeat?.cancel();
    super.dispose();
  }
}
