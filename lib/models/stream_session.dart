import 'package:cloud_firestore/cloud_firestore.dart';

class StreamSession {
  StreamSession({
    this.id,
    required this.publisherId,
    required this.publisherName,
    required this.roomId,
    required this.isActive,
    required this.createdAt,
    this.endedAt,
    this.title,
    this.description,
    this.sport,
    this.scheduledCallId,
    this.awaitingBroadcast,
    this.gameName,
    this.league,
    this.match,
  });

  final String? id;
  final String publisherId;
  final String publisherName;
  final String roomId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? endedAt;
  final String? title;
  final String? description;
  final String? sport;
  final String? scheduledCallId;
  final bool? awaitingBroadcast;
  final String? gameName;
  final String? league;
  final String? match;

  bool get isAwaitingBroadcastSession =>
      (scheduledCallId != null && scheduledCallId!.isNotEmpty) &&
      awaitingBroadcast == true;

  static DateTime _date(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.tryParse('$v') ?? DateTime.now();
  }

  factory StreamSession.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return StreamSession(
      id: doc.id,
      publisherId: '${data['publisherId'] ?? ''}',
      publisherName: '${data['publisherName'] ?? ''}',
      roomId: '${data['roomId'] ?? ''}',
      isActive: data['isActive'] == true,
      createdAt: _date(data['createdAt']),
      endedAt: data['endedAt'] != null ? _date(data['endedAt']) : null,
      title: data['title'] as String?,
      description: data['description'] as String?,
      sport: data['sport'] as String?,
      scheduledCallId: data['scheduledCallId'] as String?,
      awaitingBroadcast: data['awaitingBroadcast'] as bool?,
      gameName: data['gameName'] as String?,
      league: data['league'] as String?,
      match: data['match'] as String?,
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'publisherId': publisherId,
        'publisherName': publisherName,
        'roomId': roomId,
        'isActive': isActive,
        'createdAt': FieldValue.serverTimestamp(),
        'description': description ?? '',
        'sport': sport ?? '',
        if (title != null) 'title': title,
        if (scheduledCallId != null) 'scheduledCallId': scheduledCallId,
        if (awaitingBroadcast != null) 'awaitingBroadcast': awaitingBroadcast,
      };
}

/// Sessions where audio is expected to be publishing (not "waiting for host" placeholders).
List<StreamSession> pickPublisherRejoinCandidates(List<StreamSession> sessions) {
  final candidates = sessions
      .where((s) => s.isActive && !s.isAwaitingBroadcastSession)
      .toList();
  candidates.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return candidates;
}

StreamSession? pickPublisherRejoinStream(List<StreamSession> sessions) {
  final candidates = pickPublisherRejoinCandidates(sessions);
  return candidates.isEmpty ? null : candidates.first;
}
