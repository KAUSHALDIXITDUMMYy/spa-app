import 'dart:async';
import 'dart:math';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';

import 'agora_token_service.dart';
import 'api_client.dart';

/// Playback/recording gain (Agora range 0–400; 100 = SDK default).
const int _kAudiencePlaybackVolume = 85;
const int _kPublisherRecordingVolume = 72;

String _joinFailureHint(ConnectionChangedReasonType reason) {
  switch (reason) {
    case ConnectionChangedReasonType.connectionChangedInvalidAppId:
      return 'Invalid Agora App ID (check backend Agora credentials).';
    case ConnectionChangedReasonType.connectionChangedInvalidChannelName:
      return 'Invalid channel name for Agora.';
    case ConnectionChangedReasonType.connectionChangedInvalidToken:
      return 'Invalid token or UID mismatch (check backend token server).';
    case ConnectionChangedReasonType.connectionChangedTokenExpired:
      return 'Token expired; try joining again.';
    case ConnectionChangedReasonType.connectionChangedRejectedByServer:
      return 'Rejected by Agora server (e.g. duplicate join). Leave channel and retry.';
    case ConnectionChangedReasonType.connectionChangedBannedByServer:
      return 'Banned or kicked from the channel.';
    case ConnectionChangedReasonType.connectionChangedJoinFailed:
      return 'Could not join (network or server); try again or switch networks.';
    default:
      return reason.name;
  }
}

enum LiveRole { publisher, audience }

/// Wraps Agora RTC for audio-only live broadcasting (matches web `mode: "live"`).
/// Tokens and App ID come from the backend — change Agora creds on the server only.
class AgoraLiveService {
  AgoraLiveService(ApiClient apiClient)
      : _tokenService = AgoraTokenService(apiClient);

  final AgoraTokenService _tokenService;

  RtcEngine? _engine;
  RtcEngineEventHandler? _eventHandler;
  String? _engineAppId;
  int _uid = 0;
  bool _joined = false;

  // Stored for token renewal
  String? _currentChannelId;
  LiveRole? _currentRole;
  String? _currentStreamSessionId;

  bool get isJoined => _joined;

  static int randomUid() {
    final r = Random();
    return r.nextInt(0x7fffffff);
  }

  void _unregisterHandler() {
    final e = _engine;
    final h = _eventHandler;
    if (e != null && h != null) {
      e.unregisterEventHandler(h);
    }
    _eventHandler = null;
  }

  Future<void> _applyVoiceProcessing(RtcEngine engine, LiveRole role) async {
    await engine.setAudioScenario(AudioScenarioType.audioScenarioMeeting);
    await engine.setAudioProfile(
      profile: AudioProfileType.audioProfileSpeechStandard,
      scenario: AudioScenarioType.audioScenarioMeeting,
    );
    try {
      await engine.setAINSMode(
        enabled: true,
        mode: AudioAinsMode.ainsModeBalanced,
      );
    } catch (_) {}

    if (role == LiveRole.publisher) {
      try {
        await engine.adjustRecordingSignalVolume(_kPublisherRecordingVolume);
      } catch (_) {}
    } else {
      try {
        await engine.adjustPlaybackSignalVolume(_kAudiencePlaybackVolume);
        await engine.setDefaultAudioRouteToSpeakerphone(true);
      } catch (_) {}
    }
  }

