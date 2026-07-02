import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'checklist_web_store.dart';

class ChecklistRoutine {
  final int id;
  final String name;
  final bool isMorning;
  // HH:MM string, nullable = no specific time
  final String? triggerTime;
  // 'daily', 'weekdays', 'weekends', 'manual'
  final String recurrence;
  ChecklistRoutine({
    required this.id,
    required this.name,
    required this.isMorning,
    this.triggerTime,
    this.recurrence = 'daily',
  });
}

class ChecklistItem {
  final int id;
  final int routineId;
  final String label;
  final int orderIndex;
  final bool checked;
  final DateTime? checkedAt;

  ChecklistItem({
    required this.id,
    required this.routineId,
    required this.label,
    required this.orderIndex,
    required this.checked,
    this.checkedAt,
  });

  ChecklistItem copyWith({bool? checked, DateTime? checkedAt}) => ChecklistItem(
        id: id,
        routineId: routineId,
        label: label,
        orderIndex: orderIndex,
        checked: checked ?? this.checked,
        checkedAt: checkedAt ?? this.checkedAt,
      );
}

class ChecklistRepo {
  static const _kDbVersion = 3;
  static const _kDbName = 'soma_checklist.db';

  static const morningDefaults = <String>[
    'Wear OMI',
    'OMI charged?',
    'Limitless Pendant on?',
    'Phone charged?',
  ];

  static const eveningDefaults = <String>[
    'Wind-down (no screens)',
    'Take evening meds',
    'ACIM / reflection',
    "Set out tomorrow's items",
  ];

  static const _kEveningRoutineIdPref = 'evening_routine_id';

