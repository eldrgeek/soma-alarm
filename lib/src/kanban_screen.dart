import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'settings.dart';

// Status → column index
int _columnFor(String status) => switch (status.toLowerCase()) {
      'active' => 0,
      'awaiting mike' => 1,
      'blocked' => 2,
      _ => 3, // Parked / Done
    };

const _columnLabels = ['Active', 'Awaiting Mike', 'Blocked', 'Parked / Done'];
const _columnColors = [Colors.tealAccent, Colors.amberAccent, Colors.redAccent, Colors.grey];

// ── Inline text segmentation ─────────────────────────────────────────────────

enum _SegKind { plain, mention, project }

class _TextSeg {
  final String text;
  final _SegKind kind;
  final Map<String, dynamic>? project;
  const _TextSeg(this.text, this.kind, [this.project]);
}

List<_TextSeg> _parseSegments(
  String text,
  List<Map<String, dynamic>> allProjects,
) {
  if (text.isEmpty) return [_TextSeg(text, _SegKind.plain)];

  // Sort project names longest-first for greedy matching.
  final names = allProjects
      .where((p) => (p['name'] as String? ?? '').isNotEmpty)
      .map((p) => (p['name'] as String, p))
      .toList()
    ..sort((a, b) => b.$1.length.compareTo(a.$1.length));

  final segs = <_TextSeg>[];
  int pos = 0;

  void appendPlain(String ch) {
    if (segs.isNotEmpty && segs.last.kind == _SegKind.plain) {
      final last = segs.removeLast();
      segs.add(_TextSeg(last.text + ch, _SegKind.plain));
    } else {
      segs.add(_TextSeg(ch, _SegKind.plain));
    }
  }

  while (pos < text.length) {
    // @mention
    if (text[pos] == '@') {
      int end = pos + 1;
      while (end < text.length && RegExp(r'[a-zA-Z0-9_-]').hasMatch(text[end])) {
        end++;
      }
      if (end > pos + 1) {
        segs.add(_TextSeg(text.substring(pos, end), _SegKind.mention));
        pos = end;
        continue;
      }
    }

    // Project name match (case-insensitive)
    bool found = false;
    for (final (name, proj) in names) {
      final end = pos + name.length;
      if (end <= text.length &&
          text.substring(pos, end).toLowerCase() == name.toLowerCase()) {
        segs.add(_TextSeg(text.substring(pos, end), _SegKind.project, proj));
        pos = end;
        found = true;
        break;
      }
    }
    if (found) continue;

    appendPlain(text[pos]);
    pos++;
  }

  return segs;
}

Widget _buildLinkedText(
  String text,
  TextStyle baseStyle, {
  required List<Map<String, dynamic>> allProjects,
  required void Function(String name) onMention,
  required void Function(Map<String, dynamic> project) onProject,
}) {
  final segs = _parseSegments(text, allProjects);
  if (segs.every((s) => s.kind == _SegKind.plain)) {
    return Text(text, style: baseStyle);
  }
  return Text.rich(
    TextSpan(
      children: segs.map((seg) {
        switch (seg.kind) {
          case _SegKind.plain:
            return TextSpan(text: seg.text, style: baseStyle);
          case _SegKind.mention:
            return WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: () => onMention(seg.text.substring(1)),
                child: Text(
                  seg.text,
                  style: baseStyle.copyWith(
                    color: Colors.tealAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          case _SegKind.project:
            return WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: () => onProject(seg.project!),
                child: Text(
                  seg.text,
                  style: baseStyle.copyWith(
                    color: Colors.amberAccent,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.amberAccent.withValues(alpha: 0.5),
                  ),
                ),
              ),
            );
        }
      }).toList(),
    ),
  );
}

void _showSpecialistBottomSheet(BuildContext ctx, String ownerName) {
  showModalBottomSheet(
    context: ctx,
    backgroundColor: Theme.of(ctx).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline, size: 20, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                ownerName,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Specialist · active in SOMA',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 16),
          Text(
            'Use the reply field on a project card to send a scoped message to $ownerName.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          ),
        ],
      ),
    ),
  );
}

// ── Main Kanban screen ────────────────────────────────────────────────────────

class KanbanScreen extends StatefulWidget {
  const KanbanScreen({super.key});

  @override
  State<KanbanScreen> createState() => _KanbanScreenState();
}

class _KanbanScreenState extends State<KanbanScreen> {
  String _base = Settings.defaultYeshieHost;
  List<Map<String, dynamic>> _projects = [];
  String? _error;
  bool _loading = false;
  Timer? _pollTimer;
  final _pageController = PageController();
  int _currentColumn = 0;

