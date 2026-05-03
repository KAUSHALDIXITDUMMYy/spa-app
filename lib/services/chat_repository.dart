import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  ChatMessage({
    this.id,
    required this.streamSessionId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.text,
    required this.createdAt,
  });

  final String? id;
  final String streamSessionId;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String text;
  final DateTime createdAt;
}

class ChatRepository {
  ChatRepository(this._db);

  final FirebaseFirestore _db;

  Future<void> sendMessage({
    required String streamSessionId,
    required String senderId,
    required String senderName,
    required String senderRole,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _db.collection('streamChatMessages').add({
      'streamSessionId': streamSessionId,
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Raw snapshots (for doc change detection — e.g. chat notifications).
  Stream<QuerySnapshot<Map<String, dynamic>>> watchChatMessageSnapshots(
    String streamSessionId, {
    int limit = 100,
  }) {
    return _db
        .collection('streamChatMessages')
        .where('streamSessionId', isEqualTo: streamSessionId)
        .orderBy('createdAt', descending: false)
        .limit(limit)
        .snapshots();
  }

  Stream<List<ChatMessage>> watchMessages(String streamSessionId, {int limit = 100}) {
    return watchChatMessageSnapshots(streamSessionId, limit: limit).map((snap) {
      return snap.docs.map((doc) {
        final data = doc.data();
        final role = '${data['senderRole'] ?? 'subscriber'}';
        return ChatMessage(
          id: doc.id,
          streamSessionId: '${data['streamSessionId']}',
          senderId: '${data['senderId']}',
          senderName: '${data['senderName']}',
          senderRole:
              role == 'publisher' || role == 'admin' ? role : 'subscriber',
          text: '${data['text']}',
          createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        );
      }).toList();
    });
  }
}

