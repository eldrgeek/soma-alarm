import 'dart:convert';
import 'package:http/http.dart' as http;

import 'settings.dart';

class WebhookClient {
  static Future<void> post({
    required String eventId,
    required String title,
    required DateTime scheduledTime,
    required DateTime firedTime,
    required String action,
    String? location,
    String? alarmKind,
  }) async {
    if (!await Settings.webhookEnabled()) return;
    final url = await Settings.webhookUrl();
    try {
      await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'event_id': eventId,
              'title': title,
              'scheduled_time': scheduledTime.toUtc().toIso8601String(),
              'fired_time': firedTime.toUtc().toIso8601String(),
              'action': action,
              if (location != null && location.isNotEmpty) 'location': location,
              if (alarmKind != null) 'alarm_kind': alarmKind,
              'source': 'soma-alarm-android',
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // swallow — webhook is best-effort
    }
  }
}
