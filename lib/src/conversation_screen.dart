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

// Allow tests to fast-forward the idle timer.
@visibleForTesting
Duration kIdleNudgeDuration = const Duration(minutes: 2);

class _ConversationScreenState extends State<ConversationScreen>
    with WidgetsBindingObserver {
  String _base = Settings.defaultYeshieHost;

  final _scrollController = ScrollController();
  final _inputController = TextEditingController();

  List<_Message> _messages = [];
  bool _sending = false;
  bool _sendSuccess = false;
  Timer? _pollTimer;
  String? _lastTs;

  // ── Draft-batch state ────────────────────────────────────────────────
  List<String> _draftBatch = [];
  bool _showIdleBanner = false;
  Timer? _idleTimer;
  bool _flushing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadHost().then((_) {
      _startPolling(active: true);
      _fetchMessages();
    });
    _loadDraftBatch();
    _inputController.addListener(_onInputChanged);
  }

  Future<void> _loadHost() async {
    final host = await Settings.yeshieHost();
    if (mounted) setState(() => _base = host);
  }

  Future<void> _loadDraftBatch() async {
    final batch = await Settings.draftBatch();
    if (mounted) setState(() => _draftBatch = batch);
  }

  void _onInputChanged() {
    // Reset idle timer whenever Mike types.
    _resetIdleTimer();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (mounted) setState(() => _showIdleBanner = false);
    if (_draftBatch.isNotEmpty) {
      _idleTimer = Timer(kIdleNudgeDuration, () {
        if (mounted && _draftBatch.isNotEmpty) {
          setState(() => _showIdleBanner = true);
        }
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _idleTimer?.cancel();
    _scrollController.dispose();
    _inputController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    _startPolling(active: active);
    if (!active && _draftBatch.isNotEmpty) {
      // Window backgrounded — show idle banner.
      if (mounted) setState(() => _showIdleBanner = true);
    }
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
    } catch (_) {}
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

  // ── Local Send: appends to draft batch, no network ───────────────────
  Future<void> _localSend() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    final newBatch = [..._draftBatch, text];
    _inputController.clear();
    setState(() {
      _draftBatch = newBatch;
      _showIdleBanner = false;
    });
    await Settings.saveDraftBatch(newBatch);
    _resetIdleTimer();
    _scrollToBottom();
  }

  // ── Remove a draft from the batch ───────────────────────────────────
  Future<void> _removeDraft(int index) async {
    final newBatch = List<String>.from(_draftBatch)..removeAt(index);
    setState(() {
      _draftBatch = newBatch;
      if (newBatch.isEmpty) _showIdleBanner = false;
    });
    await Settings.saveDraftBatch(newBatch);
    if (newBatch.isNotEmpty) _resetIdleTimer();
  }

  // ── Flush draft batch to /dispatch_input_compressed ─────────────────
  Future<void> _flushBatch() async {
    if (_draftBatch.isEmpty || _flushing) return;
    setState(() { _flushing = true; _showIdleBanner = false; });

    final combined = _draftBatch.join('\n\n\n');
    final secret = await _loadSecret();

    try {
      final resp = await http.post(
        Uri.parse('$_base/dispatch_input_compressed'),
        headers: {
          'Content-Type': 'application/json',
          if (secret.isNotEmpty) 'x-dispatch-token': secret,
        },
        body: jsonEncode({'message': combined, 'source': 'pulse-draft-batch'}),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (resp.statusCode == 200) {
        // Show each draft as a "sent" message in the thread (optimistic)
        final now = DateTime.now().toUtc().toIso8601String();
        final sentMessages = _draftBatch
            .asMap()
            .entries
            .map((e) => _Message(
                  from: 'mike',
                  ts: now,
                  body: e.value,
                  source: 'pulse-draft-batch',
                ))
            .toList();
        setState(() {
          _messages = [..._messages, ...sentMessages];
          _lastTs = now;
          _draftBatch = [];
        });
        await Settings.saveDraftBatch([]);
        _idleTimer?.cancel();
        _scrollToBottom();
      } else {
        _showError('Send failed: HTTP ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) _showError('$e');
    } finally {
      if (mounted) setState(() => _flushing = false);
    }
  }

  // ── Quick "Send now" — bypass batch, send directly ───────────────────
  Future<void> _sendNow() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final optimisticTs = DateTime.now().toUtc().toIso8601String();
    final optimistic = _Message(from: 'mike', ts: optimisticTs, body: text, source: 'pulse-quickcapture');
    setState(() {
      _messages = [..._messages, optimistic];
      _lastTs = optimisticTs;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final resp = await http.post(
        Uri.parse('$_base/pulse/capture'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      ).timeout(const Duration(seconds: 5));
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

  Future<String> _loadSecret() async {
    // Try to load relay secret from ~/.dispatch/relay.secret
    // On web, we can't read the filesystem; skip the token (localhost-only anyway)
    return '';
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // ── Idle / blur nudge banner ──────────────────────────────────
        if (_showIdleBanner && _draftBatch.isNotEmpty)
          _IdleBanner(
            draftCount: _draftBatch.length,
            flushing: _flushing,
            onSend: _flushBatch,
            onDismiss: () => setState(() => _showIdleBanner = false),
          ),

        // ── Thread ────────────────────────────────────────────────────
        Expanded(
          child: _messages.isEmpty && _draftBatch.isEmpty
              ? _EmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  itemCount: _messages.length + _draftBatch.length,
                  itemBuilder: (ctx, i) {
                    if (i < _messages.length) {
                      return _MessageBubble(msg: _messages[i]);
                    }
                    final draftIndex = i - _messages.length;
                    return _DraftBubble(
                      text: _draftBatch[draftIndex],
                      onRemove: () => _removeDraft(draftIndex),
                    );
                  },
                ),
        ),

        // ── Input bar ─────────────────────────────────────────────────
        _InputBar(
          controller: _inputController,
          sending: _sending,
          flushing: _flushing,
          success: _sendSuccess,
          hasDrafts: _draftBatch.isNotEmpty,
          onLocalSend: _localSend,
          onSendToDee: _flushBatch,
          onSendNow: _sendNow,
        ),
      ],
    );
  }
}

// ── Data model ───────────────────────────────────────────────────────────────

class _Message {
  final String from;
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

// ── Draft bubble ─────────────────────────────────────────────────────────────

class _DraftBubble extends StatelessWidget {
  final String text;
  final VoidCallback onRemove;
  const _DraftBubble({required this.text, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.35),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(4),
                ),
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.5),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(text,
                      style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface.withOpacity(0.7))),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('draft',
                            style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.errorContainer,
              ),
              child: Icon(Icons.close, size: 12, color: theme.colorScheme.error),
            ),
          ),
          const SizedBox(width: 6),
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.4),
            child: const Text('M',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ── Idle / blur nudge banner ──────────────────────────────────────────────────

class _IdleBanner extends StatelessWidget {
  final int draftCount;
  final bool flushing;
  final VoidCallback onSend;
  final VoidCallback onDismiss;
  const _IdleBanner({
    required this.draftCount,
    required this.flushing,
    required this.onSend,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF9C4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.schedule_send, size: 18, color: Color(0xFF8B6914)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ready to send $draftCount draft${draftCount == 1 ? '' : 's'} to Dee?',
              style: const TextStyle(fontSize: 13, color: Color(0xFF8B6914)),
            ),
          ),
          TextButton(
            onPressed: flushing ? null : onSend,
            child: flushing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Send', style: TextStyle(color: Color(0xFF8B6914), fontWeight: FontWeight.bold)),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 16, color: Color(0xFF8B6914)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ── Message bubble ───────────────────────────────────────────────────────────

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
                                color: theme.colorScheme.onSurfaceVariant),
                            code: TextStyle(
                                fontSize: 12,
                                backgroundColor: theme.colorScheme.surface,
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
                            : theme.colorScheme.onSurfaceVariant.withOpacity(0.5)),
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
            'Type a message.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Local Send saves it as a draft.\nSend to Dee flushes drafts.',
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
  final bool flushing;
  final bool success;
  final bool hasDrafts;
  final VoidCallback onLocalSend;
  final VoidCallback onSendToDee;
  final VoidCallback onSendNow;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.flushing,
    required this.success,
    required this.hasDrafts,
    required this.onLocalSend,
    required this.onSendToDee,
    required this.onSendNow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
                  enabled: !sending && !flushing,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                ),
              ),
              // Send Now (always-visible escape hatch)
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
                            key: const ValueKey('send-now'),
                            icon: const Icon(Icons.send, size: 20),
                            tooltip: 'Send now',
                            onPressed: onSendNow,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
              ),
            ],
          ),
          // Local Send + Send to Dee buttons
          Row(
            children: [
              _SmallButton(
                label: 'Local Send',
                icon: Icons.inbox,
                tooltip: 'Save as draft (no network)',
                onPressed: onLocalSend,
                enabled: !sending && !flushing,
              ),
              const SizedBox(width: 8),
              if (hasDrafts)
                _SmallButton(
                  label: flushing ? 'Sending…' : 'Send to Dee',
                  icon: Icons.send_to_mobile,
                  tooltip: 'Flush drafts to Dee via compression layer',
                  onPressed: flushing ? null : onSendToDee,
                  enabled: !flushing,
                  primary: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool primary;

  const _SmallButton({
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.enabled = true,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(
          foregroundColor: primary
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
