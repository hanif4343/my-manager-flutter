import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/vault_entry.dart';
import 'vault_service.dart';

class VaultCsvImportResult {
  final int imported;
  final int skipped;
  VaultCsvImportResult({required this.imported, required this.skipped});
}

/// CSV is plaintext — exporting writes every password out in the clear,
/// exactly like Chrome's or Bitwarden's own "export as CSV" feature.
/// That is the whole point of a portable backup format, but it means the
/// resulting file is exactly as sensitive as the vault itself; the UI
/// side of this (vault_screen.dart) is expected to warn about that
/// before calling exportCsv.
class VaultCsvService {
  static const _headers = ['type', 'title', 'username', 'secret', 'url', 'notes'];

  static Future<void> exportCsv(List<VaultEntry> entries) async {
    final rows = <List<String>>[_headers];
    for (final e in entries) {
      rows.add([e.type, e.title, e.username ?? '', e.secret, e.url ?? '', e.notes ?? '']);
    }
    final csvText = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/vault_export.csv');
    await file.writeAsString(csvText);
    await Share.shareXFiles([XFile(file.path)],
        text: 'My Manager ভল্ট এক্সপোর্ট — এই ফাইলে পাসওয়ার্ড প্লেইন টেক্সটে আছে, সাবধানে রাখুন');
  }

  /// Recognises this app's own export headers, and a handful of common
  /// aliases used by Chrome/Bitwarden-style exports, so a CSV from
  /// elsewhere can be brought in too — not just round-tripping our own.
  static const _aliases = {
    'type': ['type'],
    'title': ['title', 'name'],
    'username': ['username', 'login_username'],
    'secret': ['secret', 'password', 'login_password'],
    'url': ['url', 'uri', 'login_uri'],
    'notes': ['notes', 'note'],
  };

  static Future<VaultCsvImportResult?> pickAndImport() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final picked = result?.files.single;
    if (picked?.bytes == null) return null;

    final text = String.fromCharCodes(picked!.bytes!);
    final rows = const CsvToListConverter(shouldParseNumbers: false).convert(text);
    if (rows.isEmpty) return VaultCsvImportResult(imported: 0, skipped: 0);

    final header = rows.first.map((h) => h.toString().trim().toLowerCase()).toList();
    final colIndex = <String, int>{};
    _aliases.forEach((field, names) {
      for (final n in names) {
        final i = header.indexOf(n);
        if (i != -1) { colIndex[field] = i; break; }
      }
    });

    String cell(List row, String field) {
      final i = colIndex[field];
      if (i == null || i >= row.length) return '';
      return row[i]?.toString() ?? '';
    }

    final newEntries = <VaultEntry>[];
    int imported = 0, skipped = 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final row in rows.skip(1)) {
      if (row.length == 1 && (row.first as String).trim().isEmpty) continue; // blank line
      final title = cell(row, 'title').trim();
      final secret = cell(row, 'secret').trim();
      if (title.isEmpty || secret.isEmpty) { skipped++; continue; }

      var type = cell(row, 'type').trim().toLowerCase();
      if (!['login', 'note', 'card', 'token', 'wifi'].contains(type)) type = 'login';

      imported++;
      newEntries.add(VaultEntry(
        id: 'v_${now}_$imported',
        type: type,
        title: title,
        username: cell(row, 'username').trim().isEmpty ? null : cell(row, 'username').trim(),
        secret: secret,
        url: cell(row, 'url').trim().isEmpty ? null : cell(row, 'url').trim(),
        notes: cell(row, 'notes').trim().isEmpty ? null : cell(row, 'notes').trim(),
        createdAt: now,
        updatedAt: now,
      ));
    }

    for (final e in newEntries) {
      await VaultService.insert(e);
    }
    return VaultCsvImportResult(imported: imported, skipped: skipped);
  }
}
