import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../task/task_handlers.dart';

class ForegroundServiceHelper {
  static Future<void> init() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'sportsmagician_live',
        channelName: 'Live audio',
        channelDescription:
            'Keeps broadcast or listening active while the app is in the background.',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<bool> ensureNotificationPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    final current = await FlutterForegroundTask.checkNotificationPermission();
    if (current == NotificationPermission.granted) return true;
    final req = await FlutterForegroundTask.requestNotificationPermission();
    return req == NotificationPermission.granted;
  }

  /// [useMicrophone] true for publishers (foreground service type `microphone`).
  static Future<void> startLiveTask({
    required String title,
    required String text,
    bool useMicrophone = false,
  }) async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    await ensureNotificationPermission();
    final types = <ForegroundServiceTypes>[
      ForegroundServiceTypes.mediaPlayback,
      if (useMicrophone) ForegroundServiceTypes.microphone,
    ];
    if (await FlutterForegroundTask.isRunningService) {
      return;
    }
    await FlutterForegroundTask.startService(
      notificationTitle: title,
      notificationText: text,
      serviceTypes: types,
      callback: foregroundTaskStartCallback,
    );
  }

  static Future<void> stopLiveTask() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    await FlutterForegroundTask.stopService();
  }
}
