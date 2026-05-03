import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/chat_notification_service.dart';
import '../services/chat_repository.dart';
import '../theme/app_theme.dart';

/// Matches web `components/ui/stream-chat-panel.tsx` bubble colours (dark theme).
class _StreamChatBubbleStyle {
  const _StreamChatBubbleStyle({
    required this.background,
    required this.foreground,
    this.border,
  });

  final Color background;
  final Color foreground;
  final BorderSide? border;

  static _StreamChatBubbleStyle ownMessage(BuildContext context) {
    return _StreamChatBubbleStyle(
      background: AppColors.primary,
      foreground: AppColors.primaryForeground,
    );
  }

  /// Other user, role publisher — `bg-muted border`
  static _StreamChatBubbleStyle publisherOther() {
    return _StreamChatBubbleStyle(
      background: AppColors.muted,
      foreground: AppColors.foreground,
      border: const BorderSide(color: AppColors.border, width: 1),
    );
  }

  /// Other user, role subscriber — `bg-muted/70`
  static _StreamChatBubbleStyle subscriberOther() {
    final bg = Color.alphaBlend(
      AppColors.muted.withValues(alpha: 0.7),
      AppColors.card,
    );
    return _StreamChatBubbleStyle(
      background: bg,
      foreground: AppColors.foreground,
    );
  }

  /// Other user, role admin — dark violet panel from web
  static _StreamChatBubbleStyle adminOther() {
    return _StreamChatBubbleStyle(
      background: const Color(0x662E1064),
      foreground: const Color(0xFFE9D5FF),
      border: const BorderSide(color: Color(0xFF6D28D9), width: 1),
    );
  }

  static _StreamChatBubbleStyle forOtherMessage(ChatMessage m) {
    switch (m.senderRole) {
      case 'publisher':
        return publisherOther();
      case 'admin':
        return adminOther();
      default:
        return subscriberOther();
    }
  }
}

String _roleLabel(String role) {
  switch (role) {
    case 'publisher':
      return '(Publisher)';
    case 'admin':
      return '(Admin)';
    case 'subscriber':
      return '(Subscriber)';
    default:
      return '';
  }
}

Future<void> showStreamChatModal({
  required BuildContext context,
  required ChatRepository chat,
  required String streamSessionId,
  required String currentUserId,
  required String currentUserName,
  required bool isPublisher,
  required bool canSend,
  String senderRole = 'subscriber',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    builder: (ctx) => _StreamChatModalBody(
      chat: chat,
      streamSessionId: streamSessionId,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      isPublisher: isPublisher,
      canSend: canSend,
      senderRole: senderRole,
    ),
  );
}

class _StreamChatModalBody extends StatefulWidget {
  const _StreamChatModalBody({
    required this.chat,
    required this.streamSessionId,
    required this.currentUserId,
    required this.currentUserName,
    required this.isPublisher,
    required this.canSend,
    required this.senderRole,
  });

  final ChatRepository chat;
  final String streamSessionId;
  final String currentUserId;
  final String currentUserName;
  final bool isPublisher;
  final bool canSend;
  final String senderRole;

  @override
  State<_StreamChatModalBody> createState() => _StreamChatModalBodyState();
}

class _StreamChatModalBodyState extends State<_StreamChatModalBody> {
  final _scroll = ScrollController();
  late final TextEditingController _ctrl;
  ChatNotificationService? _chatNotif;
  bool _registeredSheetOpen = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatNotif ??= context.read<ChatNotificationService>();
    if (!_registeredSheetOpen) {
      _registeredSheetOpen = true;
      _chatNotif?.setChatSheetOpen(true);
    }
  }

  @override
  void dispose() {
    if (_registeredSheetOpen) {
      _chatNotif?.setChatSheetOpen(false);
    }
    _scroll.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final desc = widget.isPublisher
        ? 'Reply to privileged subscribers'
        : widget.canSend
            ? 'Chat with the publisher'
            : 'You don\'t have chat access. Contact admin for privileges.';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.52,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 18, color: AppColors.foreground.withValues(alpha: 0.9)),
                      const SizedBox(width: 8),
                      Text(
                        'Live Chat',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.mutedForeground,
                          fontSize: 12,
                        ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: StreamBuilder<List<ChatMessage>>(
                      stream: widget.chat.watchMessages(widget.streamSessionId),
                      builder: (_, snap) {
                        final msgs = snap.data ?? [];
                        _scrollToEnd();
                        if (msgs.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'No messages yet. Send a message to start the conversation.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.mutedForeground,
                                      fontSize: 12,
                                    ),
                              ),
                            ),
                          );
                        }
                        return ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(12),
                          itemCount: msgs.length,
                          itemBuilder: (_, i) {
                            final m = msgs[i];
                            final mine = m.senderId == widget.currentUserId;
                            final style =
                                mine ? _StreamChatBubbleStyle.ownMessage(context) : _StreamChatBubbleStyle.forOtherMessage(m);
                            final roleSuffix = _roleLabel(m.senderRole);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Column(
                                crossAxisAlignment:
                                    mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    constraints: BoxConstraints(
                                      maxWidth: MediaQuery.of(context).size.width * 0.88,
                                    ),
                                    decoration: BoxDecoration(
                                      color: style.background,
                                      borderRadius: BorderRadius.circular(10),
                                      border: style.border != null
                                          ? Border.fromBorderSide(style.border!)
                                          : null,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text.rich(
                                          TextSpan(
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: style.foreground.withValues(alpha: 0.8),
                                            ),
                                            children: [
                                              TextSpan(text: m.senderName),
                                              if (roleSuffix.isNotEmpty)
                                                TextSpan(
                                                  text: ' $roleSuffix',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w500,
                                                    color: style.foreground.withValues(alpha: 0.75),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          m.text,
                                          style: TextStyle(
                                            fontSize: 14,
                                            height: 1.35,
                                            color: style.foreground,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    MaterialLocalizations.of(context)
                                        .formatTimeOfDay(TimeOfDay.fromDateTime(m.createdAt)),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          fontSize: 10,
                                          color: AppColors.mutedForeground,
                                        ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (widget.canSend)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        style: const TextStyle(fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.primaryForeground,
                      ),
                      onPressed: _send,
                      icon: const Icon(Icons.send, size: 20),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    await widget.chat.sendMessage(
      streamSessionId: widget.streamSessionId,
      senderId: widget.currentUserId,
      senderName: widget.currentUserName,
      senderRole: widget.senderRole,
      text: t,
    );
    _ctrl.clear();
  }
}
