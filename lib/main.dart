import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';

import 'src/alarms.dart';
import 'src/app.dart';
import 'src/background.dart';
import 'theme/theme_provider.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    return await runBackgroundPoll();
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeProvider = ThemeProvider();
  await themeProvider.load();

  await AlarmService.instance.init();
  AlarmService.instance.onNotificationTap = navigateToAlarmAction;
  final launchRec = await AlarmService.instance.getLaunchAlarmRecord();

  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    'soma-calendar-poll',
    'calendarPoll',
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );

  runApp(
    ChangeNotifierProvider.value(
      value: themeProvider,
      child: const SomaAlarmApp(),
    ),
  );

  if (launchRec != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigateToAlarmAction(launchRec);
    });
  }
}
