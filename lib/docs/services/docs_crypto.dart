import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// ডকুমেন্টের এনক্রিপ্টেড ফাইল-স্টোর।
///
///  • একটা র‍্যান্ডম ২৫৬-বিট মাস্টার কী তৈরি হয় ও Android Keystore-ব্যাকড secure
///    storage-এ থাকে (ভল্টের পাসওয়ার্ডের মতোই ডিভাইস-লক নির্ভর)।
///  • প্রতিটা ফাইল AES-256-GCM-এ এনক্রিপ্ট হয়ে app-private ফোল্ডারে `.enc` নামে
///    থাকে — গ্যালারিতে বা ফাইল ম্যানেজারে ছবি/PDF দেখা যায় না।
///  • ফরম্যাট: [১ বাইট ভার্সন][১২ বাইট nonce][১৬ বাইট MAC][সাইফারটেক্সট]।
///  • ভারী কাজ আলাদা isolate-এ, তাই UI আটকায় না।
///
/// গুরুত্বপূর্ণ: মাস্টার কী শুধু এই ফোনে। ফোন রিসেট/অ্যাপ আনইন্সটলে কী হারালে ফাইল
/// খোলা যায় না — তাই পাসওয়ার্ডসহ এনক্রিপ্টেড ব্যাকআপ (DocsBackupService) আলাদা।
class DocsCrypto {
  static const _keyName = 'docs_master_key_v1';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static Uint8List? _key;

  static Future<Uint8List> _masterKey() async {
    if (_key != null) return _key!;
    var s = await _storage.read(key: _keyName);
    if (s == null || s.isEmpty) {
      final r = Random.secure();
      final k = Uint8List.fromList(List<int>.generate(32, (_) => r.nextInt(256)));
      s = base64Encode(k);
      await _storage.write(key: _keyName, value: s);
    }
    return _key = Uint8List.fromList(base64Decode(s));
  }

  // ── বাইট এনক্রিপশন ──

  static Future<Uint8List> encrypt(Uint8List data) async {
    final key = await _masterKey();
    return Isolate.run(() => encryptWithKey(data, key));
  }

  static Future<Uint8List> decrypt(Uint8List blob) async {
    final key = await _masterKey();
    return Isolate.run(() => decryptWithKey(blob, key));
  }

  /// যেকোনো ২৫৬-বিট কী দিয়ে (ব্যাকআপেও এটাই ব্যবহার হয়)।
  static Future<Uint8List> encryptWithKey(Uint8List data, List<int> key) async {
    final rnd = Random.secure();
    final nonce = List<int>.generate(12, (_) => rnd.nextInt(256));
    final box = await AesGcm.with256bits().encrypt(data, secretKey: SecretKey(key), nonce: nonce);
    final out = BytesBuilder(copy: false)
      ..addByte(1)
      ..add(nonce)
      ..add(box.mac.bytes)
      ..add(box.cipherText);
    return out.toBytes();
  }

  static Future<Uint8List> decryptWithKey(Uint8List blob, List<int> key) async {
    if (blob.length < 29 || blob[0] != 1) throw const FormatException('অচেনা ফাইল ফরম্যাট');
    final nonce = blob.sublist(1, 13);
    final mac = blob.sublist(13, 29);
    final ct = blob.sublist(29);
    final clear = await AesGcm.with256bits()
        .decrypt(SecretBox(ct, nonce: nonce, mac: Mac(mac)), secretKey: SecretKey(key));
    return Uint8List.fromList(clear);
  }

  // ── ছোট টেক্সট (ডকুমেন্ট নম্বর) ──

  static Future<String> encryptText(String text) async {
    if (text.isEmpty) return '';
    return base64Encode(await encrypt(Uint8List.fromList(utf8.encode(text))));
  }

  static Future<String> decryptText(String enc) async {
    if (enc.isEmpty) return '';
    try {
      return utf8.decode(await decrypt(Uint8List.fromList(base64Decode(enc))));
    } catch (_) {
      return '';
    }
  }

  // ── ফাইল-স্টোর ──

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/docs_vault');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String newFileId() => 'f_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';

  static Future<String> saveFile(Uint8List plain, {String? fileId}) async {
    final id = fileId ?? newFileId();
    final enc = await encrypt(plain);
    await File('${(await _dir()).path}/$id.enc').writeAsBytes(enc, flush: true);
    return id;
  }

  static Future<Uint8List> readFile(String fileId) async {
    final f = File('${(await _dir()).path}/$fileId.enc');
    return decrypt(await f.readAsBytes());
  }

  static Future<void> deleteFile(String fileId) async {
    try {
      final f = File('${(await _dir()).path}/$fileId.enc');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
