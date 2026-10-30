import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// ডেটা হারানো ঠেকানোর ছোট সরঞ্জাম: ব্যাকআপের আইটেম গোনা, আর "বদলে ফেলার" আগে বর্তমান ডেটার কপি রাখা।
class SafetyNet {
  /// JSON-এর শীর্ষ স্তরের সব তালিকার আইটেম মিলিয়ে সংখ্যা। পড়া না গেলে (যেমন এনক্রিপ্টেড) null।
  static int? itemCount(String text) {
    try {
      final d = jsonDecode(text);
      if (d is! Map) return null;
      var n = 0;
      d.forEach((k, v) {
        if (v is List) n += v.length;
      });
      return n;
    } catch (_) {
      return null;
    }
  }

  /// তালিকার নাম → আইটেম সংখ্যা (ব্যাকআপে কী আছে দেখাতে)।
  static Map<String, int> listCounts(String text) {
    final out = <String, int>{};
    try {
      final d = jsonDecode(text);
      if (d is Map) {
        d.forEach((k, v) {
          if (v is List) out[k.toString()] = v.length;
        });
      }
    } catch (_) {}
    return out;
  }

  static const _labels = {
    'projects': 'প্রজেক্ট',
    'ideas': 'আইডিয়া',
    'idea_files': 'ফাইল',
    'project_versions': 'ভার্সন',
    'accounts': 'হিসাব/মাস',
    'entries': 'এন্ট্রি',
    'budgets': 'বাজেট',
    'debts': 'দেনা-পাওনা',
    'essentials': 'আবশ্যিক খরচ',
    'circulars': 'সার্কুলার',
    'docs': 'ডকুমেন্ট',
    'members': 'সদস্য',
    'dates': 'তারিখ',
    'bills': 'বিল',
    'contacts': 'জরুরি তথ্য',
    'reminders': 'রিমাইন্ডার',
  };

  static String label(String key) => _labels[key] ?? key;

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/safety_backups');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// রিস্টোরে বর্তমান ডেটা বদলে যাওয়ার আগে তার একটা কপি ফোনে রাখে (প্রতি মডিউলে শেষ ৫টা)।
  static Future<File?> snapshot(String module, String json) async {
    try {
      final dir = await _dir();
      final t = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final f = File('${dir.path}/${module}_${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}.json');
      await f.writeAsString(json, flush: true);
      final mine = dir.listSync().whereType<File>().where((x) => x.uri.pathSegments.last.startsWith('${module}_')).toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (var i = 5; i < mine.length; i++) {
        try {
          await mine[i].delete();
        } catch (_) {}
      }
      return f;
    } catch (_) {
      return null;
    }
  }
}
