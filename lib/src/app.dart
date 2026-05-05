import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/theme_provider.dart';
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
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Pulse',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: themeProvider.themeData,
        home: const HomePage(),
      ),
    );
  }
}
