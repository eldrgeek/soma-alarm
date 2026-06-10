import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';

import 'src/alarms.dart';
import 'src/app.dart';
import 'src/background.dart';
import 'src/web_shell.dart';
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

  if (!kIsWeb) {
    await AlarmService.instance.init();
    AlarmService.instance.onNotificationTap = navigateToAlarmAction;
    AlarmService.instance.onHealthNotificationTap = navigateToHealthTab;
    // Asks render in the global AsksBanner; opening the app is enough.
    AlarmService.instance.onAskNotificationTap = (_) => WebShell.requestTab(0);
  }
  final launchRec =
      kIsWeb ? null : await AlarmService.instance.getLaunchAlarmRecord();

  if (!kIsWeb) {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      'soma-calendar-poll',
      'calendarPoll',
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

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
