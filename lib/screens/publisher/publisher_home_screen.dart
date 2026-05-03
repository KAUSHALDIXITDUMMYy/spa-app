import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../constants/sports.dart';
import '../../models/scheduled_call.dart';
import '../../models/stream_session.dart';
import '../../services/agora_live_service.dart';
import '../../services/chat_notification_service.dart';
import '../../services/chat_repository.dart';
import '../../widgets/stream_chat_modal.dart';
import '../../services/foreground_service_helper.dart';
import '../../services/publisher_broadcast_audio_session.dart';
import '../../services/scheduled_calls_repository.dart';
import '../../services/streaming_repository.dart';
import '../../state/auth_notifier.dart';
import '../../theme/app_theme.dart';
import '../../widgets/subscriber_alert_cards.dart';

/// Web SPA palette hints: teal scheduled card, amber rejoin / warnings.
const Color _kTealBorder = Color(0xFF2DD4BF);
const Color _kTealTint = Color(0xFF134E4A);
const Color _kAmberBorder = Color(0xFFFBBF24);
const Color _kAmberTint = Color(0xFF78350F);

class PublisherHomeScreen extends StatefulWidget {
  const PublisherHomeScreen({super.key});

  @override
  State<PublisherHomeScreen> createState() => _PublisherHomeScreenState();
}

