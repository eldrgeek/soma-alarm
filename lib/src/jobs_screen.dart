import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'settings.dart';

// ── Status helpers ───────────────────────────────────────────────────────────

Color _jobStatusColor(String status) => switch (status) {
      'complete' => Colors.green,
      'running' => Colors.blue,
      'failed' => Colors.red,
      'queued' => Colors.amber,
      'cancelled' => Colors.grey,
      _ => Colors.grey,
    };

// GH API status/conclusion → internal status
String _normalizeGhStatus(String ghStatus, String? ghConclusion) {
  return switch (ghStatus) {
    'in_progress' => 'running',
    'queued' || 'waiting' || 'requested' || 'pending' => 'queued',
    'completed' => switch (ghConclusion) {
        'success' || 'skipped' => 'complete',
        'failure' || 'timed_out' => 'failed',
        _ => 'cancelled',
      },
    _ => 'unknown',
  };
}

Map<String, dynamic> _normalizeGhRun(Map<String, dynamic> run, String repo) {
  final ghStatus = run['status'] as String? ?? '';
  final ghConclusion = run['conclusion'] as String?;
  final status = _normalizeGhStatus(ghStatus, ghConclusion);
  return {
    'source': 'gh-actions',
    'task_name': '${run['name']}',
    'status': status,
    'started_at': run['run_started_at'],
    'finished_at':
        (status == 'running' || status == 'queued') ? null : run['updated_at'],
    'tags': ['gh-actions', repo.split('/').last],
    'run_url': run['html_url'],
    'run_id': run['id'],
    'repo': repo,
    'workflow_name': run['name'] as String? ?? '',
    'gh_status': ghStatus,
    'gh_conclusion': ghConclusion,
    'jobs_url': run['jobs_url'],
  };
}

String _elapsedStr(String? startedAt, String? finishedAt) {
  if (startedAt == null) return '';
  final start = DateTime.tryParse(startedAt);
  if (start == null) return '';
  final end = finishedAt != null
      ? (DateTime.tryParse(finishedAt) ?? DateTime.now().toUtc())
      : DateTime.now().toUtc();
  final diff = end.difference(start);
  if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
  if (diff.inMinutes > 0) return '${diff.inMinutes}m ${diff.inSeconds.remainder(60)}s';
  return '${diff.inSeconds}s';
}