  Future<RtcEngine> _ensureEngine(String appId) async {
    if (_engine != null && _engineAppId == appId) return _engine!;

    if (_engine != null) {
      _unregisterHandler();
      try {
        await _engine!.leaveChannel();
      } catch (_) {}
      await _engine!.release();
      _engine = null;
      _engineAppId = null;
    }

    final engine = createAgoraRtcEngine();
    await engine.initialize(
      RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      ),
    );
    await engine.enableAudio();
    await engine.setAudioScenario(AudioScenarioType.audioScenarioMeeting);
    await engine.setAudioProfile(
      profile: AudioProfileType.audioProfileSpeechStandard,
      scenario: AudioScenarioType.audioScenarioMeeting,
    );
    if (kDebugMode) {
      await engine.setLogLevel(LogLevel.logLevelInfo);
    }
    _engine = engine;
    _engineAppId = appId;
    return engine;
  }

  /// Fetches a fresh token and calls renewToken on the active channel.
  /// Agora calls onTokenPrivilegeWillExpire ~30s before expiry.
  Future<void> _renewToken() async {
    final channelId = _currentChannelId;
    final role = _currentRole;
    final engine = _engine;
    if (channelId == null || role == null || engine == null || !_joined) return;

    try {
      final tokenInfo = await _tokenService.fetchToken(
        channelName: channelId,
        role: role,
        streamSessionId: _currentStreamSessionId,
        uid: _uid,
      );
      await engine.renewToken(tokenInfo.token);
      if (kDebugMode) {
        debugPrint('[AgoraLiveService] Token renewed successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AgoraLiveService] Token renewal failed: $e');
      }
    }
  }

  Future<void> join({
    required String channelId,
    required LiveRole role,
    String? streamSessionId,
    int? uid,
  }) async {
    await leave();

    _currentChannelId = channelId;
    _currentRole = role;
    _currentStreamSessionId = streamSessionId;

    final tokenInfo = await _tokenService.fetchToken(
      channelName: channelId,
      role: role,
      streamSessionId: streamSessionId,
      uid: uid,
    );

    final engine = await _ensureEngine(tokenInfo.appId);
    _uid = tokenInfo.uid;
    final token = tokenInfo.token;

    await _applyVoiceProcessing(engine, role);

    final joinDone = Completer<void>();
    var awaitingJoinResult = false;

    void finishJoinOk() {
      if (!joinDone.isCompleted) joinDone.complete();
    }

    void finishJoinErr(Object error) {
      if (!joinDone.isCompleted) joinDone.completeError(error);
    }

    Future<void> tuneAudiencePlayback(RtcEngine rtc, int remoteUid) async {
      if (role != LiveRole.audience) return;
      try {
        await rtc.muteAllRemoteAudioStreams(false);
        if (remoteUid > 0) {
          await rtc.muteRemoteAudioStream(uid: remoteUid, mute: false);
          await rtc.adjustUserPlaybackSignalVolume(
            uid: remoteUid,
            volume: _kAudiencePlaybackVolume,
          );
        }
        await rtc.adjustPlaybackSignalVolume(_kAudiencePlaybackVolume);
        await rtc.setDefaultAudioRouteToSpeakerphone(true);
        await rtc.setEnableSpeakerphone(true);
      } catch (_) {}
    }

    _eventHandler = RtcEngineEventHandler(
      onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
        finishJoinOk();
      },
      onError: (ErrorCodeType err, String msg) {
        if (!awaitingJoinResult) return;
        finishJoinErr(Exception('Agora error: $err — $msg'));
      },
      onConnectionStateChanged:
          (RtcConnection connection, ConnectionStateType state, ConnectionChangedReasonType reason) {
        if (!awaitingJoinResult) return;
        if (state == ConnectionStateType.connectionStateFailed) {
          finishJoinErr(Exception('Agora connection failed: ${_joinFailureHint(reason)}'));
        }
      },
      onTokenPrivilegeWillExpire: (RtcConnection connection, String token) {
        // Token is about to expire — renew it to keep the stream alive.
        unawaited(_renewToken());
      },
      onRequestToken: (RtcConnection connection) {
        // Token already expired — attempt emergency renewal.
        unawaited(_renewToken());
      },
      onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
        if (role == LiveRole.audience) {
          unawaited(tuneAudiencePlayback(engine, remoteUid));
        }
      },
      onRemoteAudioStateChanged:
          (RtcConnection connection, int remoteUid, RemoteAudioState state,
              RemoteAudioStateReason reason, int elapsed) {
        if (role != LiveRole.audience) return;
        if (state == RemoteAudioState.remoteAudioStateStarting ||
            state == RemoteAudioState.remoteAudioStateDecoding) {
          unawaited(tuneAudiencePlayback(engine, remoteUid));
        }
      },
    );
    engine.registerEventHandler(_eventHandler!);

    await engine.setClientRole(
      role: role == LiveRole.publisher
          ? ClientRoleType.clientRoleBroadcaster
          : ClientRoleType.clientRoleAudience,
    );

    try {
      awaitingJoinResult = true;
      await engine.joinChannel(
        token: token,
        channelId: channelId,
        uid: _uid,
        options: ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          clientRoleType: role == LiveRole.publisher
              ? ClientRoleType.clientRoleBroadcaster
              : ClientRoleType.clientRoleAudience,
          publishMicrophoneTrack: role == LiveRole.publisher,
          autoSubscribeAudio: true,
        ),
      );

      await joinDone.future.timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw TimeoutException(
          'Timed out joining Agora channel (no onJoinChannelSuccess within 25s). '
          'Check backend Agora credentials, token, network, and that the host is broadcasting.',
        ),
      );

      await _applyVoiceProcessing(engine, role);

      if (role == LiveRole.audience) {
        await tuneAudiencePlayback(engine, 0);
      }
      _joined = true;
    } catch (e) {
      _joined = false;
      _unregisterHandler();
      _currentChannelId = null;
      _currentRole = null;
      _currentStreamSessionId = null;
      try {
        await engine.leaveChannel();
      } catch (_) {}
      rethrow;
    } finally {
      awaitingJoinResult = false;
    }
  }

  Future<void> muteLocalAudio(bool mute) async {
    final engine = _engine;
    if (engine == null) return;
    await engine.muteLocalAudioStream(mute);
  }

  Future<void> leave() async {
    _currentChannelId = null;
    _currentRole = null;
    _currentStreamSessionId = null;
    final engine = _engine;
    if (engine == null && _eventHandler == null) return;
    try {
      if (engine != null) {
        if (_joined) {
          try {
            await engine.adjustPlaybackSignalVolume(100);
            await engine.adjustRecordingSignalVolume(100);
          } catch (_) {}
        }
        await engine.leaveChannel();
      }
    } catch (_) {}
    _joined = false;
    _unregisterHandler();
  }

  Future<void> dispose() async {
    await leave();
    await _engine?.release();
    _engine = null;
    _engineAppId = null;
  }
}
