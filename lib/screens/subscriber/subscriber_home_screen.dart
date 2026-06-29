import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../constants/sports.dart';
import '../../models/scheduled_call.dart';
import '../../models/subscriber_permission.dart';
import '../../services/admin_broadcasts_repository.dart';
import '../../services/agora_live_service.dart';
import '../../services/api_client.dart';
import '../../services/chat_notification_service.dart';
import '../../services/chat_repository.dart';
import '../../services/daily_schedule_repository.dart';
import '../../services/foreground_service_helper.dart';
import '../../services/listener_audio_session.dart';
import '../../services/scheduled_calls_repository.dart';
import '../../services/subscriber_repository.dart';
import '../../state/auth_notifier.dart';
import '../../theme/app_theme.dart';
import '../../widgets/stream_chat_modal.dart';
import '../../widgets/subscriber_alert_cards.dart';
import '../../widgets/subscriber_audio_bars.dart';

class SubscriberHomeScreen extends StatefulWidget {
  const SubscriberHomeScreen({super.key});

  @override
  State<SubscriberHomeScreen> createState() => _SubscriberHomeScreenState();
}

class _SubscriberHomeScreenState extends State<SubscriberHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  AgoraLiveService? _agora;
  bool _agoraReady = false;
  Timer? _poll;

  List<SubscriberPermission> _adHoc = [];
  List<SubscriberPermission> _scheduled = [];
  SubscriberPermission? _selected;
  SubscriberPermission? _pending;
  bool _loading = true;
  bool _refreshing = false;
  String _sportFilter = sportFilterAll;
  String _scheduledSportFilter = sportFilterAll;
  String? _error;
  String? _listenError;
  bool _listening = false;
  /// Calendar rows keyed by `streamSession.id` (matches web `callMetaByStreamSessionId`).
  Map<String, ScheduledCall?> _scheduledCallMetaBySessionId = {};
  String _scheduleListDateKey = getLocalDateKey();
  Timer? _scheduleDayTimer;
  final Map<String, Stream<List<ScheduledCall>>> _scheduleStreamCache = {};
  ChatNotificationService? _chatNotifSvc;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load());
    _scheduleDayTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      final dk = getLocalDateKey();
      if (dk != _scheduleListDateKey && mounted) {
        setState(() => _scheduleListDateKey = dk);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatNotifSvc ??= context.read<ChatNotificationService>();
    if (!_agoraReady) {
      _agora = AgoraLiveService(context.read<ApiClient>());
      _agoraReady = true;
    }
  }

  @override
  void dispose() {
    unawaited(_chatNotifSvc?.stopWatchingLiveSession() ?? Future<void>.value());
    _poll?.cancel();
    _scheduleDayTimer?.cancel();
    _tabs.dispose();
    unawaited(ListenerAudioSession.restoreDefault());
    unawaited(_agora?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  void _syncLiveChatNotifications() {
    if (!mounted) return;
    final uid = context.read<AuthNotifier>().firebaseUser?.uid;
    final svc = _chatNotifSvc;
    if (svc == null || uid == null) return;
    final sid = _selected?.streamSession?.id?.trim();
    if (_listening && sid != null && sid.isNotEmpty) {
      unawaited(svc.watchLiveSession(sessionId: sid, recipientUserId: uid));
    } else {
      unawaited(svc.stopWatchingLiveSession());
    }
  }

  void _guardRole(AuthNotifier auth) {
    if (auth.profile?.role != 'subscriber') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/unauthorized');
      });
    }
  }

  Future<void> _load({bool manual = false}) async {
    final uid = context.read<AuthNotifier>().firebaseUser?.uid;
    if (uid == null) return;
    if (manual) setState(() => _refreshing = true);
    try {
      final repo = context.read<SubscriberRepository>();
      final scheduledRepo = context.read<ScheduledCallsRepository>();
      final split = await repo.getAvailableStreamsSplit(uid);
      if (!mounted) return;
      var tearDownListening = false;
      setState(() {
        _adHoc = split.adHoc;
        _scheduled = split.scheduled;
        _loading = false;
        _refreshing = false;
        _error = null;
        if (_selected != null) {
          final id = _selected!.id;
          final merged = [..._adHoc, ..._scheduled];
          var still = false;
          for (final p in merged) {
            if (p.id == id) {
              still = true;
              break;
            }
          }
          if (!still) {
            tearDownListening = true;
            _selected = null;
            _listening = false;
          }
        }
      });
      if (tearDownListening) {
        await _tearDownListeningSession();
      }
      await _hydrateScheduledCallMeta(scheduledRepo, split.scheduled);
      if (mounted) _syncLiveChatNotifications();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _hydrateScheduledCallMeta(
    ScheduledCallsRepository scheduledRepo,
    List<SubscriberPermission> scheduled,
  ) async {
    final next = <String, ScheduledCall?>{};
    for (final p in scheduled) {
      final sess = p.streamSession;
      final sid = sess?.id;
      if (sid == null) continue;
      final cid = sess?.scheduledCallId?.trim();
      if (cid == null || cid.isEmpty) {
        next[sid] = null;
        continue;
      }
      next[sid] = await scheduledRepo.getScheduledCallById(cid);
    }
    if (!mounted) return;
    setState(() => _scheduledCallMetaBySessionId = next);
  }

  Future<void> _applyPendingSelection() async {
    final next = _pending;
    if (next == null) return;
    _pending = null;
    await _openStream(next);
  }

  Future<void> _openStream(SubscriberPermission p) async {
    final session = p.streamSession;
    if (session == null || !session.isActive) return;
    if (session.isAwaitingBroadcastSession) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for host to go live in this room.')),
      );
      return;
    }

    if (_selected?.id == p.id) return;

    if (_selected != null) {
      _pending = p;
      await _stopStream();
      return;
    }

    setState(() {
      _listenError = null;
      _listening = false;
    });
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final mic = await Permission.microphone.request();
        if (!mic.isGranted) {
          if (!mounted) return;
          setState(() {
            _listenError =
                'Microphone permission is required to connect to the live audio session.';
          });
          return;
        }
      }
      await ListenerAudioSession.activateForListening();
      await ForegroundServiceHelper.startLiveTask(
        title: 'Listening',
        text: session.title ?? 'Sportsmagician',
        useMicrophone: false,
      );
      await _agora!.join(
        channelId: session.roomId,
        role: LiveRole.audience,
        streamSessionId: session.id,
      );
      setState(() {
        _selected = p;
        _listening = true;
      });
      _syncLiveChatNotifications();
      await _applyPendingSelection();
    } catch (e) {
      await _tearDownListeningSession();
      setState(() {
        _listenError = '$e';
        _listening = false;
        _selected = null;
      });
    }
  }

  Future<void> _tearDownListeningSession() async {
    await _agora!.leave();
    await ForegroundServiceHelper.stopLiveTask();
    await ListenerAudioSession.restoreDefault();
  }

  Future<void> _stopStream() async {
    await _tearDownListeningSession();
    setState(() {
      _selected = null;
      _listening = false;
      _listenError = null;
    });
    _syncLiveChatNotifications();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await _applyPendingSelection();
  }

  Iterable<SubscriberPermission> _filtered(
    List<SubscriberPermission> list,
    String sportFilter,
  ) sync* {
    for (final perm in list) {
      final sport = perm.streamSession?.sport;
      if (sportFilter == sportFilterAll) {
        yield perm;
      } else if (sportFilter == sportFilterUnspecified) {
        if (sport == null || sport.trim().isEmpty) yield perm;
      } else if (sport == sportFilter) {
        yield perm;
      }
    }
  }

  void _openChat(SubscriberPermission p, AuthNotifier auth) {
    final sid = p.streamSession?.id;
    if (sid == null) return;
    final allow = auth.profile?.allowChat == true;
    if (!allow) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat is disabled for your account.')),
      );
      return;
    }
    final chat = context.read<ChatRepository>();
    showStreamChatModal(
      context: context,
      chat: chat,
      streamSessionId: sid,
      currentUserId: auth.firebaseUser!.uid,
      currentUserName: auth.profile?.displayName ?? auth.profile?.email ?? 'Subscriber',
      isPublisher: false,
      canSend: allow,
      senderRole: 'subscriber',
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final scheduledRepo = context.watch<ScheduledCallsRepository>();
    final dailyScheduleRepo = context.watch<DailyScheduleRepository>();
    _guardRole(auth);

    final inactive = auth.profile?.isActive == false;
    final uid = auth.firebaseUser?.uid ?? '';

    if (inactive) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Subscriber Dashboard'),
          actions: [
            TextButton(
              onPressed: () async {
                await auth.signOut();
                if (context.mounted) context.go('/');
              },
              child: const Text('Sign Out'),
            ),
          ],
        ),
        body: SubscriberInactivePanel(
          onSignOut: () async {
            await auth.signOut();
            if (context.mounted) context.go('/');
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscriber Dashboard'),
        actions: [
          IconButton(
            onPressed: _refreshing ? null : () => _load(manual: true),
            icon: _refreshing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          TextButton(
            onPressed: () async {
              await _stopStream();
              await auth.signOut();
              if (context.mounted) context.go('/');
            },
            child: const Text('Sign Out'),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Live streams'),
            Tab(text: 'Scheduled rooms'),
            Tab(text: 'Notifications'),
            Tab(text: 'Today\'s schedule'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildStreamsTab(auth),
          _buildScheduledStreamsTab(auth, scheduledRepo, uid),
          _buildNotificationsTab(uid),
          _buildAdminDailyScheduleTab(dailyScheduleRepo),
        ],
      ),
    );
  }

  Widget _buildStreamsTab(AuthNotifier auth) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final rows = _filtered(_adHoc, _sportFilter).toList();
    final filterEmpty =
        rows.isEmpty && _adHoc.isNotEmpty && _sportFilter != sportFilterAll;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: _sportFilter,
          decoration: const InputDecoration(labelText: 'Filter by sport'),
          items: [
            const DropdownMenuItem(value: sportFilterAll, child: Text('All sports')),
            const DropdownMenuItem(
                value: sportFilterUnspecified, child: Text('Not specified')),
            ...usStreamSports.map((s) => DropdownMenuItem(value: s, child: Text(s))),
          ],
          onChanged: (v) => setState(() => _sportFilter = v ?? sportFilterAll),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          SubscriberDestructiveAlert(message: _error!),
        ],
        if (_listenError != null) ...[
          const SizedBox(height: 12),
          SubscriberDestructiveAlert(message: _listenError!),
        ],
        if (filterEmpty) ...[
          const SizedBox(height: 12),
          const SubscriberInfoAlert(
            message:
                'No live streams match this sport. Try “All sports” or pick another category.',
          ),
        ],
        const SizedBox(height: 12),
        if (rows.isEmpty && !filterEmpty)
          const Text(
            'No live streams right now.',
            style: TextStyle(color: AppColors.mutedForeground),
          ),
        ...rows.map((p) => _streamCard(p, auth)),
      ],
    );
  }

  Widget _buildScheduledStreamsTab(
    AuthNotifier auth,
    ScheduledCallsRepository scheduledRepo,
    String uid,
  ) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final rows = _filtered(_scheduled, _scheduledSportFilter).toList();
    final filterEmpty = rows.isEmpty &&
        _scheduled.isNotEmpty &&
        _scheduledSportFilter != sportFilterAll;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildPublisherCallSlotsSection(scheduledRepo, uid),
        const SizedBox(height: 16),
        Text(
          'Live scheduled rooms',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: _scheduledSportFilter,
          decoration: const InputDecoration(
            labelText: 'Filter by sport',
            helperText: 'Scheduled & admin-assigned rooms only',
          ),
          items: [
            const DropdownMenuItem(value: sportFilterAll, child: Text('All sports')),
            const DropdownMenuItem(
              value: sportFilterUnspecified,
              child: Text('Not specified'),
            ),
            ...usStreamSports.map((s) => DropdownMenuItem(value: s, child: Text(s))),
          ],
          onChanged: (v) =>
              setState(() => _scheduledSportFilter = v ?? sportFilterAll),
        ),
        if (_listenError != null) ...[
          const SizedBox(height: 12),
          SubscriberDestructiveAlert(message: _listenError!),
        ],
        if (filterEmpty) ...[
          const SizedBox(height: 12),
          const SubscriberInfoAlert(
            message:
                'No scheduled rooms match this sport. Try “All sports” or pick another category.',
          ),
        ],
        const SizedBox(height: 12),
        if (rows.isEmpty && !filterEmpty)
          const Text(
            'No scheduled rooms are live for you.',
            style: TextStyle(color: AppColors.mutedForeground),
          ),
        ...rows.map(
          (p) => _streamCard(
            p,
            auth,
            scheduledCall: p.streamSession?.id != null
                ? _scheduledCallMetaBySessionId[p.streamSession!.id]
                : null,
          ),
        ),
      ],
    );
  }

  Widget _streamCard(
    SubscriberPermission p,
    AuthNotifier auth, {
    ScheduledCall? scheduledCall,
  }) {
    final s = p.streamSession!;
    final waiting = s.isAwaitingBroadcastSession;
    final sel = _selected?.id == p.id;
    final desc = (scheduledCall?.description ?? s.description ?? '').trim();
    final cal = scheduledCall;
    final rawTitle = (cal?.title ?? s.title ?? 'Untitled').trim();
    final title = rawTitle.isEmpty ? 'Untitled' : rawTitle;
    final publisherLine = cal?.publisherName ?? p.publisherName;
    final sportRaw = cal?.sport ?? s.sport;
    String? timeLine;
    if (cal != null) {
      final start = TimeOfDay.fromDateTime(cal.startsAt).format(context);
      final end = TimeOfDay.fromDateTime(cal.endsAt).format(context);
      timeLine = '$start – $end · $publisherLine';
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: sel ? AppColors.primary : AppColors.border,
          width: sel ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  label: Text(waiting ? 'Waiting for host' : 'LIVE',
                      style: const TextStyle(fontSize: 11)),
                  backgroundColor: waiting
                      ? AppColors.muted
                      : AppColors.destructive.withValues(alpha: 0.25),
                ),
                Chip(
                  label:
                      Text(streamSportLabel(sportRaw), style: const TextStyle(fontSize: 11)),
                ),
                if (cal != null && cal.dateKey.isNotEmpty)
                  Chip(
                    label: Text(
                      cal.dateKey,
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ),
                if (sel && _listening && !waiting)
                  Chip(
                    avatar: const Icon(Icons.equalizer, size: 14, color: Color(0xFF22C55E)),
                    label: const Text('Playing', style: TextStyle(fontSize: 11)),
                    backgroundColor: AppColors.muted.withValues(alpha: 0.5),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text(
              timeLine ??
                  'Started: ${TimeOfDay.fromDateTime(s.createdAt).format(context)} · $publisherLine',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.mutedForeground,
                  ),
            ),
            if (waiting) ...[
              const SizedBox(height: 10),
              const SubscriberInfoAlert(
                message:
                    'This room is open but the publisher has not started broadcasting yet. '
                    'Keep the app open and tap Listen when they go live—audio will connect automatically.',
              ),
            ],
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.muted.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  desc,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.mutedForeground,
                        height: 1.35,
                      ),
                ),
              ),
            ],
            if (sel && _listening && !waiting) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.muted.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SubscriberAudioBars(playing: true),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: waiting ? null : () => _openStream(p),
                    child: Text(sel ? 'Listening' : 'Listen'),
                  ),
                ),
                if (sel)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: OutlinedButton(
                      onPressed: _stopStream,
                      child: const Text('Stop'),
                    ),
                  ),
                IconButton(
                  onPressed: () => _openChat(p, auth),
                  icon: const Icon(Icons.chat_bubble_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Stream<List<ScheduledCall>> _cachedSubscriberScheduleStream(
    ScheduledCallsRepository repo,
    String uid,
    String dateKey,
  ) {
    final key = '$uid|$dateKey';
    return _scheduleStreamCache.putIfAbsent(
      key,
      () => repo.watchSubscriberScheduleForDate(uid, dateKey),
    );
  }

  /// Firestore `scheduledCalls` for today (publishers you follow) — web metadata for assignments.
  Widget _buildPublisherCallSlotsSection(
    ScheduledCallsRepository repo,
    String uid,
  ) {
    final dateKey = _scheduleListDateKey;
    return StreamBuilder<List<ScheduledCall>>(
      key: ValueKey('subscriber-call-slots-$uid-$dateKey'),
      stream: _cachedSubscriberScheduleStream(repo, uid, dateKey),
      builder: (_, snap) {
        if (snap.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Could not load call slots: ${snap.error}',
                style: const TextStyle(color: AppColors.destructive, fontSize: 13),
              ),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final mine = snap.data ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Today’s call slots',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Games assigned to publishers you follow ($dateKey).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.mutedForeground,
                  ),
            ),
            const SizedBox(height: 10),
            if (mine.isEmpty)
              Text(
                'Nothing scheduled for your publishers today.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.mutedForeground,
                    ),
              )
            else
              ...mine.map(
                (c) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    title: Text(c.title),
                    subtitle: Text(
                      '${c.publisherName} · '
                      '${MaterialLocalizations.of(context).formatMediumDate(c.startsAt)} '
                      '· ${TimeOfDay.fromDateTime(c.startsAt).format(context)} · '
                      '${c.roomId}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildNotificationsTab(String uid) {
    final subRepo = context.read<SubscriberRepository>();
    final bcRepo = context.read<AdminBroadcastsRepository>();

    return StreamBuilder<bool>(
      stream: subRepo.watchAssignmentEligibility(uid),
      builder: (_, eligSnap) {
        if (eligSnap.connectionState == ConnectionState.waiting && !eligSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final eligible = eligSnap.data ?? false;
        if (!eligible) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.shield_outlined, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Notifications',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Admin messages appear here once you are assigned to at least one publisher or stream.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.mutedForeground,
                            ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'You don’t have any publisher or stream assignments yet. '
                        'Contact your administrator if you need access.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        return StreamBuilder<List<AdminBroadcastPost>>(
          stream: bcRepo.watchBroadcasts(),
          builder: (_, snap) {
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load notifications: ${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.destructive),
                  ),
                ),
              );
            }
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Notifications',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Messages from your administrator',
                    style: TextStyle(color: AppColors.mutedForeground, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  const Center(
                    child: Text(
                      'No messages from admin yet.',
                      style: TextStyle(color: AppColors.mutedForeground),
                    ),
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.notifications_none, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Notifications',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Messages from your administrator',
                        style: TextStyle(color: AppColors.mutedForeground, fontSize: 13),
                      ),
                    ],
                  );
                }
                final b = items[i - 1];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'MESSAGE FROM ADMIN',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SelectableText(
                          b.message,
                          style: const TextStyle(fontSize: 14, height: 1.35),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${MaterialLocalizations.of(context).formatFullDate(b.createdAt)} · ${TimeOfDay.fromDateTime(b.createdAt).format(context)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildAdminDailyScheduleTab(DailyScheduleRepository repo) {
    return StreamBuilder<DailySchedulePost?>(
      stream: repo.watchCurrent(),
      builder: (_, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load schedule: ${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.destructive),
              ),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final post = snap.data;
        final text = (post?.content ?? '').trim();
        if (text.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_month, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Today’s schedule',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'No schedule has been posted for today yet. Check back later.',
                style: TextStyle(color: AppColors.mutedForeground),
              ),
            ],
          );
        }

        final updated = post?.updatedAt;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Today’s schedule',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (updated != null) ...[
              const SizedBox(height: 6),
              Text(
                'Last updated: ${MaterialLocalizations.of(context).formatFullDate(updated)} '
                'at ${TimeOfDay.fromDateTime(updated).format(context)}',
                style: const TextStyle(fontSize: 12, color: AppColors.mutedForeground),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.muted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                text,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
