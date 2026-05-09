import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

Color _jobStatusColor(String status) => switch (status) {
      'complete' => Colors.green,
      'running' => Colors.blue,
      'failed' => Colors.red,
      _ => Colors.grey,
    };

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  List<Map<String, dynamic>> _items = [];
  String? _error;
  Timer? _pollTimer;
  bool _fetching = false;

  Map<String, dynamic>? _selectedJob;
  String? _reportContent;
  bool _loadingDetail = false;

  static const _base = 'http://localhost:3333';

  @override
  void initState() {
    super.initState();
    _poll();
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final interval =
        (_selectedJob != null && _selectedJob!['status'] == 'running') ? 2 : 5;
    _pollTimer =
        Timer.periodic(Duration(seconds: interval), (_) => _poll());
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
          .get(Uri.parse('$_base/artifacts/cc-dispatch?limit=50'))
          .timeout(const Duration(seconds: 4));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final items = (data['items'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        setState(() {
          _items = items;
          _error = null;
        });
        // Refresh detail if viewing a running job that just completed
        if (_selectedJob != null) {
          final updated = items.firstWhere(
            (j) =>
                j['task_name'] == _selectedJob!['task_name'] &&
                j['started_at'] == _selectedJob!['started_at'],
            orElse: () => _selectedJob!,
          );
          if (updated['status'] != _selectedJob!['status'] &&
              updated['report_path'] != null) {
            setState(() => _selectedJob = updated);
            _loadDetail(updated['report_path'] as String);
          }
        }
      } else {
        setState(() => _error = 'HTTP ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _fetching = false;
    }
  }

  Future<void> _loadDetail(String reportPath) async {
    setState(() => _loadingDetail = true);
    try {
      final resp = await http
          .get(Uri.parse(
              '$_base/artifacts/file?path=${Uri.encodeQueryComponent(reportPath)}'))
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        _reportContent = resp.statusCode == 200
            ? resp.body
            : 'Error loading report: HTTP ${resp.statusCode}';
      });
    } catch (e) {
      if (mounted) setState(() => _reportContent = 'Failed to load: $e');
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  void _openDetail(Map<String, dynamic> job) {
    setState(() {
      _selectedJob = job;
      _reportContent = null;
    });
    _startPolling();
    if (job['report_path'] != null) {
      _loadDetail(job['report_path'] as String);
    }
  }

  void _closeDetail() {
    setState(() {
      _selectedJob = null;
      _reportContent = null;
    });
    _startPolling();
  }

  @override
  Widget build(BuildContext context) {
    return _selectedJob != null ? _buildDetail(context) : _buildList(context);
  }

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
        title: const Text('Pulse — Jobs'),
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
        itemBuilder: (ctx, i) => _JobCard(
          job: _items[i],
          onTap: () => _openDetail(_items[i]),
        ),
      ),
    );
  }

  Widget _buildDetail(BuildContext context) {
    final job = _selectedJob!;
    final status = job['status'] as String? ?? 'unknown';
    final color = _jobStatusColor(status);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _closeDetail,
        ),
        title: Text(
          job['task_name'] as String? ?? '',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          _StatusPill(status: status, color: color),
          const SizedBox(width: 12),
        ],
      ),
      body: _loadingDetail
          ? const Center(child: CircularProgressIndicator())
          : job['report_path'] == null
              ? const Center(child: Text('No report yet — job still running'))
              : _reportContent == null
                  ? const Center(child: CircularProgressIndicator())
                  : Markdown(
                      data: _reportContent!,
                      selectable: true,
                    ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final VoidCallback onTap;

  const _JobCard({required this.job, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = job['status'] as String? ?? 'unknown';
    final color = _jobStatusColor(status);
    final taskName = job['task_name'] as String? ?? '';
    final startedAt = job['started_at'] as String?;
    final finishedAt = job['finished_at'] as String?;
    final sizeBytes = job['size_bytes'] as int?;

    String elapsed = '';
    if (startedAt != null) {
      final start = DateTime.tryParse(startedAt);
      if (start != null) {
        final end = finishedAt != null
            ? (DateTime.tryParse(finishedAt) ?? DateTime.now())
            : DateTime.now().toUtc();
        final diff = end.difference(start);
        if (diff.inHours > 0) {
          elapsed =
              '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
        } else if (diff.inMinutes > 0) {
          elapsed =
              '${diff.inMinutes}m ${diff.inSeconds.remainder(60)}s';
        } else {
          elapsed = '${diff.inSeconds}s';
        }
      }
    }

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
              Icon(Icons.circle, color: color, size: 10),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      taskName,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (elapsed.isNotEmpty || sizeStr.isNotEmpty)
                      Text(
                        [
                          if (elapsed.isNotEmpty) elapsed,
                          if (sizeStr.isNotEmpty) sizeStr,
                        ].join(' · '),
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey),
                      ),
                  ],
                ),
              ),
              _StatusPill(status: status, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  final Color color;

  const _StatusPill({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
