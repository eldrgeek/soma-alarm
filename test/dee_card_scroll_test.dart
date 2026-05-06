// Bug D — Dee Stream card detail view is not scrollable.
//
// Repro: a long-bodied card is tapped to expand. Only the top half of the
// body is visible; the user can't reach the bottom paragraph and there is
// no visible scroll affordance.
//
// Fix: the expanded body is wrapped in a Scrollbar + SingleChildScrollView
// inside a height-bounded ConstrainedBox, so the user sees a clear thumb
// and can scroll within the card to reach the bottom of the message.
//
// These tests use `initiallyExpanded: true` so they don't depend on the
// InkWell tap behavior (which is covered by manual / integration testing).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sidekick/src/dee_stream/dee_said_models.dart';
import 'package:sidekick/src/dee_stream/dee_stream_page.dart';

const String _bottomMarker = 'BOTTOM-OF-BODY-MARKER';

DeeSaidEntry _longEntry() {
  final paragraphs = <String>[];
  for (var i = 0; i < 30; i++) {
    paragraphs.add(
      'Paragraph $i: ${'lorem ipsum dolor sit amet, consectetur adipiscing elit. ' * 4}',
    );
  }
  paragraphs.add(_bottomMarker);
  return DeeSaidEntry(
    id: 'long-1',
    title: 'Dee said:',
    body: paragraphs.join('\n\n'),
    status: 'pending',
    createdAt: DateTime(2026, 5, 6, 9, 30),
    updatedAt: DateTime(2026, 5, 6, 9, 30),
  );
}

Widget _harness(Widget card) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox.expand(child: card),
    ),
  );
}

void main() {
  group('Bug D — expanded Dee card has a scrollable body', () {
    testWidgets('expanded body lives inside a Scrollbar + SingleChildScrollView',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 851));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_harness(DeeCard(
        entry: _longEntry(),
        read: false,
        onMarkRead: () {},
        initiallyExpanded: true,
      )));
      await tester.pumpAndSettle();

      // Bug D's specific complaint: there's no scroll affordance. Fix asserts
      // a Scrollbar wrapping a SingleChildScrollView is present in the
      // expanded body.
      expect(find.byType(Scrollbar), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsAtLeastNWidgets(1));
    });

    testWidgets('long body — bottom marker is reachable by scrolling within the card',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 851));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_harness(DeeCard(
        entry: _longEntry(),
        read: false,
        onMarkRead: () {},
        initiallyExpanded: true,
      )));
      await tester.pumpAndSettle();

      // The marker exists in the tree (whole body is laid out).
      final marker = find.text(_bottomMarker);
      expect(marker, findsOneWidget);

      // Scroll inside the SingleChildScrollView to reveal it.
      final scrollable = find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      );
      await tester.dragUntilVisible(
        marker,
        scrollable.first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      final ro = tester.getRect(marker);
      expect(ro.top, lessThan(851),
          reason: 'Bottom marker must end up inside the visible viewport.');
      expect(ro.bottom, greaterThan(0));
    });

    testWidgets('short body — no scrollbar needed (sanity)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 851));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final shortEntry = DeeSaidEntry(
        id: 'short-1',
        title: 'Dee said:',
        body: 'Quick note.',
        status: 'pending',
        createdAt: DateTime(2026, 5, 6, 9, 30),
        updatedAt: DateTime(2026, 5, 6, 9, 30),
      );

      await tester.pumpWidget(_harness(DeeCard(
        entry: shortEntry,
        read: false,
        onMarkRead: () {},
        initiallyExpanded: true,
      )));
      await tester.pumpAndSettle();

      // Scroll wrapper is unconditional, but the short body still renders.
      expect(find.text('Quick note.'), findsAtLeastNWidgets(1));
    });
  });
}
