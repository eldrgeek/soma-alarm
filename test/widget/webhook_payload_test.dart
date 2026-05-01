import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soma_alarm/src/webhook.dart';

void main() {
  group('WebhookClient payload', () {
    test('includes alarm_kind when provided', () async {
      SharedPreferences.setMockInitialValues({
        'webhook_url': 'https://example.com/hook',
        'webhook_enabled': true,
      });

      String? capturedBody;
      final mockClient = MockClient((request) async {
        capturedBody = request.body;
        return http.Response('ok', 200);
      });

      await http.runWithClient(
        () => WebhookClient.post(
          eventId: 'test-1',
          title: 'Test Event',
          scheduledTime: DateTime.utc(2026, 1, 1, 12, 0),
          firedTime: DateTime.utc(2026, 1, 1, 12, 1),
          action: 'fire',
          alarmKind: 'lead',
        ),
        () => mockClient,
      );

      expect(capturedBody, isNotNull);
      final payload = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(payload['alarm_kind'], 'lead');
      expect(payload['event_id'], 'test-1');
      expect(payload['title'], 'Test Event');
      expect(payload['action'], 'fire');
      expect(payload['source'], 'soma-alarm-android');
    });

    test('omits alarm_kind when null', () async {
      SharedPreferences.setMockInitialValues({
        'webhook_url': 'https://example.com/hook',
        'webhook_enabled': true,
      });

      String? capturedBody;
      final mockClient = MockClient((request) async {
        capturedBody = request.body;
        return http.Response('ok', 200);
      });

      await http.runWithClient(
        () => WebhookClient.post(
          eventId: 'test-2',
          title: 'No Kind',
          scheduledTime: DateTime.utc(2026, 1, 1, 12, 0),
          firedTime: DateTime.utc(2026, 1, 1, 12, 1),
          action: 'fire',
        ),
        () => mockClient,
      );

      expect(capturedBody, isNotNull);
      final payload = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(payload.containsKey('alarm_kind'), isFalse);
    });

    test('omits location when null or empty', () async {
      SharedPreferences.setMockInitialValues({
        'webhook_url': 'https://example.com/hook',
        'webhook_enabled': true,
      });

      String? capturedBody;
      final mockClient = MockClient((request) async {
        capturedBody = request.body;
        return http.Response('ok', 200);
      });

      await http.runWithClient(
        () => WebhookClient.post(
          eventId: 'test-3',
          title: 'No Location',
          scheduledTime: DateTime.utc(2026, 1, 1, 12, 0),
          firedTime: DateTime.utc(2026, 1, 1, 12, 1),
          action: 'fire',
          location: '',
        ),
        () => mockClient,
      );

      expect(capturedBody, isNotNull);
      final payload = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(payload.containsKey('location'), isFalse);
    });

    test('includes location when non-empty', () async {
      SharedPreferences.setMockInitialValues({
        'webhook_url': 'https://example.com/hook',
        'webhook_enabled': true,
      });

      String? capturedBody;
      final mockClient = MockClient((request) async {
        capturedBody = request.body;
        return http.Response('ok', 200);
      });

      await http.runWithClient(
        () => WebhookClient.post(
          eventId: 'test-4',
          title: 'With Location',
          scheduledTime: DateTime.utc(2026, 1, 1, 12, 0),
          firedTime: DateTime.utc(2026, 1, 1, 12, 1),
          action: 'fire',
          location: 'Conference Room A',
          alarmKind: 'start',
        ),
        () => mockClient,
      );

      expect(capturedBody, isNotNull);
      final payload = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(payload['location'], 'Conference Room A');
      expect(payload['alarm_kind'], 'start');
    });

    test('skips POST when webhook disabled', () async {
      SharedPreferences.setMockInitialValues({
        'webhook_url': 'https://example.com/hook',
        'webhook_enabled': false,
      });

      var wasCalled = false;
      final mockClient = MockClient((request) async {
        wasCalled = true;
        return http.Response('ok', 200);
      });

      await http.runWithClient(
        () => WebhookClient.post(
          eventId: 'test-5',
          title: 'Disabled',
          scheduledTime: DateTime.utc(2026, 1, 1, 12, 0),
          firedTime: DateTime.utc(2026, 1, 1, 12, 1),
          action: 'fire',
        ),
        () => mockClient,
      );

      expect(wasCalled, isFalse);
    });
  });
}
