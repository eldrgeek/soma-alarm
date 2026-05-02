import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soma_alarm/src/settings_page.dart';

import 'test_helpers.dart';

void main() {
  setUp(() {
    setupMockPlatformChannels();
  });

  Widget buildApp() => const MaterialApp(home: SettingsPage());

  group('SettingsPage _save()', () {
    testWidgets('invalid URL shows error snackbar', (tester) async {
      SharedPreferences.setMockInitialValues({
        'webhook_url': 'not-a-url',
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid URL — must be https://...'), findsOneWidget);
    });

    testWidgets('http URL shows error snackbar', (tester) async {
      SharedPreferences.setMockInitialValues({
        'webhook_url': 'http://example.com/hook',
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid URL — must be https://...'), findsOneWidget);
    });

    testWidgets('valid HTTPS URL saves and shows Saved snackbar', (tester) async {
      SharedPreferences.setMockInitialValues({
        'webhook_url': 'https://example.com/hook',
        'webhook_enabled': true,
        'morning_enabled': false,
        'lead_minutes': 15,
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 5));

      expect(find.text('Saved.'), findsOneWidget);
      expect(find.text('Test webhook'), findsOneWidget);
    });
  });
}
