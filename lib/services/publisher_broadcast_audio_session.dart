import 'package:audio_session/audio_session.dart';

/// Publisher mic capture + Agora: playAndRecord / voice communication so audio
/// keeps running when the app is backgrounded or the phone locks (with FG service).
class PublisherBroadcastAudioSession {
  PublisherBroadcastAudioSession._();

  static bool _active = false;

  static Future<void> activateForBroadcast() async {
    final session = await AudioSession.instance;
    await session.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker |
            AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ),
    );
    await session.setActive(true);
    _active = true;
  }

  static Future<void> restoreDefault() async {
    if (!_active) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    await session.setActive(true);
    _active = false;
  }
}
