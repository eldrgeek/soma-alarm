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

  // Filter state
  String _statusFilter = 'All'; // All | Running | Complete | Failed
  Set<String> _selectedTags = {}; // empty = all tags shown
  List<String> _availableTags = [];
  Map<String, int> _tagCounts = {};

  // Detail state
  Map<String, dynamic>? _selectedJob;
  String? _reportContent; // markdown for completed jobs
  String? _logContent;    // tail for running jobs
  bool _loadingDetail = false;
  Timer? _logTailTimer;

  static const _base = 'http://localhost:3333';

  @override
  void initState() {
    super.initState();
    _poll();
    _fetchTags();
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final interval =
        (_selectedJob != null && _selectedJob!['status'] == 'running') ? 2 : 5;
    _pollTimer = Timer.periodic(Duration(seconds: interval), (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _logTailTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchTags() async {
    try {
      final resp = await http
          .get(Uri.parse('$_base/artifacts/tags'))
          .timeout(const Duration(seconds: 4));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          _availableTags = List<String>.from(data['tags'] as List? ?? []);
          _tagCounts = Map<String, int>.from(
              (data['counts'] as Map<String, dynamic>? ?? {})
                  .map((k, v) => MapEntry(k, v as int)));
        });
      }
    } catch (_) {}
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
            // Job finished — swap to report view
            setState(() {
              _selectedJob = updated;
              _logContent = null;
            });
            _stopLogTail();
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

  Future<void> _fetchLogTail() async {
    final job = _selectedJob;
    if (job == null || job['status'] != 'running') return;
    final logPath = job['log_path'] as String?;
    if (logPath == null) return;
    try {
      final resp = await http
          .get(Uri.parse(
              '$_base/artifacts/file?path=${Uri.encodeQueryComponent(logPath)}&tail=100'))
          .timeout(const Duration(seconds: 4));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() => _logContent = resp.body);
      }
    } catch (_) {}
  }

  void _startLogTail() {
    _logTailTimer?.cancel();
    _fetchLogTail();
    _logTailTimer = Timer.periodic(const Duration(seconds: 2), (_) => _fetchLogTail());
  }

  void _stopLogTail() {
    _logTailTimer?.cancel();
    _logTailTimer = null;
  }

  void _openDetail(Map<String, dynamic> job) {
    setState(() {
      _selectedJob = job;
      _reportContent = null;
      _logContent = null;
    });
    _startPolling();
    if (job['status'] == 'running') {
      _startLogTail();
    } else if (job['report_path'] != null) {
      _stopLogTail();
      _loadDetail(job['report_path'] as String);
    }
  }

  void _closeDetail() {
    _stopLogTail();
    setState(() {
      _selectedJob = null;
      _reportContent = null;
      _logContent = null;
    });
    _startPolling();
  }

  List<Map<String, dynamic>> get _filteredItems {
    return _items.where((job) {
      // Status filter
      if (_statusFilter != 'All') {
        final status = job['status'] as String? ?? '';
        if (status.toLowerCase() != _statusFilter.toLowerCase()) return false;
      }
      // Tag filter (multi-select OR logic)
      if (_selectedTags.isNotEmpty) {
        final tags = List<String>.from(job['tags'] as List? ?? []);
        if (!tags.any((t) => _selectedTags.contains(t))) return false;
      }
      return true;
    }).toList();
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

    final filtered = _filteredItems;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pulse — Jobs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              _poll();
              _fetchTags();
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status filter chips
          _StatusFilterRow(
            selected: _statusFilter,
            onSelected: (s) => setState(() => _statusFilter = s),
            items: _items,
          ),
          // Tag filter chips
          if (_availableTags.isNotEmpty)
            _TagFilterRow(
              tags: _availableTags,
              counts: _tagCounts,
              selected: _selectedTags,
              onChanged: (tags) => setState(() => _selectedTags = tags),
            ),
          // Jobs list
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No jobs match filters'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) => _JobCard(
                      job: filtered[i],
                      onTap: () => _openDetail(filtered[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetail(BuildContext context) {
    final job = _selectedJob!;
    final status = job['status'] as String? ?? 'unknown';
    final color = _jobStatusColor(status);
    final isRunning = status == 'running';

    // Compute elapsed
    String elapsed = '';
    final startedAt = job['started_at'] as String?;
    final finishedAt = job['finished_at'] as String?;
    if (startedAt != null) {
      final start = DateTime.tryParse(startedAt);
      if (start != null) {
        final end = finishedAt != null
            ? (DateTime.tryParse(finishedAt) ?? DateTime.now().toUtc())
            : DateTime.now().toUtc();
        final diff = end.difference(start);
        if (diff.inHours > 0) {
          elapsed = '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
        } else if (diff.inMinutes > 0) {
          elapsed = '${diff.inMinutes}m ${diff.inSeconds.remainder(60)}s';
        } else {
          elapsed = '${diff.inSeconds}s';
        }
      }
    }

    Widget body;
    if (isRunning) {
      // Log tail view
      body = _LogTailView(
        logContent: _logContent,
        taskName: job['task_name'] as String? ?? '',
        elapsed: elapsed,
      );
    } else if (_loadingDetail) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_reportContent != null) {
      body = Markdown(data: _reportContent!, selectable: true);
    } else {
      body = const Center(child: CircularProgressIndicator());
    }

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
          if (elapsed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Text(elapsed,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          _StatusPill(status: status, color: color),
          const SizedBox(width: 12),
        ],
      ),
      body: body,
    );
  }
}

