import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'src/alarms.dart';
import 'src/app.dart';
import 'src/background.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    return await runBackgroundPoll();
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AlarmService.instance.init();
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  await Workmanager().registerPeriodicTask(
    'soma-calendar-poll',
    'calendarPoll',
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );
  runApp(const SomaAlarmApp());
}
