import 'package:flutter/services.dart';

/// অন্য অ্যাপ খোলা / লিংক খোলার জন্য নেটিভ ব্রিজ (MainActivity.kt)।
class AppLauncher {
  static const _ch = MethodChannel('com.hanif.mymanager/launcher');

  static Future<bool> launchApp(String package) async {
    try {
      return (await _ch.invokeMethod<bool>('launchApp', {'package': package})) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openUrl(String url) async {
    var u = url.trim();
    if (u.isEmpty) return false;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    try {
      return (await _ch.invokeMethod<bool>('openUrl', {'url': u})) ?? false;
    } catch (_) {
      return false;
    }
  }
}
