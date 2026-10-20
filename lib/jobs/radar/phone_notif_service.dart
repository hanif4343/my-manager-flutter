import 'dart:convert';
import 'package:flutter/services.dart';
import '../../services/settings_service.dart';
import 'radar_service.dart';

/// ফোনে ইনস্টল করা চাকরির অ্যাপের নোটিফিকেশন থেকে ধরা এন্ট্রি।
class PhoneAlert {
  final String pkg;
  final String title;
  final String text;
  final DateTime time;
  final bool match; // টার্গেট পদের কীওয়ার্ড মিলেছে কি না

  PhoneAlert({required this.pkg, required this.title, required this.text, required this.time, required this.match});

  String get key => '$pkg|$title|$text';

  Map<String, dynamic> toMap() => {
        'pkg': pkg, 'title': title, 'text': text, 'time': time.millisecondsSinceEpoch, 'match': match,
      };

  factory PhoneAlert.fromMap(Map<String, dynamic> m) => PhoneAlert(
        pkg: (m['pkg'] as String?) ?? '',
        title: (m['title'] as String?) ?? '',
        text: (m['text'] as String?) ?? '',
        time: DateTime.fromMillisecondsSinceEpoch((m['time'] as num?)?.toInt() ?? 0),
        match: (m['match'] as bool?) ?? false,
      );

  /// ব্রাউজারে খোঁজার লিংক (স্বয়ংক্রিয় ওয়েব-অনুসন্ধান রাডারের কাজ; এটা হাতে দেখার শর্টকাট)।
  String get searchUrl =>
      'https://www.google.com/search?q=${Uri.encodeQueryComponent('${title.isEmpty ? text : title} নিয়োগ বিজ্ঞপ্তি')}';
}

class AppInfo {
  final String label;
  final String pkg;
  AppInfo(this.label, this.pkg);
}

/// Kotlin NotificationListenerService-এর সাথে সংযোগ। শুধু ব্যবহারকারীর বেছে দেওয়া অ্যাপ।
class PhoneNotifService {
  static const _ch = MethodChannel('com.hanif.mymanager/jobnotif');
  static const _kAlerts = 'radar_phone_alerts';
  static const _maxAlerts = 100;

  static Future<bool> isEnabled() async {
    try {
      return (await _ch.invokeMethod<bool>('isEnabled')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openSettings() async {
    try {
      await _ch.invokeMethod('openSettings');
    } catch (_) {}
  }

  static Future<List<String>> packages() async {
    try {
      final r = await _ch.invokeMethod<List<dynamic>>('getPackages');
      return (r ?? const []).map((e) => e.toString()).toList()..sort();
    } catch (_) {
      return [];
    }
  }

  static Future<void> setPackages(List<String> pkgs) async {
    try {
      await _ch.invokeMethod('setPackages', {'packages': pkgs});
    } catch (_) {}
  }

  static Future<List<AppInfo>> searchApps(String q) async {
    try {
      final r = await _ch.invokeMethod<List<dynamic>>('searchApps', {'query': q});
      return (r ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map((m) => AppInfo((m['label'] ?? '').toString(), (m['pkg'] ?? '').toString()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static bool _matches(String s) =>
      RadarService.keywords.any((k) => RegExp(k, caseSensitive: false).hasMatch(s));

  static List<PhoneAlert> alerts() {
    final raw = SettingsService.getString(_kAlerts);
    if (raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => PhoneAlert.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      list.sort((a, b) {
        if (a.match != b.match) return a.match ? -1 : 1;
        return b.time.compareTo(a.time);
      });
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<PhoneAlert> l) async {
    final keep = l.length > _maxAlerts ? l.sublist(l.length - _maxAlerts) : l;
    await SettingsService.setString(_kAlerts, jsonEncode(keep.map((e) => e.toMap()).toList()));
  }

  /// নেটিভ কিউ থেকে নতুন নোটিফিকেশন এনে জমা করে। নতুন যোগ হওয়ার সংখ্যা ফেরত দেয়।
  static Future<int> sync() async {
    String raw;
    try {
      raw = (await _ch.invokeMethod<String>('drain')) ?? '[]';
    } catch (_) {
      return 0;
    }
    List<dynamic> incoming;
    try {
      incoming = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return 0;
    }
    if (incoming.isEmpty) return 0;
    final cur = alerts();
    final keys = cur.map((e) => e.key).toSet();
    var added = 0;
    for (final e in incoming) {
      final m = Map<String, dynamic>.from(e as Map);
      final title = (m['title'] ?? '').toString();
      final text = (m['text'] ?? '').toString();
      final a = PhoneAlert(
        pkg: (m['pkg'] ?? '').toString(),
        title: title,
        text: text,
        time: DateTime.fromMillisecondsSinceEpoch((m['time'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch),
        match: _matches('$title\n$text'),
      );
      if (keys.add(a.key)) {
        cur.add(a);
        added++;
      }
    }
    await _save(cur);
    return added;
  }

  static Future<void> remove(String key) async {
    final cur = alerts()..removeWhere((e) => e.key == key);
    await _save(cur);
  }

  static Future<void> clear() => SettingsService.setString(_kAlerts, '[]');
}
