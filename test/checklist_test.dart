// Covers the checklist / to-do feature end to end on both backends:
//  - ChecklistWebStore (web path: shared_preferences-backed JSON, new code)
//  - ChecklistRepo native path (sqflite, via sqflite_common_ffi for VM tests)
//
// Widget-level coverage lives in checklist_page_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sidekick/src/checklist.dart';
import 'package:sidekick/src/checklist_web_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('ChecklistWebStore (web to-do backend)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('seeds a To-Do routine with the RocketMoney demo item', () async {
      final store = ChecklistWebStore();
      final routines = await store.routines();
      final todo = routines.firstWhere((r) => r.name == 'To-Do');
      final items = await store.items(todo.id);
      expect(items, hasLength(1));
      expect(items.first.label, 'Link BoA card in RocketMoney');
      expect(items.first.checked, isFalse);
    });

    test('add, toggle, and remove item', () async {
      final store = ChecklistWebStore();
      final routines = await store.routines();
      final todo = routines.firstWhere((r) => r.name == 'To-Do');

      final newId = await store.addItem(todo.id, 'Buy milk');
      var items = await store.items(todo.id);
      expect(items.any((i) => i.id == newId && i.label == 'Buy milk'), isTrue);

      await store.setChecked(newId, true);
      items = await store.items(todo.id);
      expect(items.firstWhere((i) => i.id == newId).checked, isTrue);

      await store.removeItem(newId);
      items = await store.items(todo.id);
      expect(items.any((i) => i.id == newId), isFalse);
    });

    test('persists across new store instances (simulates process restart)', () async {
      final store1 = ChecklistWebStore();
      final routines = await store1.routines();
      final todo = routines.firstWhere((r) => r.name == 'To-Do');
      final id = await store1.addItem(todo.id, 'Survive a restart');
      await store1.setChecked(id, true);

      // Fresh instance, same backing shared_preferences store —
      // this is what happens when the serving process restarts.
      final store2 = ChecklistWebStore();
      final items = await store2.items(todo.id);
      final restored = items.firstWhere((i) => i.label == 'Survive a restart');
      expect(restored.checked, isTrue);
    });
  });

  group('ChecklistRepo (native sqflite backend, unaffected by web changes)', () {
    test('add, toggle, and remove item against a real sqlite db', () async {
      final repo = ChecklistRepo();
      final morning = await repo.morningRoutine();
      expect(morning, isNotNull);

      final id = await repo.addItem(morning!.id, 'Native item');
      var items = await repo.items(morning.id);
      expect(items.any((i) => i.id == id && i.label == 'Native item'), isTrue);

      await repo.setChecked(id, true);
      items = await repo.items(morning.id);
      expect(items.firstWhere((i) => i.id == id).checked, isTrue);

      await repo.removeItem(id);
      items = await repo.items(morning.id);
      expect(items.any((i) => i.id == id), isFalse);
    });
  });
}
