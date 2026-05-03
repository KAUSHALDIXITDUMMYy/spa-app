import 'dart:async';
import 'dart:math';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:agora_token_generator/agora_token_generator.dart';
import 'package:flutter/foundation.dart';

import '../constants/agora_config.dart';

String _joinFailureHint(ConnectionChangedReasonType reason) {
  switch (reason) {
    case ConnectionChangedReasonType.connectionChangedInvalidAppId:
      return 'Invalid Agora App ID (check Agora Console vs app config).';
    case ConnectionChangedReasonType.connectionChangedInvalidChannelName:
      return 'Invalid channel name for Agora.';
    case ConnectionChangedReasonType.connectionChangedInvalidToken:
      return 'Invalid token or UID mismatch vs token (check App Certificate / token build).';
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
class AgoraLiveService {
  AgoraLiveService();

  RtcEngine? _engine;
  RtcEngineEventHandler? _eventHandler;
  int _uid = 0;
  bool _joined = false;

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

  Future<RtcEngine> _ensureEngine() async {
    if (_engine != null) return _engine!;
    final engine = createAgoraRtcEngine();
    await engine.initialize(
      RtcEngineContext(
        appId: AgoraConfig.appId,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      ),
    );
    await engine.enableAudio();
    await engine.setAudioScenario(
      AudioScenarioType.audioScenarioGameStreaming,
    );
    if (kDebugMode) {
      await engine.setLogLevel(LogLevel.logLevelInfo);
    }
    _engine = engine;
    return engine;
  }

  String _buildToken(String channelId, int uid) {
    return RtcTokenBuilder.buildTokenWithUid(
      appId: AgoraConfig.appId,
      appCertificate: AgoraConfig.appCertificate,
      channelName: channelId,
      uid: uid,
      tokenExpireSeconds: AgoraConfig.tokenExpireSeconds,
    );
  }

  Future<void> join({
    required String channelId,
    required LiveRole role,
    int? uid,
  }) async {
    await leave();
    final engine = await _ensureEngine();
    _uid = uid ?? randomUid();
    final token = _buildToken(channelId, _uid);

    if (role == LiveRole.audience) {
      // Match host profile: game streaming tends to give stronger playback levels than chatroom.
      await engine.setAudioScenario(AudioScenarioType.audioScenarioGameStreaming);
      await engine.setDefaultAudioRouteToSpeakerphone(true);
    } else {
      await engine.setAudioScenario(AudioScenarioType.audioScenarioGameStreaming);
    }

    final joinDone = Completer<void>();
    var awaitingJoinResult = false;

    void finishJoinOk() {
      if (!joinDone.isCompleted) joinDone.complete();
    }

    void finishJoinErr(Object error) {
      if (!joinDone.isCompleted) joinDone.completeError(error);
    }

    Future<void> boostAudiencePlayback(RtcEngine rtc, int remoteUid) async {
      if (role != LiveRole.audience) return;
      try {
        await rtc.muteAllRemoteAudioStreams(false);
        if (remoteUid > 0) {
          await rtc.muteRemoteAudioStream(uid: remoteUid, mute: false);
          await rtc.adjustUserPlaybackSignalVolume(uid: remoteUid, volume: 400);
        }
        await rtc.adjustPlaybackSignalVolume(400);
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
      onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
        if (role == LiveRole.audience) {
          unawaited(boostAudiencePlayback(engine, remoteUid));
        }
      },
      onRemoteAudioStateChanged:
          (RtcConnection connection, int remoteUid, RemoteAudioState state,
              RemoteAudioStateReason reason, int elapsed) {
        if (role != LiveRole.audience) return;
        if (state == RemoteAudioState.remoteAudioStateStarting ||
            state == RemoteAudioState.remoteAudioStateDecoding) {
          unawaited(boostAudiencePlayback(engine, remoteUid));
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
          'Check token, App ID, network, and that the host is broadcasting.',
        ),
      );

      if (role == LiveRole.audience) {
        await boostAudiencePlayback(engine, 0);
        unawaited(() async {
          for (final ms in [250, 900, 2200]) {
            await Future<void>.delayed(Duration(milliseconds: ms));
            if (!_joined || !identical(_engine, engine)) return;
            await boostAudiencePlayback(engine, 0);
          }
        }());
      }
      _joined = true;
    } catch (e) {
      _joined = false;
      _unregisterHandler();
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
    final engine = _engine;
    if (engine == null && _eventHandler == null) return;
    try {
      if (engine != null) {
        if (_joined) {
          try {
            await engine.adjustPlaybackSignalVolume(100);
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
  }
}
