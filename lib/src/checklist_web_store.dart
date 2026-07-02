import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'checklist.dart';

/// Web backend for the checklist/to-do feature.
///
/// sqflite has no default web implementation, so `ChecklistRepo` delegates
/// to this store when `kIsWeb`. Same idiom as `Settings` (shared_preferences
/// + JSON-encoded blob) — no database introduced. Native platforms are
/// untouched; this class is never constructed off web.
class ChecklistWebStore {
  static const _kPrefsKey = 'checklist_web_v1';
  static const _kEveningRoutineIdPref = 'evening_routine_id_web';

  // In-memory cache of the decoded blob; reloaded lazily, written on every
  // mutation. Simple and correct for the data volumes a to-do list has.
  Map<String, dynamic>? _cache;
  int _nextRoutineId = 1;
  int _nextItemId = 1;

  Future<Map<String, dynamic>> _load() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKey);
    if (raw == null || raw.isEmpty) {
      _cache = _seedDefault();
      await _save(prefs);
      return _cache!;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _cache = decoded;
      _nextRoutineId = (decoded['nextRoutineId'] as int?) ?? 1;
      _nextItemId = (decoded['nextItemId'] as int?) ?? 1;
      return _cache!;
    } catch (_) {
      _cache = _seedDefault();
      await _save(prefs);
      return _cache!;
    }
  }

  Map<String, dynamic> _seedDefault() {
    final routines = <Map<String, dynamic>>[];
    final items = <Map<String, dynamic>>[];

    final morningId = _nextRoutineId++;
    routines.add({
      'id': morningId,
      'name': 'Morning routine',
      'isMorning': true,
      'triggerTime': null,
      'recurrence': 'daily',
    });
    for (var i = 0; i < ChecklistRepo.morningDefaults.length; i++) {
      items.add({
        'id': _nextItemId++,
        'routineId': morningId,
        'label': ChecklistRepo.morningDefaults[i],
        'orderIndex': i,
        'checked': false,
        'checkedAt': null,
        'checkedDay': null,
      });
    }

    // General/daily to-do routine — the list Mike actually interacts with
    // day to day (not just morning/evening scaffolding).
    final todoId = _nextRoutineId++;
    routines.add({
      'id': todoId,
      'name': 'To-Do',
      'isMorning': false,
      'triggerTime': null,
      'recurrence': 'manual',
    });
    items.add({
      'id': _nextItemId++,
      'routineId': todoId,
      'label': 'Link BoA card in RocketMoney',
      'orderIndex': 0,
      'checked': false,
      'checkedAt': null,
      'checkedDay': null,
    });

    return {
      'routines': routines,
      'items': items,
      'nextRoutineId': _nextRoutineId,
      'nextItemId': _nextItemId,
    };
  }

  Future<void> _save([SharedPreferences? prefsIn]) async {
    final prefs = prefsIn ?? await SharedPreferences.getInstance();
    final data = _cache!;
    data['nextRoutineId'] = _nextRoutineId;
    data['nextItemId'] = _nextItemId;
    await prefs.setString(_kPrefsKey, jsonEncode(data));
  }

  String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> resetIfNewDay() async {
    final data = await _load();
    final today = _today();
    final items = (data['items'] as List).cast<Map<String, dynamic>>();
    final routines = (data['routines'] as List).cast<Map<String, dynamic>>();
    // 'manual' routines (the plain to-do list) are not daily checklists —
    // completed items stay checked until the user unchecks or deletes them.
    final manualRoutineIds = routines
        .where((r) => (r['recurrence'] as String?) == 'manual')
        .map((r) => r['id'] as int)
        .toSet();
    var changed = false;
    for (final it in items) {
      if (manualRoutineIds.contains(it['routineId'])) continue;
      if (it['checked'] == true && it['checkedDay'] != today) {
        it['checked'] = false;
        it['checkedAt'] = null;
        it['checkedDay'] = null;
        changed = true;
      }
    }
    if (changed) await _save();
  }

  Future<List<ChecklistRoutine>> routines() async {
    final data = await _load();
    final routines = (data['routines'] as List).cast<Map<String, dynamic>>();
    final sorted = [...routines]
      ..sort((a, b) {
        final aM = (a['isMorning'] as bool) ? 0 : 1;
        final bM = (b['isMorning'] as bool) ? 0 : 1;
        if (aM != bM) return aM.compareTo(bM);
        return (a['id'] as int).compareTo(b['id'] as int);
      });
    return sorted.map(_routineFromMap).toList();
  }

  ChecklistRoutine _routineFromMap(Map<String, dynamic> r) => ChecklistRoutine(
        id: r['id'] as int,
        name: r['name'] as String,
        isMorning: r['isMorning'] as bool,
        triggerTime: r['triggerTime'] as String?,
        recurrence: (r['recurrence'] as String?) ?? 'daily',
      );

  Future<int> createRoutine(String name) async {
    final data = await _load();
    final id = _nextRoutineId++;
    (data['routines'] as List).add({
      'id': id,
      'name': name,
      'isMorning': false,
      'triggerTime': null,
      'recurrence': 'daily',
    });
    await _save();
    return id;
  }

  Future<void> updateRoutine(int id, {String? name, String? triggerTime, String? recurrence}) async {
    final data = await _load();
    final routines = (data['routines'] as List).cast<Map<String, dynamic>>();
    final r = routines.firstWhere((x) => x['id'] == id, orElse: () => {});
    if (r.isEmpty) return;
    if (name != null) r['name'] = name;
    if (triggerTime != null) r['triggerTime'] = triggerTime;
    if (recurrence != null) r['recurrence'] = recurrence;
    await _save();
  }

  Future<void> deleteRoutine(int routineId) async {
    final data = await _load();
    (data['items'] as List).removeWhere((it) => it['routineId'] == routineId);
    (data['routines'] as List).removeWhere((r) => r['id'] == routineId);
    await _save();
  }

  Future<List<ChecklistItem>> items(int routineId) async {
    await resetIfNewDay();
    final data = await _load();
    final items = (data['items'] as List).cast<Map<String, dynamic>>();
    final filtered = items.where((it) => it['routineId'] == routineId).toList()
      ..sort((a, b) {
        final oi = (a['orderIndex'] as int).compareTo(b['orderIndex'] as int);
        if (oi != 0) return oi;
        return (a['id'] as int).compareTo(b['id'] as int);
      });
    return filtered.map(_itemFromMap).toList();
  }

  ChecklistItem _itemFromMap(Map<String, dynamic> r) => ChecklistItem(
        id: r['id'] as int,
        routineId: r['routineId'] as int,
        label: r['label'] as String,
        orderIndex: r['orderIndex'] as int,
        checked: r['checked'] as bool,
        checkedAt: r['checkedAt'] != null ? DateTime.parse(r['checkedAt'] as String) : null,
      );

  Future<void> setChecked(int itemId, bool checked) async {
    final data = await _load();
    final items = (data['items'] as List).cast<Map<String, dynamic>>();
    final it = items.firstWhere((x) => x['id'] == itemId, orElse: () => {});
    if (it.isEmpty) return;
    it['checked'] = checked;
    it['checkedAt'] = checked ? DateTime.now().toIso8601String() : null;
    it['checkedDay'] = checked ? _today() : null;
    await _save();
  }

  Future<int> addItem(int routineId, String label) async {
    final data = await _load();
    final items = (data['items'] as List).cast<Map<String, dynamic>>();
    final maxOrder = items
        .where((it) => it['routineId'] == routineId)
        .map((it) => it['orderIndex'] as int)
        .fold<int>(-1, (a, b) => a > b ? a : b);
    final id = _nextItemId++;
    items.add({
      'id': id,
      'routineId': routineId,
      'label': label,
      'orderIndex': maxOrder + 1,
      'checked': false,
      'checkedAt': null,
      'checkedDay': null,
    });
    await _save();
    return id;
  }

  Future<void> removeItem(int itemId) async {
    final data = await _load();
    (data['items'] as List).removeWhere((it) => it['id'] == itemId);
    await _save();
  }

  Future<ChecklistRoutine?> morningRoutine() async {
    final list = await routines();
    for (final r in list) {
      if (r.isMorning) return r;
    }
    return null;
  }

  Future<ChecklistRoutine?> eveningRoutine() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_kEveningRoutineIdPref);
    if (id == null) return null;
    final list = await routines();
    for (final r in list) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<ChecklistRoutine> ensureEveningRoutine() async {
    final existing = await eveningRoutine();
    if (existing != null) return existing;
    final data = await _load();
    final id = _nextRoutineId++;
    (data['routines'] as List).add({
      'id': id,
      'name': 'Evening routine',
      'isMorning': false,
      'triggerTime': null,
      'recurrence': 'daily',
    });
    final items = (data['items'] as List).cast<Map<String, dynamic>>();
    for (var i = 0; i < ChecklistRepo.eveningDefaults.length; i++) {
      items.add({
        'id': _nextItemId++,
        'routineId': id,
        'label': ChecklistRepo.eveningDefaults[i],
        'orderIndex': i,
        'checked': false,
        'checkedAt': null,
        'checkedDay': null,
      });
    }
    await _save();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kEveningRoutineIdPref, id);
    return ChecklistRoutine(id: id, name: 'Evening routine', isMorning: false);
  }
}
