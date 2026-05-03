import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/user_profile.dart';

class AuthService {
  AuthService(this._auth, this._db);

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  static const _sessionKey = 'subscriber_session_id';
  static const _sessionTimeoutMs = 5 * 60 * 1000;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<UserProfile?> getUserProfile(String uid, {int retry = 0}) async {
    try {
      final snap = await _db.collection('users').doc(uid).get();
      if (snap.exists) {
        return UserProfile.fromMap(uid, snap.data()!);
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

  Future<UserProfile?> userDocByEmail(String email) async {
    final q = await _db
        .collection('users')
        .where('email', isEqualTo: email.toLowerCase())
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    final doc = q.docs.first;
    return UserProfile.fromMap(doc.id, doc.data());
  }

  Future<void> _migratePendingUser({
    required String oldPendingId,
    required String newUid,
    required UserProfile pendingData,
  }) async {
    final pubDisplayName =
        pendingData.displayName ?? pendingData.email.split('@').first;

    Future<void> updateQuery(String coll, String field) async {
      final snap = await _db.collection(coll).where(field, isEqualTo: oldPendingId).get();
      for (final d in snap.docs) {
        await d.reference.update({field: newUid});
      }
    }

    await updateQuery('streamPermissions', 'subscriberId');
    await updateQuery('zoomPublisherAssignments', 'subscriberId');
    await updateQuery('streamAssignments', 'subscriberId');
    await updateQuery('zoomCallAssignments', 'subscriberId');

    final permsPub = await _db
        .collection('streamPermissions')
        .where('publisherId', isEqualTo: oldPendingId)
        .get();
    for (final d in permsPub.docs) {
      await d.reference.update({'publisherId': newUid});
    }

    final sched = await _db
        .collection('scheduledCalls')
        .where('publisherId', isEqualTo: oldPendingId)
        .get();
    for (final d in sched.docs) {
      await d.reference.update({
        'publisherId': newUid,
        'publisherName': pubDisplayName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    final sessions = await _db
        .collection('streamSessions')
        .where('publisherId', isEqualTo: oldPendingId)
        .get();
    for (final d in sessions.docs) {
      await d.reference.update({
        'publisherId': newUid,
        'publisherName': pubDisplayName,
      });
    }

    final zoomCalls = await _db
        .collection('zoomCalls')
        .where('publisherId', isEqualTo: oldPendingId)
        .get();
    for (final d in zoomCalls.docs) {
      await d.reference.update({'publisherId': newUid});
    }
  }

  Future<String?> signIn(String email, String password) async {
    final lower = email.trim().toLowerCase();

    final pendingSnap = await _db
        .collection('users')
        .where('email', isEqualTo: lower)
        .limit(1)
        .get();

    if (pendingSnap.docs.isNotEmpty) {
      final doc = pendingSnap.docs.first;
      final data = doc.data();
      final isPending = data['isPending'] == true;
      final pendingPw = data['pendingPassword'] as String?;
      if (isPending && pendingPw == password) {
        final cred =
            await _auth.createUserWithEmailAndPassword(email: lower, password: password);
        final newUid = cred.user!.uid;
        final profile = UserProfile.fromMap(doc.id, data);

        await _migratePendingUser(
          oldPendingId: doc.id,
          newUid: newUid,
          pendingData: profile,
        );

        await _db.collection('users').doc(newUid).set({
          'uid': newUid,
          'email': cred.user!.email,
          'role': data['role'],
          'displayName': data['displayName'],
          'createdAt': data['createdAt'],
          'isActive': data['isActive'],
          'allowChat': data['allowChat'] ?? false,
          'isPending': false,
          'pendingPassword': null,
        });

        if (data['role'] == 'subscriber') {
          final sessionId = const Uuid().v4();
          await _db.collection('users').doc(newUid).update({
            'sessionId': sessionId,
            'lastLoginAt': FieldValue.serverTimestamp(),
          });
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_sessionKey, sessionId);
        }

        await doc.reference.delete();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return null;
      }
    }

    try {
      final cred =
          await _auth.signInWithEmailAndPassword(email: lower, password: password);
      final uid = cred.user!.uid;
      final profile = await getUserProfile(uid);
      if (profile == null) return 'Could not load profile.';

      if (profile.role == 'subscriber') {
        final prefs = await SharedPreferences.getInstance();
        final localSid = prefs.getString(_sessionKey);

        if (profile.sessionId != null && profile.sessionId!.isNotEmpty) {
          if (localSid != null && localSid == profile.sessionId) {
            await _db.collection('users').doc(uid).update({
              'lastLoginAt': FieldValue.serverTimestamp(),
            });
          } else {
            final last = profile.lastLoginAt?.millisecondsSinceEpoch ?? 0;
            final expired =
                DateTime.now().millisecondsSinceEpoch - last > _sessionTimeoutMs;
            if (expired) {
              final sessionId = const Uuid().v4();
              await _db.collection('users').doc(uid).update({
                'sessionId': sessionId,
                'lastLoginAt': FieldValue.serverTimestamp(),
              });
              await prefs.setString(_sessionKey, sessionId);
            } else {
              await _auth.signOut();
              return 'This account is already active on another device. Sign out there or wait a few minutes.';
            }
          }
        } else {
          final sessionId = const Uuid().v4();
          await _db.collection('users').doc(uid).update({
            'sessionId': sessionId,
            'lastLoginAt': FieldValue.serverTimestamp(),
          });
          await prefs.setString(_sessionKey, sessionId);
        }
      }

      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Sign in failed';
    }
  }

  Future<void> signOutCurrent() async {
    final u = _auth.currentUser;
    if (u != null) {
      final profile = await getUserProfile(u.uid);
      if (profile?.role == 'subscriber') {
        await _db.collection('users').doc(u.uid).update({'sessionId': null});
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_sessionKey);
      }
    }
    await _auth.signOut();
  }

  Future<void> acceptTerms(String uid) async {
    await _db.collection('users').doc(uid).update({
      'termsAcceptedAt': FieldValue.serverTimestamp(),
    });
  }
}
