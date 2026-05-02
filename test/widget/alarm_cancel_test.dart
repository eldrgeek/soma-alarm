import 'package:flutter_test/flutter_test.dart';
import 'package:soma_alarm/src/alarms.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    setupMockPlatformChannels();
  });

  group('AlarmService cancel semantics', () {
    const eventId = 'cal1::ev42::2026-05-01T09:00:00.000Z';

    int leadId(String id) => id.hashCode & 0x3fffffff;
    int startId(String id) => (id.hashCode & 0x3fffffff) | 0x40000000;

    setUp(() async {
      await AlarmService.instance.init();
      cancelledNotificationIds.clear();
    });

    test('cancelAlarm(lead: true) only cancels lead notification', () async {
      await AlarmService.instance.cancelAlarm(eventId, lead: true);

      expect(cancelledNotificationIds, contains(leadId(eventId)));
      expect(cancelledNotificationIds, isNot(contains(startId(eventId))));
      expect(cancelledNotificationIds.length, 1);
    });

    test('cancelAlarm(lead: false) only cancels start notification', () async {
      await AlarmService.instance.cancelAlarm(eventId, lead: false);

      expect(cancelledNotificationIds, contains(startId(eventId)));
      expect(cancelledNotificationIds, isNot(contains(leadId(eventId))));
      expect(cancelledNotificationIds.length, 1);
    });

    test('cancelForEvent cancels both lead and start', () async {
      await AlarmService.instance.cancelForEvent(eventId);

      expect(cancelledNotificationIds, contains(leadId(eventId)));
      expect(cancelledNotificationIds, contains(startId(eventId)));
      expect(cancelledNotificationIds.length, 2);
    });

    test('lead and start IDs are different for same event', () {
      expect(leadId(eventId), isNot(equals(startId(eventId))));
      expect(leadId(eventId) & 0x40000000, 0);
      expect(startId(eventId) & 0x40000000, 0x40000000);
    });
  });
}
