import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'calendar.dart';
import 'checklist.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _calReader = CalendarReader();
  final _repo = ChecklistRepo();

  bool _loading = true;
  String? _error;
  List<CalendarEventLite> _events = [];
  ChecklistRoutine? _morningRoutine;
  List<ChecklistItem> _morningItems = [];
  ChecklistRoutine? _eveningRoutine;
  List<ChecklistItem> _eveningItems = [];
  List<_ProgressEntry> _progressEntries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final calFuture = _loadCalendar();
      final routinesFuture = _loadRoutines();
      final progressFuture = _loadProgress();
      await Future.wait([calFuture, routinesFuture, progressFuture]);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCalendar() async {
    if (kIsWeb) return;
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day, 23, 59, 59);
      final events = await _calReader.upcomingEvents(
        window: midnight.difference(now) + const Duration(seconds: 1),
      );
      if (mounted) setState(() => _events = events);
    } catch (_) {}
  }

  Future<void> _loadRoutines() async {
    if (kIsWeb) return;
    await _repo.resetIfNewDay();
    final morning = await _repo.morningRoutine();
    final morningItems = morning != null ? await _repo.items(morning.id) : <ChecklistItem>[];
    final evening = await _repo.eveningRoutine();
    final eveningItems = evening != null ? await _repo.items(evening.id) : <ChecklistItem>[];
    if (mounted) {
      setState(() {
        _morningRoutine = morning;
        _morningItems = morningItems;
        _eveningRoutine = evening;
        _eveningItems = eveningItems;
      });
    }
  }

  Future<void> _loadProgress() async {
    // Overnight progress: reads *-progress.log files from the SOMA/audits dir.
    // This path is on the Mac host, not accessible from the phone — leaving a
    // clearly-labeled placeholder. Wired in the morning when relay is available.
    if (kIsWeb) return;
    try {
      // Try the app-local documents dir as a fallback; real SOMA path is Mac-side.
      final dir = await getApplicationDocumentsDirectory();
      final auditsDir = Directory('${dir.path}/soma_audits');
      if (!auditsDir.existsSync()) {
        return; // no local audits — placeholder is shown in build()
      }
      final logs = auditsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('-progress.log'))
          .toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      final entries = <_ProgressEntry>[];
      for (final f in logs.take(3)) {
        final name = f.uri.pathSegments.last;
        final lines = f.readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
        final last = lines.isNotEmpty ? lines.last : '(empty)';
        entries.add(_ProgressEntry(name: name, lastLine: last));
      }
      if (mounted) setState(() => _progressEntries = entries);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, MMMM d').format(now);
    final timeStr = DateFormat('h:mm a').format(now);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(dateStr, style: Theme.of(context).textTheme.titleMedium),
            Text(timeStr,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Card(
                      color: Colors.red.shade900,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('Error: $_error',
                            style: const TextStyle(color: Colors.white)),
                      ),
                    ),

                  // ── Calendar events ────────────────────────────────────
                  _sectionHeader(context, Icons.calendar_today, "Today's events"),
                  const SizedBox(height: 8),
                  if (_events.isEmpty)
                    _emptyCard('No calendar events today.')
                  else
                    ..._events.map((e) => _eventCard(context, e)),

                  const SizedBox(height: 24),

                  // ── Morning routine ────────────────────────────────────
                  _routineSection(
                    context,
                    icon: Icons.wb_sunny_outlined,
                    title: 'Morning routine',
                    routine: _morningRoutine,
                    items: _morningItems,
                  ),

                  const SizedBox(height: 24),

                  // ── Evening routine ────────────────────────────────────
                  _routineSection(
                    context,
                    icon: Icons.nights_stay_outlined,
                    title: 'Evening routine',
                    routine: _eveningRoutine,
                    items: _eveningItems,
                    notSeededLabel: 'Evening routine not set up yet — open Routines to configure.',
                  ),

                  const SizedBox(height: 24),

                  // ── Overnight progress ─────────────────────────────────
                  _sectionHeader(context, Icons.bedtime_outlined, 'Overnight progress'),
                  const SizedBox(height: 8),
                  if (_progressEntries.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '⏳ Wired in the morning',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'SOMA audit logs live on the Mac host (~/Projects/SOMA/audits/). '
                              'Relay bridge needed to surface them here — not yet wired.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._progressEntries.map((e) => Card(
                          child: ListTile(
                            leading: const Icon(Icons.description_outlined),
                            title: Text(e.name,
                                style: const TextStyle(
                                    fontSize: 12, fontFamily: 'monospace')),
                            subtitle: Text(e.lastLine,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                          ),
                        )),
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(BuildContext context, IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }

  Widget _emptyCard(String msg) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(msg),
      ),
    );
  }

  Widget _eventCard(BuildContext context, CalendarEventLite e) {
    final fmt = DateFormat('h:mm a');
    final time = fmt.format(e.start);
    final endTime = e.end != null ? ' – ${fmt.format(e.end!)}' : '';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event),
        title: Text(e.title),
        subtitle: Text('$time$endTime${e.location != null && e.location!.isNotEmpty ? ' • ${e.location}' : ''}'),
      ),
    );
  }

  Widget _routineSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required ChecklistRoutine? routine,
    required List<ChecklistItem> items,
    String? notSeededLabel,
  }) {
    final total = items.length;
    final done = items.where((i) => i.checked).length;
    final pct = total == 0 ? 0.0 : done / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, icon, title),
        const SizedBox(height: 8),
        if (routine == null)
          _emptyCard(notSeededLabel ?? '$title not configured.')
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('$done / $total',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...items.map((item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(
                                item.checked
                                    ? Icons.check_box
                                    : Icons.check_box_outline_blank,
                                size: 18,
                                color: item.checked
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item.label,
                                  style: TextStyle(
                                    decoration: item.checked
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: item.checked
                                        ? Theme.of(context).colorScheme.outline
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ProgressEntry {
  final String name;
  final String lastLine;
  const _ProgressEntry({required this.name, required this.lastLine});
}