  // sqflite has no default web backend. On web, every method below
  // delegates to a shared_preferences-backed store with the same public
  // API instead — same idiom as `Settings` (JSON blob, no database).
  // Native (Android/iOS) is completely untouched below this line.
  static final ChecklistWebStore _webStore = ChecklistWebStore();

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final path = p.join(dir, _kDbName);
    _db = await openDatabase(
      path,
      version: _kDbVersion,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Add checked_day for daily-reset logic (may be missing on old installs)
          try {
            await db.execute('ALTER TABLE items ADD COLUMN checked_day TEXT');
          } catch (_) { /* already exists */ }
        }
        if (oldVersion < 3) {
          // Add trigger_time and recurrence to routines
          try {
            await db.execute('ALTER TABLE routines ADD COLUMN trigger_time TEXT');
          } catch (_) {}
          try {
            await db.execute("ALTER TABLE routines ADD COLUMN recurrence TEXT NOT NULL DEFAULT 'daily'");
          } catch (_) {}
        }
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE routines(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            is_morning INTEGER NOT NULL DEFAULT 0,
            trigger_time TEXT,
            recurrence TEXT NOT NULL DEFAULT 'daily'
          )
        ''');
        await db.execute('''
          CREATE TABLE items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            routine_id INTEGER NOT NULL,
            label TEXT NOT NULL,
            order_index INTEGER NOT NULL DEFAULT 0,
            checked INTEGER NOT NULL DEFAULT 0,
            checked_at TEXT,
            checked_day TEXT,
            FOREIGN KEY(routine_id) REFERENCES routines(id) ON DELETE CASCADE
          )
        ''');
        final morningId = await db.insert('routines', {
          'name': 'Morning routine',
          'is_morning': 1,
        });
        for (var i = 0; i < morningDefaults.length; i++) {
          await db.insert('items', {
            'routine_id': morningId,
            'label': morningDefaults[i],
            'order_index': i,
            'checked': 0,
          });
        }
      },
    );
    return _db!;
  }

  String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> resetIfNewDay() async {
    if (kIsWeb) return _webStore.resetIfNewDay();
    final db = await _open();
    final today = _today();
    // 'manual' routines (e.g. the plain to-do list) are not daily
    // checklists — completed items stay checked until the user unchecks
    // or deletes them, so they're excluded from the daily reset sweep.
    await db.rawUpdate('''
      UPDATE items SET checked = 0, checked_at = NULL, checked_day = NULL
      WHERE (checked_day IS NULL OR checked_day != ?) AND checked = 1
        AND routine_id NOT IN (
          SELECT id FROM routines WHERE recurrence = 'manual'
        )
    ''', [today]);
  }

  Future<List<ChecklistRoutine>> routines() async {
    if (kIsWeb) return _webStore.routines();
    final db = await _open();
    final rows = await db.query('routines', orderBy: 'is_morning DESC, id ASC');
    return rows
        .map((r) => ChecklistRoutine(
              id: r['id'] as int,
              name: r['name'] as String,
              isMorning: (r['is_morning'] as int) == 1,
              triggerTime: r['trigger_time'] as String?,
              recurrence: (r['recurrence'] as String?) ?? 'daily',
            ))
        .toList();
  }

  Future<int> createRoutine(String name) async {
    if (kIsWeb) return _webStore.createRoutine(name);
    final db = await _open();
    return db.insert('routines', {'name': name, 'is_morning': 0});
  }

  Future<void> updateRoutine(int id, {String? name, String? triggerTime, String? recurrence}) async {
    if (kIsWeb) {
      return _webStore.updateRoutine(id, name: name, triggerTime: triggerTime, recurrence: recurrence);
    }
    final db = await _open();
    final vals = <String, dynamic>{};
    if (name != null) vals['name'] = name;
    if (triggerTime != null) vals['trigger_time'] = triggerTime;
    if (recurrence != null) vals['recurrence'] = recurrence;
    if (vals.isNotEmpty) await db.update('routines', vals, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteRoutine(int routineId) async {
    if (kIsWeb) return _webStore.deleteRoutine(routineId);
    final db = await _open();
    await db.delete('items', where: 'routine_id = ?', whereArgs: [routineId]);
    await db.delete('routines', where: 'id = ?', whereArgs: [routineId]);
  }

  Future<List<ChecklistItem>> items(int routineId) async {
    if (kIsWeb) return _webStore.items(routineId);
    await resetIfNewDay();
    final db = await _open();
    final rows = await db.query(
      'items',
      where: 'routine_id = ?',
      whereArgs: [routineId],
      orderBy: 'order_index ASC, id ASC',
    );
    return rows
        .map((r) => ChecklistItem(
              id: r['id'] as int,
              routineId: r['routine_id'] as int,
              label: r['label'] as String,
              orderIndex: r['order_index'] as int,
              checked: (r['checked'] as int) == 1,
              checkedAt: r['checked_at'] != null
                  ? DateTime.parse(r['checked_at'] as String)
                  : null,
            ))
        .toList();
  }

  Future<void> setChecked(int itemId, bool checked) async {
    if (kIsWeb) return _webStore.setChecked(itemId, checked);
    final db = await _open();
    await db.update(
      'items',
      {
        'checked': checked ? 1 : 0,
        'checked_at': checked ? DateTime.now().toIso8601String() : null,
        'checked_day': checked ? _today() : null,
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<int> addItem(int routineId, String label) async {
    if (kIsWeb) return _webStore.addItem(routineId, label);
    final db = await _open();
    final maxOrder = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COALESCE(MAX(order_index), -1) FROM items WHERE routine_id = ?',
            [routineId])) ??
        -1;
    return db.insert('items', {
      'routine_id': routineId,
      'label': label,
      'order_index': maxOrder + 1,
      'checked': 0,
    });
  }

  Future<void> removeItem(int itemId) async {
    if (kIsWeb) return _webStore.removeItem(itemId);
    final db = await _open();
    await db.delete('items', where: 'id = ?', whereArgs: [itemId]);
  }

  Future<ChecklistRoutine?> morningRoutine() async {
    // routines() already branches on kIsWeb internally.
    final list = await routines();
    for (final r in list) {
      if (r.isMorning) return r;
    }
    return null;
  }

  // The plain, non-daily to-do list. Web seeds this routine automatically
  // (see ChecklistWebStore); native does not auto-create it (Pixel/Android
  // parity is a deliberate follow-up, not silently added to existing
  // installs) — it only surfaces here if the user has already created one
  // via the Routines screen.
  Future<ChecklistRoutine?> todoRoutine() async {
    final list = await routines();
    for (final r in list) {
      if (r.name == 'To-Do') return r;
    }
    return null;
  }

  Future<ChecklistRoutine?> eveningRoutine() async {
    if (kIsWeb) return _webStore.eveningRoutine();
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_kEveningRoutineIdPref);
    if (id == null) return null;
    final db = await _open();
    final rows = await db.query('routines', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return ChecklistRoutine(
      id: r['id'] as int,
      name: r['name'] as String,
      isMorning: (r['is_morning'] as int) == 1,
      triggerTime: r['trigger_time'] as String?,
      recurrence: (r['recurrence'] as String?) ?? 'daily',
    );
  }

  Future<ChecklistRoutine> ensureEveningRoutine() async {
    if (kIsWeb) return _webStore.ensureEveningRoutine();
    final existing = await eveningRoutine();
    if (existing != null) return existing;
    final db = await _open();
    final id = await db.insert('routines', {'name': 'Evening routine', 'is_morning': 0});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kEveningRoutineIdPref, id);
    for (var i = 0; i < eveningDefaults.length; i++) {
      await db.insert('items', {
        'routine_id': id,
        'label': eveningDefaults[i],
        'order_index': i,
        'checked': 0,
      });
    }
    return ChecklistRoutine(id: id, name: 'Evening routine', isMorning: false);
  }
}
