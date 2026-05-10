import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

import 'settings.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with WidgetsBindingObserver {
  String _base = Settings.defaultYeshieHost;

  final _scrollController = ScrollController();
  final _inputController = TextEditingController();

  List<_Message> _messages = [];
  bool _sending = false;
  bool _sendSuccess = false;
  Timer? _pollTimer;
  // Track the last message ts for incremental polling.
  String? _lastTs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadHost().then((_) {
      _startPolling(active: true);
      _fetchMessages();
    });
  }

  Future<void> _loadHost() async {
    final host = await Settings.yeshieHost();
    if (mounted) setState(() => _base = host);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollController.dispose();
    _inputController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Slow poll when backgrounded, fast when foregrounded.
    final active = state == AppLifecycleState.resumed;
    _startPolling(active: active);
  }

  void _startPolling({required bool active}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      Duration(seconds: active ? 3 : 10),
      (_) => _fetchMessages(),
    );
  }

  Future<void> _fetchMessages() async {
    final uri = Uri.parse(
      _lastTs != null
          ? '$_base/dispatch/conversation?since=${Uri.encodeComponent(_lastTs!)}&limit=200'
          : '$_base/dispatch/conversation?limit=200',
    );
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final newMsgs = (data['messages'] as List<dynamic>)
            .map((e) => _Message.fromJson(e as Map<String, dynamic>))
            .toList();
        if (newMsgs.isNotEmpty) {
          setState(() {
            _messages = _lastTs == null
                ? newMsgs
                : [..._messages, ...newMsgs];
            _lastTs = _messages.last.ts;
          });
          _scrollToBottom();
        }
      }
    } catch (_) {
      // Silently retry next poll cycle.
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);

    // Optimistic add — show Mike's message immediately.
    final optimisticTs = DateTime.now().toUtc().toIso8601String();
    final optimistic = _Message(
      from: 'mike',
      ts: optimisticTs,
      body: text,
      source: 'pulse-quickcapture',
    );
    setState(() {
      _messages = [..._messages, optimistic];
      _lastTs = optimisticTs;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final resp = await http
          .post(
            Uri.parse('$_base/pulse/capture'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() => _sendSuccess = true);
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _sendSuccess = false);
      } else {
        _showError('Send failed: HTTP ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) _showError('$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? _EmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                      vertical: 12, horizontal: 16),
                  itemCount: _messages.length,
                  itemBuilder: (ctx, i) => _MessageBubble(msg: _messages[i]),
                ),
        ),
        _InputBar(
          controller: _inputController,
          sending: _sending,
          success: _sendSuccess,
          onSend: _send,
        ),
      ],
    );
  }
}

// ── Data model ───────────────────────────────────────────────────────────────

class _Message {
  final String from; // "mike" | "dee"
  final String ts;
  final String body;
  final String? source;
  final String? inReplyTo;

  const _Message({
    required this.from,
    required this.ts,
    required this.body,
    this.source,
    this.inReplyTo,
  });

  factory _Message.fromJson(Map<String, dynamic> j) => _Message(
        from: (j['from'] as String?) ?? 'mike',
        ts: (j['ts'] as String?) ?? '',
        body: (j['body'] as String?) ?? '',
        source: j['source'] as String?,
        inReplyTo: j['in_reply_to'] as String?,
      );
}

// ── Bubble ───────────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final _Message msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isMike = msg.from == 'mike';
    final theme = Theme.of(context);
    final ts = _formatTs(msg.ts);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMike ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMike) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.secondary,
              child: const Text('D',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMike
                    ? theme.colorScheme.primary.withOpacity(0.85)
                    : theme.colorScheme.surfaceVariant,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMike ? 16 : 4),
                  bottomRight: Radius.circular(isMike ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: isMike
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  isMike
                      ? Text(msg.body,
                          style: TextStyle(
                              fontSize: 14,
                              color: theme.colorScheme.onPrimary))
                      : MarkdownBody(
                          data: msg.body,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(
                                fontSize: 14,
                                color:
                                    theme.colorScheme.onSurfaceVariant),
                            code: TextStyle(
                                fontSize: 12,
                                backgroundColor:
                                    theme.colorScheme.surface,
                                color: theme.colorScheme.onSurface),
                          ),
                        ),
                  const SizedBox(height: 4),
                  Text(
                    ts,
                    style: TextStyle(
                        fontSize: 11,
                        color: isMike
                            ? theme.colorScheme.onPrimary.withOpacity(0.6)
                            : theme.colorScheme.onSurfaceVariant
                                .withOpacity(0.5)),
                  ),
                ],
              ),
            ),
          ),
          if (isMike) ...[
            const SizedBox(width: 6),
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.primary,
              child: const Text('M',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTs(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inSeconds < 60) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24 && dt.day == now.day) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      return '${dt.month}/${dt.day} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            'Send a message — Dee will reply asynchronously.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Replies are generated via a per-message claude -p invocation\n'
            'to keep token costs near zero when idle.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}

// ── Input bar ─────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final bool success;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.success,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
            top: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Message Dee…',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              style: const TextStyle(fontSize: 14),
              onSubmitted: (_) => onSend(),
              enabled: !sending,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.send,
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: success
                ? const Icon(Icons.check_circle,
                    key: ValueKey('ok'), color: Colors.green, size: 22)
                : sending
                    ? const SizedBox(
                        key: ValueKey('spin'),
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        key: const ValueKey('send'),
                        icon: const Icon(Icons.send, size: 20),
                        tooltip: 'Send',
                        onPressed: onSend,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
          ),
        ],
      ),
    );
  }
}
