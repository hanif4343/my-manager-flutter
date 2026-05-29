import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/project.dart';
import '../models/idea.dart';
import '../models/idea_file.dart';

class DBHelper {
  static Database? _db;
  static const _version = 5;

  static Future<Database> get db async {
    _db ??= await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), 'mymanager.db');
    return openDatabase(path, version: _version,
        onCreate: _onCreate, onUpgrade: _onUpgrade);
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
        version INTEGER DEFAULT 1,
        sort_order INTEGER DEFAULT 0,
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
        is_archived INTEGER DEFAULT 0,
        deadline INTEGER,
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
    await db.execute('''
      CREATE TABLE project_versions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL,
        version INTEGER NOT NULL,
        note TEXT,
        snapshot TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY(project_id) REFERENCES projects(id)
      )
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      await db.execute('ALTER TABLE projects ADD COLUMN version INTEGER DEFAULT 1');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS project_versions(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          project_id INTEGER NOT NULL,
          version INTEGER NOT NULL,
          note TEXT,
          snapshot TEXT,
          created_at INTEGER NOT NULL,
          FOREIGN KEY(project_id) REFERENCES projects(id)
        )
      ''');
    }
    if (oldV < 3) {
      try {
        await db.execute('ALTER TABLE ideas ADD COLUMN is_archived INTEGER DEFAULT 0');
      } catch (_) {}
    }
    if (oldV < 4) {
      try {
        await db.execute('ALTER TABLE projects ADD COLUMN sort_order INTEGER DEFAULT 0');
        final rows = await db.query('projects', orderBy: 'updated_at DESC');
        for (int i = 0; i < rows.length; i++) {
          await db.update('projects', {'sort_order': i},
              where: 'id=?', whereArgs: [rows[i]['id']]);
        }
      } catch (_) {}
    }
    if (oldV < 5) {
      try {
        await db.execute('ALTER TABLE ideas ADD COLUMN deadline INTEGER');
      } catch (_) {}
    }
  }

  // ── PROJECTS ──────────────────────────────────────────
  static Future<List<Project>> getProjects() async {
    final d = await db;
    final rows = await d.query('projects', orderBy: 'sort_order ASC, updated_at DESC');
    return rows.map(Project.fromMap).toList();
  }

  static Future<int> insertProject(Project p) async {
    final d = await db;
    await d.execute('UPDATE projects SET sort_order = sort_order + 1');
    return d.insert('projects', {...p.toMap(), 'sort_order': 0});
  }

  static Future<void> updateProject(Project p) async {
    final d = await db;
    await d.update('projects', p.toMap(), where: 'id=?', whereArgs: [p.id]);
  }

  static Future<void> updateProjectOrder(int id, int order) async {
    final d = await db;
    await d.update('projects', {'sort_order': order},
        where: 'id=?', whereArgs: [id]);
  }

  static Future<void> deleteProject(int id) async {
    final d = await db;
    final ideas = await d.query('ideas', where: 'project_id=?', whereArgs: [id]);
    for (final idea in ideas) {
      await d.delete('idea_files', where: 'idea_id=?', whereArgs: [idea['id']]);
    }
    await d.delete('ideas', where: 'project_id=?', whereArgs: [id]);
    await d.delete('project_versions', where: 'project_id=?', whereArgs: [id]);
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

  // ── PROJECT VERSIONS ──────────────────────────────────
  static Future<List<Map<String, dynamic>>> getProjectVersions(int projectId) async {
    final d = await db;
    return d.query('project_versions',
        where: 'project_id=?', whereArgs: [projectId], orderBy: 'version DESC');
  }

  static Future<void> saveProjectVersion(int projectId, int version, String note) async {
    final d = await db;
    final ideas = await d.query('ideas', where: 'project_id=?', whereArgs: [projectId]);
    final snapshot = ideas.toString();
    await d.insert('project_versions', {
      'project_id': projectId,
      'version': version,
      'note': note,
      'snapshot': snapshot,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await d.update('projects', {'version': version, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id=?', whereArgs: [projectId]);
  }

  // ── IDEAS ─────────────────────────────────────────────
  static Future<List<Idea>> getIdeas(int projectId, {bool includeArchived = false}) async {
    final d = await db;
    final where = includeArchived
        ? 'project_id=?'
        : 'project_id=? AND (is_archived IS NULL OR is_archived=0)';
    final rows = await d.query('ideas',
        where: where, whereArgs: [projectId], orderBy: 'created_at DESC');
    return rows.map(Idea.fromMap).toList();
  }

  static Future<List<Idea>> getArchivedIdeas(int projectId) async {
    final d = await db;
    final rows = await d.query('ideas',
        where: 'project_id=? AND is_archived=1',
        whereArgs: [projectId], orderBy: 'updated_at DESC');
    return rows.map(Idea.fromMap).toList();
  }

  /// Get all non-archived ideas across all projects (for daily digest)
  static Future<List<Idea>> getAllActiveIdeas() async {
    final d = await db;
    final rows = await d.query('ideas',
        where: 'is_archived=0 OR is_archived IS NULL',
        orderBy: 'deadline ASC');
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

  static Future<void> archiveIdea(int id) async {
    final d = await db;
    await d.update('ideas',
        {'is_archived': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id=?', whereArgs: [id]);
  }

  static Future<void> unarchiveIdea(int id) async {
    final d = await db;
    await d.update('ideas',
        {'is_archived': 0, 'status': 'todo', 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id=?', whereArgs: [id]);
  }

  static Future<void> deleteIdea(int id) async {
    final d = await db;
    await d.delete('idea_files', where: 'idea_id=?', whereArgs: [id]);
    await d.delete('ideas', where: 'id=?', whereArgs: [id]);
  }

  // Bulk operations
  static Future<void> bulkUpdateStatus(List<int> ids, String status) async {
    final d = await db;
    final n = DateTime.now().millisecondsSinceEpoch;
    for (final id in ids) {
      await d.update('ideas', {'status': status, 'updated_at': n},
          where: 'id=?', whereArgs: [id]);
    }
  }

  static Future<void> bulkDelete(List<int> ids) async {
    final d = await db;
    for (final id in ids) {
      await d.delete('idea_files', where: 'idea_id=?', whereArgs: [id]);
      await d.delete('ideas', where: 'id=?', whereArgs: [id]);
    }
  }

  static Future<void> bulkMoveToProject(List<int> ids, int toProjectId) async {
    final d = await db;
    final n = DateTime.now().millisecondsSinceEpoch;
    for (final id in ids) {
      await d.update('ideas', {'project_id': toProjectId, 'updated_at': n},
          where: 'id=?', whereArgs: [id]);
      await d.update('idea_files', {'project_id': toProjectId},
          where: 'idea_id=?', whereArgs: [id]);
    }
  }

  // ── FILES ─────────────────────────────────────────────
  static Future<List<IdeaFile>> getFiles(int ideaId) async {
    final d = await db;
    final rows = await d.query('idea_files',
        where: 'idea_id=?', whereArgs: [ideaId], orderBy: 'created_at ASC');
    return rows.map(IdeaFile.fromMap).toList();
  }

  static Future<List<IdeaFile>> getAllFilesForProject(int projectId) async {
    final d = await db;
    final rows = await d.query('idea_files',
        where: 'project_id=?', whereArgs: [projectId]);
    return rows.map(IdeaFile.fromMap).toList();
  }

  static Future<int> insertFile(IdeaFile file) async {
    final d = await db;
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

  static Future<void> renameFile(int id, String newName) async {
    final d = await db;
    await d.update('idea_files',
        {'name': newName, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id=?', whereArgs: [id]);
  }

  static Future<int> copyFile(IdeaFile file, int toIdeaId, int toProjectId) async {
    final n = DateTime.now().millisecondsSinceEpoch;
    return insertFile(IdeaFile(
      ideaId: toIdeaId, projectId: toProjectId,
      name: file.name, type: file.type,
      content: file.content, createdAt: n, updatedAt: n,
    ));
  }

  static Future<void> moveFile(int fileId, int toIdeaId, int toProjectId) async {
    final d = await db;
    await d.update('idea_files',
        {'idea_id': toIdeaId, 'project_id': toProjectId,
         'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id=?', whereArgs: [fileId]);
  }

  static Future<List<Idea>> getAllIdeas() async {
    final d = await db;
    final rows = await d.query('ideas', orderBy: 'project_id ASC');
    return rows.map(Idea.fromMap).toList();
  }
}
