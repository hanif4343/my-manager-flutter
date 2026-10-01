import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/family_models.dart';

/// পরিবার মডিউলের নিজের আলাদা ডাটাবেস (family.db)।
class FamilyDB {
  static Database? _db;
  static const _version = 1;

  static Future<Database> get db async {
    _db ??= await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'family.db');
    return openDatabase(path, version: _version, onCreate: (db, v) async {
      await db.execute('''
        CREATE TABLE members(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          relation TEXT,
          birth_date TEXT,
          blood TEXT,
          phone TEXT,
          note TEXT,
          bday_rem TEXT,
          created_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE family_dates(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          kind TEXT,
          date TEXT NOT NULL,
          note TEXT,
          rem TEXT,
          created_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE bills(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          type TEXT,
          amount INTEGER NOT NULL DEFAULT 0,
          due_day INTEGER NOT NULL DEFAULT 10,
          last_paid_month TEXT,
          note TEXT,
          rem TEXT,
          created_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE contacts(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          kind TEXT,
          phone TEXT,
          note TEXT,
          created_at INTEGER NOT NULL
        )
      ''');
    });
  }

  // ── সাধারণ সহায়ক ──
  static Future<int> _insert(String table, Map<String, dynamic> m) async {
    final d = await db;
    final copy = Map<String, dynamic>.from(m)..remove('id');
    return d.insert(table, copy);
  }

  static Future<void> _update(String table, Map<String, dynamic> m, int id) async {
    final d = await db;
    await d.update(table, m, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> _delete(String table, int id) async {
    final d = await db;
    await d.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  // ── সদস্য ──
  static Future<List<FamilyMember>> members() async =>
      (await (await db).query('members', orderBy: 'created_at ASC')).map(FamilyMember.fromMap).toList();
  static Future<int> insertMember(FamilyMember m) => _insert('members', m.toMap());
  static Future<void> updateMember(FamilyMember m) => _update('members', m.toMap(), m.id!);
  static Future<void> deleteMember(int id) => _delete('members', id);

  // ── গুরুত্বপূর্ণ তারিখ ──
  static Future<List<FamilyDate>> dates() async =>
      (await (await db).query('family_dates', orderBy: 'created_at ASC')).map(FamilyDate.fromMap).toList();
  static Future<int> insertDate(FamilyDate x) => _insert('family_dates', x.toMap());
  static Future<void> updateDate(FamilyDate x) => _update('family_dates', x.toMap(), x.id!);
  static Future<void> deleteDate(int id) => _delete('family_dates', id);

  // ── বিল ──
  static Future<List<FamilyBill>> bills() async =>
      (await (await db).query('bills', orderBy: 'due_day ASC, id ASC')).map(FamilyBill.fromMap).toList();
  static Future<int> insertBill(FamilyBill b) => _insert('bills', b.toMap());
  static Future<void> updateBill(FamilyBill b) => _update('bills', b.toMap(), b.id!);
  static Future<void> deleteBill(int id) => _delete('bills', id);

  // ── জরুরি তথ্য ──
  static Future<List<FamilyContact>> contacts() async =>
      (await (await db).query('contacts', orderBy: 'created_at ASC')).map(FamilyContact.fromMap).toList();
  static Future<int> insertContact(FamilyContact c) => _insert('contacts', c.toMap());
  static Future<void> updateContact(FamilyContact c) => _update('contacts', c.toMap(), c.id!);
  static Future<void> deleteContact(int id) => _delete('contacts', id);
}
