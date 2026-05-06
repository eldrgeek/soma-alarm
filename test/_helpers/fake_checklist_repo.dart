import 'package:sidekick/src/checklist.dart';
import 'package:sidekick/src/checklist_page.dart';

/// In-memory ChecklistApi for widget tests. Mirrors the persistence semantics
/// of ChecklistRepo (autoincrement IDs, FK cascade on routine delete) without
/// touching sqflite.
class FakeChecklistRepo implements ChecklistApi {
  final List<ChecklistRoutine> _routines = [];
  final List<ChecklistItem> _items = [];
  int _nextRoutineId = 1;
  int _nextItemId = 1;

  FakeChecklistRepo({bool seedMorning = true}) {
    if (seedMorning) {
      _routines.add(ChecklistRoutine(
        id: _nextRoutineId++,
        name: 'Morning routine',
        isMorning: true,
      ));
    }
  }

  @override
  Future<void> resetIfNewDay() async {}

  @override
  Future<List<ChecklistRoutine>> routines() async => List.of(_routines);

  @override
  Future<List<ChecklistItem>> items(int routineId) async =>
      _items.where((i) => i.routineId == routineId).toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

  @override
  Future<int> createRoutine(String name) async {
    final id = _nextRoutineId++;
    _routines.add(ChecklistRoutine(id: id, name: name, isMorning: false));
    return id;
  }

  @override
  Future<void> deleteRoutine(int routineId) async {
    _items.removeWhere((i) => i.routineId == routineId);
    _routines.removeWhere((r) => r.id == routineId);
  }

  @override
  Future<int> addItem(int routineId, String label) async {
    final id = _nextItemId++;
    final order =
        _items.where((i) => i.routineId == routineId).length;
    _items.add(ChecklistItem(
      id: id,
      routineId: routineId,
      label: label,
      orderIndex: order,
      checked: false,
    ));
    return id;
  }

  @override
  Future<void> removeItem(int itemId) async {
    _items.removeWhere((i) => i.id == itemId);
  }

  @override
  Future<void> setChecked(int itemId, bool checked) async {
    final idx = _items.indexWhere((i) => i.id == itemId);
    if (idx < 0) return;
    final old = _items[idx];
    _items[idx] = ChecklistItem(
      id: old.id,
      routineId: old.routineId,
      label: old.label,
      orderIndex: old.orderIndex,
      checked: checked,
      checkedAt: checked ? DateTime.now() : null,
    );
  }
}
