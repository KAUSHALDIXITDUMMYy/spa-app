import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'chat_repository.dart';

/// Local device notifications when someone else posts to [streamChatMessages] for the active live session.
/// Works while the app is foreground/background; not a replacement for FCM when the app is force-killed.
class ChatNotificationService {
  ChatNotificationService(this._chatRepo);

  final ChatRepository _chatRepo;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'stream_chat';
  static const _channelName = 'Live chat';

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  bool _chatSheetOpen = false;

  static Future<void> initialize() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      ),
    );

    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Alerts when someone sends a message during a live stream.',
          importance: Importance.high,
        ),
      );
    }

    if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }
  }

  void setChatSheetOpen(bool open) => _chatSheetOpen = open;

  Future<void> _ensureNotifyPermission() async {
    if (Platform.isAndroid) {
      await Permission.notification.request();
    }
  }

  static String _roleTitle(String role) {
    switch (role) {
      case 'publisher':
        return 'Publisher';
      case 'admin':
        return 'Admin';
      default:
        return 'Subscriber';
    }
  }

  static String _truncate(String text, [int max = 140]) {
    final t = text.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max)}…';
  }

  Future<void> watchLiveSession({
    required String sessionId,
    required String recipientUserId,
  }) async {
    await _ensureNotifyPermission();
    await _sub?.cancel();

    var firstSnapshot = true;
    _sub = _chatRepo.watchChatMessageSnapshots(sessionId).listen(
      (snap) {
        if (firstSnapshot) {
          firstSnapshot = false;
          return;
        }
        if (_chatSheetOpen) return;

        for (final change in snap.docChanges) {
          if (change.type != DocumentChangeType.added) continue;
          final data = change.doc.data();
          if (data == null) continue;
          final senderId = '${data['senderId'] ?? ''}'.trim();
          if (senderId.isEmpty || senderId == recipientUserId) continue;

          final name = '${data['senderName'] ?? 'Someone'}'.trim();
          final role = '${data['senderRole'] ?? 'subscriber'}'.trim();
          final text = '${data['text'] ?? ''}';

          final nid = change.doc.id.hashCode & 0x7fffffff;
          unawaited(
            _plugin.show(
              nid,
              'Live chat · ${_roleTitle(role)}',
              '$name: ${_truncate(text)}',
              NotificationDetails(
                android: AndroidNotificationDetails(
                  _channelId,
                  _channelName,
                  channelDescription:
                      'New messages while you are in a live audio session.',
                  importance: Importance.high,
                  priority: Priority.high,
                ),
                iOS: const DarwinNotificationDetails(
                  presentAlert: true,
                  presentBadge: true,
                  presentSound: true,
                ),
              ),
            ),
          );
        }
      },
      onError: (_) {},
    );
  }

  Future<void> stopWatchingLiveSession() async {
    await _sub?.cancel();
    _sub = null;
  }
}
