import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/doc_models.dart';

/// ডকুমেন্ট ভল্টের মেটাডাটা (docs.db)। ফাইলের আসল বিষয়বস্তু এখানে নেই —
/// সেগুলো এনক্রিপ্ট হয়ে আলাদা ফোল্ডারে থাকে (DocsCrypto)।
///
/// v2: `tpl` কলাম যোগ — কোন ধরনের ডকুমেন্ট (NID, SSC…) তা মনে রাখতে।
/// v3: `owner` কলাম যোগ — কার ডকুমেন্ট (নিজের/স্ত্রী/সন্তান…)।
class DocsDB {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await openDatabase(
      join(await getDatabasesPath(), 'docs.db'),
      version: 3,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE docs(
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            category TEXT,
            number_enc TEXT,
            expiry TEXT,
            note TEXT,
            pages TEXT,
            rem TEXT,
            tpl TEXT,
            owner TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute('ALTER TABLE docs ADD COLUMN tpl TEXT');
        }
        if (oldV < 3) {
          await db.execute('ALTER TABLE docs ADD COLUMN owner TEXT');
        }
      },
    );
    return _db!;
  }

  static Future<List<VaultDoc>> all() async {
    final d = await db;
    final rows = await d.query('docs', orderBy: 'updated_at DESC');
    return rows.map(VaultDoc.fromMap).toList();
  }

  static Future<void> upsert(VaultDoc doc) async {
    final d = await db;
    await d.insert('docs', doc.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> delete(String id) async {
    final d = await db;
    await d.delete('docs', where: 'id = ?', whereArgs: [id]);
  }
}
