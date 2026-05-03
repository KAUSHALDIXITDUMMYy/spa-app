import 'stream_session.dart';

/// Enriched permission row shown to subscribers (mirrors `SubscriberPermission`).
class SubscriberPermission {
  SubscriberPermission({
    required this.id,
    required this.subscriberId,
    required this.publisherId,
    required this.publisherName,
    required this.isActive,
    this.streamSession,
    this.createdAt,
  });

  final String id;
  final String subscriberId;
  final String publisherId;
  final String publisherName;
  final bool isActive;
  final StreamSession? streamSession;
  final DateTime? createdAt;
}

bool streamSessionIsScheduledRoom(StreamSession? session) {
  if (session == null) return false;
  if (session.scheduledCallId != null && session.scheduledCallId!.isNotEmpty) {
    return true;
  }
  final rid = session.roomId.trim();
  return rid.startsWith('sched-');
}

int streamSessionCreatedAtMs(StreamSession? session) {
  if (session?.createdAt == null) return 1 << 62;
  return session!.createdAt.millisecondsSinceEpoch;
}

int compareSubscriberPermissionsByStreamStart(
  SubscriberPermission a,
  SubscriberPermission b,
) {
  final ta = streamSessionCreatedAtMs(a.streamSession);
  final tb = streamSessionCreatedAtMs(b.streamSession);
  if (ta != tb) return ta.compareTo(tb);
  return a.publisherName.compareTo(b.publisherName);
}