class _PublisherHomeScreenState extends State<PublisherHomeScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _sport = defaultStreamSport;
  final _agora = AgoraLiveService();

  StreamSession? _liveSession;
  StreamSession? _lastEndedSession;
  bool _busy = false;
  bool _muted = false;
  String? _error;
  String? _success;
  ScheduledCall? _pickedSchedule;
  ChatNotificationService? _chatNotifSvc;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshLastEnded());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatNotifSvc ??= context.read<ChatNotificationService>();
  }

  @override
  void dispose() {
    unawaited(_chatNotifSvc?.stopWatchingLiveSession() ?? Future<void>.value());
    _title.dispose();
    _description.dispose();
    _agora.dispose();
    super.dispose();
  }

  void _syncLiveChatNotifications() {
    if (!mounted) return;
    final uid = context.read<AuthNotifier>().firebaseUser?.uid;
    final svc = _chatNotifSvc;
    if (svc == null || uid == null) return;
    final sid = _liveSession?.id?.trim();
    if (sid != null && sid.isNotEmpty) {
      unawaited(svc.watchLiveSession(sessionId: sid, recipientUserId: uid));
    } else {
      unawaited(svc.stopWatchingLiveSession());
    }
  }

  Future<void> _refreshLastEnded() async {
    final uid = context.read<AuthNotifier>().firebaseUser?.uid;
    if (uid == null) return;
    final repo = context.read<StreamingRepository>();
    final s = await repo.fetchMostRecentEndedPublisherSession(uid);
    if (mounted) setState(() => _lastEndedSession = s);
  }

  void _guardRole(AuthNotifier auth) {
    if (auth.profile?.role != 'publisher') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/unauthorized');
      });
    }
  }

  Future<void> _requestSignOut(AuthNotifier auth) async {
    if (_liveSession != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('End your broadcast first'),
          content: const Text(
            'You are still live. Use the red End Stream button in the live controls below, '
            'then sign out when you are done. Signing out now would disconnect listeners while '
            'the session may still appear active.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }
    await auth.signOut();
    if (mounted) context.go('/');
  }

  void _useLastDetails() {
    final s = _lastEndedSession;
    if (s == null) return;
    setState(() {
      _title.text = (s.title ?? '').trim();
      _description.text = (s.description ?? '').trim();
      final sp = s.sport?.trim();
      _sport = (sp != null && sp.isNotEmpty) ? sp : defaultStreamSport;
    });
  }

  Future<void> _startBroadcast(
    AuthNotifier auth,
    StreamingRepository repo, {
    required bool scheduled,
  }) async {
    final user = auth.firebaseUser;
    final profile = auth.profile;
    if (user == null || profile == null) return;

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      setState(() => _error = 'Microphone permission is required to broadcast.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });

    try {
      await PublisherBroadcastAudioSession.activateForBroadcast();
      await ForegroundServiceHelper.startLiveTask(
        title: 'Live broadcast',
        text: 'Sportsmagician is using your microphone.',
        useMicrophone: true,
      );

      late StreamSession session;
      late String channel;

      if (scheduled && _pickedSchedule != null) {
        final sch = _pickedSchedule!;
        final sid = await repo.activateScheduledSession(
          scheduledCallId: sch.id,
          publisherId: user.uid,
          publisherName: profile.displayName ?? profile.email,
          roomId: sch.roomId,
          title: sch.title,
          description: sch.description ?? '',
          sport: sch.sport ?? '',
        );
        session = await repo.fetchSession(sid);
        channel = sch.roomId;
      } else {
        final roomId = repo.generateRoomId(user.uid);
        session = await repo.createStreamSession(
          publisherId: user.uid,
          publisherName: profile.displayName ?? profile.email,
          roomId: roomId,
          title: _title.text.trim().isEmpty ? 'Live stream' : _title.text.trim(),
          description: _description.text.trim(),
          sport: _sport,
        );
        channel = roomId;
      }

      await _agora.join(channelId: channel, role: LiveRole.publisher);

      setState(() {
        _liveSession = session;
        _busy = false;
        _success =
            scheduled ? 'Scheduled room is live!' : 'Audio stream started successfully!';
      });
      _syncLiveChatNotifications();
    } catch (e) {
      await ForegroundServiceHelper.stopLiveTask();
      await PublisherBroadcastAudioSession.restoreDefault();
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _endBroadcast(StreamingRepository repo) async {
    final s = _liveSession;
    if (s?.id == null) return;
    setState(() => _busy = true);
    try {
      await _agora.leave();
      await repo.resetScheduledAfterBroadcast(s!.id!);
      await ForegroundServiceHelper.stopLiveTask();
      await PublisherBroadcastAudioSession.restoreDefault();
      setState(() {
        _liveSession = null;
        _pickedSchedule = null;
        _busy = false;
        _success = 'Stream ended successfully!';
        _error = null;
      });
      _syncLiveChatNotifications();
      await _refreshLastEnded();
    } catch (e) {
      await ForegroundServiceHelper.stopLiveTask();
      await PublisherBroadcastAudioSession.restoreDefault();
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _rejoin(StreamSession session, StreamingRepository repo) async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      await PublisherBroadcastAudioSession.activateForBroadcast();
      await ForegroundServiceHelper.startLiveTask(
        title: 'Live broadcast',
        text: 'Sportsmagician is using your microphone.',
        useMicrophone: true,
      );
      await _agora.join(channelId: session.roomId, role: LiveRole.publisher);
      setState(() {
        _liveSession = session;
        _title.text = session.title ?? '';
        _description.text = session.description ?? '';
        final sp = session.sport?.trim();
        _sport = (sp != null && sp.isNotEmpty) ? sp : defaultStreamSport;
        _busy = false;
        _success = 'Rejoined stream successfully!';
      });
      _syncLiveChatNotifications();
    } catch (e) {
      await ForegroundServiceHelper.stopLiveTask();
      await PublisherBroadcastAudioSession.restoreDefault();
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    await _agora.muteLocalAudio(next);
    setState(() => _muted = next);
  }

  void _openChat(BuildContext context, String sessionId, AuthNotifier auth) {
    final chat = context.read<ChatRepository>();
    showStreamChatModal(
      context: context,
      chat: chat,
      streamSessionId: sessionId,
      currentUserId: auth.firebaseUser!.uid,
      currentUserName: auth.profile?.displayName ?? auth.profile?.email ?? 'Host',
      isPublisher: true,
      canSend: true,
      senderRole: 'publisher',
    );
  }

  Widget _badge({
    required String label,
    bool outline = false,
    Color? fg,
    Color? bg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg ?? (outline ? Colors.transparent : AppColors.muted),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: outline ? AppColors.border : Colors.transparent),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: outline ? 10 : 11,
          fontWeight: FontWeight.w600,
          fontFamily: outline ? 'monospace' : null,
          color: fg ?? AppColors.foreground,
        ),
      ),
    );
  }

  Widget _scheduledRoomsSection(
    BuildContext context, {
    required String uid,
    required AuthNotifier auth,
    required ScheduledCallsRepository scheduledRepo,
    required bool inactive,
  }) {
    final dateKey = getLocalDateKey();
    final dtFmt = DateFormat('MMM d, yyyy, h:mm a');

    return Container(
      decoration: BoxDecoration(
        color: _kTealTint.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kTealBorder.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month, size: 22, color: _kTealBorder.withValues(alpha: 0.95)),
              const SizedBox(width: 8),
              Text(
                "Today's scheduled rooms",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Calls assigned to you for today ($dateKey), plus any scheduled room you currently host '
            'in Firestore. Choose one, then use Go live in scheduled room below. You can still start '
            'an ad-hoc stream if nothing is selected.',
            style: const TextStyle(color: AppColors.mutedForeground, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<ScheduledCall>>(
            stream: scheduledRepo.watchPublisherTodaysScheduledRoomsMerged(
              firebaseUid: uid,
              profileUid: auth.profile?.uid,
              firebaseEmail: auth.firebaseUser?.email,
              profileEmail: auth.profile?.email,
            ),
            builder: (_, snap) {
              if (snap.hasError) {
                return Text(
                  'Could not load scheduled rooms: ${snap.error}',
                  style: const TextStyle(color: AppColors.destructive, fontSize: 13),
                );
              }
              final mine = snap.data ?? [];
              if (mine.isEmpty) {
                return const Text(
                  'No scheduled rooms for you right now. If your admin just reassigned you, refresh the page. '
                  'If you were created before first login, ask the admin to confirm your publisher is selected '
                  'on the scheduled call.',
                  style: TextStyle(color: AppColors.mutedForeground, fontSize: 13, height: 1.35),
                );
              }
              final disabledPick = inactive || _liveSession != null;
              return Column(
                children: mine.map((c) {
                  final inWindow = isCallInTimeWindow(c);
                  final selected = _pickedSchedule?.id == c.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 280),
                                child: Text(
                                  c.title,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                ),
                              ),
                              if (c.dateKey.isNotEmpty && c.dateKey != dateKey)
                                _badge(label: c.dateKey, outline: true),
                              _badge(
                                label: inWindow ? 'In time window' : 'Outside window',
                                outline: !inWindow,
                                bg: inWindow ? AppColors.muted : null,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${dtFmt.format(c.startsAt)} → ${dtFmt.format(c.endsAt)}',
                            style: const TextStyle(fontSize: 12, color: AppColors.mutedForeground),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Room: ${c.roomId}',
                            style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.mutedForeground),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: selected
                                ? OutlinedButton(
                                    onPressed: disabledPick ? null : () => setState(() => _pickedSchedule = null),
                                    child: const Text('Clear selection'),
                                  )
                                : ElevatedButton.icon(
                                    onPressed: disabledPick ? null : () => setState(() => _pickedSchedule = c),
                                    icon: const Icon(Icons.podcasts, size: 18),
                                    label: const Text('Broadcast here'),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _rejoinCard(
    BuildContext context, {
    required StreamingRepository repo,
    required String uid,
    required bool inactive,
  }) {
    return StreamBuilder<StreamSession?>(
      stream: repo.watchPublisherBroadcastingSession(uid),
      builder: (_, snap) {
        final active = snap.data;
        if (_liveSession != null || active == null) return const SizedBox.shrink();
        final title = active.title?.trim().isNotEmpty == true ? active.title!.trim() : 'Untitled stream';
        return Container(
          decoration: BoxDecoration(
            color: _kAmberTint.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kAmberBorder.withValues(alpha: 0.55)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.refresh, color: _kAmberBorder.withValues(alpha: 0.95)),
                  const SizedBox(width: 8),
                  Text(
                    'Rejoin Your Active Stream',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Your stream "$title" is still active. Rejoin to continue broadcasting.',
                style: const TextStyle(color: AppColors.mutedForeground, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 8),
              const Text(
                'This app broadcasts from your microphone.',
                style: TextStyle(color: AppColors.mutedForeground, fontSize: 12),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: inactive || _busy ? null : () => _rejoin(active, repo),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(_busy ? 'Rejoining…' : 'Rejoin Stream'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _alerts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null && _error!.isNotEmpty) ...[
          SubscriberDestructiveAlert(message: _error!),
          const SizedBox(height: 12),
        ],
        if (_success != null && _success!.isNotEmpty) ...[
          SubscriberInfoAlert(message: _success!),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _scheduledGoLiveCard(BuildContext context, {required bool inactive}) {
    final sch = _pickedSchedule!;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kTealBorder.withValues(alpha: 0.65)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month, color: _kTealBorder.withValues(alpha: 0.95)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Scheduled room broadcast',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: const TextStyle(color: AppColors.mutedForeground, fontSize: 13, height: 1.35),
              children: [
                const TextSpan(text: "You're using the admin-assigned room for "),
                TextSpan(
                  text: sch.title,
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.foreground),
                ),
                const TextSpan(
                  text: '. Audio uses your microphone on this device.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.muted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: SelectableText(
              'Room: ${sch.roomId}',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: inactive || _busy
                      ? null
                      : () => _startBroadcast(context.read<AuthNotifier>(), context.read<StreamingRepository>(),
                            scheduled: true),
                  icon: const Icon(Icons.podcasts, size: 18),
                  label: Text(_busy ? 'Starting…' : 'Go live in scheduled room'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: inactive || _busy ? null : () => setState(() => _pickedSchedule = null),
              child: const Text('Use ad-hoc stream instead'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _adHocCard(BuildContext context, {required AuthNotifier auth, required bool inactive}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ad-hoc audio stream',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              "Your own title, category, and room—not tied to today's scheduled calls. "
              'Use the scheduled section above when you were assigned a room.',
              style: TextStyle(color: AppColors.mutedForeground, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Stream title'),
              enabled: !inactive && _liveSession == null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
              enabled: !inactive && _liveSession == null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _sport,
              decoration: const InputDecoration(labelText: 'Sport / category'),
              items: usStreamSports.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: inactive || _liveSession != null ? null : (v) => setState(() => _sport = v ?? defaultStreamSport),
            ),
            const SizedBox(height: 8),
            const Text(
              'Subscribers can filter live streams by this category.',
              style: TextStyle(fontSize: 11, color: AppColors.mutedForeground),
            ),
            const SizedBox(height: 12),
            const Text(
              'This app broadcasts from your microphone.',
              style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_lastEndedSession != null)
                  OutlinedButton.icon(
                    onPressed: inactive || _busy || _liveSession != null ? null : _useLastDetails,
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('Use Last Details'),
                  ),
                ElevatedButton.icon(
                  onPressed: inactive || _busy || _liveSession != null
                      ? null
                      : () => _startBroadcast(auth, context.read<StreamingRepository>(), scheduled: false),
                  icon: const Icon(Icons.podcasts, size: 18),
                  label: Text(_busy ? 'Starting…' : 'Start Audio Stream'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _liveControlsCard(BuildContext context, AuthNotifier auth, StreamingRepository repo) {
    final session = _liveSession!;
    final sport = session.sport?.trim();
    final showSport = sport != null && sport.isNotEmpty && sport != defaultStreamSport;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.destructive.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(
                            color: AppColors.destructive,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (session.scheduledCallId != null && session.scheduledCallId!.trim().isNotEmpty)
                        _badge(label: 'Scheduled room', outline: true, fg: _kTealBorder),
                      if (showSport) _badge(label: streamSportLabel(session.sport), bg: AppColors.muted),
                      Text(
                        session.title ?? 'Broadcast',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.destructive,
                    foregroundColor: AppColors.foreground,
                  ),
                  onPressed: _busy ? null : () => _endBroadcast(repo),
                  child: Text(_busy ? 'Ending…' : 'End Stream'),
                ),
              ],
            ),
            if ((session.description ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                session.description!.trim(),
                style: const TextStyle(color: AppColors.mutedForeground, fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kAmberTint.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kAmberBorder.withValues(alpha: 0.45)),
              ),
              child: const Text(
                'Stay on this screen until End Stream. If audio pauses after switching apps, return here—we keep '
                'the foreground service active for your mic.',
                style: TextStyle(fontSize: 12, height: 1.35, color: AppColors.foreground),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _toggleMute,
                    icon: Icon(_muted ? Icons.mic_off : Icons.mic),
                    label: Text(_muted ? 'Unmute broadcast' : 'Mute broadcast'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: session.id == null ? null : () => _openChat(context, session.id!, auth),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Chat'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _audioStreamStatusCard() {
    final live = _liveSession != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Audio Stream Status',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              live
                  ? (_muted
                      ? 'Live: broadcast is muted.'
                      : 'Live: your microphone is being broadcast to subscribers.')
                  : 'Start a stream, then your microphone is what subscribers hear.',
              style: const TextStyle(color: AppColors.mutedForeground, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 16),
            Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.muted.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.podcasts,
                    size: 48,
                    color: live ? AppColors.primary : AppColors.mutedForeground.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    live ? 'Audio Stream Active' : 'Audio stream will start when you begin broadcasting',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: live ? 16 : 13,
                      color: live ? AppColors.foreground : AppColors.mutedForeground,
                    ),
                  ),
                  if (live) ...[
                    const SizedBox(height: 8),
                    Text(
                      _muted ? 'Broadcast is muted' : 'Microphone is live',
                      style: const TextStyle(fontSize: 12, color: AppColors.mutedForeground),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final repo = context.watch<StreamingRepository>();
    final scheduledRepo = context.watch<ScheduledCallsRepository>();
    _guardRole(auth);

    final uid = auth.firebaseUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    final inactive = auth.profile?.isActive == false;
    final name = auth.profile?.displayName ?? auth.profile?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Publisher Dashboard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text(
              'Welcome back, $name',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal, color: AppColors.mutedForeground),
            ),
          ],
        ),
        actions: [
          if (_liveSession != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.destructive.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: AppColors.destructive, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'LIVE${_liveSession!.sport != null && _liveSession!.sport!.trim().isNotEmpty && _liveSession!.sport!.trim() != defaultStreamSport ? ' · ${_liveSession!.sport!.trim()}' : ''}: ${_liveSession!.title ?? 'Broadcast'}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.destructive),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          TextButton(onPressed: () => _requestSignOut(auth), child: const Text('Sign Out')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (inactive) ...[
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.destructive),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person_off, color: AppColors.destructive.withValues(alpha: 0.95), size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Account Inactive',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const Text(
                                'Your access has been temporarily disabled',
                                style: TextStyle(color: AppColors.mutedForeground, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const SubscriberDestructiveAlert(
                      message:
                          'Your account is currently inactive. You are unable to stream or access content at this time.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Your account has been deactivated by an administrator. This means:',
                      style: TextStyle(color: AppColors.mutedForeground, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.only(left: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• You cannot start or manage streams', style: TextStyle(color: AppColors.mutedForeground)),
                          Text('• All your publishing features are temporarily disabled',
                              style: TextStyle(color: AppColors.mutedForeground)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Please contact your administrator to reactivate your account.',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            _scheduledRoomsSection(context, uid: uid, auth: auth, scheduledRepo: scheduledRepo, inactive: inactive),
            const SizedBox(height: 24),
            if (_liveSession == null) ...[
              _rejoinCard(context, repo: repo, uid: uid, inactive: inactive),
              const SizedBox(height: 16),
              _alerts(),
              if (_pickedSchedule != null) ...[
                _scheduledGoLiveCard(context, inactive: inactive),
              ] else ...[
                _adHocCard(context, auth: auth, inactive: inactive),
              ],
            ] else ...[
              _alerts(),
              _liveControlsCard(context, auth, repo),
            ],
            const SizedBox(height: 16),
            _audioStreamStatusCard(),
          ],
        ],
      ),
    );
  }
}
