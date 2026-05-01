import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soma_alarm/src/home_page.dart';

import 'test_helpers.dart';

void main() {
  setUp(() {
    setupMockPlatformChannels();
  });

  Widget buildApp() => const MaterialApp(home: HomePage());

  group('HomePage diagnostics dialog', () {
    testWidgets('opens and displays expected fields', (tester) async {
      SharedPreferences.setMockInitialValues({
        'webhook_url': 'https://example.com/hook',
        'webhook_enabled': true,
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.bug_report));
      await tester.pumpAndSettle();

      expect(find.text('Diagnostics'), findsOneWidget);
      expect(find.textContaining('Version: 0.1.0'), findsOneWidget);
      expect(find.textContaining('Build:'), findsOneWidget);
      expect(find.textContaining('Calendar permission:'), findsOneWidget);
      expect(find.textContaining('Raw instances'), findsOneWidget);
      expect(find.textContaining('Scheduled alarms:'), findsOneWidget);
      expect(find.textContaining('Webhook:'), findsOneWidget);
      expect(find.text('Force Calendar Sync'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('Close button dismisses dialog', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.bug_report));
      await tester.pumpAndSettle();
      expect(find.text('Diagnostics'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Diagnostics'), findsNothing);
    });
  });
}
