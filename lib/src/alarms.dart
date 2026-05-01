import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'webhook.dart';

const String kEventChannel = 'soma_event_alarms_v2';
const String kMorningChannel = 'soma_morning_alarm_v2';
const String _kOldEventChannel = 'soma_event_alarms';
const String _kOldMorningChannel = 'soma_morning_alarm';

const String kActionSnooze5 = 'snooze5';
const String kActionSnooze10 = 'snooze10';
const String kActionDismiss = 'dismiss';
const String kActionFire = 'fire';
const String kActionMorning = 'morning';

class AlarmRecord {
  final String eventId;
  final String title;
  final DateTime scheduled;
  final String? location;
  final bool dismissed;
  final bool isLeadAlarm;

  AlarmRecord({
    required this.eventId,
    required this.title,
    required this.scheduled,
    this.location,
    this.dismissed = false,
    this.isLeadAlarm = true,
  });

  Map<String, dynamic> toJson() => {
        'event_id': eventId,
        'title': title,
        'scheduled': scheduled.toIso8601String(),
        'location': location,
        'dismissed': dismissed,
        'is_lead': isLeadAlarm,
      };

  factory AlarmRecord.fromJson(Map<String, dynamic> j) => AlarmRecord(
        eventId: j['event_id'] as String,
        title: j['title'] as String,
        scheduled: DateTime.parse(j['scheduled'] as String),
        location: j['location'] as String?,
        dismissed: (j['dismissed'] as bool?) ?? false,
        isLeadAlarm: (j['is_lead'] as bool?) ?? true,
      );
}

