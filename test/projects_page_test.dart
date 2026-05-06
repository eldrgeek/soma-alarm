import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sidekick/src/projects.dart';
import 'package:sidekick/src/projects_page.dart';

class _FakeRepo extends ProjectsRepo {
  _FakeRepo(this._items);
  final List<Project> _items;

  @override
  Future<List<Project>> list({
    required bool recentOnly,
    required ProjectSort sort,
  }) async {
    final filtered = recentOnly
        ? _items.where((p) => p.pinnedToRecent).toList()
        : List<Project>.from(_items);
    filtered.sort((a, b) => switch (sort) {
          ProjectSort.alphabetical =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          ProjectSort.mostRecent =>
            b.lastAccessedAt.compareTo(a.lastAccessedAt),
        });
    return filtered;
  }

  @override
  Future<Project> create(String name) async => throw UnimplementedError();
  @override
  Future<void> touch(int id) async {}
  @override
  Future<void> pinToRecent(int id) async {}
  @override
  Future<void> removeFromRecent(int id) async {}
  @override
  Future<void> delete(int id) async {}
}

Project _proj({
  required int id,
  required String name,
  required bool pinned,
  DateTime? accessed,
}) {
  final now = DateTime(2026, 5, 6, 12);
  return Project(
    id: id,
    name: name,
    createdAt: now,
    lastAccessedAt: accessed ?? now,
    pinnedToRecent: pinned,
  );
}

void main() {
  testWidgets('renders Recent and All tabs with correct items', (tester) async {
    final repo = _FakeRepo([
      _proj(id: 1, name: 'Aardvark', pinned: true,
          accessed: DateTime(2026, 5, 6, 10)),
      _proj(id: 2, name: 'Banana', pinned: false,
          accessed: DateTime(2026, 5, 6, 11)),
      _proj(id: 3, name: 'Cherry', pinned: true,
          accessed: DateTime(2026, 5, 6, 12)),
    ]);

    await tester.pumpWidget(MaterialApp(home: ProjectsPage(repo: repo)));
    await tester.pumpAndSettle();

    // Recent tab: only pinned items.
    expect(find.text('Aardvark'), findsOneWidget);
    expect(find.text('Cherry'), findsOneWidget);
    expect(find.text('Banana'), findsNothing);

    // Switch to All.
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(find.text('Aardvark'), findsOneWidget);
    expect(find.text('Banana'), findsOneWidget);
    expect(find.text('Cherry'), findsOneWidget);
  });

  testWidgets('Recent/All toggle changes which list is shown', (tester) async {
    final repo = _FakeRepo([
      _proj(id: 1, name: 'Pinned-One', pinned: true),
      _proj(id: 2, name: 'Unpinned-Two', pinned: false),
    ]);

    await tester.pumpWidget(MaterialApp(home: ProjectsPage(repo: repo)));
    await tester.pumpAndSettle();

    // Default tab is Recent.
    expect(find.text('Pinned-One'), findsOneWidget);
    expect(find.text('Unpinned-Two'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(find.text('Pinned-One'), findsOneWidget);
    expect(find.text('Unpinned-Two'), findsOneWidget);

    await tester.tap(find.text('Recent'));
    await tester.pumpAndSettle();

    expect(find.text('Unpinned-Two'), findsNothing);
  });

  testWidgets('empty Recent shows guidance copy', (tester) async {
    final repo = _FakeRepo([]);
    await tester.pumpWidget(MaterialApp(home: ProjectsPage(repo: repo)));
    await tester.pumpAndSettle();
    expect(find.textContaining('No recent projects'), findsOneWidget);
  });
}
