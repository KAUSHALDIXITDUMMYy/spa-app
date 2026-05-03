import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/stream_session.dart';
import '../models/subscriber_permission.dart';

class SubscriberRepository {
  SubscriberRepository(this._db);

  final FirebaseFirestore _db;

  Future<List<SubscriberPermission>> getSubscriberPermissions(
    String subscriberId,
  ) async {
    final permissionsSnap = await _db
        .collection('streamPermissions')
        .where('subscriberId', isEqualTo: subscriberId)
        .where('isActive', isEqualTo: true)
        .get();

    final assignmentsSnap = await _db
        .collection('streamAssignments')
        .where('subscriberId', isEqualTo: subscriberId)
        .where('isActive', isEqualTo: true)
        .get();

    final usersSnap = await _db.collection('users').get();
    final usersMap = <String, Map<String, dynamic>>{};
    for (final d in usersSnap.docs) {
      usersMap[d.id] = d.data();
    }

    final streamsSnap = await _db
        .collection('streamSessions')
        .where('isActive', isEqualTo: true)
        .get();
    final activeStreamsById = <String, StreamSession>{};
    for (final d in streamsSnap.docs) {
      activeStreamsById[d.id] = StreamSession.fromDoc(d);
    }

    final enriched = <SubscriberPermission>[];

    for (final doc in permissionsSnap.docs) {
      final data = doc.data();
      final publisherId = '${data['publisherId'] ?? ''}';
      final pubData = usersMap[publisherId];
      final publisherName = '${pubData?['displayName'] ?? pubData?['email'] ?? 'Unknown Publisher'}';

      final streamsForPublisher =
          activeStreamsById.values.where((s) => s.publisherId == publisherId).toList();

      if (streamsForPublisher.isEmpty) {
        enriched.add(
          SubscriberPermission(
            id: doc.id,
            subscriberId: subscriberId,
            publisherId: publisherId,
            publisherName: publisherName,
            isActive: true,
          ),
        );
      } else {
        for (final stream in streamsForPublisher) {
          enriched.add(
            SubscriberPermission(
              id: '${doc.id}_${stream.id}',
              subscriberId: subscriberId,
              publisherId: publisherId,
              publisherName: publisherName,
              isActive: true,
              streamSession: stream,
            ),
          );
        }
      }
    }

    for (final doc in assignmentsSnap.docs) {
      final data = doc.data();
      final streamSessionId = '${data['streamSessionId'] ?? ''}';
      final stream = activeStreamsById[streamSessionId];
      if (stream != null) {
        final pubData = usersMap[stream.publisherId];
        enriched.add(
          SubscriberPermission(
            id: doc.id,
            subscriberId: subscriberId,
            publisherId: stream.publisherId,
            publisherName:
                '${pubData?['displayName'] ?? pubData?['email'] ?? 'Unknown Publisher'}',
            isActive: true,
            streamSession: stream,
            createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
          ),
        );
      }
    }

    final unique = <String, SubscriberPermission>{};
    for (final perm in enriched) {
      final sid = perm.streamSession?.id ?? perm.id;
      final key = '${perm.subscriberId}_${perm.publisherId}_$sid';
      unique.putIfAbsent(key, () => perm);
    }
    return unique.values.toList();
  }

  Future<({List<SubscriberPermission> adHoc, List<SubscriberPermission> scheduled})>
      getAvailableStreamsSplit(String subscriberId) async {
    final all = await getSubscriberPermissions(subscriberId);
    final available = all.where((p) => p.streamSession?.isActive == true).toList();
    final adHoc = <SubscriberPermission>[];
    final scheduled = <SubscriberPermission>[];
    for (final p in available) {
      if (streamSessionIsScheduledRoom(p.streamSession)) {
        scheduled.add(p);
      } else {
        adHoc.add(p);
      }
    }
    adHoc.sort(compareSubscriberPermissionsByStreamStart);
    scheduled.sort(compareSubscriberPermissionsByStreamStart);
    return (adHoc: adHoc, scheduled: scheduled);
  }

  Stream<bool> watchAssignmentEligibility(String subscriberId) {
    final controller = StreamController<bool>.broadcast();
    var hasPerm = false;
    var hasAssign = false;

    void emit() => controller.add(hasPerm || hasAssign);

    final sub1 = _db
        .collection('streamPermissions')
        .where('subscriberId', isEqualTo: subscriberId)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .snapshots()
        .listen((s) {
      hasPerm = s.docs.isNotEmpty;
      emit();
    });

    final sub2 = _db
        .collection('streamAssignments')
        .where('subscriberId', isEqualTo: subscriberId)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .snapshots()
        .listen((s) {
      hasAssign = s.docs.isNotEmpty;
      emit();
    });

    controller.onCancel = () async {
      await sub1.cancel();
      await sub2.cancel();
    };

    return controller.stream;
  }
}
