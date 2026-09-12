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
