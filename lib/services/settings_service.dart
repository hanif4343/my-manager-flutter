import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _p {
    assert(_prefs != null, 'SettingsService.init() must be called first');
    return _prefs!;
  }

  static bool get isDark => _p.getBool('isDark') ?? true;
  static Future<void> setDark(bool val) => _p.setBool('isDark', val);
}
