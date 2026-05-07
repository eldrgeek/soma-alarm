import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../settings.dart';
import 'dee_reactions.dart';
import 'dee_said_client.dart';
import 'dee_said_models.dart';
import 'dee_said_segmenter.dart';
import 'dee_segment_bar.dart';
import 'relay_resolver.dart';

class DeeStreamPage extends StatefulWidget {
  const DeeStreamPage({super.key});

  @override
  State<DeeStreamPage> createState() => _DeeStreamPageState();
}

class _DeeStreamPageState extends State<DeeStreamPage> {
  static const Duration _pollInterval = Duration(seconds: 10);

  DeeSaidClient? _client;
  RelayResolver? _resolver;
  String? _userUrl;
  Timer? _timer;
  List<DeeSaidEntry> _entries = [];
  final Set<String> _readIds = <String>{};
  String? _lastError;
  Map<String, String> _attemptErrors = const {};
  bool _loading = true;
  final ReactionsRepo _reactions = ReactionsRepo();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _client?.close();
    _resolver?.close();
    _reactions.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final url = await Settings.relayUrl();
    if (!mounted) return;
    final resolver = RelayResolver(
      userUrl: url,
      candidates: kDefaultRelayCandidates,
    );
    setState(() {
      _userUrl = url;
      _resolver = resolver;
      _client = DeeSaidClient(resolver: resolver);
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
    );
  }

  Widget _buildBody() {
    if (_loading && _entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_entries.isEmpty) {
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
          return _ErrorCard(
            message: _lastError!,
            attemptErrors: _attemptErrors,
            onRetry: _refresh,
            onEditUrl: _editRelayUrl,
          );
        }
        final idx = _lastError != null ? i - 1 : i;
        final e = _entries[idx];
        return DeeCard(
          entry: e,
          read: _readIds.contains(e.id),
          onMarkRead: () => _markRead(e.id),
          reactions: _reactions,
          client: _client,
        );
      },
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
  final ReactionsRepo? reactions;
  final DeeSaidClient? client;
  const DeeCard({
    super.key,
    required this.entry,
    required this.read,
    required this.onMarkRead,
    this.initiallyExpanded = false,
    this.reactions,
    this.client,
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
                        _SegmentBlock(
                          seg: seg,
                          entryId: widget.entry.id,
                          reactions: widget.reactions,
                          client: widget.client,
                        ),
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

class _SegmentBlock extends StatefulWidget {
  final MessageSegment seg;
  final String entryId;
  final ReactionsRepo? reactions;
  final DeeSaidClient? client;
  const _SegmentBlock({
    required this.seg,
    required this.entryId,
    this.reactions,
    this.client,
  });

  @override
  State<_SegmentBlock> createState() => _SegmentBlockState();
}

class _SegmentBlockState extends State<_SegmentBlock> {
  SegmentReaction _reaction = const SegmentReaction();
  StreamSubscription<void>? _sub;

  String get _segId => widget.seg.idFor(widget.entryId);

  @override
  void initState() {
    super.initState();
    _load();
    _sub = widget.reactions?.changes.listen((_) => _load());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = widget.reactions;
    if (repo == null) return;
    final r = await repo.get(_segId);
    if (!mounted) return;
    setState(() => _reaction = r);
  }

  Future<void> _onTap(String token) async {
    final repo = widget.reactions;
    if (repo == null) return;
    final next = await repo.toggle(_segId, token);
    if (mounted) setState(() => _reaction = next);
    // Only POST to relay if the token is now present (a "set", not an unset)
    // and it isn't the thread token (thread sends its body via _onSubmitThread).
    if (token != Reaction.thread && next.tokens.contains(token)) {
      _firePostReaction(token);
    }
  }

  Future<void> _onSubmitThread(String note) async {
    final repo = widget.reactions;
    if (repo == null) return;
    await repo.setNote(_segId, note);
    if (mounted) {
      setState(() => _reaction = _reaction.withNote(note));
    }
    _firePostReaction(Reaction.thread, note: note);
  }

  void _firePostReaction(String token, {String? note}) {
    final c = widget.client;
    if (c == null) return;
    // Fire-and-forget: local persistence is the source of truth; relay is
    // a best-effort signal back to Dee. Swallow errors silently.
    unawaited(c.postReaction(
      segmentId: _segId,
      deeMessageId: widget.entryId,
      reaction: token,
      note: note,
      segmentText: widget.seg.text,
    ).catchError((_) {}));
  }

  Future<void> _onFourButton(String choice) async {
    final repo = widget.reactions;
    if (repo == null) return;
    // Store the choice as the note so a single text field captures it; also
    // set a token so the chip stays selected on rebuild.
    final next = SegmentReaction(tokens: {'reply:$choice'}, note: null);
    await repo.set(_segId, next);
    if (mounted) setState(() => _reaction = next);
    final c = widget.client;
    if (c != null) {
      unawaited(c.postReaction(
        segmentId: _segId,
        deeMessageId: widget.entryId,
        reaction: 'reply:$choice',
        segmentText: widget.seg.text,
      ).catchError((_) {}));
    }
  }

  String? get _selectedFourButton {
    for (final t in _reaction.tokens) {
      if (t.startsWith('reply:')) return t.substring('reply:'.length);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFourButton = isFourButtonSegment(widget.seg.text);
    return Container(
      key: Key('segment-block-${widget.seg.index}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.seg.heading != null && widget.seg.heading!.isNotEmpty) ...[
            SelectableText(widget.seg.heading!,
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
          ],
          SelectableText(widget.seg.text, style: theme.textTheme.bodyMedium),
          if (widget.reactions != null)
            isFourButton
                ? FourButtonReplyBar(
                    selected: _selectedFourButton,
                    onChoose: _onFourButton,
                  )
                : SegmentResponseBar(
                    current: _reaction,
                    onTap: _onTap,
                    onSubmitThread: _onSubmitThread,
                  ),
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
