import 'package:cloud_firestore/cloud_firestore.dart';

/// Admin-posted text for all subscribers (`dailySchedule/current` on web).
class DailySchedulePost {
  DailySchedulePost({required this.content, this.updatedAt});

  final String content;
  final DateTime? updatedAt;
}

class DailyScheduleRepository {
  DailyScheduleRepository(this._db);

  final FirebaseFirestore _db;

  /// Same document as web `lib/schedule.ts` (`SCHEDULE_DOC_ID = "current"`).
  Stream<DailySchedulePost?> watchCurrent() {
    return _db.doc('dailySchedule/current').snapshots().map((snap) {
      if (!snap.exists) return null;
      final data = snap.data() ?? {};
      return DailySchedulePost(
        content: '${data['content'] ?? ''}',
        updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      );
    });
  }
}
