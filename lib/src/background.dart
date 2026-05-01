import 'package:flutter/foundation.dart';

import 'alarms.dart';
import 'calendar.dart';
import 'settings.dart';

Future<bool> runBackgroundPoll() async {
  try {
    debugPrint('SOMA: poll start');
    await AlarmService.instance.init();
    final lead = await Settings.leadMinutes();
    final reader = CalendarReader();
    final events = await reader.upcomingEvents();
    debugPrint('SOMA: calendar returned ${events.length} events');
    if (events.isNotEmpty) {
      debugPrint('SOMA: first event: ${events.first.title} at ${events.first.start}');
    }

    final existing = await AlarmService.instance.scheduledAlarms();
    final existingIds = existing.map((e) => e.eventId).toSet();
    final liveIds = events.map((e) => e.stableId).toSet();

    for (final stale in existingIds.difference(liveIds)) {
      await AlarmService.instance.cancelForEvent(stale);
    }

    var scheduled = 0;
    for (final ev in events) {
      final leadWhen = ev.start.subtract(Duration(minutes: lead));
      if (leadWhen.isAfter(DateTime.now())) {
        await AlarmService.instance.scheduleEventAlarm(AlarmRecord(
          eventId: ev.stableId,
          title: ev.title,
          scheduled: leadWhen,
          location: ev.location,
          isLeadAlarm: true,
        ));
        scheduled++;
      }
      if (ev.start.isAfter(DateTime.now())) {
        await AlarmService.instance.scheduleEventAlarm(AlarmRecord(
          eventId: ev.stableId,
          title: ev.title,
          scheduled: ev.start,
          location: ev.location,
          isLeadAlarm: false,
        ));
        scheduled++;
      }
    }
    debugPrint('SOMA: scheduled $scheduled alarms');

    final morningOn = await Settings.morningEnabled();
    if (morningOn) {
      final t = await Settings.morningTime();
      await AlarmService.instance
          .scheduleMorningAlarm(hour: t.hour, minute: t.minute);
    } else {
      await AlarmService.instance.cancelMorningAlarm();
    }
    debugPrint('SOMA: poll complete');
    return true;
  } catch (e, st) {
    debugPrint('SOMA: poll FAILED: $e\n$st');
    return false;
  }
}
