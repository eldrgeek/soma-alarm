import 'dart:async';

import 'package:flutter/material.dart';

import 'on_device_assistant.dart';

/// On-device AI chat (v0) — talks to Gemini Nano through the ML Kit GenAI
/// Prompt API / AICore. No network call, no relay round-trip, works offline.
///
/// DESIGN CONSTRAINT: inference here is strictly foreground and on-demand.
/// This screen only invokes [OnDeviceAssistant.ask] in direct response to a
/// user tapping Send, and releases the native model handle in [dispose].
/// Nothing here registers with WorkManager's 15-min poll (`background.dart`)
/// and nothing keeps the model resident once this screen closes.
class OnDeviceChatScreen extends StatefulWidget {
  const OnDeviceChatScreen({super.key, OnDeviceAssistant? assistant})
      : _assistant = assistant;

  final OnDeviceAssistant? _assistant;

  @override
  State<OnDeviceChatScreen> createState() => _OnDeviceChatScreenState();
}

class _ChatTurn {
  _ChatTurn({required this.role, required this.text});
  final String role; // 'you' | 'assistant'
  String text;
}

class _OnDeviceChatScreenState extends State<OnDeviceChatScreen> {
  late final OnDeviceAssistant _assistant =
      widget._assistant ?? MlKitGenaiAssistant();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatTurn> _turns = [];

  AssistantAvailability _availability = AssistantAvailability.unavailable;
  bool _checking = true;
  bool _downloading = false;
  int? _downloadBytes;
  bool _sending = false;
  StreamSubscription<String>? _askSub;
  StreamSubscription<AssistantDownloadEvent>? _downloadSub;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshAvailability();
  }

  Future<void> _refreshAvailability() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    final status = await _assistant.checkAvailability();
    if (!mounted) return;
    setState(() {
      _availability = status;
      _checking = false;
    });
  }

  void _startDownload() {
    setState(() {
      _downloading = true;
      _error = null;
    });
    _downloadSub?.cancel();
    _downloadSub = _assistant.downloadModel().listen(
      (event) {
        if (!mounted) return;
        setState(() {
          if (event.event == 'started' || event.event == 'progress') {
            _downloadBytes = event.bytes ?? _downloadBytes;
          }
          if (event.event == 'completed') {
            _downloading = false;
            _availability = AssistantAvailability.available;
          }
          if (event.event == 'failed') {
            _downloading = false;
            _error = event.error ?? 'Model download failed.';
          }
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _downloading = false;
          _error = '$e';
        });
      },
      onDone: () {
        if (mounted && _downloading) setState(() => _downloading = false);
      },
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      _turns.add(_ChatTurn(role: 'you', text: text));
      _turns.add(_ChatTurn(role: 'assistant', text: ''));
      _sending = true;
      _error = null;
    });
    _scrollToEnd();

    _askSub?.cancel();
    _askSub = _assistant.ask(text).listen(
      (chunk) {
        if (!mounted) return;
        setState(() => _turns.last.text += chunk);
        _scrollToEnd();
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _sending = false;
          if (_turns.isNotEmpty && _turns.last.text.isEmpty) {
            _turns.last.text = '(no response)';
          }
          _error = 'Generation failed: $e';
        });
      },
      onDone: () {
        if (mounted) setState(() => _sending = false);
      },
    );
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _askSub?.cancel();
    _downloadSub?.cancel();
    unawaited(_assistant.close());
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('On-device AI'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-check availability',
            onPressed: _checking ? null : _refreshAvailability,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_checking) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: _buildBody(theme)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (_availability == AssistantAvailability.available)
              _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    switch (_availability) {
      case AssistantAvailability.unsupported:
        return _buildInfoCard(
          theme,
          icon: Icons.smartphone,
          title: 'Not available on this platform',
          body:
              "On-device AI runs through Android's ML Kit GenAI Prompt API. "
              'It only works in the Pulse Android app.',
        );
      case AssistantAvailability.unavailable:
        return _buildInfoCard(
          theme,
          icon: Icons.offline_bolt_outlined,
          title: "This phone can't run on-device AI",
          body:
              'Gemini Nano via AICore needs a supported device and Android '
              "version. This device doesn't currently support it — the rest "
              'of Pulse is unaffected. Tap refresh to check again.',
        );
      case AssistantAvailability.downloadable:
        return _buildDownloadCard(theme);
      case AssistantAvailability.downloading:
        return _buildDownloadCard(theme);
      case AssistantAvailability.available:
        return _buildChatList(theme);
    }
  }

  Widget _buildInfoCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadCard(ThemeData theme) {
    final active = _downloading || _availability == AssistantAvailability.downloading;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.download_for_offline_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              active
                  ? 'Downloading the on-device model…'
                  : 'On-device model not downloaded yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (_downloadBytes != null) ...[
              const SizedBox(height: 8),
              Text(
                '${(_downloadBytes! / (1024 * 1024)).toStringAsFixed(1)} MB so far',
              ),
            ],
            const SizedBox(height: 16),
            if (active)
              const CircularProgressIndicator()
            else
              FilledButton.icon(
                onPressed: _startDownload,
                icon: const Icon(Icons.download),
                label: const Text('Download model'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatList(ThemeData theme) {
    if (_turns.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Ask anything. This runs entirely on-device (Gemini Nano) — '
            'no network round-trip, works offline.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      itemCount: _turns.length,
      itemBuilder: (context, i) {
        final turn = _turns[i];
        final isYou = turn.role == 'you';
        return Align(
          alignment: isYou ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isYou
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              turn.text.isEmpty && !isYou ? '…' : turn.text,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                enabled: !_sending,
                decoration: const InputDecoration(
                  hintText: 'Message the on-device model…',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
