import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../settings.dart';
import 'dee_said_client.dart';
import 'dee_said_models.dart';
import 'dee_said_segmenter.dart';

class DeeStreamPage extends StatefulWidget {
  const DeeStreamPage({super.key});

  @override
  State<DeeStreamPage> createState() => _DeeStreamPageState();
}

class _DeeStreamPageState extends State<DeeStreamPage> {
  static const Duration _pollInterval = Duration(seconds: 10);

  DeeSaidClient? _client;
  String? _baseUrl;
  Timer? _timer;
  List<DeeSaidEntry> _entries = [];
  final Set<String> _readIds = <String>{};
  String? _lastError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _client?.close();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final url = await Settings.relayUrl();
    if (!mounted) return;
    setState(() {
      _baseUrl = url;
      _client = DeeSaidClient(url);
    });
    await _refresh();
    _timer = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_client == null) return;
    try {
      final entries = await _client!.fetchEntries();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
        _lastError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _lastError = '$e';
      });
    }
  }

  void _markRead(String id) {
    setState(() => _readIds.add(id));
  }

  Future<void> _editRelayUrl() async {
    final ctrl = TextEditingController(text: _baseUrl ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Relay URL'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'http://host:3333',
            helperText: 'Tailscale name or LAN IP. Don\'t hardcode 192.168.x.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    await Settings.setRelayUrl(result);
    _client?.close();
    if (!mounted) return;
    setState(() {
      _baseUrl = result;
      _client = DeeSaidClient(result);
      _loading = true;
      _entries = [];
      _lastError = null;
    });
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dee Stream'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_outlined),
            tooltip: 'Relay URL',
            onPressed: _editRelayUrl,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_entries.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_lastError != null)
            _ErrorCard(message: _lastError!, onRetry: _refresh)
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No "Dee said" entries yet.',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Polling ${_baseUrl ?? ''} every 10s.\n'
                      'Pull-to-refresh to retry now.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _entries.length + (_lastError != null ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (_lastError != null && i == 0) {
          return _ErrorCard(message: _lastError!, onRetry: _refresh);
        }
        final idx = _lastError != null ? i - 1 : i;
        final e = _entries[idx];
        return _DeeCard(
          entry: e,
          read: _readIds.contains(e.id),
          onMarkRead: () => _markRead(e.id),
        );
      },
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.shade900,
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Relay error',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: Colors.white)),
            const SizedBox(height: 6),
            Text(message,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Retry'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeeCard extends StatefulWidget {
  final DeeSaidEntry entry;
  final bool read;
  final VoidCallback onMarkRead;
  const _DeeCard({
    required this.entry,
    required this.read,
    required this.onMarkRead,
  });

  @override
  State<_DeeCard> createState() => _DeeCardState();
}

class _DeeCardState extends State<_DeeCard> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: widget.entry.body));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied entire message')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d • h:mm a');
    final theme = Theme.of(context);
    final segmented = segmentMessage(widget.entry.body);
    final hasOpenItems = segmented.openItems.isNotEmpty;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(
                            fmt.format(widget.entry.createdAt.toLocal()),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (hasOpenItems) ...[
                            const SizedBox(width: 8),
                            _OpenItemsBadge(count: segmented.openItems.length),
                          ],
                          if (widget.read) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.check,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant),
                          ],
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          widget.entry.firstLine,
                          maxLines: _expanded ? null : 2,
                          overflow: _expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      switch (v) {
                        case 'copy':
                          _copyAll();
                          break;
                        case 'share':
                          _share(context, widget.entry.body);
                          break;
                        case 'read':
                          widget.onMarkRead();
                          break;
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'copy',
                          child: Text('Copy entire message')),
                      PopupMenuItem(value: 'share', child: Text('Share')),
                      PopupMenuItem(value: 'read', child: Text('Mark read')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final seg in segmented.segments) _SegmentBlock(seg: seg),
                  if (hasOpenItems) ...[
                    const SizedBox(height: 8),
                    Text('Open items',
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    for (final item in segmented.openItems)
                      _OpenItemTile(item: item),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentBlock extends StatelessWidget {
  final MessageSegment seg;
  const _SegmentBlock({required this.seg});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (seg.heading != null && seg.heading!.isNotEmpty) ...[
            SelectableText(seg.heading!,
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
          ],
          SelectableText(seg.text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _OpenItemsBadge extends StatelessWidget {
  final int count;
  const _OpenItemsBadge({required this.count});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$count open',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onTertiaryContainer)),
    );
  }
}

class _OpenItemTile extends StatelessWidget {
  final OpenItem item;
  const _OpenItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(item.prompt, style: theme.textTheme.bodyMedium),
          if (item.choices.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final c in item.choices)
                  Chip(
                    label: Text(c),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

void _share(BuildContext context, String text) {
  // No share_plus dep yet; fall back to clipboard + toast.
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Copied (share via clipboard)')),
  );
}
