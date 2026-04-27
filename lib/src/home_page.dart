import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'alarms.dart';
import 'background.dart';
import 'calendar.dart';
import 'checklist_page.dart';
import 'settings_page.dart';

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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await _reader.ensurePermissions();
    final events = await _reader.upcomingEvents();
    await runBackgroundPoll();
    final scheduled = await AlarmService.instance.scheduledAlarms();
    if (!mounted) return;
    setState(() {
      _events = events;
      _scheduled = scheduled;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEE MMM d • h:mm a');
    return Scaffold(
      appBar: AppBar(
        title: const Text('SOMA Alarm'),
        actions: [
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
