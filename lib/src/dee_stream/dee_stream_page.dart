import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../settings.dart';
import 'dee_said_client.dart';
import 'dee_said_models.dart';
import 'dee_said_segmenter.dart';
import 'dispatch_input_client.dart';
import 'relay_resolver.dart';
import 'reply_composer.dart';

class DeeStreamPage extends StatefulWidget {
  const DeeStreamPage({super.key});

  @override
  State<DeeStreamPage> createState() => _DeeStreamPageState();
}

class _DeeStreamPageState extends State<DeeStreamPage> {
  static const Duration _pollInterval = Duration(seconds: 10);

  DeeSaidClient? _client;
  DispatchInputClient? _dispatchClient;
  RelayResolver? _resolver;
  String? _userUrl;
  String _dispatchToken = '';
  Timer? _timer;
  List<DeeSaidEntry> _entries = [];
  final List<YouSaidEntry> _youSaidEntries = <YouSaidEntry>[];
  final Set<String> _readIds = <String>{};
  String? _lastError;
  Map<String, String> _attemptErrors = const {};
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
    _dispatchClient?.close();
    _resolver?.close();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final url = await Settings.relayUrl();
    final token = await Settings.dispatchToken();
    if (!mounted) return;
    final resolver = RelayResolver(
      userUrl: url,
      candidates: kDefaultRelayCandidates,
    );
    setState(() {
      _userUrl = url;
      _dispatchToken = token;
      _resolver = resolver;
      _client = DeeSaidClient(resolver: resolver);
      _dispatchClient = DispatchInputClient(
        resolver: resolver,
        tokenGetter: () => _dispatchToken,
      );
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
        _attemptErrors = const {};
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _lastError = '$e';
        _attemptErrors = _resolver?.lastErrors ?? const {};
      });
    }
  }

  void _markRead(String id) {
    setState(() => _readIds.add(id));
  }

  Future<void> _openReplyComposer() async {
    if (_dispatchClient == null) return;
    if (_dispatchToken.isEmpty) {
      await _editDispatchToken();
      if (_dispatchToken.isEmpty) return; // user cancelled
    }
    final entry = await showReplyComposer(context, client: _dispatchClient!);
    if (entry == null || !mounted) return;
    setState(() => _youSaidEntries.add(entry));
  }

  Future<void> _editDispatchToken() async {
    final controller = TextEditingController(text: _dispatchToken);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dispatch Token'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SelectableText(
              'Shared secret from ~/.dispatch/relay.secret on the relay host. '
              'Required to POST replies to Dee.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: false,
              decoration: const InputDecoration(
                hintText: 'Paste token',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await Settings.setDispatchToken(result);
    if (!mounted) return;
    setState(() => _dispatchToken = result.trim());
  }

  Future<void> _editRelayUrl() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _RelayUrlDialog(
        initial: _userUrl ?? '',
        candidates: kDefaultRelayCandidates,
      ),
    );
    if (result == null) return;
    await Settings.setRelayUrl(result);
    _client?.close();
    _resolver?.close();
    if (!mounted) return;
    final resolver = RelayResolver(
      userUrl: result,
      candidates: kDefaultRelayCandidates,
    );
    setState(() {
      _userUrl = result;
      _resolver = resolver;
      _client = DeeSaidClient(resolver: resolver);
      _loading = true;
      _entries = [];
      _lastError = null;
      _attemptErrors = const {};
    });
    await _refresh();
  }

  String get _activeUrl =>
      _resolver?.cached ??
      (_userUrl?.isNotEmpty == true ? _userUrl! : '(probing fallbacks)');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dee Stream'),
        actions: [
          IconButton(
            icon: const Icon(Icons.key_outlined),
            tooltip: 'Dispatch token',
            onPressed: _editDispatchToken,
          ),
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
      body: SelectionArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: _buildBody(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('reply_to_dee_fab'),
        onPressed: _dispatchClient == null ? null : _openReplyComposer,
        icon: const Icon(Icons.reply),
        label: const Text('Reply to Dee'),
      ),
    );
  }

  /// Merge Dee + You entries, newest first.
  List<Object> _mergedItems() {
    final items = <Object>[]
      ..addAll(_entries)
      ..addAll(_youSaidEntries);
    items.sort((a, b) {
      final ta = a is DeeSaidEntry ? a.createdAt : (a as YouSaidEntry).sentAt;
      final tb = b is DeeSaidEntry ? b.createdAt : (b as YouSaidEntry).sentAt;
      return tb.compareTo(ta);
    });
    return items;
  }

  Widget _buildBody() {
    final merged = _mergedItems();
    if (_loading && merged.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (merged.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_lastError != null)
            _ErrorCard(
              message: _lastError!,
              attemptErrors: _attemptErrors,
              onRetry: _refresh,
              onEditUrl: _editRelayUrl,
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText('No "Dee said" entries yet.',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    SelectableText(
                      'Polling $_activeUrl every 10s.\n'
                      'Pull-to-refresh to retry now.\n'
                      'Tap "Reply to Dee" to send a message.',
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
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      itemCount: merged.length + (_lastError != null ? 1 : 0) + 1, // +1 trailing pad for FAB
      itemBuilder: (ctx, i) {
        if (_lastError != null && i == 0) {
          return _ErrorCard(
            message: _lastError!,
            attemptErrors: _attemptErrors,
            onRetry: _refresh,
            onEditUrl: _editRelayUrl,
          );
        }
        final idx = _lastError != null ? i - 1 : i;
        if (idx >= merged.length) {
          return const SizedBox(height: 80);
        }
        final item = merged[idx];
        if (item is YouSaidEntry) {
          return YouSaidCard(entry: item);
        }
        final e = item as DeeSaidEntry;
        return DeeCard(
          entry: e,
          read: _readIds.contains(e.id),
          onMarkRead: () => _markRead(e.id),
        );
      },
    );
  }
}

/// Card rendering a message Mike sent via the Reply composer. Visually
/// mirrors DeeCard but right-aligned with a "you said" label so the stream
/// reads as a back-and-forth.
class YouSaidCard extends StatelessWidget {
  final YouSaidEntry entry;
  const YouSaidCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('h:mm:ss a');
    final ts = fmt.format(entry.sentAt);
    final isFailed = entry.status == 'failed';
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 6, 12, 6),
      child: Card(
        key: const Key('you_said_card'),
        color: isFailed
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    isFailed ? Icons.error_outline : Icons.check_circle_outline,
                    size: 14,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isFailed ? 'failed · $ts' : 'you said · $ts',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SelectableText(
                entry.body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                textAlign: TextAlign.end,
              ),
              if (entry.error != null) ...[
                const SizedBox(height: 4),
                SelectableText(
                  entry.error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final Map<String, String> attemptErrors;
  final VoidCallback onRetry;
  final VoidCallback onEditUrl;
  const _ErrorCard({
    required this.message,
    required this.attemptErrors,
    required this.onRetry,
    required this.onEditUrl,
  });

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
            SelectableText('Relay error',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: Colors.white)),
            const SizedBox(height: 6),
            SelectableText(message,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
            if (attemptErrors.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText('Attempts:',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: Colors.white70)),
              for (final entry in attemptErrors.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: SelectableText(
                    '• ${entry.key} → ${entry.value}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onEditUrl,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('Edit URL'),
                ),
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DeeCard extends StatefulWidget {
  final DeeSaidEntry entry;
  final bool read;
  final VoidCallback onMarkRead;
  final bool initiallyExpanded;
  const DeeCard({
    super.key,
    required this.entry,
    required this.read,
    required this.onMarkRead,
    this.initiallyExpanded = false,
  });

  @override
  State<DeeCard> createState() => _DeeCardState();
}

class _DeeCardState extends State<DeeCard> {
  late bool _expanded = widget.initiallyExpanded;

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
                          SelectableText(
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
                        SelectableText(
                          widget.entry.firstLine,
                          maxLines: _expanded ? null : 2,
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
            // Bug D fix: long expanded bodies overflowed past the visible
            // viewport with no scroll affordance. Cap the body to ~55% of
            // screen height and put it inside a scrollbar-decorated
            // SingleChildScrollView so the user has a clear scroll handle.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final seg in segmented.segments)
                        _SegmentBlock(seg: seg),
                      if (hasOpenItems) ...[
                        const SizedBox(height: 8),
                        SelectableText('Open items',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        for (final item in segmented.openItems)
                          _OpenItemTile(item: item),
                      ],
                    ],
                  ),
                ),
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
      child: SelectableText('$count open',
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
                    label: SelectableText(c),
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

class _RelayUrlDialog extends StatefulWidget {
  final String initial;
  final List<String> candidates;
  const _RelayUrlDialog({required this.initial, required this.candidates});

  @override
  State<_RelayUrlDialog> createState() => _RelayUrlDialogState();
}

class _RelayUrlDialogState extends State<_RelayUrlDialog> {
  late final TextEditingController _ctrl;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
      _testOk = false;
    });
    final probe = RelayResolver(
      userUrl: _ctrl.text.trim(),
      candidates: const [],
    );
    final err = await probe.probeOne(_ctrl.text.trim());
    probe.close();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = err == null;
      _testResult = err ?? 'OK — relay reachable';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Relay URL'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'http://host:3333',
              helperText: 'Leave empty to auto-try LAN/Tailscale fallbacks.',
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            'Auto-tried fallbacks (in order):',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          for (final c in widget.candidates)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: GestureDetector(
                onTap: () => setState(() => _ctrl.text = c),
                child: SelectableText(
                  '  • $c',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          if (_testResult != null) ...[
            const SizedBox(height: 12),
            SelectableText(
              _testResult!,
              style: TextStyle(
                color: _testOk ? Colors.green.shade300 : Colors.red.shade300,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _testing ? null : _test,
          child: _testing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Test'),
        ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
            child: const Text('Save')),
      ],
    );
  }
}
