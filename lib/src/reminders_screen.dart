import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'alarms.dart';
import 'background.dart';
import 'calendar.dart';
import 'settings.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _calReader = CalendarReader();

  bool _loading = false;
  String? _error;
  List<CalendarEventLite> _events = [];
  List<AlarmRecord> _scheduled = [];
  int _leadMinutes = 30;

  @override
  void initState() {
    super.initState();
    _loadSettings().then((_) => _refresh());
  }

  Future<void> _loadSettings() async {
    final lead = await Settings.leadMinutes();
    if (mounted) setState(() => _leadMinutes = lead);
  }

  Future<void> _refresh() async {
    if (kIsWeb) return;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      await runBackgroundPoll();
      final events = await _calReader.upcomingEvents(window: const Duration(hours: 48));
      final scheduled = await AlarmService.instance.scheduledAlarms();
      final now = DateTime.now();
      if (!mounted) return;
      setState(() {
        _events = events.where((e) => (e.end ?? e.start).isAfter(now)).toList();
        _scheduled = scheduled.where((a) => a.firedAt == null && a.isLeadAlarm).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  Future<void> _setLeadMinutes(int v) async {
    await Settings.setLeadMinutes(v);
    if (mounted) setState(() => _leadMinutes = v);
    await _refresh();
  }

  AlarmRecord? _alarmFor(CalendarEventLite ev) {
    return _scheduled.cast<AlarmRecord?>().firstWhere(
      (a) => a?.eventId == ev.stableId,
      orElse: () => null,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reminders'),
            Text('Calendar event alerts', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _refresh),
        ],
      ),
      body: Column(
        children: [
          // Lead time configurator
          Container(
            color: theme.colorScheme.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.alarm, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                const Text('Notify', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                ...[5, 10, 15, 30, 60].map((m) {
                  final sel = _leadMinutes == m;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('${m}m'),
                      selected: sel,
                      onSelected: (_) => _setLeadMinutes(m),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }),
                const Text('before', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          const Divider(height: 1),

          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade900,
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.white)),
            ),

          Expanded(
            child: kIsWeb
                ? const Center(child: Text('Calendar not available on web'))
                : _events.isEmpty && !_loading
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.event_available, size: 48, color: Colors.grey),
                            const SizedBox(height: 12),
                            const Text('No upcoming events in next 48h',
                                style: TextStyle(color: Colors.grey)),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _refresh,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Refresh'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _events.length,
                        itemBuilder: (ctx, i) => _EventTile(
                          event: _events[i],
                          alarm: _alarmFor(_events[i]),
                          leadMinutes: _leadMinutes,
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final CalendarEventLite event;
  final AlarmRecord? alarm;
  final int leadMinutes;

  const _EventTile({required this.event, required this.alarm, required this.leadMinutes});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final start = event.start;
    final diff = start.difference(now);
    final timeStr = DateFormat('E h:mm a').format(start);
    final alarmAt = alarm?.scheduled;
    final alarmStr = alarmAt != null ? DateFormat('h:mm a').format(alarmAt.toLocal()) : null;
    final isScheduled = alarm != null;

    String diffStr;
    if (diff.inMinutes < 60) {
      diffStr = 'in ${diff.inMinutes}m';
    } else if (diff.inHours < 24) {
      diffStr = 'in ${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
    } else {
      diffStr = 'tomorrow';
    }

    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: isScheduled
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          isScheduled ? Icons.alarm_on : Icons.alarm_off,
          size: 16,
          color: isScheduled
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(event.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(
        [
          timeStr,
          diffStr,
          if (event.location != null && event.location!.isNotEmpty) event.location!,
        ].join(' · '),
        style: const TextStyle(fontSize: 11),
      ),
      trailing: isScheduled
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Alarm set', style: TextStyle(fontSize: 10, color: Colors.green)),
                if (alarmStr != null)
                  Text(alarmStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            )
          : Text(
              '${leadMinutes}m lead\nnot scheduled',
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 10, color: Colors.orange),
            ),
    );
  }
}
