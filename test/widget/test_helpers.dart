import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// IDs of notifications cancelled via the mock plugin.
List<int> cancelledNotificationIds = [];

/// IDs of notifications scheduled via the mock plugin.
List<Map<String, dynamic>> scheduledNotifications = [];

void setupMockPlatformChannels() {
  SharedPreferences.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('org.esr.soma_alarm/calendar'),
    (call) async {
      if (call.method == 'getInstances') return <dynamic>[];
      if (call.method == 'requestSync') return true;
      return null;
    },
  );

  cancelledNotificationIds = [];
  scheduledNotifications = [];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dexterous.com/flutter/local_notifications'),
    (call) async {
      switch (call.method) {
        case 'initialize':
        case 'createNotificationChannelGroup':
        case 'createNotificationChannel':
        case 'requestNotificationsPermission':
        case 'requestExactAlarmsPermission':
          return true;
        case 'zonedSchedule':
          final args = call.arguments as Map;
          scheduledNotifications.add(Map<String, dynamic>.from(args));
          return null;
        case 'cancel':
          final args = call.arguments as Map;
          cancelledNotificationIds.add(args['id'] as int);
          return null;
        case 'pendingNotificationRequests':
          return <Map<String, dynamic>>[];
        default:
          return null;
      }
    },
  );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter_timezone'),
    (call) async {
      if (call.method == 'getLocalTimezone') return 'America/Denver';
      return null;
    },
  );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/permissions/methods'),
    (call) async {
      if (call.method == 'checkPermissionStatus') return 1;
      if (call.method == 'requestPermissions') return {0: 1};
      return null;
    },
  );
}
