import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

import 'settings.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  List<Map<String, dynamic>> _items = [];
  String? _error;
  Timer? _pollTimer;
  bool _fetching = false;

  Map<String, dynamic>? _selected;
  String? _content;
  bool _loadingDetail = false;

  String _base = Settings.defaultYeshieHost;

  @override
  void initState() {
    super.initState();
    _loadHost().then((_) {
      _poll();
      _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _poll());
    });
  }

  Future<void> _loadHost() async {
    final host = await Settings.yeshieHost();
    if (mounted) setState(() => _base = host);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final resp = await http
          .get(Uri.parse('$_base/artifacts/activity?limit=60'))
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          _items = (data['items'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          _error = null;
        });
      } else {
        setState(() => _error = 'HTTP ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _fetching = false;
    }
  }

  Future<void> _loadDetail(Map<String, dynamic> item) async {
    setState(() {
      _selected = item;
      _content = null;
      _loadingDetail = true;
    });
    final filePath = item['path'] as String? ?? '';
    try {
      final resp = await http
          .get(Uri.parse(
              '$_base/artifacts/file?path=${Uri.encodeQueryComponent(filePath)}'))
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        _content = resp.statusCode == 200
            ? resp.body
            : 'Error: HTTP ${resp.statusCode}';
      });
    } catch (e) {
      if (mounted) setState(() => _content = 'Failed to load: $e');
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  void _closeDetail() => setState(() {
        _selected = null;
        _content = null;
      });

  @override
  Widget build(BuildContext context) => SelectionArea(
        child: _selected != null ? _buildDetail(context) : _buildList(context),
      );

  Widget _buildList(BuildContext context) {
    if (_error != null && _items.isEmpty) {
      return Center(
          child: Text('Error: $_error',
              style: const TextStyle(color: Colors.red)));
    }
    if (_items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pulse — Activity'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _poll,
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        itemBuilder: (ctx, i) => _ActivityCard(
          item: _items[i],
          onTap: () => _loadDetail(_items[i]),
        ),
      ),
    );
  }

  Widget _buildDetail(BuildContext context) {
    final item = _selected!;
    final name = item['name'] as String? ?? '';
    final kind = item['kind'] as String? ?? '';
    final isLog = kind == 'log';

    Widget body;
    if (_loadingDetail) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_content == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (isLog) {
      // Monospace for logs
      body = Container(
        color: const Color(0xFF0D0D0D),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            _content!,
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFFD4D4D4),
                height: 1.4),
          ),
        ),
      );
    } else {
      body = Markdown(data: _content!, selectable: true);
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _closeDetail,
        ),
        title: Text(name,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            overflow: TextOverflow.ellipsis),
        actions: [
          _KindBadge(kind: kind),
          const SizedBox(width: 12),
        ],
      ),
      body: body,
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  const _ActivityCard({required this.item, required this.onTap});

  String _age(String? mtimeStr) {
    if (mtimeStr == null) return '';
    final mtime = DateTime.tryParse(mtimeStr);
    if (mtime == null) return '';
    final diff = DateTime.now().toUtc().difference(mtime);
    if (diff.inDays > 1) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  @override
  Widget build(BuildContext context) {
    final name = item['name'] as String? ?? '';
    final kind = item['kind'] as String? ?? '';
    final mtime = item['mtime'] as String?;
    final sizeBytes = item['size_bytes'] as int?;
    final sizeStr = sizeBytes != null
        ? '${(sizeBytes / 1024).toStringAsFixed(1)} KB'
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _KindBadge(kind: kind),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                    if (mtime != null || sizeStr.isNotEmpty)
                      Text(
                        [_age(mtime), if (sizeStr.isNotEmpty) sizeStr]
                            .where((s) => s.isNotEmpty)
                            .join(' · '),
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  final String kind;
  const _KindBadge({required this.kind});

  Color _color() => switch (kind) {
        'audit' => Colors.blue,
        'log' => Colors.grey,
        'report' => Colors.green,
        'spec' => Colors.orange,
        'wall' => Colors.purple,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _color().withOpacity(0.15),
        border: Border.all(color: _color().withOpacity(0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(kind,
          style: TextStyle(
              fontSize: 10,
              color: _color(),
              fontWeight: FontWeight.w600)),
    );
  }
}
