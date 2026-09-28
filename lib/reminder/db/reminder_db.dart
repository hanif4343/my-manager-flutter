import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/reminder.dart';

/// রিমাইন্ডার নিজের আলাদা ফাইলে (reminders.db) থাকে — বাকি অ্যাপের
/// ডাটাবেসে কোনো হাত পড়ে না। নোটিফিকেশনের Done / Not yet বাটন
/// ব্যাকগ্রাউন্ড আইসোলেট থেকেও এই ক্লাস ব্যবহার করে।
class ReminderDB {
  static Database? _db;
  static const _version = 1;
  static const fileName = 'reminders.db';

  static Future<Database> get db async {
    _db ??= await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final path = join(await getDatabasesPath(), fileName);
    return openDatabase(path, version: _version, onCreate: (db, v) async {
      await db.execute('''
        CREATE TABLE reminders(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          note TEXT,
          kind TEXT NOT NULL DEFAULT 'note',
          date TEXT NOT NULL,
          times TEXT NOT NULL,
          repeat TEXT NOT NULL DEFAULT 'none',
          done INTEGER NOT NULL DEFAULT 0,
          last_done_date TEXT,
          created_at INTEGER NOT NULL
        )
      ''');
    });
  }

  static Future<int> insert(Reminder r) async {
    final d = await db;
    final map = r.toMap()..remove('id');
    return d.insert('reminders', map);
  }

  static Future<void> update(Reminder r) async {
    final d = await db;
    await d.update('reminders', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
  }

  static Future<void> delete(int id) async {
    final d = await db;
    await d.delete('reminders', where: 'id = ?', whereArgs: [id]);
  }

  static Future<Reminder?> getById(int id) async {
    final d = await db;
    final rows = await d.query('reminders', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Reminder.fromMap(rows.first);
  }

  static Future<List<Reminder>> all() async {
    final d = await db;
    final rows = await d.query('reminders', orderBy: 'date ASC, id ASC');
    return rows.map(Reminder.fromMap).toList();
  }
}
