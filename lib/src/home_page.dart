import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import 'alarms.dart';
import 'background.dart';
import 'calendar.dart';
import 'checklist_page.dart';
import 'settings.dart';
import 'settings_page.dart';

const _buildSha = String.fromEnvironment('BUILD_SHA', defaultValue: 'dev');
const _buildTime = String.fromEnvironment('BUILD_TIME', defaultValue: '');

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _reader = CalendarReader();
  List<CalendarEventLite> _events = [];
  List<AlarmRecord> _scheduled = [];
  bool _loading = false;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _lastError = null;
    });
    try {
      await _reader.ensurePermissions();
      final events = await _reader.upcomingEvents();
      final pollOk = await runBackgroundPoll();
      final scheduled = await AlarmService.instance.scheduledAlarms();
      if (!mounted) return;
      setState(() {
        _events = events;
        _scheduled = scheduled;
        _loading = false;
        if (!pollOk) _lastError = 'Background poll returned false';
      });
    } catch (e) {
      debugPrint('SOMA-HOME: refresh error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _lastError = '$e';
      });
    }
  }

  Future<void> _forceCalendarSync() async {
    const channel = MethodChannel('org.esr.soma_alarm/calendar');
    try {
      final result = await channel.invokeMethod<bool>('requestSync');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result == true
              ? 'Calendar sync requested. Refreshing...'
              : 'No Google calendar accounts found.'),
        ),
      );
      if (result == true) {
        await Future<void>.delayed(const Duration(seconds: 3));
        await _refresh();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync failed: $e')),
      );
    }
  }

  Future<void> _showDiagnostics() async {
    final calPerm = await Permission.calendarFullAccess.status;

    const channel = MethodChannel('org.esr.soma_alarm/calendar');
    var rawCount = 0;
    var filteredCount = 0;
    if (calPerm.isGranted) {
      try {
        final now = DateTime.now();
        final List<dynamic> results =
            await channel.invokeMethod('getInstances', {
          'begin': now.millisecondsSinceEpoch,
          'end': now.add(const Duration(hours: 24)).millisecondsSinceEpoch,
        });
        rawCount = results.length;
        for (final item in results) {
          final map = Map<String, dynamic>.from(item as Map);
          final allDay = map['all_day'] as bool? ?? false;
          if (allDay) continue;
          final beginMs = map['begin'] as int;
          final start = DateTime.fromMillisecondsSinceEpoch(beginMs);
          if (start.isAfter(now)) filteredCount++;
        }
      } catch (_) {}
    }

    final scheduled = await AlarmService.instance.scheduledAlarms();
    final webhookUrl = await Settings.webhookUrl();
    final webhookOn = await Settings.webhookEnabled();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Diagnostics'),
        content: SingleChildScrollView(
          child: Text(
            'Version: 0.1.0\n'
            'Build: $_buildSha\n'
            '${_buildTime.isNotEmpty ? 'Built: $_buildTime\n' : ''}'
            '\n'
            'Calendar permission: $calPerm\n'
            'Raw instances (24h): $rawCount\n'
            'Filtered events: $filteredCount\n'
            '\n'
            'Scheduled alarms: ${scheduled.length}\n'
            '\n'
            'Webhook: ${webhookOn ? "ON" : "OFF"}\n'
            'URL: $webhookUrl\n'
            '${_lastError != null ? '\nLast error: $_lastError' : ''}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _forceCalendarSync();
            },
            child: const Text('Force Calendar Sync'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEE MMM d • h:mm a');
    const isDev = _buildSha == 'dev';
    return Scaffold(
      appBar: AppBar(
        title: const Text('SOMA Alarm'),
        backgroundColor: isDev ? Colors.deepOrange : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Diagnostics',
            onPressed: _showDiagnostics,
          ),
          IconButton(
            icon: const Icon(Icons.checklist_rtl),
            tooltip: 'Routines',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ChecklistPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (isDev)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'v0.1.0 — $_buildSha${_buildTime.isNotEmpty ? ' — $_buildTime' : ''}',
                  style: TextStyle(
                    color: Colors.deepOrange.shade200,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            if (_lastError != null)
              Card(
                color: Colors.red.shade900,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('Error: $_lastError',
                      style: const TextStyle(color: Colors.white)),
                ),
              ),
            Text('Upcoming events (24h)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_events.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No events in the next 24 hours.'),
                ),
              ),
            ..._events.map((e) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.event),
                    title: Text(e.title),
                    subtitle: Text(
                      [
                        fmt.format(e.start),
                        if ((e.location ?? '').isNotEmpty) e.location!,
                      ].join(' • '),
                    ),
                  ),
                )),
            const SizedBox(height: 24),
            Text('Scheduled alarms',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_scheduled.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No alarms scheduled.'),
                ),
              ),
            ..._scheduled.map((a) => Card(
                  child: ListTile(
                    leading: Icon(a.isLeadAlarm
                        ? Icons.alarm
                        : Icons.notifications_active),
                    title: Text(a.title),
                    subtitle: Text(
                        '${a.isLeadAlarm ? "Lead" : "Start"} • ${fmt.format(a.scheduled.toLocal())}'),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
