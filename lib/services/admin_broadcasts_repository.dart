import 'package:cloud_firestore/cloud_firestore.dart';

/// Rows in `adminBroadcasts` (web `subscribeAdminBroadcasts`).
class AdminBroadcastPost {
  AdminBroadcastPost({
    required this.id,
    required this.message,
    required this.createdAt,
    this.createdByName,
  });

  final String id;
  final String message;
  final DateTime createdAt;
  final String? createdByName;
}

class AdminBroadcastsRepository {
  AdminBroadcastsRepository(this._db);

  final FirebaseFirestore _db;

  Stream<List<AdminBroadcastPost>> watchBroadcasts({int limit = 80}) {
    return _db
        .collection('adminBroadcasts')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      return snap.docs.map((d) {
        final data = d.data();
        return AdminBroadcastPost(
          id: d.id,
          message: '${data['message'] ?? ''}',
          createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          createdByName: data['createdByName'] as String?,
        );
      }).toList();
    });
  }
}
