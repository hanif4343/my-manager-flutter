import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/cashbook_account.dart';
import '../models/cashbook_entry.dart';
import '../models/cashbook_budget.dart';
import '../models/cashbook_debt.dart';

/// The Cashbook is deliberately kept out of mymanager.db — its own file
/// (cashbook.db), its own version history, its own migrations. Nothing
/// about the rest of the app (projects/ideas/vault) ever has to know
/// this table layout exists, and vice versa.
class CashbookDB {
  static Database? _db;
  static const _version = 1;
  static const fileName = 'cashbook.db';

  static Future<Database> get db async {
    _db ??= await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), fileName);
    return openDatabase(path, version: _version, onCreate: _onCreate);
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE accounts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        icon TEXT NOT NULL DEFAULT '👛',
        sort_order INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT NOT NULL,
        note TEXT,
        date TEXT NOT NULL,
        voucher_image TEXT,
        recurring INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(account_id) REFERENCES accounts(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE budgets(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL UNIQUE,
        monthly_limit REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE debts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        note TEXT,
        cleared INTEGER DEFAULT 0,
        date TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    // First-run only: seed a starting "নগদ" wallet so the account
    // switcher isn't empty on day one.
    await db.insert('accounts', {
      'name': 'নগদ',
      'icon': '💵',
      'sort_order': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── ACCOUNTS ──────────────────────────────────────────
  static Future<List<CashbookAccount>> getAccounts() async {
    final d = await db;
    final rows = await d.query('accounts', orderBy: 'id DESC');
    return rows.map(CashbookAccount.fromMap).toList();
  }

  static Future<int> insertAccount(CashbookAccount a) async {
    final d = await db;
    return d.insert('accounts', a.toMap());
  }

  static Future<void> deleteAccount(int id) async {
    final d = await db;
    await d.delete('entries', where: 'account_id=?', whereArgs: [id]);
    await d.delete('accounts', where: 'id=?', whereArgs: [id]);
  }

  static Future<void> renameAccount(int id, String newName) async {
    final d = await db;
    await d.update('accounts', {'name': newName}, where: 'id=?', whereArgs: [id]);
  }

  /// Balance of every account at once, for the "সব হিসাব" overview —
  /// one query per account is fine at this scale (dozens, not thousands).
  static Future<Map<int, double>> getAllBalances() async {
    final d = await db;
    final rows = await d.rawQuery('''
      SELECT account_id,
        COALESCE(SUM(CASE WHEN type='in' THEN amount ELSE -amount END), 0) as balance
      FROM entries GROUP BY account_id
    ''');
    return {for (final r in rows) r['account_id'] as int: (r['balance'] as num).toDouble()};
  }

  // Matches the exact spelling used by the legacy app's own month-named
  // ledgers (imported ones say "ফেব্রুয়ারী"/"আগষ্ট", not the more common
  // "ফেব্রুয়ারি"/"আগস্ট") — so a freshly auto-created month never ends up
  // as a separate, differently-spelled duplicate of an old one.
  static const _ledgerMonthNames = ['জানুয়ারি', 'ফেব্রুয়ারী', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
    'জুলাই', 'আগষ্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর'];
  static const _bnDigit = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
  static String _toBnDigits(int n) => n.toString().split('').map((c) => _bnDigit[int.parse(c)]).join();

  /// Creates this calendar month's ledger (e.g. "সেপ্টেম্বর-২০২৬") the
  /// first time the Cashbook is opened after the month has turned over —
  /// called from screen load, same "recompute on open" pattern as
  /// recurring entries and the reminder notification. Never touches or
  /// renames past months; only ever adds the current one, once.
  static Future<void> ensureCurrentMonthLedger() async {
    final now = DateTime.now();
    final name = '${_ledgerMonthNames[now.month - 1]}-${_toBnDigits(now.year)}';
    final d = await db;
    final existing = await d.query('accounts', where: 'name=?', whereArgs: [name], limit: 1);
    if (existing.isEmpty) {
      await d.insert('accounts', {
        'name': name,
        'icon': '📒',
        'sort_order': 0,
        'created_at': now.millisecondsSinceEpoch,
      });
    }
  }

  // ── ENTRIES ───────────────────────────────────────────
  static Future<List<CashbookEntry>> getEntries({int? accountId}) async {
    final d = await db;
    final rows = accountId == null
        ? await d.query('entries', orderBy: 'date DESC, id DESC')
        : await d.query('entries',
            where: 'account_id=?', whereArgs: [accountId], orderBy: 'date DESC, id DESC');
    return rows.map(CashbookEntry.fromMap).toList();
  }

  /// All entries whose note/category/amount text contains [query] — the
  /// global search that reaches across every account at once.
  static Future<List<CashbookEntry>> searchEntries(String query) async {
    final d = await db;
    final q = '%${query.toLowerCase()}%';
    final rows = await d.query('entries',
        where: 'LOWER(note) LIKE ? OR LOWER(category) LIKE ? OR CAST(amount AS TEXT) LIKE ?',
        whereArgs: [q, q, q], orderBy: 'date DESC, id DESC');
    return rows.map(CashbookEntry.fromMap).toList();
  }

  static Future<int> insertEntry(CashbookEntry e) async {
    final d = await db;
    return d.insert('entries', e.toMap());
  }

  static Future<void> updateEntry(CashbookEntry e) async {
    final d = await db;
    await d.update('entries', e.toMap(), where: 'id=?', whereArgs: [e.id]);
  }

  static Future<void> deleteEntry(int id) async {
    final d = await db;
    await d.delete('entries', where: 'id=?', whereArgs: [id]);
  }

  static String todayIso() => DateTime.now().toIso8601String().substring(0, 10);

  /// Used by the 8pm reminder — if today already has at least one entry
  /// (in any account) there's nothing to nudge the user about.
  static Future<bool> hasEntryToday() async {
    final d = await db;
    final rows = await d.query('entries', where: 'date=?', whereArgs: [todayIso()], limit: 1);
    return rows.isNotEmpty;
  }

  /// For every entry marked 🔁 recurring whose month is in the past,
  /// create this month's copy if one doesn't already exist — called once
  /// when the Cashbook screen opens so bills/salary keep showing up
  /// without the user re-typing them every month.
  static Future<int> processRecurring() async {
    final all = await getEntries();
    final thisMonth = todayIso().substring(0, 7);
    final recurringSources = all.where((e) => e.recurring && e.monthKey != thisMonth);
    final latestBySignature = <String, CashbookEntry>{};
    for (final e in recurringSources) {
      final sig = '${e.accountId}|${e.category}|${e.note}|${e.type}';
      final prev = latestBySignature[sig];
      if (prev == null || e.date.compareTo(prev.date) > 0) latestBySignature[sig] = e;
    }
    int created = 0;
    for (final src in latestBySignature.values) {
      final sig = '${src.accountId}|${src.category}|${src.note}|${src.type}';
      final alreadyThisMonth = all.any((e) =>
          e.monthKey == thisMonth &&
          '${e.accountId}|${e.category}|${e.note}|${e.type}' == sig);
      if (!alreadyThisMonth) {
        final n = DateTime.now().millisecondsSinceEpoch;
        await insertEntry(src.copyWith(date: todayIso(), updatedAt: n));
        created++;
      }
    }
    return created;
  }

  // ── BUDGETS ───────────────────────────────────────────
  static Future<List<CashbookBudget>> getBudgets() async {
    final d = await db;
    final rows = await d.query('budgets', orderBy: 'id ASC');
    return rows.map(CashbookBudget.fromMap).toList();
  }

  static Future<void> upsertBudget(CashbookBudget b) async {
    final d = await db;
    final existing = await d.query('budgets', where: 'category=?', whereArgs: [b.category]);
    if (existing.isEmpty) {
      await d.insert('budgets', b.toMap());
    } else {
      await d.update('budgets', {'monthly_limit': b.monthlyLimit},
          where: 'category=?', whereArgs: [b.category]);
    }
  }

  static Future<void> deleteBudget(int id) async {
    final d = await db;
    await d.delete('budgets', where: 'id=?', whereArgs: [id]);
  }

  /// Sum of খরচ entries in [category] for the current calendar month,
  /// across every account — a budget is a household-wide limit.
  static Future<double> spentThisMonth(String category) async {
    final d = await db;
    final thisMonth = todayIso().substring(0, 7);
    final rows = await d.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as total FROM entries
      WHERE type='out' AND category=? AND date LIKE ?
    ''', [category, '$thisMonth%']);
    return (rows.first['total'] as num).toDouble();
  }

  // ── DEBTS (দেনা-পাওনা) ────────────────────────────────
  static Future<List<CashbookDebt>> getDebts() async {
    final d = await db;
    final rows = await d.query('debts', orderBy: 'cleared ASC, date DESC');
    return rows.map(CashbookDebt.fromMap).toList();
  }

  static Future<int> insertDebt(CashbookDebt debt) async {
    final d = await db;
    return d.insert('debts', debt.toMap());
  }

  static Future<void> setDebtCleared(int id, bool cleared) async {
    final d = await db;
    await d.update('debts', {'cleared': cleared ? 1 : 0}, where: 'id=?', whereArgs: [id]);
  }

  static Future<void> deleteDebt(int id) async {
    final d = await db;
    await d.delete('debts', where: 'id=?', whereArgs: [id]);
  }

  // ── FULL EXPORT/IMPORT (for Drive backup) ────────────
  static Future<Map<String, dynamic>> exportAll() async {
    final d = await db;
    return {
      'accounts': await d.query('accounts'),
      'entries': await d.query('entries'),
      'budgets': await d.query('budgets'),
      'debts': await d.query('debts'),
    };
  }

  static Future<void> importAll(Map<String, dynamic> data) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('entries');
      await txn.delete('accounts');
      await txn.delete('budgets');
      await txn.delete('debts');
      for (final row in (data['accounts'] as List? ?? [])) {
        await txn.insert('accounts', Map<String, dynamic>.from(row));
      }
      for (final row in (data['entries'] as List? ?? [])) {
        await txn.insert('entries', Map<String, dynamic>.from(row));
      }
      for (final row in (data['budgets'] as List? ?? [])) {
        await txn.insert('budgets', Map<String, dynamic>.from(row));
      }
      for (final row in (data['debts'] as List? ?? [])) {
        await txn.insert('debts', Map<String, dynamic>.from(row));
      }
    });
  }

  // ── LEGACY IMPORT (e.g. from another cash-book app's .db export) ────
  /// Accounts are matched or created by name, so importing the same
  /// backup twice never creates duplicate wallets — only new entries
  /// would be appended (harmless duplicates in the entries list, but at
  /// least accounts stay clean). [entries] items need: accountName,
  /// type ('in'/'out'), amount, date ('YYYY-MM-DD'), note.
  static Future<int> importLegacy({
    required List<String> accountNames,
    required List<Map<String, dynamic>> entries,
  }) async {
    final d = await db;
    int inserted = 0;
    await d.transaction((txn) async {
      final nameToId = <String, int>{};
      final existing = await txn.query('accounts');
      for (final row in existing) {
        nameToId[row['name'] as String] = row['id'] as int;
      }
      for (final name in accountNames) {
        if (!nameToId.containsKey(name)) {
          final id = await txn.insert('accounts', {
            'name': name,
            'icon': '📒',
            'sort_order': nameToId.length,
            'created_at': DateTime.now().millisecondsSinceEpoch,
          });
          nameToId[name] = id;
        }
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final e in entries) {
        final accId = nameToId[e['accountName']];
        if (accId == null) continue;
        await txn.insert('entries', {
          'account_id': accId,
          'type': e['type'],
          'amount': e['amount'],
          'category': 'other',
          'note': e['note'] ?? '',
          'date': e['date'],
          'voucher_image': null,
          'recurring': 0,
          'created_at': now,
          'updated_at': now,
        });
        inserted++;
      }
    });
    return inserted;
  }
}
