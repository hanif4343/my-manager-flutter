import 'dart:async';
import 'dart:convert';
import '../../services/drive_service.dart';
import '../db/cashbook_db.dart';

/// Cashbook data gets backed up to Drive after every change, regardless of
/// the general app's periodic-backup toggle — money records are sensitive.
///
/// ঠিক করা সমস্যা (ড্রাইভে যাচ্ছিল না / ড্রাইভ থেকে আসছিল না):
///  • আগে `drive.isSignedIn` false হলেই চুপচাপ ফিরে যেত — অথচ অ্যাপ নতুন করে চালুর পর
///    সাইন-ইন আপনা-আপনি ফেরে না। এখন প্রতিবার আগে silent sign-in চেষ্টা করা হয়।
///  • ক্যাশবুক খোলা ও এন্ট্রি সেভ — দুই জায়গা থেকে একসাথে ব্যাকআপ চলে ২টা ফাইল বানিয়ে
///    ফেলত, রিস্টোরে পুরনোটা উঠে আসত। এখন ডিবাউন্স + DriveService-এ লাইন করা।
///  • রিস্টোর ব্যর্থ হলে আসল কারণ ([failReason]) দেখানো যায়।
class CashbookBackupService {
  static const _fileName = 'cashbook_backup.json';
  static DateTime? lastBackupAt;
  static Timer? _timer;

  /// সর্বশেষ রিস্টোর/ব্যাকআপ ব্যর্থ হলে কেন — UI-তে দেখানোর জন্য।
  static String? get failReason => DriveService.instance.lastError;

  static Future<String> _json() async {
    final data = await CashbookDB.exportAll();
    return jsonEncode({
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      ...data,
    });
  }

  /// পরিবর্তনের পর ডাকা হয়; কয়েকটা ডাক জমিয়ে একবারই আপলোড করে। কখনো ইউজারের কাজ আটকায় না।
  static Future<void> backupSilently() {
    _timer?.cancel();
    final done = Completer<void>();
    _timer = Timer(const Duration(seconds: 3), () async {
      try {
        final drive = DriveService.instance;
        if (await drive.ensureSignedIn()) {
          final result = await drive.backupJson(_fileName, await _json());
          if (result == DriveBackupResult.success) lastBackupAt = DateTime.now();
        }
      } catch (_) {
        // Best-effort — a failed background backup should never block or
        // interrupt whatever the person was doing in the Cashbook.
      }
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  /// হাতে-চালানো ব্যাকআপ (ব্যাকআপ কেন্দ্রের জন্য) — ফলাফল জানায়।
  static Future<DriveBackupResult> backupNow() async {
    final drive = DriveService.instance;
    if (!await drive.ensureSignedIn(interactive: true)) return DriveBackupResult.notSignedIn;
    final r = await drive.backupJson(_fileName, await _json());
    if (r == DriveBackupResult.success) lastBackupAt = DateTime.now();
    return r;
  }

  static Future<bool> restoreFromDrive() async {
    final drive = DriveService.instance;
    final json = await drive.restoreJson(_fileName); // সাইন-ইনও এখানেই সামলায়
    if (json == null || json.isEmpty) return false;
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      await CashbookDB.importAll(data);
      return true;
    } catch (e) {
      drive.lastError = 'ব্যাকআপ ফাইল পড়া/বসানো যায়নি: $e';
      return false;
    }
  }
}
