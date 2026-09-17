import 'dart:convert';
import '../../services/drive_service.dart';
import '../db/cashbook_db.dart';

/// Cashbook data gets backed up to Drive after every single change,
/// regardless of the general app's periodic-backup toggle — the person
/// asked for this explicitly since money records are sensitive. It's a
/// best-effort, silent, fire-and-forget call: if the person isn't
/// signed in to Drive yet there's simply nothing to do, and any network
/// failure is swallowed so it never interrupts data entry.
class CashbookBackupService {
  static const _fileName = 'cashbook_backup.json';
  static DateTime? lastBackupAt;

  static Future<void> backupSilently() async {
    final drive = DriveService.instance;
    if (!drive.isSignedIn) return;
    try {
      final data = await CashbookDB.exportAll();
      final json = jsonEncode({
        'version': 1,
        'exported_at': DateTime.now().toIso8601String(),
        ...data,
      });
      final result = await drive.backupJson(_fileName, json);
      if (result == DriveBackupResult.success) {
        lastBackupAt = DateTime.now();
      }
    } catch (_) {
      // Best-effort — a failed background backup should never block or
      // interrupt whatever the person was doing in the Cashbook.
    }
  }

  static Future<bool> restoreFromDrive() async {
    final drive = DriveService.instance;
    if (!drive.isSignedIn) return false;
    final json = await drive.restoreJson(_fileName);
    if (json == null) return false;
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      await CashbookDB.importAll(data);
      return true;
    } catch (_) {
      return false;
    }
  }
}
