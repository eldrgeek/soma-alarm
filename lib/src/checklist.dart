import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class ChecklistRoutine {
  final int id;
  final String name;
  final bool isMorning;
  ChecklistRoutine({required this.id, required this.name, required this.isMorning});
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
}

class ChecklistRepo {
  static const _kDbVersion = 1;
  static const _kDbName = 'soma_checklist.db';

  static const morningDefaults = <String>[
    'Wear OMI',
    'OMI charged?',
    'Limitless Pendant on?',
    'Phone charged?',
  ];

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final path = p.join(dir, _kDbName);
    _db = await openDatabase(
      path,
      version: _kDbVersion,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE routines(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            is_morning INTEGER NOT NULL DEFAULT 0
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
    final db = await _open();
    final today = _today();
    await db.update(
      'items',
      {'checked': 0, 'checked_at': null, 'checked_day': null},
      where: '(checked_day IS NULL OR checked_day != ?) AND checked = 1',
      whereArgs: [today],
    );
  }

  Future<List<ChecklistRoutine>> routines() async {
    final db = await _open();
    final rows = await db.query('routines', orderBy: 'is_morning DESC, id ASC');
    return rows
        .map((r) => ChecklistRoutine(
              id: r['id'] as int,
              name: r['name'] as String,
              isMorning: (r['is_morning'] as int) == 1,
            ))
        .toList();
  }

  Future<int> createRoutine(String name) async {
    final db = await _open();
    return db.insert('routines', {'name': name, 'is_morning': 0});
  }

  Future<void> deleteRoutine(int routineId) async {
    final db = await _open();
    await db.delete('items', where: 'routine_id = ?', whereArgs: [routineId]);
    await db.delete('routines', where: 'id = ?', whereArgs: [routineId]);
  }

  Future<List<ChecklistItem>> items(int routineId) async {
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
    final db = await _open();
    await db.delete('items', where: 'id = ?', whereArgs: [itemId]);
  }

  Future<ChecklistRoutine?> morningRoutine() async {
    final list = await routines();
    for (final r in list) {
      if (r.isMorning) return r;
    }
    return null;
  }
}