class AlarmService {
  AlarmService._();
  static final instance = AlarmService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const String _kScheduledKey = 'scheduled_alarms';

  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    final localName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localName));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onAction,
      onDidReceiveBackgroundNotificationResponse: _onActionBackground,
    );

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();

    await androidImpl?.deleteNotificationChannel(_kOldEventChannel);
    await androidImpl?.deleteNotificationChannel(_kOldMorningChannel);

    final vibPattern = Int64List.fromList(<int>[0, 500, 200, 500, 200, 500]);
    await androidImpl?.createNotificationChannel(AndroidNotificationChannel(
      kEventChannel,
      'Calendar event alarms',
      description: 'Alarms fired before calendar events.',
      importance: Importance.max,
      sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      vibrationPattern: vibPattern,
    ));
    await androidImpl?.createNotificationChannel(AndroidNotificationChannel(
      kMorningChannel,
      'Morning routine',
      description: 'Daily morning routine alarm.',
      importance: Importance.max,
      sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      vibrationPattern: vibPattern,
    ));

    _initialized = true;
  }

  int _idFor(String eventId, {required bool lead}) {
    final base = eventId.hashCode & 0x3fffffff;
    return lead ? base : base | 0x40000000;
  }

  AndroidNotificationDetails _eventDetails() {
    return AndroidNotificationDetails(
      kEventChannel,
      'Calendar event alarms',
      channelDescription: 'Alarms fired before calendar events.',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      playSound: true,
      sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(<int>[0, 500, 200, 500, 200, 500]),
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(kActionSnooze5, 'Snooze 5',
            cancelNotification: true, showsUserInterface: false),
        AndroidNotificationAction(kActionSnooze10, 'Snooze 10',
            cancelNotification: true, showsUserInterface: false),
        AndroidNotificationAction(kActionDismiss, 'Dismiss',
            cancelNotification: true, showsUserInterface: false),
      ],
    );
  }

  AndroidNotificationDetails _morningDetails() {
    return AndroidNotificationDetails(
      kMorningChannel,
      'Morning routine',
      channelDescription: 'Daily morning routine alarm.',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      playSound: true,
      sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(<int>[0, 500, 200, 500, 200, 500]),
    );
  }

  Future<void> scheduleEventAlarm(AlarmRecord rec) async {
    final id = _idFor(rec.eventId, lead: rec.isLeadAlarm);
    final tzWhen = tz.TZDateTime.from(rec.scheduled, tz.local);
    if (tzWhen.isBefore(tz.TZDateTime.now(tz.local))) return;
    await _plugin.zonedSchedule(
      id,
      rec.title,
      _alarmBody(rec),
      tzWhen,
      NotificationDetails(android: _eventDetails()),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: jsonEncode(rec.toJson()),
    );
    await _persistScheduled(rec);
  }

  String _alarmBody(AlarmRecord rec) {
    final whenLocal = rec.scheduled.toLocal();
    final hh = whenLocal.hour.toString().padLeft(2, '0');
    final mm = whenLocal.minute.toString().padLeft(2, '0');
    final loc = (rec.location != null && rec.location!.isNotEmpty)
        ? ' • ${rec.location}'
        : '';
    return rec.isLeadAlarm
        ? 'Starts at $hh:$mm$loc'
        : 'NOW • $hh:$mm$loc';
  }

  Future<void> cancelForEvent(String eventId) async {
    await _plugin.cancel(_idFor(eventId, lead: true));
    await _plugin.cancel(_idFor(eventId, lead: false));
    await _removeScheduled(eventId);
  }

  Future<void> cancelAlarm(String eventId, {required bool lead}) async {
    await _plugin.cancel(_idFor(eventId, lead: lead));
    await _removeScheduledByKind(eventId, lead: lead);
  }

  Future<void> scheduleMorningAlarm({
    required int hour,
    required int minute,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) {
      when = when.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      0xCAFE,
      'Morning routine',
      'Tap to run today\'s checklist',
      when,
      NotificationDetails(android: _morningDetails()),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: jsonEncode({'kind': 'morning'}),
    );
  }

  Future<void> cancelMorningAlarm() => _plugin.cancel(0xCAFE);

  Future<void> scheduleTestAlarm() async {
    final when = DateTime.now().add(const Duration(seconds: 5));
    await scheduleEventAlarm(AlarmRecord(
      eventId: 'test-alarm-${when.millisecondsSinceEpoch}',
      title: 'Test alarm',
      scheduled: when,
      isLeadAlarm: false,
    ));
  }

  Future<List<AlarmRecord>> scheduledAlarms() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_kScheduledKey) ?? const [];
    return list
        .map((s) => AlarmRecord.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> _persistScheduled(AlarmRecord rec) async {
    final p = await SharedPreferences.getInstance();
    final existing = p.getStringList(_kScheduledKey) ?? <String>[];
    existing.removeWhere((s) {
      final j = jsonDecode(s) as Map<String, dynamic>;
      return j['event_id'] == rec.eventId && (j['is_lead'] ?? true) == rec.isLeadAlarm;
    });
    existing.add(jsonEncode(rec.toJson()));
    await p.setStringList(_kScheduledKey, existing);
  }

  Future<void> _removeScheduled(String eventId) async {
    final p = await SharedPreferences.getInstance();
    final existing = p.getStringList(_kScheduledKey) ?? <String>[];
    existing.removeWhere((s) {
      final j = jsonDecode(s) as Map<String, dynamic>;
      return j['event_id'] == eventId;
    });
    await p.setStringList(_kScheduledKey, existing);
  }

  Future<void> _removeScheduledByKind(String eventId, {required bool lead}) async {
    final p = await SharedPreferences.getInstance();
    final existing = p.getStringList(_kScheduledKey) ?? <String>[];
    existing.removeWhere((s) {
      final j = jsonDecode(s) as Map<String, dynamic>;
      return j['event_id'] == eventId && (j['is_lead'] ?? true) == lead;
    });
    await p.setStringList(_kScheduledKey, existing);
  }

  Future<void> _onAction(NotificationResponse resp) async {
    await _handleResponse(resp);
  }

  static Future<void> _handleResponse(NotificationResponse resp) async {
    if (resp.payload == null) return;
    final j = jsonDecode(resp.payload!) as Map<String, dynamic>;
    if (j['kind'] == 'morning') {
      await WebhookClient.post(
        eventId: 'morning-${DateTime.now().toIso8601String().split('T').first}',
        title: 'Morning routine',
        scheduledTime: DateTime.now(),
        firedTime: DateTime.now(),
        action: kActionMorning,
        alarmKind: 'morning',
      );
      return;
    }
    final rec = AlarmRecord.fromJson(j);
    final actionId = resp.actionId ?? kActionFire;
    await WebhookClient.post(
      eventId: rec.eventId,
      title: rec.title,
      scheduledTime: rec.scheduled,
      firedTime: DateTime.now(),
      action: actionId,
      location: rec.location,
      alarmKind: rec.isLeadAlarm ? 'lead' : 'start',
    );

    final svc = AlarmService.instance;
    await svc.init();

    if (actionId == kActionSnooze5 || actionId == kActionSnooze10) {
      final mins = actionId == kActionSnooze5 ? 5 : 10;
      final snoozed = AlarmRecord(
        eventId: rec.eventId,
        title: rec.title,
        scheduled: DateTime.now().add(Duration(minutes: mins)),
        location: rec.location,
        isLeadAlarm: rec.isLeadAlarm,
      );
      await svc.scheduleEventAlarm(snoozed);
    } else if (actionId == kActionDismiss) {
      await svc.cancelAlarm(rec.eventId, lead: rec.isLeadAlarm);
    }
  }
}

@pragma('vm:entry-point')
Future<void> _onActionBackground(NotificationResponse resp) async {
  await AlarmService._handleResponse(resp);
}
