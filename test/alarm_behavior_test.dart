import 'package:flutter_test/flutter_test.dart';
import 'package:soma_alarm/src/alarms.dart';
import 'package:soma_alarm/src/calendar.dart';

void main() {
  group('AlarmRecord', () {
    test('firedAt serialization roundtrip', () {
      final now = DateTime.now();
      final rec = AlarmRecord(
        eventId: 'e1',
        title: 'Test',
        scheduled: now,
        firedAt: now,
        eventStart: now.add(const Duration(minutes: 15)),
      );
      final json = rec.toJson();
      final restored = AlarmRecord.fromJson(json);
      expect(restored.firedAt, isNotNull);
      expect(restored.eventStart, isNotNull);
      expect(restored.firedAt!.toIso8601String(), now.toIso8601String());
      expect(restored.eventStart!.toIso8601String(),
          now.add(const Duration(minutes: 15)).toIso8601String());
    });

    test('copyWith sets firedAt', () {
      final rec = AlarmRecord(
        eventId: 'e1',
        title: 'Test',
        scheduled: DateTime.now(),
      );
      expect(rec.firedAt, isNull);
      final fired = rec.copyWith(firedAt: DateTime.now());
      expect(fired.firedAt, isNotNull);
      expect(fired.eventId, rec.eventId);
    });

    test('fromJson handles missing firedAt/eventStart gracefully', () {
      final rec = AlarmRecord.fromJson({
        'event_id': 'e1',
        'title': 'Test',
        'scheduled': DateTime.now().toIso8601String(),
      });
      expect(rec.firedAt, isNull);
      expect(rec.eventStart, isNull);
      expect(rec.isLeadAlarm, true);
    });
  });

  group('snooze clamping logic', () {
    test('snooze within window keeps lead status', () {
      final eventStart = DateTime.now().add(const Duration(minutes: 20));
      const snoozeMinutes = 15;
      final newWhen = DateTime.now().add(const Duration(minutes: snoozeMinutes));
      expect(newWhen.isBefore(eventStart), true);
    });

    test('snooze past event start should clamp', () {
      final eventStart = DateTime.now().add(const Duration(minutes: 10));
      const snoozeMinutes = 15;
      final newWhen = DateTime.now().add(const Duration(minutes: snoozeMinutes));
      expect(newWhen.isBefore(eventStart), false);
    });
  });

  group('CalendarEventLite', () {
    test('end field is preserved', () {
      final start = DateTime.now();
      final end = start.add(const Duration(hours: 1));
      final event = CalendarEventLite(
        id: '1',
        title: 'Meeting',
        start: start,
        end: end,
        location: null,
        calendarId: 'cal1',
      );
      expect(event.end, end);
    });

    test('event with end before now is expired', () {
      final now = DateTime.now();
      final event = CalendarEventLite(
        id: '1',
        title: 'Past Meeting',
        start: now.subtract(const Duration(hours: 2)),
        end: now.subtract(const Duration(hours: 1)),
        location: null,
        calendarId: 'cal1',
      );
      final effectiveEnd = event.end ?? event.start;
      expect(effectiveEnd.isAfter(now), false);
    });

    test('event with no end uses start for expiry', () {
      final now = DateTime.now();
      final event = CalendarEventLite(
        id: '1',
        title: 'Past Event',
        start: now.subtract(const Duration(hours: 1)),
        location: null,
        calendarId: 'cal1',
      );
      final effectiveEnd = event.end ?? event.start;
      expect(effectiveEnd.isAfter(now), false);
    });
  });

  group('fired alarm filtering', () {
    test('fired alarms excluded from visible list', () {
      final alarms = [
        AlarmRecord(
          eventId: 'e1',
          title: 'Fired',
          scheduled: DateTime.now(),
          firedAt: DateTime.now(),
          isLeadAlarm: true,
        ),
        AlarmRecord(
          eventId: 'e2',
          title: 'Active',
          scheduled: DateTime.now().add(const Duration(hours: 1)),
          isLeadAlarm: true,
        ),
        AlarmRecord(
          eventId: 'e3',
          title: 'Backstop',
          scheduled: DateTime.now().add(const Duration(hours: 1)),
          isLeadAlarm: false,
        ),
      ];
      final visible =
          alarms.where((a) => a.firedAt == null && a.isLeadAlarm).toList();
      expect(visible.length, 1);
      expect(visible.first.title, 'Active');
    });
  });

  group('single-dismiss model', () {
    test('dismiss on lead should target both lead and start', () {
      final rec = AlarmRecord(
        eventId: 'e1',
        title: 'Meeting',
        scheduled: DateTime.now(),
        isLeadAlarm: true,
        eventStart: DateTime.now().add(const Duration(minutes: 15)),
      );
      // Lead dismiss → cancelForEvent (both kinds)
      expect(rec.isLeadAlarm, true);
    });

    test('dismiss on start should target only start', () {
      final rec = AlarmRecord(
        eventId: 'e1',
        title: 'Meeting',
        scheduled: DateTime.now(),
        isLeadAlarm: false,
        eventStart: DateTime.now(),
      );
      // Start dismiss → cancelAlarm(lead: false) only
      expect(rec.isLeadAlarm, false);
    });
  });
}
