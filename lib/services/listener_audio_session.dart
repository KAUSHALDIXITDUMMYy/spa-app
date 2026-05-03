import 'package:audio_session/audio_session.dart';

/// Subscriber listen uses media-style focus/loudness. The app-wide [speech()]
/// preset sets [androidWillPauseWhenDucked], which often makes RTC playback
/// nearly silent after focus changes.
class ListenerAudioSession {
  ListenerAudioSession._();

  static bool _listeningBoostActive = false;

  static Future<void> activateForListening() async {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.moviePlayback,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ),
    );
    await session.setActive(true);
    _listeningBoostActive = true;
  }

  /// Restore the default session used elsewhere (publishers, UI).
  static Future<void> restoreDefault() async {
    if (!_listeningBoostActive) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    await session.setActive(true);
    _listeningBoostActive = false;
  }
}
