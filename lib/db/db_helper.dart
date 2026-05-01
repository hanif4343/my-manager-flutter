import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/project.dart';
import '../models/idea.dart';
import '../models/idea_file.dart';

class DBHelper {
  static Database? _db;
  static const _version = 1;

  static Future<Database> get db async {
    _db ??= await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), 'mymanager.db');
    return openDatabase(path, version: _version, onCreate: _onCreate);
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE projects(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        color INTEGER NOT NULL DEFAULT 4284955319,
        tags TEXT,
        status TEXT DEFAULT 'active',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE ideas(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        status TEXT DEFAULT 'todo',
        priority TEXT DEFAULT 'medium',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(project_id) REFERENCES projects(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE idea_files(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        idea_id INTEGER NOT NULL,
        project_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        content TEXT,
        version INTEGER DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(idea_id) REFERENCES ideas(id)
      )
    ''');
  }

  // ── PROJECTS ──────────────────────────────────────────
  static Future<List<Project>> getProjects() async {
    final d = await db;
    final rows = await d.query('projects', orderBy: 'updated_at DESC');
    return rows.map(Project.fromMap).toList();
  }

  static Future<int> insertProject(Project p) async {
    final d = await db;
    return d.insert('projects', p.toMap());
  }

  static Future<void> updateProject(Project p) async {
    final d = await db;
    await d.update('projects', p.toMap(), where: 'id=?', whereArgs: [p.id]);
  }

  static Future<void> deleteProject(int id) async {
    final d = await db;
    final ideas = await d.query('ideas', where: 'project_id=?', whereArgs: [id]);
    for (final idea in ideas) {
      await d.delete('idea_files', where: 'idea_id=?', whereArgs: [idea['id']]);
    }
    await d.delete('ideas', where: 'project_id=?', whereArgs: [id]);
    await d.delete('projects', where: 'id=?', whereArgs: [id]);
  }

  static Future<Map<String, int>> getProjectStats(int projectId) async {
    final d = await db;
    final ideas = await d.query('ideas', where: 'project_id=?', whereArgs: [projectId]);
    final total = ideas.length;
    final done = ideas.where((i) => i['status'] == 'done').length;
    final doing = ideas.where((i) => i['status'] == 'doing').length;
    return {'total': total, 'done': done, 'doing': doing, 'todo': total - done - doing};
  }

  // ── IDEAS ─────────────────────────────────────────────
  static Future<List<Idea>> getIdeas(int projectId) async {
    final d = await db;
    final rows = await d.query('ideas',
        where: 'project_id=?', whereArgs: [projectId], orderBy: 'created_at DESC');
    return rows.map(Idea.fromMap).toList();
  }

  static Future<int> insertIdea(Idea idea) async {
    final d = await db;
    return d.insert('ideas', idea.toMap());
  }

  static Future<void> updateIdea(Idea idea) async {
    final d = await db;
    await d.update('ideas', idea.toMap(), where: 'id=?', whereArgs: [idea.id]);
  }

  static Future<void> deleteIdea(int id) async {
    final d = await db;
    await d.delete('idea_files', where: 'idea_id=?', whereArgs: [id]);
    await d.delete('ideas', where: 'id=?', whereArgs: [id]);
  }

  // ── FILES ─────────────────────────────────────────────
  static Future<List<IdeaFile>> getFiles(int ideaId) async {
    final d = await db;
    final rows = await d.query('idea_files',
        where: 'idea_id=?', whereArgs: [ideaId], orderBy: 'created_at ASC');
    return rows.map(IdeaFile.fromMap).toList();
  }

  static Future<int> insertFile(IdeaFile file) async {
    final d = await db;
    // auto-version
    final existing = await d.query('idea_files',
        where: 'idea_id=? AND name LIKE ?',
        whereArgs: [file.ideaId, '${file.baseName}%']);
    final version = existing.length + 1;
    return d.insert('idea_files', {...file.toMap(), 'version': version});
  }

  static Future<void> updateFile(IdeaFile file) async {
    final d = await db;
    await d.update('idea_files', file.toMap(), where: 'id=?', whereArgs: [file.id]);
  }

  static Future<void> deleteFile(int id) async {
    final d = await db;
    await d.delete('idea_files', where: 'id=?', whereArgs: [id]);
  }
}