  @override
  void initState() {
    super.initState();
    Settings.yeshieHost().then((h) {
      if (mounted) setState(() => _base = h);
      _fetch();
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _fetch());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (_loading) return;
    if (mounted) setState(() => _loading = true);
    try {
      final resp = await http
          .get(Uri.parse('$_base/pulse/projects'))
          .timeout(const Duration(seconds: 6));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = (data['projects'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        setState(() {
          _projects = list;
          _error = null;
        });
      } else {
        final body = jsonDecode(resp.body) as Map<String, dynamic>? ?? {};
        setState(() => _error = body['error']?.toString() ?? 'HTTP ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _columnProjects(int col) =>
      _projects.where((p) => _columnFor(p['status'] as String? ?? '') == col).toList();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 720;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Board'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _fetch,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade900,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          Expanded(
            child: wide ? _wideLayout() : _narrowLayout(),
          ),
        ],
      ),
    );
  }

  Widget _wideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(4, (i) => Expanded(child: _column(i))),
    );
  }

  Widget _narrowLayout() {
    return Column(
      children: [
        _columnTabBar(),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _currentColumn = i),
            itemCount: 4,
            itemBuilder: (_, i) => _column(i),
          ),
        ),
      ],
    );
  }

  Widget _columnTabBar() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (ctx, i) {
          final selected = _currentColumn == i;
          final count = _columnProjects(i).length;
          return GestureDetector(
            onTap: () => _pageController.animateToPage(
              i,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: selected
                    ? _columnColors[i].withValues(alpha: 0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? _columnColors[i] : Colors.grey.shade700,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Text(
                '${_columnLabels[i]}${count > 0 ? " ($count)" : ""}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? _columnColors[i] : Colors.grey.shade400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _column(int col) {
    final items = _columnProjects(col);
    final accent = _columnColors[col];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _columnLabels[col],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accent,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 6),
              if (items.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${items.length}',
                    style: TextStyle(fontSize: 10, color: accent),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    '(no projects)',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) => _projectCard(ctx, items[i], accent),
                ),
        ),
      ],
    );
  }

  Widget _projectCard(BuildContext ctx, Map<String, dynamic> p, Color accent) {
    final name = p['name'] as String? ?? '—';
    final desc = p['description'] as String? ?? '';
    final lastTouched = p['last_touched'] as String? ?? '';
    final owner = p['owner'] as String? ?? '';
    final actions = (p['open_mike_actions'] as List?)?.length ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showDetail(ctx, p),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  if (actions > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade800,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$actions',
                        style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  if (lastTouched.isNotEmpty)
                    Text(
                      lastTouched,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey, fontFamily: 'monospace'),
                    ),
                  const Spacer(),
                  if (owner.isNotEmpty)
                    GestureDetector(
                      onTap: () => _showSpecialistBottomSheet(ctx, owner),
                      child: Text(
                        owner,
                        style: TextStyle(
                          fontSize: 10,
                          color: accent.withValues(alpha: 0.9),
                          decoration: TextDecoration.underline,
                          decorationColor: accent.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext ctx, Map<String, dynamic> p) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Theme.of(ctx).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _KanbanDetailSheet(
        project: p,
        allProjects: _projects,
        base: _base,
      ),
    );
  }
}

// ── Detail sheet (StatefulWidget for reply composer + draft) ─────────────────

class _KanbanDetailSheet extends StatefulWidget {
  final Map<String, dynamic> project;
  final List<Map<String, dynamic>> allProjects;
  final String base;

  const _KanbanDetailSheet({
    required this.project,
    required this.allProjects,
    required this.base,
  });

  @override
  State<_KanbanDetailSheet> createState() => _KanbanDetailSheetState();
}

class _KanbanDetailSheetState extends State<_KanbanDetailSheet> {
  final _replyController = TextEditingController();
  bool _replySending = false;
  bool _replySent = false;
  Timer? _draftTimer;

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadDraft() async {
    final name = widget.project['name'] as String? ?? '';
    final draft = await Settings.kanbanReplyDraft(name);
    if (mounted && draft.isNotEmpty) {
      _replyController.text = draft;
      _replyController.selection = TextSelection.collapsed(offset: draft.length);
    }
  }

