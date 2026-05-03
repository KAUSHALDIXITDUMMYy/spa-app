import 'package:cloud_firestore/cloud_firestore.dart';

class ZoomCall {
  ZoomCall({
    this.id,
    required this.publisherId,
    required this.title,
    required this.isActive,
    this.url,
    this.joinUrl,
    this.meetingNumber,
    this.password,
  });

  final String? id;
  final String publisherId;
  final String title;
  final bool isActive;
  final String? url;
  final String? joinUrl;
  final String? meetingNumber;
  final String? password;

  factory ZoomCall.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return ZoomCall(
      id: doc.id,
      publisherId: '${data['publisherId'] ?? ''}',
      title: '${data['title'] ?? ''}',
      isActive: data['isActive'] == true,
      url: data['url'] as String?,
      joinUrl: data['joinUrl'] as String?,
      meetingNumber: data['meetingNumber'] as String?,
      password: data['password'] as String?,
    );
  }

  String? get launchableUrl {
    if (joinUrl != null && joinUrl!.isNotEmpty) return joinUrl;
    if (url != null && url!.isNotEmpty) return url;
    return null;
  }
}

class ZoomRepository {
  ZoomRepository(this._db);

  final FirebaseFirestore _db;

  Future<ZoomCall?> getCall(String id) async {
    final snap = await _db.collection('zoomCalls').doc(id).get();
    if (!snap.exists) return null;
    return ZoomCall.fromDoc(snap);
  }

  Stream<List<ZoomCall>> watchPublisherCalls(String publisherId) {
    return _db
        .collection('zoomCalls')
        .where('publisherId', isEqualTo: publisherId)
        .snapshots()
        .map((s) {
      final rows = s.docs.map(ZoomCall.fromDoc).toList()
        ..sort((a, b) => b.title.compareTo(a.title));
      return rows;
    });
  }
}
