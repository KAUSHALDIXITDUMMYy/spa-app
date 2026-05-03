import 'package:cloud_firestore/cloud_firestore.dart';

class ScheduledCall {
  ScheduledCall({
    required this.id,
    required this.dateKey,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.roomId,
    required this.publisherId,
    required this.publisherName,
    this.description,
    this.sport,
  });

  final String id;
  final String dateKey;
  final String title;
  final String? description;
  final DateTime startsAt;
  final DateTime endsAt;
  final String roomId;
  final String publisherId;
  final String publisherName;
  final String? sport;

  factory ScheduledCall.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    DateTime d(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return DateTime.now();
    }

    return ScheduledCall(
      id: doc.id,
      dateKey: '${data['dateKey'] ?? ''}',
      title: '${data['title'] ?? ''}',
      description: data['description'] as String?,
      startsAt: d(data['startsAt']),
      endsAt: d(data['endsAt']),
      roomId: '${data['roomId'] ?? ''}',
      publisherId: '${data['publisherId'] ?? ''}',
      publisherName: '${data['publisherName'] ?? ''}',
      sport: data['sport'] as String?,
    );
  }
}
