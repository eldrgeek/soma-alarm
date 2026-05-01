import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class CalendarEventLite {
  final String id;
  final String title;
  final DateTime start;
  final DateTime? end;
  final String? location;
  final String calendarId;

  CalendarEventLite({
    required this.id,
    required this.title,
    required this.start,
    this.end,
    required this.location,
    required this.calendarId,
  });

  String get stableId => '$calendarId::$id::${start.toUtc().toIso8601String()}';
}

class CalendarReader {
  static const _channel = MethodChannel('org.esr.soma_alarm/calendar');

  Future<bool> ensurePermissions() async {
    var status = await Permission.calendarFullAccess.status;
    debugPrint('SOMA-CAL: permission=$status');
    if (!status.isGranted) {
      status = await Permission.calendarFullAccess.request();
      debugPrint('SOMA-CAL: requested permission=$status');
    }
    return status.isGranted;
  }

  Future<List<CalendarEventLite>> upcomingEvents({
    Duration window = const Duration(hours: 24),
  }) async {
    if (!await ensurePermissions()) {
      debugPrint('SOMA-CAL: no permission, returning empty');
      return const [];
    }
    final now = DateTime.now();
    final end = now.add(window);
    try {
      final List<dynamic> results = await _channel.invokeMethod('getInstances', {
        'begin': now.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
      });
      debugPrint('SOMA-CAL: platform channel returned ${results.length} instances');
      final out = <CalendarEventLite>[];
      for (final item in results) {
        final map = Map<String, dynamic>.from(item as Map);
        final allDay = map['all_day'] as bool? ?? false;
        if (allDay) continue;
        final beginMs = map['begin'] as int;
        final start = DateTime.fromMillisecondsSinceEpoch(beginMs);
        if (start.isBefore(now) || start.isAfter(end)) continue;
        final endMs = map['end'] as int?;
        final eventEnd = endMs != null
            ? DateTime.fromMillisecondsSinceEpoch(endMs)
            : null;
        final title = (map['title'] as String?)?.trim();
        out.add(CalendarEventLite(
          id: map['event_id'] as String? ?? '$beginMs',
          title: (title != null && title.isNotEmpty) ? title : '(no title)',
          start: start,
          end: eventEnd,
          location: map['location'] as String?,
          calendarId: map['calendar_id'] as String? ?? '',
        ));
      }
      debugPrint('SOMA-CAL: ${out.length} after filtering (excl allDay + out-of-range)');
      if (out.isNotEmpty) {
        debugPrint('SOMA-CAL: first: ${out.first.title} at ${out.first.start}');
      }
      return out;
    } catch (e, st) {
      debugPrint('SOMA-CAL: platform channel error: $e\n$st');
      return const [];
    }
  }
}
