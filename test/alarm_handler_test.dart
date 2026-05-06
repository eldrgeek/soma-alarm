// Bug B — "Alarm notification dismisses on any click except the alarm itself."
//
// Real-world bug surface: tapping the Snooze 5/10/15 or Dismiss action
// buttons in the Android system notification appears to "just dismiss" the
// notification without scheduling a snoozed alarm or correctly cancelling
// the event.
//
// Where the bug actually lives: the Dart action-dispatch logic that
// decides, given a notification response, what to do next. We extracted
// that logic into a pure function `decideNotificationAction` (in
// lib/src/alarms.dart) so it can be unit-tested deterministically.
//
// LIMITATION (documented in TDD.md): a true end-to-end test of the
// system-notification-action path requires either:
//   (a) instrumenting the FlutterLocalNotificationsPlugin to drive
//       a synthetic action tap, or
//   (b) running an Android instrumentation test that uses UIAutomator
//       to expand the notification shade and tap action buttons.
// Neither is in scope for v1 of the TDD pipeline. These unit tests cover
// the dispatch-decision correctness — the most common failure mode.
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/src/alarms.dart';

void main() {
  group('Bug B — decideNotificationAction', () {
    final now = DateTime(2026, 5, 6, 9, 0, 0);
    AlarmRecord lead({DateTime? eventStart}) => AlarmRecord(
          eventId: 'e1',
          title: 'Standup',
          scheduled: now,
          isLeadAlarm: true,
          eventStart:
              eventStart ?? now.add(const Duration(minutes: 30)),
        );

    test('snooze5 reschedules same kind 5 minutes from now', () {
      final d = decideNotificationAction(
          rec: lead(), actionId: kActionSnooze5, now: now);
      expect(d.kind, NotificationActionKind.reschedule);
      expect(d.rescheduled!.scheduled,
          now.add(const Duration(minutes: 5)));
      expect(d.rescheduled!.isLeadAlarm, true);
      expect(d.rescheduled!.eventId, 'e1');
    });

    test('snooze10 reschedules 10 minutes from now', () {
      final d = decideNotificationAction(
          rec: lead(), actionId: kActionSnooze10, now: now);
      expect(d.rescheduled!.scheduled,
          now.add(const Duration(minutes: 10)));
    });

    test('snooze15 reschedules 15 minutes from now', () {
      final d = decideNotificationAction(
          rec: lead(), actionId: kActionSnooze15, now: now);
      expect(d.rescheduled!.scheduled,
          now.add(const Duration(minutes: 15)));
    });

    test('snooze past event start swaps to backstop (T=0) alarm', () {
      // Event starts in 8 min, user picks snooze 15 → snooze would land
      // past event start, so the system schedules a T=0 backstop instead.
      final rec = lead(eventStart: now.add(const Duration(minutes: 8)));
      final d = decideNotificationAction(
          rec: rec, actionId: kActionSnooze15, now: now);
      expect(d.kind, NotificationActionKind.reschedule);
      expect(d.rescheduled!.isLeadAlarm, false,
          reason: 'past-eventStart snooze must become a start-time backstop');
      expect(d.rescheduled!.scheduled,
          now.add(const Duration(minutes: 8)));
    });

    test('snooze past event start that has already happened → ignore', () {
      final rec = lead(eventStart: now.subtract(const Duration(minutes: 1)));
      final d = decideNotificationAction(
          rec: rec, actionId: kActionSnooze5, now: now);
      expect(d.kind, NotificationActionKind.ignore,
          reason: 'no useful action after the event has started');
    });

    test('dismiss on lead cancels both lead and start (single-dismiss model)',
        () {
      final d = decideNotificationAction(
          rec: lead(), actionId: kActionDismiss, now: now);
      expect(d.kind, NotificationActionKind.cancelEvent);
    });

    test('dismiss on backstop (start-time) cancels only that kind', () {
      final rec = AlarmRecord(
        eventId: 'e1',
        title: 'Standup',
        scheduled: now,
        isLeadAlarm: false,
        eventStart: now,
      );
      final d = decideNotificationAction(
          rec: rec, actionId: kActionDismiss, now: now);
      expect(d.kind, NotificationActionKind.cancelKind);
    });

    test('unknown actionId → ignore (no silent state mutation)', () {
      final d = decideNotificationAction(
          rec: lead(), actionId: 'bogus', now: now);
      expect(d.kind, NotificationActionKind.ignore);
    });

    test('snooze when eventStart is null reschedules same kind', () {
      final rec = AlarmRecord(
        eventId: 'e1',
        title: 'No-start event',
        scheduled: now,
        isLeadAlarm: true,
      );
      final d = decideNotificationAction(
          rec: rec, actionId: kActionSnooze10, now: now);
      expect(d.kind, NotificationActionKind.reschedule);
      expect(d.rescheduled!.scheduled,
          now.add(const Duration(minutes: 10)));
    });
  });
}
