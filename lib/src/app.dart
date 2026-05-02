import 'package:flutter/material.dart';

import 'alarm_action_screen.dart';
import 'alarms.dart';
import 'home_page.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void navigateToAlarmAction(AlarmRecord rec) {
  navigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => AlarmActionScreen(record: rec)),
  );
}

class SomaAlarmApp extends StatelessWidget {
  const SomaAlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C4DFF),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'SOMA Alarm',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: colorScheme.surface,
      ),
      home: const HomePage(),
    );
  }
}
