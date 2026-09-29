import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/vault_entry.dart';

/// Stores vault entries in Android's encrypted, Keystore-backed
/// EncryptedSharedPreferences — deliberately separate from the app's
/// regular SQLite database, since passwords/tokens need real encryption
/// at rest, not just being one more row in a plain database file.
///
/// All entries live under a single key as a JSON blob. For a personal
/// vault (tens to low hundreds of entries) this is simpler and
/// completely adequate — no need for a second database engine just for
/// this.
class VaultService {
  static const _key = 'vault_entries_v1';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<List<VaultEntry>> getAll() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list.map((e) => VaultEntry.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveAll(List<VaultEntry> entries) async {
    await _storage.write(
      key: _key,
      value: jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> insert(VaultEntry entry) async {
    final list = await getAll();
    list.add(entry);
    await _saveAll(list);
  }

  /// Bulk add for CSV import: one read and one write for the whole
  /// batch (calling [insert] per entry would re-read and re-encrypt the
  /// entire vault hundreds of times). Uses a *strict* read — unlike
  /// [getAll], which swallows errors and returns an empty list — so if
  /// the stored vault ever failed to parse, this throws instead of
  /// quietly overwriting every existing entry with just the new ones.
  static Future<void> insertMany(List<VaultEntry> entries) async {
    if (entries.isEmpty) return;
    final raw = await _storage.read(key: _key);
    final List<VaultEntry> list;
    if (raw == null || raw.isEmpty) {
      list = [];
    } else {
      final decoded = jsonDecode(raw) as List; // throws if corrupt — intentional
      list = decoded.map((e) => VaultEntry.fromJson(e as Map<String, dynamic>)).toList();
    }
    list.addAll(entries);
    await _saveAll(list);
  }

  /// ব্যাকআপ থেকে রিস্টোরের জন্য মার্জ: একবার পড়ে, একবার লেখে।
  ///  • একই id আছে ও ব্যাকআপের এন্ট্রি নতুন → আপডেট
  ///  • একই id আছে ও পুরোনো/সমান → বাদ
  ///  • id আলাদা কিন্তু হুবহু একই তথ্য → বাদ (ডুপ্লিকেট)
  ///  • নয়তো নতুন যোগ
  /// strict read: ভল্ট পার্স না হলে এক্সেপশন ছোঁড়ে, চুপচাপ ওভাররাইট করে না।
  /// রিটার্ন: [যোগ, আপডেট, বাদ]
  static Future<List<int>> mergeMany(List<VaultEntry> incoming) async {
    final raw = await _storage.read(key: _key);
    final List<VaultEntry> list;
    if (raw == null || raw.isEmpty) {
      list = [];
    } else {
      final decoded = jsonDecode(raw) as List;
      list = decoded.map((e) => VaultEntry.fromJson(e as Map<String, dynamic>)).toList();
    }
    final byId = <String, int>{};
    for (var i = 0; i < list.length; i++) { byId[list[i].id] = i; }
    String sig(VaultEntry e) =>
        '${e.type}\u0001${e.title}\u0001${e.username ?? ''}\u0001${e.secret}\u0001${e.url ?? ''}';
    final sigs = list.map(sig).toSet();

    var added = 0, updated = 0, skipped = 0;
    for (final e in incoming) {
      final idx = byId[e.id];
      if (idx != null) {
        if (e.updatedAt > list[idx].updatedAt) {
          list[idx] = e;
          updated++;
        } else {
          skipped++;
        }
      } else if (sigs.contains(sig(e))) {
        skipped++;
      } else {
        list.add(e);
        byId[e.id] = list.length - 1;
        sigs.add(sig(e));
        added++;
      }
    }
    if (added > 0 || updated > 0) await _saveAll(list);
    return [added, updated, skipped];
  }

  static Future<void> update(VaultEntry entry) async {
    final list = await getAll();
    final idx = list.indexWhere((e) => e.id == entry.id);
    if (idx != -1) {
      list[idx] = entry;
      await _saveAll(list);
    }
  }

  static Future<void> delete(String id) async {
    final list = await getAll();
    list.removeWhere((e) => e.id == id);
    await _saveAll(list);
  }

  /// Every password currently in the vault, for the weak/reused check —
  /// simple local logic, no external service involved.
  static Future<Map<String, int>> duplicateSecretCounts() async {
    final list = await getAll();
    final counts = <String, int>{};
    for (final e in list) {
      if (e.secret.isEmpty) continue;
      counts[e.secret] = (counts[e.secret] ?? 0) + 1;
    }
    return counts;
  }
}
