import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/theme_provider.dart';
import 'alarm_action_screen.dart';
import 'alarms.dart';
import 'home_page.dart';
import 'pages.dart';
import 'web_shell.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void navigateToAlarmAction(AlarmRecord rec) {
  navigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => AlarmActionScreen(record: rec)),
  );
}

void navigateToHealthTab(String component) {
  // By id, not index — Health may sit anywhere in the nav, or be switched off
  // entirely (in which case the shell opens it as a route).
  WebShell.requestPage(PulsePages.health);
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
        home: const WebShell(),
      ),
    );
  }
}
