import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'settings.dart';

class PutoffScreen extends StatefulWidget {
  const PutoffScreen({super.key});

  @override
  State<PutoffScreen> createState() => _PutoffScreenState();
}

class _PutoffScreenState extends State<PutoffScreen> {
  List<Map<String, dynamic>> _items = [];
  String? _error;
  bool _loading = true;

  Map<String, dynamic>? _selected;

  String _base = Settings.defaultYeshieHost;
  static const _queuePath = '~/Projects/SOMA/state/putoff-queue.json';

  @override
  void initState() {
    super.initState();
    _loadHost().then((_) => _load());
  }

  Future<void> _loadHost() async {
    final host = await Settings.yeshieHost();
    if (mounted) setState(() => _base = host);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await http
          .get(Uri.parse(
              '$_base/artifacts/file?path=${Uri.encodeQueryComponent(_queuePath)}'))
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
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      _selected != null ? _buildDetail(context) : _buildList(context);

  Widget _buildList(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child: Text('Error: $_error',
              style: const TextStyle(color: Colors.red)));
    }
    if (_items.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Pulse — Putoff Queue'),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh), onPressed: _load),
          ],
        ),
        body: const Center(child: Text('Queue is empty')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Pulse — Putoff Queue (${_items.length})'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        itemBuilder: (ctx, i) => _PutoffCard(
          item: _items[i],
          onTap: () => setState(() => _selected = _items[i]),
        ),
      ),
    );
  }

  Widget _buildDetail(BuildContext context) {
    final item = _selected!;
    final title = item['title'] as String? ?? '';
    final status = item['status'] as String? ?? 'open';
    final rawInput = item['raw_input'] as String? ?? '';
    final notes = item['notes'] as String? ?? '';
    final blockedOn =
        List<String>.from(item['blocked_on'] as List? ?? []);
    final addedTs = item['added_ts'] as String?;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _selected = null),
        ),
        title: Text(title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14)),
        actions: [
          _StatusPill(status: status),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (addedTs != null)
              Text('Added: $addedTs',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            _Section(
              label: 'Original request',
              child: Text(rawInput,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            ),
            if (blockedOn.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Section(
                label: 'Blocked on',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: blockedOn
                      .map((b) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• ',
                                    style:
                                        TextStyle(color: Colors.orange)),
                                Expanded(child: Text(b)),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
            ],
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Section(
                label: 'Notes',
                child: Text(notes,
                    style:
                        const TextStyle(fontSize: 13, color: Colors.grey)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PutoffCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  const _PutoffCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = item['title'] as String? ?? '';
    final status = item['status'] as String? ?? 'open';
    final blockedOn = List<String>.from(item['blocked_on'] as List? ?? []);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.pause_circle_outline,
                  color: Colors.orange, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                    if (blockedOn.isNotEmpty)
                      Text('Blocked on ${blockedOn.length} item(s)',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.orange)),
                  ],
                ),
              ),
              _StatusPill(status: status),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  Color get _color => switch (status) {
        'open' => Colors.orange,
        'done' => Colors.green,
        'cancelled' => Colors.grey,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.15),
        border: Border.all(color: _color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(status,
          style: TextStyle(
              color: _color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final Widget child;
  const _Section({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 10,
                color: Colors.grey,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
