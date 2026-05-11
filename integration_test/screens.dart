import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:sidekick/src/app.dart';
import 'package:sidekick/theme/theme_provider.dart';

// Run via:
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/screens.dart \
//     -d <device-id>
//
// Screenshots are collected by the driver and saved to the path set in
// test_driver/integration_test.dart (default: build/test_screenshots/).
//
// Pre-conditions:
//   Android: device unlocked, USB debugging on, adb authorized
//   iOS:     CocoaPods installed, device trusted, code-sign cert configured
//   macOS:   macOS platform target enabled (flutter create --platforms=macos .)

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
      as IntegrationTestWidgetsFlutterBinding;

  testWidgets('Pulse mobile screenshot suite', (tester) async {
    // Boot the app under test
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: const SomaAlarmApp(),
      ),
    );

    // Let the app settle — initState fires network/permission calls that
    // complete asynchronously. We give it 3 s real-time to render something
    // useful even if permissions are denied.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // ── Screen 1: Home (calendar + alarms) ───────────────────────────────
    await binding.takeScreenshot('01-home');

    // ── Screen 2: Settings ───────────────────────────────────────────────
    final settingsBtn = find.byTooltip('Settings');
    if (settingsBtn.evaluate().isNotEmpty) {
      await tester.tap(settingsBtn);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await binding.takeScreenshot('02-settings');
      // Back to home
      final backBtn = find.byTooltip('Back');
      if (backBtn.evaluate().isNotEmpty) {
        await tester.tap(backBtn);
        await tester.pumpAndSettle();
      } else {
        // Some platforms use a pop gesture
        final NavigatorState? nav = tester.state(find.byType(Navigator));
        nav?.pop();
        await tester.pumpAndSettle();
      }
    }

    // ── Screen 3: Routines / Checklist ───────────────────────────────────
    final routinesBtn = find.byTooltip('Routines');
    if (routinesBtn.evaluate().isNotEmpty) {
      await tester.tap(routinesBtn);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await binding.takeScreenshot('03-routines');
      final backBtn = find.byTooltip('Back');
      if (backBtn.evaluate().isNotEmpty) {
        await tester.tap(backBtn);
        await tester.pumpAndSettle();
      }
    }

    // ── Screen 4: Diagnostics dialog ─────────────────────────────────────
    final diagBtn = find.byTooltip('Diagnostics');
    if (diagBtn.evaluate().isNotEmpty) {
      await tester.tap(diagBtn);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await binding.takeScreenshot('04-diagnostics');
      // Dismiss dialog
      final closeBtn = find.text('Close');
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn);
        await tester.pumpAndSettle();
      }
    }

    // ── kIsWeb path (web build only) ─────────────────────────────────────
    // These screens are only visible when the app is built for web.
    // They exercise the Pulse dashboard (relay-connected).
    if (kIsWeb) {
      // Web shell: Jobs tab is index 0 (default)
      await binding.takeScreenshot('w01-jobs');

      // Activity tab
      final activityRailDest = find.text('Activity');
      if (activityRailDest.evaluate().isNotEmpty) {
        await tester.tap(activityRailDest);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        await binding.takeScreenshot('w02-activity');
      }

      // Putoff tab
      final putoffRailDest = find.text('Putoff');
      if (putoffRailDest.evaluate().isNotEmpty) {
        await tester.tap(putoffRailDest);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        await binding.takeScreenshot('w03-putoff');
      }

      // Health tab
      final healthRailDest = find.text('Health');
      if (healthRailDest.evaluate().isNotEmpty) {
        await tester.tap(healthRailDest);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        await binding.takeScreenshot('w04-health');
      }
    }
  });
}
