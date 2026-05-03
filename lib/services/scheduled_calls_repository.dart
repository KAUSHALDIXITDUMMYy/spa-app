import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/scheduled_call.dart';

String getLocalDateKey([DateTime? d]) {
  final x = d ?? DateTime.now();
  final y = x.year.toString().padLeft(4, '0');
  final m = x.month.toString().padLeft(2, '0');
  final day = x.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Same semantics as web `isCallInTimeWindow` (inclusive window).
bool isCallInTimeWindow(ScheduledCall call, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final t = n.millisecondsSinceEpoch;
  return t >= call.startsAt.millisecondsSinceEpoch &&
      t <= call.endsAt.millisecondsSinceEpoch;
}

bool sameLocalCalendarDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

Set<String> _publisherIdQueryKeys(
  String firebaseUid,
  String? firebaseEmail,
  String? profileEmail,
) {
  final keys = <String>{};
  final u = firebaseUid.trim();
  if (u.isNotEmpty) keys.add(u);

  void addVariant(String? raw) {
    final x = raw?.trim();
    if (x == null || x.isEmpty) return;
    keys.add(x);
    if (x.contains('@')) {
      final lo = x.toLowerCase();
      if (lo != x) keys.add(lo);
    }
  }

  addVariant(firebaseEmail);
  addVariant(profileEmail);
  return keys;
}

class ScheduledCallsRepository {
  ScheduledCallsRepository(this._db);

  final FirebaseFirestore _db;

  Stream<List<ScheduledCall>> watchCallsForDate(String dateKey) {
    return _db
        .collection('scheduledCalls')
        .where('dateKey', isEqualTo: dateKey)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(ScheduledCall.fromDoc).toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
      return list;
    });
  }

  Stream<List<ScheduledCall>> watchCallsForPublisher(String publisherId) {
    return _db
        .collection('scheduledCalls')
        .where('publisherId', isEqualTo: publisherId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(ScheduledCall.fromDoc).toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
      return list;
    });
  }

  bool _samePublisherId(String stored, String authUid) {
    return stored.trim() == authUid.trim();
  }

  bool _matchesPublisherAssignment({
    required String publisherIdOnDoc,
    required String firebaseUid,
    String? profileUid,
    required List<String> emailVariants,
  }) {
    final s = publisherIdOnDoc.trim();
    if (s.isEmpty) return false;
    if (_samePublisherId(s, firebaseUid)) return true;
    if (profileUid != null &&
        profileUid.isNotEmpty &&
        _samePublisherId(s, profileUid)) {
      return true;
    }
    final lower = s.toLowerCase();
    for (final e in emailVariants) {
      final x = e.trim();
      if (x.isEmpty) continue;
      if (lower == x.toLowerCase()) return true;
    }
    return false;
  }

  /// Mirrors web `ScheduledCallsPublisherSection`: today's `scheduledCalls` by local [dateKey],
  /// merged with scheduled rooms you currently host (`streamSessions` active + `scheduledCallId`),
  /// plus direct `scheduledCalls` queries for every [publisher id variant] (UID **or** email —
  /// some datasets store `pub1@sportsmagician.com` instead of Firebase UID).
  Stream<List<ScheduledCall>> watchPublisherTodaysScheduledRoomsMerged({
    required String firebaseUid,
    String? profileUid,
    String? firebaseEmail,
    String? profileEmail,
  }) {
    final dateKey = getLocalDateKey();
    final queryKeys =
        _publisherIdQueryKeys(firebaseUid, firebaseEmail, profileEmail);
    final emailVariants = <String>[
      if (firebaseEmail != null && firebaseEmail.trim().isNotEmpty)
        firebaseEmail.trim(),
      if (profileEmail != null && profileEmail.trim().isNotEmpty)
        profileEmail.trim(),
    ];

    return Stream.multi((controller) {
      var callsForToday = <ScheduledCall>[];
      final callsByPublisherQuery = <String, List<ScheduledCall>>{};
      final sessionBuckets =
          <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
      var callsFromSessions = <String, ScheduledCall>{};
      var hydrateGen = 0;

      bool matches(String publisherIdOnDoc) => _matchesPublisherAssignment(
            publisherIdOnDoc: publisherIdOnDoc,
            firebaseUid: firebaseUid,
            profileUid: profileUid,
            emailVariants: emailVariants,
          );

      /// Rows tied to this publisher from explicit `where('publisherId' == key)` streams.
      Iterable<ScheduledCall> mergedPublisherQueryCalls() sync* {
        final seen = <String>{};
        for (final list in callsByPublisherQuery.values) {
          for (final c in list) {
            if (!matches(c.publisherId)) continue;
            if (seen.add(c.id)) yield c;
          }
        }
      }

      void emit() {
        final now = DateTime.now();
        final merged = <String, ScheduledCall>{};

        for (final c in callsForToday) {
          if (matches(c.publisherId)) merged[c.id] = c;
        }

        for (final c in mergedPublisherQueryCalls()) {
          if (c.dateKey == dateKey || sameLocalCalendarDay(c.startsAt, now)) {
            merged[c.id] = c;
          }
        }

        for (final e in callsFromSessions.entries) {
          merged[e.key] = e.value;
        }

        final list = merged.values.toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
        if (!controller.isClosed) controller.add(list);
      }

      Future<void> hydrateSessionsFromBuckets() async {
        final gen = ++hydrateGen;
        final docsById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
        for (final list in sessionBuckets.values) {
          for (final d in list) {
            docsById[d.id] = d;
          }
        }
        final byCallId = <String, ScheduledCall>{};
        for (final d in docsById.values) {
          final data = d.data();
          if (data['isActive'] != true) continue;
          final cid = '${data['scheduledCallId'] ?? ''}'.trim();
          if (cid.isEmpty) continue;
          if (byCallId.containsKey(cid)) continue;
          final call = await getScheduledCallById(cid);
          if (call != null) byCallId[cid] = call;
        }
        if (gen != hydrateGen) return;
        callsFromSessions = byCallId;
        emit();
      }

      final subs = <StreamSubscription<dynamic>>[];

      subs.add(
        watchCallsForDate(dateKey).listen(
          (calls) {
            callsForToday = calls;
            emit();
          },
          onError: (_) {
            // Rules often allow `publisherId == uid` but not listing everyone’s calls for the day.
            callsForToday = [];
            emit();
          },
        ),
      );

      for (final key in queryKeys) {
        subs.add(
          watchCallsForPublisher(key).listen(
            (calls) {
              callsByPublisherQuery[key] = calls;
              emit();
            },
            onError: controller.addError,
          ),
        );

        subs.add(
          _db
              .collection('streamSessions')
              .where('publisherId', isEqualTo: key)
              .snapshots()
              .listen(
            (snap) {
              sessionBuckets[key] = snap.docs;
              unawaited(hydrateSessionsFromBuckets());
            },
            onError: controller.addError,
          ),
        );
      }

      controller.onCancel = () async {
        for (final s in subs) {
          await s.cancel();
        }
      };
    });
  }

  Future<ScheduledCall?> getScheduledCallById(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;
    final doc =
        await _db.collection('scheduledCalls').doc(trimmed).get();
    if (!doc.exists) return null;
    return ScheduledCall.fromDoc(doc);
  }

  /// Today's scheduled calls for publishers this subscriber has active
  /// [streamPermissions] for. Updates when either scheduledCalls or permissions change.
  Stream<List<ScheduledCall>> watchSubscriberScheduleForDate(
    String subscriberId,
    String dateKey,
  ) {
    return Stream.multi((controller) {
      var calls = <ScheduledCall>[];
      var allowedPublisherIds = <String>{};

      void emit() {
        final filtered = calls
            .where((c) => allowedPublisherIds.contains(c.publisherId))
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
        if (!controller.isClosed) controller.add(filtered);
      }

      final subCalls = watchCallsForDate(dateKey).listen(
        (list) {
          calls = list;
          emit();
        },
        onError: controller.addError,
      );

      final subPerm = _db
          .collection('streamPermissions')
          .where('subscriberId', isEqualTo: subscriberId)
          .where('isActive', isEqualTo: true)
          .snapshots()
          .listen(
            (snap) {
              allowedPublisherIds = snap.docs
                  .map((d) => '${d.data()['publisherId'] ?? ''}'.trim())
                  .where((id) => id.isNotEmpty)
                  .toSet();
              emit();
            },
            onError: controller.addError,
          );

      controller.onCancel = () async {
        await subCalls.cancel();
        await subPerm.cancel();
      };
    });
  }
}
