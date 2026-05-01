import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';

class CalendarEventLite {
  final String id;
  final String title;
  final DateTime start;
  final String? location;
  final String calendarId;

  CalendarEventLite({
    required this.id,
    required this.title,
    required this.start,
    required this.location,
    required this.calendarId,
  });

  String get stableId => '$calendarId::$id::${start.toUtc().toIso8601String()}';
}

class CalendarReader {
  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();

  Future<bool> ensurePermissions() async {
    var perm = await _plugin.hasPermissions();
    debugPrint('SOMA-CAL: hasPermissions=${perm.data}');
    if (perm.data != true) {
      perm = await _plugin.requestPermissions();
      debugPrint('SOMA-CAL: requestPermissions=${perm.data}');
    }
    return perm.data == true;
  }

  Future<List<CalendarEventLite>> upcomingEvents({
    Duration window = const Duration(hours: 24),
  }) async {
    if (!await ensurePermissions()) {
      debugPrint('SOMA-CAL: no permission, returning empty');
      return const [];
    }
    final cals = await _plugin.retrieveCalendars();
    final calList = cals.data ?? const <Calendar>[];
    debugPrint('SOMA-CAL: ${calList.length} calendars found');
    final out = <CalendarEventLite>[];
    final now = DateTime.now();
    final end = now.add(window);
    var rawCount = 0;
    for (final cal in calList) {
      final id = cal.id;
      if (id == null) continue;
      final res = await _plugin.retrieveEvents(
        id,
        RetrieveEventsParams(startDate: now, endDate: end),
      );
      final events = res.data ?? const <Event>[];
      rawCount += events.length;
      for (final e in events) {
        final start = e.start?.toLocal();
        if (start == null) continue;
        if (start.isBefore(now) || start.isAfter(end)) continue;
        if (e.allDay == true) continue;
        out.add(CalendarEventLite(
          id: e.eventId ?? '${start.toIso8601String()}-${e.title}',
          title: (e.title?.trim().isNotEmpty ?? false) ? e.title!.trim() : '(no title)',
          start: start,
          location: e.location,
          calendarId: id,
        ));
      }
    }
    debugPrint('SOMA-CAL: $rawCount raw events, ${out.length} after filtering');
    return out;
  }
}
