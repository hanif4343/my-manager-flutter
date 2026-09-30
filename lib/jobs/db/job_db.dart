import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/job_models.dart';

/// চাকরি হাবের নিজের আলাদা ডাটাবেস (jobs.db) — বাকি অ্যাপের ডাটাবেসে
/// হাত পড়ে না।
class JobDB {
  static Database? _db;
  static const _version = 1;

  static Future<Database> get db async {
    _db ??= await _init();
    return _db!;
  }

  /// ডিফল্ট ডকুমেন্ট চেকলিস্ট — প্রতিটা সার্কুলারের শর্ত আলাদা, তাই সবসময়
  /// বিজ্ঞপ্তির সাথে মিলিয়ে নিও; নিজের মতো যোগ/মুছতে পারবে।
  static const _defaultDocs = [
    'জাতীয় পরিচয়পত্র (NID) / জন্মনিবন্ধন',
    'সকল শিক্ষাগত সনদ ও মার্কশিট (মূল + ফটোকপি)',
    'নাগরিকত্ব সনদ',
    'চারিত্রিক সনদ / প্রত্যয়নপত্র',
    'পাসপোর্ট সাইজ ছবি (সত্যায়িত)',
    'স্বাক্ষরের স্ক্যান',
    'কোটা সনদ (প্রযোজ্য হলে)',
    'অভিজ্ঞতার সনদ (প্রযোজ্য হলে)',
    'আবেদন ফি জমার রসিদ',
    'প্রবেশপত্রের প্রিন্ট',
  ];

  static Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'jobs.db');
    return openDatabase(path, version: _version, onCreate: (db, v) async {
      await db.execute('''
        CREATE TABLE circulars(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          org TEXT,
          post TEXT,
          deadline TEXT,
          exam_date TEXT,
          fee INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'watching',
          url TEXT,
          note TEXT,
          deadline_rem TEXT,
          exam_rem TEXT,
          created_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE job_docs(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          done INTEGER NOT NULL DEFAULT 0,
          sort INTEGER NOT NULL DEFAULT 0
        )
      ''');
      for (var i = 0; i < _defaultDocs.length; i++) {
        await db.insert('job_docs', {'title': _defaultDocs[i], 'done': 0, 'sort': i});
      }
    });
  }

  // ── সার্কুলার ──
  static Future<int> insert(Circular c) async {
    final d = await db;
    final m = c.toMap()..remove('id');
    return d.insert('circulars', m);
  }

  static Future<void> update(Circular c) async {
    final d = await db;
    await d.update('circulars', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
  }

  static Future<void> delete(int id) async {
    final d = await db;
    await d.delete('circulars', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<Circular>> all() async {
    final d = await db;
    final rows = await d.query('circulars');
    return rows.map(Circular.fromMap).toList();
  }

  // ── ডকুমেন্ট ──
  static Future<List<JobDoc>> docs() async {
    final d = await db;
    final rows = await d.query('job_docs', orderBy: 'sort ASC, id ASC');
    return rows.map(JobDoc.fromMap).toList();
  }

  static Future<int> insertDoc(String title) async {
    final d = await db;
    final r = await d.rawQuery('SELECT COALESCE(MAX(sort), -1) + 1 AS n FROM job_docs');
    final next = (r.first['n'] as int?) ?? 0;
    return d.insert('job_docs', {'title': title, 'done': 0, 'sort': next});
  }

  static Future<void> setDocDone(int id, bool done) async {
    final d = await db;
    await d.update('job_docs', {'done': done ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteDoc(int id) async {
    final d = await db;
    await d.delete('job_docs', where: 'id = ?', whereArgs: [id]);
  }
}
