import 'package:device_calendar/device_calendar.dart';

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
    if (perm.data != true) {
      perm = await _plugin.requestPermissions();
    }
    return perm.data == true;
  }

  Future<List<CalendarEventLite>> upcomingEvents({
    Duration window = const Duration(hours: 24),
  }) async {
    if (!await ensurePermissions()) return const [];
    final cals = await _plugin.retrieveCalendars();
    final out = <CalendarEventLite>[];
    final now = DateTime.now();
    final end = now.add(window);
    for (final cal in cals.data ?? const <Calendar>[]) {
      final id = cal.id;
      if (id == null) continue;
      final res = await _plugin.retrieveEvents(
        id,
        RetrieveEventsParams(startDate: now, endDate: end),
      );
      for (final e in res.data ?? const <Event>[]) {
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
    return out;
  }
}