  void _onDraftChanged(String text) {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 500), () {
      final name = widget.project['name'] as String? ?? '';
      Settings.saveKanbanReplyDraft(name, text);
    });
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _replySending) return;

    final name = widget.project['name'] as String? ?? '';
    final owner = widget.project['owner'] as String? ?? 'dee';
    final id = widget.project['id'] as String?;

    setState(() => _replySending = true);
    try {
      final resp = await http
          .post(
            Uri.parse('${widget.base}/dispatch_input'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'body': text,
              'source': 'pulse-kanban-reply',
              'recipient': owner.toLowerCase(),
              'metadata': {
                'project': name,
                if (id != null) 'kanban_card_id': id,
              },
            }),
          )
          .timeout(const Duration(seconds: 6));
      if (!mounted) return;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _replyController.clear();
        await Settings.saveKanbanReplyDraft(name, '');
        setState(() => _replySent = true);
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _replySent = false);
      } else {
        _showSnack('Send failed: HTTP ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) _showSnack('$e');
    } finally {
      if (mounted) setState(() => _replySending = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _openProject(Map<String, dynamic> p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _KanbanDetailSheet(
        project: p,
        allProjects: widget.allProjects,
        base: widget.base,
      ),
    );
  }

  void _openArtifact(String artifact) {
    Clipboard.setData(ClipboardData(text: artifact));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Path copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _chip(String label, Color color, {bool isLink = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isLink ? 0.25 : 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: isLink ? 0.6 : 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w500,
            decoration: isLink ? TextDecoration.underline : null,
            decorationColor: isLink ? color.withValues(alpha: 0.5) : null,
          ),
        ),
      );

  Widget _metaRow(String label, String value, {bool mono = false, int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(fontSize: 11, fontFamily: mono ? 'monospace' : null),
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );

  Widget _metaRowLink(String label, String value, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
            ),
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.tealAccent,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.teal,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final name = p['name'] as String? ?? '—';
    final desc = p['description'] as String? ?? '';
    final lastTouched = p['last_touched'] as String? ?? '';
    final owner = p['owner'] as String? ?? '';
    final status = p['status'] as String? ?? '';
    final actions =
        (p['open_mike_actions'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final artifact = p['recent_artifact'] as String? ?? '';
    final cost = p['cost_to_date_usd'];
    final accent = _columnColors[_columnFor(status)];

    final baseTextStyle = TextStyle(fontSize: 13, color: Colors.grey.shade300);
    const actionTextStyle = TextStyle(fontSize: 13);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.92,
      builder: (_, sc) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade600,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(name,
                    style:
                        const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _chip(status, accent),
                    const SizedBox(width: 8),
                    if (owner.isNotEmpty)
                      GestureDetector(
                        onTap: () => _showSpecialistBottomSheet(context, owner),
                        child: _chip(owner, Colors.grey, isLink: true),
                      ),
                  ],
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildLinkedText(
                    desc,
                    baseTextStyle,
                    allProjects: widget.allProjects,
                    onMention: (n) => _showSpecialistBottomSheet(context, n),
                    onProject: _openProject,
                  ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Open Mike actions',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  ...actions.map((a) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ',
                                style: TextStyle(
                                    color: Colors.orange, fontSize: 13)),
                            Expanded(
                              child: _buildLinkedText(
                                a,
                                actionTextStyle,
                                allProjects: widget.allProjects,
                                onMention: (n) =>
                                    _showSpecialistBottomSheet(context, n),
                                onProject: _openProject,
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
                const SizedBox(height: 16),
                if (lastTouched.isNotEmpty) _metaRow('Last touched', lastTouched),
                if (artifact.isNotEmpty)
                  _metaRowLink(
                      'Recent artifact', artifact, () => _openArtifact(artifact)),
                if (cost != null)
                  _metaRow('Cost to date', '\$${cost.toStringAsFixed(2)}'),
              ],
            ),
          ),
          // Reply composer
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            padding: EdgeInsets.only(
              left: 16,
              right: 8,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    onChanged: _onDraftChanged,
                    decoration: InputDecoration(
                      hintText: 'Reply to $name…',
                      hintStyle: const TextStyle(fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 13),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendReply(),
                    enabled: !_replySending,
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _replySent
                        ? const Icon(Icons.check_circle,
                            key: ValueKey('ok'),
                            color: Colors.green,
                            size: 20)
                        : _replySending
                            ? const SizedBox(
                                key: ValueKey('spin'),
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : IconButton(
                                key: const ValueKey('send'),
                                icon: const Icon(Icons.send, size: 18),
                                tooltip: 'Send reply',
                                onPressed: _sendReply,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