// ── Screen ───────────────────────────────────────────────────────────────────

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  // cc-dispatch state
  List<Map<String, dynamic>> _items = [];
  String? _error;
  Timer? _pollTimer;
  bool _fetching = false;

  // GH Actions state
  List<Map<String, dynamic>> _ghRuns = [];
  String? _ghToken;
  List<String> _ghRepos = [];
  Timer? _ghPollTimer;
  bool _fetchingGh = false;

  // GH run detail state
  List<Map<String, dynamic>> _ghRunJobs = [];
  Set<String> _expandedJobIds = {};
  bool _loadingGhRunJobs = false;

  // Filter state
  String _statusFilter = 'All';
  Set<String> _selectedTags = {};
  List<String> _availableTags = [];
  Map<String, int> _tagCounts = {};

  // Detail state (cc-dispatch)
  Map<String, dynamic>? _selectedJob;
  String? _reportContent;
  String? _logContent;
  bool _loadingDetail = false;
  Timer? _logTailTimer;

  String _base = Settings.defaultYeshieHost;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadSettings().then((_) {
      _poll();
      _fetchTags();
      _startPolling();
      _fetchGhRuns();
      _startGhPolling();
    });
  }

  Future<void> _loadSettings() async {
    final host = await Settings.yeshieHost();
    final token = await Settings.githubToken();
    final repos = await Settings.githubRepos();
    if (mounted) {
      setState(() {
        _base = host;
        _ghToken = token;
        _ghRepos = repos;
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _logTailTimer?.cancel();
    _ghPollTimer?.cancel();
    super.dispose();
  }

  // ── cc-dispatch polling ────────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    final interval =
        (_selectedJob != null && _selectedJob!['status'] == 'running') ? 2 : 5;
    _pollTimer = Timer.periodic(Duration(seconds: interval), (_) => _poll());
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
        // Refresh detail if a running cc-dispatch job just completed
        if (_selectedJob != null &&
            _selectedJob!['source'] != 'gh-actions') {
          final updated = items.firstWhere(
            (j) =>
                j['task_name'] == _selectedJob!['task_name'] &&
                j['started_at'] == _selectedJob!['started_at'],
            orElse: () => _selectedJob!,
          );
          if (updated['status'] != _selectedJob!['status'] &&
              updated['report_path'] != null) {
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
      if (resp.statusCode == 200) setState(() => _logContent = resp.body);
    } catch (_) {}
  }

  void _startLogTail() {
    _logTailTimer?.cancel();
    _fetchLogTail();
    _logTailTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _fetchLogTail());
  }

  void _stopLogTail() {
    _logTailTimer?.cancel();
    _logTailTimer = null;
  }

  // ── GH Actions polling ─────────────────────────────────────────────────────

  void _startGhPolling() {
    _ghPollTimer?.cancel();
    // Rate-limit: poll every 30s; GH API allows 5000 req/h authenticated
    _ghPollTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _fetchGhRuns());
  }

  Future<void> _fetchGhRuns() async {
    final token = _ghToken;
    if (token == null || token.isEmpty || _fetchingGh) return;
    _fetchingGh = true;
    final repos = _ghRepos;
    final allRuns = <Map<String, dynamic>>[];
    for (final repo in repos) {
      try {
        final resp = await http
            .get(
              Uri.parse(
                  'https://api.github.com/repos/$repo/actions/runs?per_page=20'),
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'application/vnd.github+json',
                'X-GitHub-Api-Version': '2022-11-28',
              },
            )
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final runs = (data['workflow_runs'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          for (final run in runs) {
            allRuns.add(_normalizeGhRun(run, repo));
          }
        }
      } catch (_) {}
    }
    allRuns.sort((a, b) {
      final aTs = a['started_at'] as String? ?? '';
      final bTs = b['started_at'] as String? ?? '';
      return bTs.compareTo(aTs);
    });
    _fetchingGh = false;
    if (mounted) setState(() => _ghRuns = allRuns);

    // Refresh detail if selected GH run changed status
    final sel = _selectedJob;
    if (sel != null && sel['source'] == 'gh-actions') {
      final updated = allRuns.firstWhere(
        (r) => r['run_id'] == sel['run_id'],
        orElse: () => sel,
      );
      if (updated['status'] != sel['status']) {
        setState(() => _selectedJob = updated);
        _fetchGhRunJobs(updated);
      }
    }
  }

  Future<void> _fetchGhRunJobs(Map<String, dynamic> run) async {
    final token = _ghToken;
    if (token == null || token.isEmpty) return;
    setState(() {
      _loadingGhRunJobs = true;
      _ghRunJobs = [];
    });
    try {
      final jobsUrl = run['jobs_url'] as String?;
      if (jobsUrl == null) return;
      final resp = await http
          .get(
            Uri.parse(jobsUrl),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final jobs = (data['jobs'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        setState(() => _ghRunJobs = jobs);
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingGhRunJobs = false);
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _allItems {
    final merged = [..._items, ..._ghRuns];
    merged.sort((a, b) {
      final aTs = a['started_at'] as String? ?? '';
      final bTs = b['started_at'] as String? ?? '';
      return bTs.compareTo(aTs);
    });
    return merged;
  }

  List<Map<String, dynamic>> get _filteredItems {
    return _allItems.where((job) {
      if (_statusFilter != 'All') {
        final status = job['status'] as String? ?? '';
        if (status.toLowerCase() != _statusFilter.toLowerCase()) return false;
      }
      if (_selectedTags.isNotEmpty) {
        final tags = List<String>.from(job['tags'] as List? ?? []);
        if (!tags.any((t) => _selectedTags.contains(t))) return false;
      }
      return true;
    }).toList();
  }

  void _openDetail(Map<String, dynamic> job) {
    setState(() {
      _selectedJob = job;
      _reportContent = null;
      _logContent = null;
      _ghRunJobs = [];
      _expandedJobIds = {};
    });
    _startPolling();
    if (job['source'] == 'gh-actions') {
      _stopLogTail();
      _fetchGhRunJobs(job);
    } else if (job['status'] == 'running') {
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
      _ghRunJobs = [];
      _expandedJobIds = {};
    });
    _startPolling();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return _selectedJob != null ? _buildDetail(context) : _buildList(context);
  }

  Widget _buildList(BuildContext context) {
    final all = _allItems;
    if (_error != null && all.isEmpty) {
      return Center(
          child: Text('Error: $_error',
              style: const TextStyle(color: Colors.red)));
    }
    if (all.isEmpty) {
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
              _fetchGhRuns();
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusFilterRow(
            selected: _statusFilter,
            onSelected: (s) => setState(() => _statusFilter = s),
            items: all,
          ),
          if (_availableTags.isNotEmpty)
            _TagFilterRow(
              tags: _availableTags,
              counts: _tagCounts,
              selected: _selectedTags,
              onChanged: (tags) => setState(() => _selectedTags = tags),
            ),
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
    if (job['source'] == 'gh-actions') {
      return _buildGhRunDetail(context, job);
    }
    return _buildDispatchDetail(context, job);
  }

  // ── cc-dispatch detail ─────────────────────────────────────────────────────

  Widget _buildDispatchDetail(
      BuildContext context, Map<String, dynamic> job) {
    final status = job['status'] as String? ?? 'unknown';
    final color = _jobStatusColor(status);
    final elapsed =
        _elapsedStr(job['started_at'] as String?, job['finished_at'] as String?);
    final isRunning = status == 'running';

    Widget body;
    if (isRunning) {
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

  // ── GH Actions run detail ──────────────────────────────────────────────────

  Widget _buildGhRunDetail(BuildContext context, Map<String, dynamic> run) {
    final status = run['status'] as String? ?? 'unknown';
    final color = _jobStatusColor(status);
    final elapsed = _elapsedStr(
        run['started_at'] as String?, run['finished_at'] as String?);
    final runUrl = run['run_url'] as String?;
    final repo = run['repo'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _closeDetail,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              run['workflow_name'] as String? ?? '',
              style: const TextStyle(fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              repo,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          if (elapsed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Text(elapsed,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          _StatusPill(status: status, color: color),
          if (runUrl != null)
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 18),
              tooltip: 'Open in GitHub',
              onPressed: () => launchUrl(Uri.parse(runUrl),
                  mode: LaunchMode.externalApplication),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _GhRunJobsView(
        jobs: _ghRunJobs,
        loading: _loadingGhRunJobs,
        expandedIds: _expandedJobIds,
        onToggle: (id) => setState(() {
          if (_expandedJobIds.contains(id)) {
            _expandedJobIds.remove(id);
          } else {
            _expandedJobIds.add(id);
          }
        }),
        onOpenJob: (url) => launchUrl(Uri.parse(url),
            mode: LaunchMode.externalApplication),
        ghToken: _ghToken,
      ),
    );
  }
}

// ── GH run jobs view ─────────────────────────────────────────────────────────

class _GhRunJobsView extends StatelessWidget {
  final List<Map<String, dynamic>> jobs;
  final bool loading;
  final Set<String> expandedIds;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onOpenJob;
  final String? ghToken;

  const _GhRunJobsView({
    required this.jobs,
    required this.loading,
    required this.expandedIds,
    required this.onToggle,
    required this.onOpenJob,
    required this.ghToken,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (jobs.isEmpty) {
      return const Center(
          child: Text('No jobs found', style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: jobs.length,
      itemBuilder: (ctx, i) {
        final job = jobs[i];
        final jobId = job['id']?.toString() ?? '$i';
        final jobName = job['name'] as String? ?? '';
        final ghStatus = job['status'] as String? ?? '';
        final ghConclusion = job['conclusion'] as String?;
        final status = _normalizeGhStatus(ghStatus, ghConclusion);
        final color = _jobStatusColor(status);
        final elapsed = _elapsedStr(
            job['started_at'] as String?, job['completed_at'] as String?);
        final steps =
            (job['steps'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
                [];
        final isExpanded = expandedIds.contains(jobId);
        final jobHtmlUrl = job['html_url'] as String?;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            children: [
              ListTile(
                dense: true,
                leading: Icon(Icons.circle, color: color, size: 10),
                title: Text(jobName,
                    style: const TextStyle(fontSize: 13)),
                subtitle: elapsed.isNotEmpty
                    ? Text(elapsed,
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey))
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StatusPill(status: status, color: color),
                    if (steps.isNotEmpty)
                      IconButton(
                        icon: Icon(
                          isExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18,
                        ),
                        onPressed: () => onToggle(jobId),
                        tooltip: isExpanded ? 'Hide steps' : 'Show steps',
                      ),
                    if (jobHtmlUrl != null)
                      IconButton(
                        icon: const Icon(Icons.open_in_new, size: 16),
                        onPressed: () => onOpenJob(jobHtmlUrl),
                        tooltip: 'Open job in GitHub',
                      ),
                  ],
                ),
                onTap: steps.isNotEmpty ? () => onToggle(jobId) : null,
              ),
              if (isExpanded && steps.isNotEmpty)
                _StepsView(steps: steps),
            ],
          ),
        );
      },
    );
  }
}

// ── Steps view ────────────────────────────────────────────────────────────────

class _StepsView extends StatelessWidget {
  final List<Map<String, dynamic>> steps;
  const _StepsView({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
      child: Column(
        children: steps.map((step) {
          final name = step['name'] as String? ?? '';
          final ghStatus = step['status'] as String? ?? '';
          final ghConclusion = step['conclusion'] as String?;
          final status = _normalizeGhStatus(ghStatus, ghConclusion);
          final color = _jobStatusColor(status);
          final number = step['number'] as int? ?? 0;
          final elapsed = _elapsedStr(
              step['started_at'] as String?, step['completed_at'] as String?);

          return Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Text('$number',
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey),
                      textAlign: TextAlign.right),
                ),
                const SizedBox(width: 8),
                Icon(_stepIcon(status), color: color, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
                if (elapsed.isNotEmpty)
                  Text(elapsed,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  IconData _stepIcon(String status) => switch (status) {
        'complete' => Icons.check_circle_outline,
        'running' => Icons.radio_button_checked,
        'failed' => Icons.cancel_outlined,
        'queued' => Icons.hourglass_empty,
        'cancelled' => Icons.remove_circle_outline,
        _ => Icons.circle_outlined,
      };
}

// ── Status filter row ─────────────────────────────────────────────────────────

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
    const statuses = ['All', 'Running', 'Queued', 'Complete', 'Failed'];
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

// ── Tag filter row ────────────────────────────────────────────────────────────

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
                selectedColor: Theme.of(context).colorScheme.secondaryContainer,
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

// ── Log tail view ─────────────────────────────────────────────────────────────

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
      child: SelectionArea(
        child: Scrollbar(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            child: Text(
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
      ),
    );
  }
}

// ── Job card ──────────────────────────────────────────────────────────────────

class _JobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final VoidCallback onTap;

  const _JobCard({required this.job, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = job['status'] as String? ?? 'unknown';
    final color = _jobStatusColor(status);
    final taskName = job['task_name'] as String? ?? '';
    final elapsed =
        _elapsedStr(job['started_at'] as String?, job['finished_at'] as String?);
    final tags = List<String>.from(job['tags'] as List? ?? []);
    final sizeBytes = job['size_bytes'] as int?;
    final isGh = job['source'] == 'gh-actions';
    final repo = job['repo'] as String?;

    final sizeStr = sizeBytes != null
        ? '${(sizeBytes / 1024).toStringAsFixed(1)} KB'
        : '';

    String subtitle = [
      if (elapsed.isNotEmpty) elapsed,
      if (sizeStr.isNotEmpty) sizeStr,
      if (isGh && repo != null) repo,
    ].join(' · ');

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
                    Row(
                      children: [
                        if (isGh) ...[
                          const _SourceBadge(label: 'GH'),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            taskName,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (subtitle.isNotEmpty)
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    if (tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 4,
                          children:
                              tags.map((t) => _TagBadge(tag: t)).toList(),
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

class _SourceBadge extends StatelessWidget {
  final String label;
  const _SourceBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.15),
        border: Border.all(color: Colors.purple.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: const TextStyle(
              fontSize: 9, color: Colors.purple, fontWeight: FontWeight.w700)),
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(tag,
          style: const TextStyle(fontSize: 10, color: Colors.grey)),
    );
  }
}

// ── Status pill ───────────────────────────────────────────────────────────────

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
