import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/settings_service.dart';
import '../db/docs_db.dart';
import '../models/doc_models.dart';
import 'docs_crypto.dart';
import 'docs_service.dart';

class DocsBackupException implements Exception {
  final String message;
  DocsBackupException(this.message);
  @override String toString() => message;
}

class DocsRestoreResult {
  final int added, skipped;
  DocsRestoreResult(this.added, this.skipped);
}

/// পাসওয়ার্ড-সুরক্ষিত ডকুমেন্ট ব্যাকআপ (.mmdocs)।
///
/// ফোনের মাস্টার কী ফোনেই বাঁধা, তাই নতুন ফোনে ফাইল খুলতে আলাদা পাসওয়ার্ড-ভিত্তিক
/// ব্যাকআপ লাগে। সব ডকুমেন্ট (মেটাডাটা + নম্বর + ফাইল) এক ZIP-এ, তারপর
/// PBKDF2-HMAC-SHA256 (১.৫ লাখ ধাপ) → AES-256-GCM-এ এনক্রিপ্ট হয়ে একটাই ফাইল।
/// ফাইলটা Drive/Files-এ রাখো; পাসওয়ার্ড ছাড়া কেউ খুলতে পারবে না।
///
/// ফাইল ফরম্যাট: "MMDOCS1" | salt(16) | iter(u32) | nonce(12) | mac(16) | ciphertext
class DocsBackupService {
  static const _magic = 'MMDOCS1';
  static const _iterations = 150000;
  static const minPasswordLength = 8;
  static const _lastKey = 'docs_last_backup_ms';

  static int lastBackupMs() {
    try {
      return SettingsService.getInt(_lastKey, defaultValue: 0);
    } catch (_) {
      return 0;
    }
  }

  // ───────────────── এক্সপোর্ট ─────────────────

  static Future<int> exportToFile(String password) async {
    final docs = await DocsDB.all();
    if (docs.isEmpty) throw DocsBackupException('কোনো ডকুমেন্ট নেই — ব্যাকআপ নেওয়ার কিছু নেই');

    final archive = Archive();
    final meta = <Map<String, dynamic>>[];
    for (final d in docs) {
      final m = d.toMap();
      m['number_plain'] = await DocsService.numberOf(d);
      m.remove('number_enc');
      m['rem'] = '';
      meta.add(m);
      for (final p in d.pages) {
        try {
          final bytes = await DocsCrypto.readFile(p.fileId);
          archive.addFile(ArchiveFile('files/${p.fileId}', bytes.length, bytes));
        } catch (_) {
          // একটা ফাইল নষ্ট হলে বাকিগুলো ঠিকই যাবে।
        }
      }
    }
    final metaBytes = Uint8List.fromList(utf8.encode(jsonEncode({'version': 1, 'docs': meta})));
    archive.addFile(ArchiveFile('meta.json', metaBytes.length, metaBytes));

    // ছবি/PDF আগে থেকেই কম্প্রেসড — ZIP-এ আবার কম্প্রেস করা সময় নষ্ট, তাই NO_COMPRESSION।
    final zip = Uint8List.fromList(ZipEncoder().encode(archive, level: Deflate.NO_COMPRESSION)!);
    final out = await Isolate.run(() => _seal(zip, password));

    final dir = await getTemporaryDirectory();
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final file = File('${dir.path}/MyManager_Docs_${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}.mmdocs');
    await file.writeAsBytes(out, flush: true);
    await Share.shareXFiles([XFile(file.path)],
        text: '🗂️ My Manager ডকুমেন্ট ব্যাকআপ (এনক্রিপ্টেড — পাসওয়ার্ড ছাড়া খোলা যায় না)');
    try {
      await SettingsService.setInt(_lastKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
    return docs.length;
  }

  static Future<Uint8List> _seal(Uint8List zip, String password) async {
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    final key = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: _iterations, bits: 256)
        .deriveKeyFromPassword(password: password, nonce: salt);
    final keyBytes = await key.extractBytes();
    final enc = await DocsCrypto.encryptWithKey(zip, keyBytes); // [1][nonce][mac][ct]
    final b = BytesBuilder(copy: false)
      ..add(utf8.encode(_magic))
      ..add(salt)
      ..add(Uint8List(4)..buffer.asByteData().setUint32(0, _iterations))
      ..add(enc);
    return b.toBytes();
  }

  // ───────────────── রিস্টোর ─────────────────

  static Future<Uint8List?> pickBackupFile() async {
    final r = await FilePicker.platform.pickFiles(withData: true);
    if (r == null || r.files.isEmpty) return null;
    final f = r.files.first;
    if (f.bytes != null) return f.bytes!;
    if (f.path != null) return File(f.path!).readAsBytes();
    throw DocsBackupException('ফাইলটা পড়া যায়নি');
  }

  static Future<DocsRestoreResult> restore(Uint8List data, String password) async {
    final head = utf8.encode(_magic);
    if (data.length < head.length + 16 + 4 + 29 ||
        utf8.decode(data.sublist(0, head.length), allowMalformed: true) != _magic) {
      throw DocsBackupException('এটা My Manager ডকুমেন্ট ব্যাকআপ ফাইল নয়');
    }
    final Archive archive;
    try {
      final zip = await Isolate.run(() => _open(data, password));
      archive = ZipDecoder().decodeBytes(zip);
    } catch (_) {
      throw DocsBackupException('পাসওয়ার্ড ভুল, অথবা ফাইলটা নষ্ট');
    }

    final metaFile = archive.findFile('meta.json');
    if (metaFile == null) throw DocsBackupException('ব্যাকআপের ভেতরের তথ্য পাওয়া যায়নি');
    final meta = jsonDecode(utf8.decode(metaFile.content as List<int>)) as Map<String, dynamic>;

    final have = (await DocsDB.all()).map((d) => d.id).toSet();
    var added = 0, skipped = 0;
    for (final raw in (meta['docs'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = m['id'] as String;
      if (have.contains(id)) {
        skipped++;
        continue;
      }
      final plainNumber = (m.remove('number_plain') as String?) ?? '';
      m['number_enc'] = '';
      m['rem'] = '';
      final doc = VaultDoc.fromMap(m);
      // প্রতিটা ফাইল এই ফোনের নিজের কী দিয়ে নতুন করে এনক্রিপ্ট।
      for (final p in doc.pages) {
        final f = archive.findFile('files/${p.fileId}');
        if (f != null) {
          await DocsCrypto.saveFile(Uint8List.fromList(f.content as List<int>), fileId: p.fileId);
        }
      }
      doc.pages.removeWhere((p) => archive.findFile('files/${p.fileId}') == null);
      await DocsService.save(doc, number: plainNumber); // নম্বর এনক্রিপ্ট + মেয়াদের রিমাইন্ডার নতুন করে
      added++;
    }
    return DocsRestoreResult(added, skipped);
  }

  static Future<Uint8List> _open(Uint8List data, String password) async {
    var o = utf8.encode(_magic).length;
    final salt = data.sublist(o, o + 16);
    o += 16;
    final iter = data.buffer.asByteData(data.offsetInBytes + o, 4).getUint32(0);
    o += 4;
    if (iter < 1000 || iter > 3000000) throw const FormatException('হেডার নষ্ট');
    final key = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iter, bits: 256)
        .deriveKeyFromPassword(password: password, nonce: salt);
    final keyBytes = await key.extractBytes();
    return DocsCrypto.decryptWithKey(Uint8List.sublistView(data, o), keyBytes);
  }
}
