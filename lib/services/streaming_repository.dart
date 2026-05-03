import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/stream_session.dart';

class StreamingRepository {
  StreamingRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('streamSessions');

  String generateRoomId(String publisherId) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final r = publisherId.hashCode.abs() % 100000;
    return 'stream-$publisherId-$ts-$r';
  }

  Future<void> deactivatePublisherBroadcastSessions(
    String publisherId, {
    String? exceptSessionId,
  }) async {
    final snap = await _col
        .where('publisherId', isEqualTo: publisherId)
        .where('isActive', isEqualTo: true)
        .get();
    for (final doc in snap.docs) {
      if (exceptSessionId != null && doc.id == exceptSessionId) continue;
      final data = doc.data();
      if (data['scheduledCallId'] != null && data['awaitingBroadcast'] == true) {
        continue;
      }
      try {
        await doc.reference.update({
          'isActive': false,
          'endedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }
  }

  Future<StreamSession> createStreamSession({
    required String publisherId,
    required String publisherName,
    required String roomId,
    required String title,
    String description = '',
    String sport = '',
    String? scheduledCallId,
    bool awaitingBroadcast = false,
  }) async {
    await deactivatePublisherBroadcastSessions(publisherId);
    final ref = await _col.add({
      'publisherId': publisherId,
      'publisherName': publisherName,
      'roomId': roomId,
      'isActive': true,
      'awaitingBroadcast': awaitingBroadcast,
      'title': title,
      'description': description,
      'sport': sport,
      if (scheduledCallId != null) 'scheduledCallId': scheduledCallId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final fresh = await ref.get();
    return StreamSession.fromDoc(fresh);
  }

  /// Returns Firestore `streamSessions` document id for this broadcast.
  Future<String> activateScheduledSession({
    required String scheduledCallId,
    required String publisherId,
    required String publisherName,
    required String roomId,
    required String title,
    String description = '',
    String sport = '',
  }) async {
    final snap = await _col
        .where('scheduledCallId', isEqualTo: scheduledCallId)
        .get();
    QueryDocumentSnapshot<Map<String, dynamic>>? existing;
    for (final d in snap.docs) {
      if (d.data()['publisherId'] == publisherId) {
        existing = d;
        break;
      }
    }
    if (existing != null) {
      await deactivatePublisherBroadcastSessions(publisherId, exceptSessionId: existing.id);
      await existing.reference.update({
        'publisherId': publisherId,
        'publisherName': publisherName,
        'roomId': roomId,
        'isActive': true,
        'awaitingBroadcast': false,
        'title': title,
        'description': description,
        'sport': sport,
        'scheduledCallId': scheduledCallId,
      });
      return existing.id;
    }
    final session = await createStreamSession(
      publisherId: publisherId,
      publisherName: publisherName,
      roomId: roomId,
      title: title,
      description: description,
      sport: sport,
      scheduledCallId: scheduledCallId,
      awaitingBroadcast: false,
    );
    return session.id!;
  }

  Future<void> endStreamSession(String sessionId) async {
    await _col.doc(sessionId).update({
      'isActive': false,
      'endedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> resetScheduledAfterBroadcast(String sessionId) async {
    final ref = _col.doc(sessionId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data()!;
    if (data['scheduledCallId'] != null) {
      await ref.update({
        'isActive': true,
        'awaitingBroadcast': true,
        'endedAt': FieldValue.delete(),
      });
    } else {
      await endStreamSession(sessionId);
    }
  }

  Stream<StreamSession?> watchPublisherActiveBroadcast(String publisherId) {
    return watchPublisherBroadcastingSession(publisherId);
  }

  /// Web `subscribeToPublisherActiveStream`: one broadcasting session (not scheduled placeholders).
  Stream<StreamSession?> watchPublisherBroadcastingSession(String publisherId) {
    return _col.where('publisherId', isEqualTo: publisherId).snapshots().map((snap) {
      final list = snap.docs.map(StreamSession.fromDoc).toList();
      return pickPublisherRejoinStream(list);
    });
  }

  /// Web `getPublisherStreams` → most recent ended session for &quot;Use Last Details&quot;.
  Future<StreamSession?> fetchMostRecentEndedPublisherSession(String publisherId) async {
    final snap = await _col.where('publisherId', isEqualTo: publisherId).get();
    final ended = snap.docs.map(StreamSession.fromDoc).where((s) => !s.isActive).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ended.isEmpty ? null : ended.first;
  }

  Stream<List<StreamSession>> watchPublisherSessions(String publisherId) {
    return _col.where('publisherId', isEqualTo: publisherId).snapshots().map(
          (s) => s.docs.map(StreamSession.fromDoc).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        );
  }

  Future<StreamSession> fetchSession(String id) async {
    final snap = await _col.doc(id).get();
    if (!snap.exists) {
      throw StateError('streamSessions/$id not found');
    }
    return StreamSession.fromDoc(snap);
  }

  Future<List<StreamSession>> activeStreams() async {
    final snap =
        await _col.where('isActive', isEqualTo: true).get();
    final list = snap.docs.map(StreamSession.fromDoc).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }
}
