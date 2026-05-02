import 'dart:async';

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
const _buildChangelog = String.fromEnvironment('BUILD_CHANGELOG', defaultValue: '');

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _reader = CalendarReader();
  List<CalendarEventLite> _events = [];
  List<AlarmRecord> _scheduled = [];
  bool _loading = false;
  String? _lastError;
  DateTime? _testAlarmTime;
  Timer? _testCountdownTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    _testCountdownTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _lastError = null;
    });
    try {
      await _reader.ensurePermissions();
      await AlarmService.instance.scrubStaleRecords();
      final events = await _reader.upcomingEvents();
      final pollOk = await runBackgroundPoll();
      final scheduled = await AlarmService.instance.scheduledAlarms();
      final now = DateTime.now();
      if (!mounted) return;
      setState(() {
        _events = events
            .where((e) => (e.end ?? e.start).isAfter(now))
            .toList();
        _scheduled = scheduled
            .where((a) => a.firedAt == null && a.isLeadAlarm)
            .toList();
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

  Future<void> _showTestAlarmPicker() async {
    final delay = await showDialog<Duration>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Test alarm in...'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in {
              '30 seconds': const Duration(seconds: 30),
              '60 seconds': const Duration(seconds: 60),
              '5 minutes': const Duration(minutes: 5),
            }.entries)
              SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: FilledButton.tonal(
                    onPressed: () => Navigator.pop(ctx, entry.value),
                    child: Text(entry.key),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (delay == null || !mounted) return;
    await AlarmService.instance.scheduleTestAlarm(delay: delay);
    _startTestCountdown(delay);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Test alarm scheduled — fires in ${delay.inSeconds}s.')),
    );
  }

  void _startTestCountdown(Duration delay) {
    _testCountdownTimer?.cancel();
    setState(() => _testAlarmTime = DateTime.now().add(delay));
    _testCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _testCountdownTimer?.cancel();
        return;
      }
      final remaining = _testAlarmTime!.difference(DateTime.now());
      if (remaining.isNegative) {
        _testCountdownTimer?.cancel();
        setState(() => _testAlarmTime = null);
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _showDiagnostics() async {
    final calPerm = await Permission.calendarFullAccess.status;
    final notifPerm = await Permission.notification.status;
    final exactAlarmPerm = await Permission.scheduleExactAlarm.status;

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

    final permDenied = !calPerm.isGranted ||
        !notifPerm.isGranted ||
        !exactAlarmPerm.isGranted;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Diagnostics'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Version: 0.1.0\n'
                'Build: $_buildSha\n'
                '${_buildTime.isNotEmpty ? 'Built: $_buildTime\n' : ''}',
              ),
              const SizedBox(height: 8),
              Text('PERMISSIONS',
                  style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 4),
              _permRow('Calendar', calPerm),
              _permRow('Notifications', notifPerm),
              _permRow('Alarms & reminders', exactAlarmPerm),
              if (permDenied) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.settings, size: 18),
                    label: const Text('Open app settings'),
                    onPressed: () => openAppSettings(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Calendar\n'
                '  Raw instances (24h): $rawCount\n'
                '  Filtered events: $filteredCount\n'
                '\n'
                'Scheduled alarms: ${scheduled.length}\n'
                '\n'
                'Webhook: ${webhookOn ? "ON" : "OFF"}\n'
                'URL: $webhookUrl\n'
                '${_lastError != null ? '\nLast error: $_lastError' : ''}',
              ),
              if (_buildChangelog.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('RECENT CHANGES',
                    style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 4),
                ...(_buildChangelog.split('|').map((line) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text(
                        line.trim(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ))),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _showTestAlarmPicker();
            },
            child: const Text('Test Alarm'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _forceCalendarSync();
            },
            child: const Text('Force Sync'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _permRow(String label, PermissionStatus status) {
    final granted = status.isGranted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(granted ? Icons.check_circle : Icons.error,
              size: 16, color: granted ? Colors.green : Colors.red),
          const SizedBox(width: 8),
          Text('$label: ${granted ? "granted" : status.name}'),
        ],
      ),
    );
  }

  Widget _buildTestCountdown() {
    final remaining = _testAlarmTime!.difference(DateTime.now());
    final secs = remaining.isNegative ? 0 : remaining.inSeconds;
    final m = (secs ~/ 60).toString();
    final s = (secs % 60).toString().padLeft(2, '0');
    return Card(
      color: Colors.deepPurple.shade800,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.timer, size: 20),
            const SizedBox(width: 12),
            Text('Test alarm in $m:$s',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 16)),
          ],
        ),
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
            if (_testAlarmTime != null) ...[
              _buildTestCountdown(),
              const SizedBox(height: 12),
            ],
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
                    leading: const Icon(Icons.alarm),
                    title: Text(a.title),
                    subtitle: Text(fmt.format(a.scheduled.toLocal())),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