// ── Status filter row ───────────────────────────────────────────────────────

class _StatusFilterRow extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;
  final List<Map<String, dynamic>> items;

  const _StatusFilterRow({
    required this.selected,
    required this.onSelected,
    required this.items,
  });

  int _count(String status) {
    if (status == 'All') return items.length;
    return items
        .where((j) => (j['status'] as String? ?? '') == status.toLowerCase())
        .length;
  }

  @override
  Widget build(BuildContext context) {
    const statuses = ['All', 'Running', 'Complete', 'Failed'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: statuses.map((s) {
          final isSelected = selected == s;
          final count = _count(s);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text('$s ($count)'),
              selected: isSelected,
              onSelected: (_) => onSelected(s),
              showCheckmark: false,
              selectedColor: Theme.of(context).colorScheme.primaryContainer,
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Tag filter row ──────────────────────────────────────────────────────────

class _TagFilterRow extends StatelessWidget {
  final List<String> tags;
  final Map<String, int> counts;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  const _TagFilterRow({
    required this.tags,
    required this.counts,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
      child: Row(
        children: [
          const Text('Tag: ',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          ...tags.map((tag) {
            final isSelected = selected.contains(tag);
            final count = counts[tag] ?? 0;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text('$tag ($count)'),
                selected: isSelected,
                onSelected: (on) {
                  final next = Set<String>.from(selected);
                  if (on) {
                    next.add(tag);
                  } else {
                    next.remove(tag);
                  }
                  onChanged(next);
                },
                showCheckmark: false,
                selectedColor:
                    Theme.of(context).colorScheme.secondaryContainer,
                labelStyle: TextStyle(
                  fontSize: 11,
                  color: isSelected
                      ? Theme.of(context).colorScheme.onSecondaryContainer
                      : null,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Log tail view ───────────────────────────────────────────────────────────

class _LogTailView extends StatefulWidget {
  final String? logContent;
  final String taskName;
  final String elapsed;

  const _LogTailView({
    required this.logContent,
    required this.taskName,
    required this.elapsed,
  });

  @override
  State<_LogTailView> createState() => _LogTailViewState();
}

class _LogTailViewState extends State<_LogTailView> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(_LogTailView old) {
    super.didUpdateWidget(old);
    if (widget.logContent != old.logContent && widget.logContent != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.logContent == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      color: const Color(0xFF0D0D0D),
      child: Scrollbar(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            widget.logContent!,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Color(0xFFD4D4D4),
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Job card ────────────────────────────────────────────────────────────────

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
    final tags = List<String>.from(job['tags'] as List? ?? []);

    String elapsed = '';
    if (startedAt != null) {
      final start = DateTime.tryParse(startedAt);
      if (start != null) {
        final end = finishedAt != null
            ? (DateTime.tryParse(finishedAt) ?? DateTime.now())
            : DateTime.now().toUtc();
        final diff = end.difference(start);
        if (diff.inHours > 0) {
          elapsed = '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
        } else if (diff.inMinutes > 0) {
          elapsed = '${diff.inMinutes}m ${diff.inSeconds.remainder(60)}s';
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
                    if (tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 4,
                          children: tags
                              .map((t) => _TagBadge(tag: t))
                              .toList(),
                        ),
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

class _TagBadge extends StatelessWidget {
  final String tag;
  const _TagBadge({required this.tag});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(tag,
          style: const TextStyle(fontSize: 10, color: Colors.grey)),
    );
  }
}

// ── Status pill ─────────────────────────────────────────────────────────────

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
