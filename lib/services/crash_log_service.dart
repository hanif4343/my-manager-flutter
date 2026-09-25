import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// The Kotlin side (MyManagerApplication.kt) writes crashes — from the
/// main UI, the autofill picker Activity, or the background autofill
/// service — to this same file, appending rather than overwriting so
/// nothing gets lost between one check and the next.
class CrashLogService {
  static const _fileName = 'last_crash.txt';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<String?> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final text = await f.readAsString();
      return text.trim().isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Nothing more to do if this fails — worst case, old entries
      // stay around and get seen again next time, which is harmless.
    }
  }
}
