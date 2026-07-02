// Widget-level smoke coverage for TodayScreen, which now hosts the
// checklist/to-do rows inline (add / toggle / delete via long-press sheet).
//
// Full CRUD + persistence coverage for both backends (native sqflite and
// the web shared_preferences store) lives in checklist_test.dart, run as
// plain `test()` — sqflite_common_ffi's isolate-based I/O does not reliably
// resume inside flutter_test's widget-test pump loop, so exercising the
// interactive rows against a real database from a `testWidgets` test is
// left as a known gap (see report).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sidekick/src/today_screen.dart';

void main() {
  testWidgets('TodayScreen shows a loading state then does not crash', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TodayScreen()));
    await tester.pump();

    // The initial frame is the loading spinner while _load() awaits the
    // repo (native sqflite in this VM test harness). Confirming that much
    // renders is the crash-free smoke check for this environment; full
    // interactive coverage for both backends is in checklist_test.dart.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppBar has a refresh action', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TodayScreen()));
    await tester.pump();

    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
