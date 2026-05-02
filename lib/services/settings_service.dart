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

  // Theme
  static bool get isDark => _p.getBool('isDark') ?? true;
  static Future<void> setDark(bool val) => _p.setBool('isDark', val);

  // PIN
  static bool get pinEnabled => _p.getBool('pinEnabled') ?? false;
  static String get pin => _p.getString('pin') ?? '';
  static Future<void> setPin(String val) async {
    await _p.setString('pin', val);
    await _p.setBool('pinEnabled', val.isNotEmpty);
  }
  static Future<void> disablePin() async {
    await _p.setBool('pinEnabled', false);
    await _p.setString('pin', '');
  }
}
