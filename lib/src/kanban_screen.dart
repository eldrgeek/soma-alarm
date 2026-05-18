import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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

  Widget _projectCard(
      BuildContext ctx, Map<String, dynamic> p, Color accent) {
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
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  if (actions > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
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
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade400),
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
                          fontSize: 10,
                          color: Colors.grey,
                          fontFamily: 'monospace'),
                    ),
                  const Spacer(),
                  if (owner.isNotEmpty)
                    Text(
                      owner,
                      style: TextStyle(
                          fontSize: 10, color: accent.withValues(alpha: 0.8)),
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
    final name = p['name'] as String? ?? '—';
    final desc = p['description'] as String? ?? '';
    final lastTouched = p['last_touched'] as String? ?? '';
    final owner = p['owner'] as String? ?? '';
    final status = p['status'] as String? ?? '';
    final actions =
        (p['open_mike_actions'] as List?)?.map((e) => e.toString()).toList() ??
            [];
    final artifact = p['recent_artifact'] as String? ?? '';
    final cost = p['cost_to_date_usd'];

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Theme.of(ctx).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.92,
        builder: (_, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
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
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 4),
            Row(
              children: [
                _chip(status, _columnColors[_columnFor(status)]),
                const SizedBox(width: 8),
                if (owner.isNotEmpty) _chip(owner, Colors.grey),
              ],
            ),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(desc,
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade300)),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Open Mike actions',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
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
                            child: Text(a,
                                style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  )),
            ],
            const SizedBox(height: 16),
            if (lastTouched.isNotEmpty)
              _metaRow('Last touched', lastTouched),
            if (artifact.isNotEmpty)
              _metaRow('Recent artifact', artifact,
                  mono: true, maxLines: 2),
            if (cost != null)
              _metaRow('Cost to date', '\$${cost.toStringAsFixed(2)}'),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500)),
      );

  Widget _metaRow(String label, String value,
      {bool mono = false, int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500)),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                    fontSize: 11,
                    fontFamily: mono ? 'monospace' : null),
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}
