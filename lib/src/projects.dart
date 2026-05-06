import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

enum ProjectSort { alphabetical, mostRecent }

class Project {
  final int id;
  final String name;
  final DateTime createdAt;
  final DateTime lastAccessedAt;
  final bool pinnedToRecent;

  Project({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.lastAccessedAt,
    required this.pinnedToRecent,
  });

  factory Project.fromRow(Map<String, Object?> r) => Project(
        id: r['id'] as int,
        name: r['name'] as String,
        createdAt: DateTime.parse(r['created_at'] as String),
        lastAccessedAt: DateTime.parse(r['last_accessed_at'] as String),
        pinnedToRecent: (r['pinned_to_recent'] as int) == 1,
      );
}

class ProjectsRepo {
  static const _kDbVersion = 1;
  static const _kDbName = 'sidekick_projects.db';

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
          CREATE TABLE projects(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at TEXT NOT NULL,
            last_accessed_at TEXT NOT NULL,
            pinned_to_recent INTEGER NOT NULL DEFAULT 1
          )
        ''');
      },
    );
    return _db!;
  }

  Future<List<Project>> list({
    required bool recentOnly,
    required ProjectSort sort,
  }) async {
    final db = await _open();
    final where = recentOnly ? 'pinned_to_recent = 1' : null;
    final orderBy = switch (sort) {
      ProjectSort.alphabetical => 'name COLLATE NOCASE ASC',
      ProjectSort.mostRecent => 'last_accessed_at DESC',
    };
    final rows = await db.query(
      'projects',
      where: where,
      orderBy: orderBy,
    );
    return rows.map(Project.fromRow).toList();
  }

  Future<Project> create(String name) async {
    final db = await _open();
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('projects', {
      'name': name,
      'created_at': now,
      'last_accessed_at': now,
      'pinned_to_recent': 1,
    });
    final rows = await db.query('projects', where: 'id = ?', whereArgs: [id]);
    return Project.fromRow(rows.first);
  }

  Future<void> touch(int id) async {
    final db = await _open();
    await db.update(
      'projects',
      {
        'last_accessed_at': DateTime.now().toIso8601String(),
        'pinned_to_recent': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> pinToRecent(int id) async {
    final db = await _open();
    await db.update(
      'projects',
      {'pinned_to_recent': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> removeFromRecent(int id) async {
    final db = await _open();
    await db.update(
      'projects',
      {'pinned_to_recent': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(int id) async {
    final db = await _open();
    await db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }
}
