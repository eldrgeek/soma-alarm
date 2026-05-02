import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'alarms.dart';

class AlarmActionScreen extends StatefulWidget {
  final AlarmRecord record;
  const AlarmActionScreen({super.key, required this.record});

  @override
  State<AlarmActionScreen> createState() => _AlarmActionScreenState();
}

class _AlarmActionScreenState extends State<AlarmActionScreen> {
  late Timer _ticker;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
    });
  }

  void _updateRemaining() {
    final evStart = widget.record.eventStart;
    if (evStart == null) {
      setState(() => _remaining = Duration.zero);
      return;
    }
    final diff = evStart.difference(DateTime.now());
    setState(() => _remaining = diff.isNegative ? Duration.zero : diff);
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  bool get _pastEventStart {
    final evStart = widget.record.eventStart;
    if (evStart == null) return false;
    return !DateTime.now().isBefore(evStart);
  }

  bool _snoozeWouldExceed(int minutes) {
    final evStart = widget.record.eventStart;
    if (evStart == null) return false;
    return !DateTime.now().add(Duration(minutes: minutes)).isBefore(evStart);
  }

  Future<void> _snooze(int minutes) async {
    final svc = AlarmService.instance;
    final rec = widget.record;
    final now = DateTime.now();
    final newWhen = now.add(Duration(minutes: minutes));
    final evStart = rec.eventStart;

    await svc.markFired(rec);

    if (evStart != null && !newWhen.isBefore(evStart)) {
      if (now.isBefore(evStart)) {
        await svc.scheduleEventAlarm(AlarmRecord(
          eventId: rec.eventId,
          title: rec.title,
          scheduled: evStart,
          location: rec.location,
          isLeadAlarm: false,
          eventStart: evStart,
        ));
      }
    } else {
      await svc.scheduleEventAlarm(AlarmRecord(
        eventId: rec.eventId,
        title: rec.title,
        scheduled: newWhen,
        location: rec.location,
        isLeadAlarm: rec.isLeadAlarm,
        eventStart: evStart,
      ));
    }

    await svc.cancelNotification(rec.eventId, lead: rec.isLeadAlarm);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _dismiss() async {
    final svc = AlarmService.instance;
    final rec = widget.record;

    await svc.markFired(rec);

    if (rec.isLeadAlarm) {
      await svc.cancelForEvent(rec.eventId);
    } else {
      await svc.cancelAlarm(rec.eventId, lead: false);
    }

    await svc.cancelNotification(rec.eventId, lead: rec.isLeadAlarm);
    if (mounted) Navigator.of(context).pop();
  }

  String _formatCountdown(Duration d) {
    if (d == Duration.zero) return 'NOW';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final rec = widget.record;
    final fmt = DateFormat('EEE MMM d • h:mm a');
    final eventTime = rec.eventStart ?? rec.scheduled;
    final showSnooze = rec.isLeadAlarm && !_pastEventStart;

    return Scaffold(
      appBar: AppBar(title: const Text('Alarm')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Text(
              rec.title,
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              fmt.format(eventTime.toLocal()),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white70,
                  ),
              textAlign: TextAlign.center,
            ),
            if (rec.location != null && rec.location!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.white54),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      rec.location!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white54,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 32),
            if (rec.eventStart != null)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _pastEventStart
                      ? Colors.red.withAlpha(40)
                      : Colors.deepPurple.withAlpha(40),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      _pastEventStart ? 'Event started' : 'Starts in',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white54,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatCountdown(_remaining),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            if (showSnooze) ...[
              Row(
                children: [
                  for (final mins in [5, 10, 15]) ...[
                    if (mins > 5) const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed:
                            _snoozeWouldExceed(mins) ? null : () => _snooze(mins),
                        child: Text('Snooze $mins'),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _dismiss,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                ),
                child: const Text('Dismiss', style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
