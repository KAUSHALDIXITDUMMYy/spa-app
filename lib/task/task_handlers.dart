import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the process eligible for continued mic capture / playback while the app
/// is backgrounded or the screen is locked (Android foreground service).
@pragma('vm:entry-point')
void foregroundTaskStartCallback() {
  FlutterForegroundTask.setTaskHandler(_LiveAudioTaskHandler());
}

class _LiveAudioTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
