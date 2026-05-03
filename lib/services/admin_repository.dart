import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/stream_session.dart';
import '../models/user_profile.dart';

class AdminRepository {
  AdminRepository(this._db);

  final FirebaseFirestore _db;

  Future<int> logoutAllUsers() async {
    final snap = await _db.collection('users').get();
    var count = 0;
    for (final doc in snap.docs) {
      final sid = doc.data()['sessionId'];
      if (sid != null) {
        await doc.reference.update({'sessionId': null});
        count++;
      }
    }
    return count;
  }

  Stream<List<UserProfile>> watchUsers() {
    return _db.collection('users').snapshots().map(
          (s) => s.docs
              .map((d) => UserProfile.fromMap(d.id, d.data()))
              .toList()
            ..sort((a, b) => a.email.compareTo(b.email)),
        );
  }

  Stream<List<StreamSession>> watchActiveSessions() {
    return _db
        .collection('streamSessions')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map(
          (s) => s.docs.map(StreamSession.fromDoc).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        );
  }

  Future<void> submitContactMessage({
    required String name,
    required String email,
    required String message,
    String subject = '',
  }) async {
    await _db.collection('contactMessages').add({
      'name': name.trim(),
      'email': email.trim(),
      'subject': subject.trim(),
      'message': message.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'source': 'flutter_app',
    });
  }
}
