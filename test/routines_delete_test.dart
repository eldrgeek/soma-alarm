// Bug A — Cannot delete routines.
//
// TDD discipline: this test was written first against an unmodified
// ChecklistPage; it failed because no UI affordance existed for deletion.
// The fix added long-press on the routine ChoiceChip → bottom sheet →
// confirm dialog → ChecklistApi.deleteRoutine().
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/src/checklist_page.dart';

import '_helpers/fake_checklist_repo.dart';

void main() {
  group('Bug A — delete routine via long-press', () {
    testWidgets('long-press chip → bottom sheet → confirm → routine gone',
        (tester) async {
      final repo = FakeChecklistRepo();
      await repo.createRoutine('Workout');

      await tester.pumpWidget(MaterialApp(
        home: ChecklistPage(repo: repo),
      ));
      await tester.pumpAndSettle();

      // Both chips render.
      expect(find.text('Morning routine'), findsOneWidget);
      expect(find.text('Workout'), findsOneWidget);

      // Long-press on the user-created routine.
      await tester.longPress(find.text('Workout'));
      await tester.pumpAndSettle();

      // Bottom sheet opens with a Delete entry.
      expect(find.text('Delete routine'), findsOneWidget);
      await tester.tap(find.text('Delete routine'));
      await tester.pumpAndSettle();

      // Confirm dialog with the routine's name in the title.
      expect(find.textContaining('Delete "Workout"?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      // Routine gone from UI and from repo.
      expect(find.text('Workout'), findsNothing);
      expect((await repo.routines()).map((r) => r.name).toList(),
          ['Morning routine']);
    });

    testWidgets('cancelling the confirm dialog leaves routine in place',
        (tester) async {
      final repo = FakeChecklistRepo();
      await repo.createRoutine('Workout');

      await tester.pumpWidget(MaterialApp(home: ChecklistPage(repo: repo)));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Workout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete routine'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Workout'), findsOneWidget);
      expect((await repo.routines()).length, 2);
    });

    testWidgets('cannot delete the only remaining routine', (tester) async {
      // Repo seeds Morning routine; that's the only one.
      final repo = FakeChecklistRepo();

      await tester.pumpWidget(MaterialApp(home: ChecklistPage(repo: repo)));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Morning routine'));
      await tester.pumpAndSettle();

      // The Delete row exists but is disabled (subtitle explains why).
      expect(find.text("Can't delete the only routine"), findsOneWidget);
    });
  });
}
