import 'dart:convert';
import '../models/cashbook_category.dart';
import '../../services/settings_service.dart';

/// Everything about the Cashbook that isn't a plain database row:
/// merging built-in + user-added categories, and the couple of settings
/// (lock on/off) the screens need to check.
class CashbookService {
  static const _customCategoriesKey = 'cashbook_custom_categories';
  static const _lockEnabledKey = 'cashbook_lock_enabled';

  /// Built-in categories first, then whatever the user has added from the
  /// entry form's "+ নতুন" chip, in the order they were added.
  static List<CashbookCategory> getCategories() {
    final raw = SettingsService.getString(_customCategoriesKey, defaultValue: '[]');
    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      list = [];
    }
    final custom = list
        .map((m) => CashbookCategory.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    return [...defaultCashbookCategories, ...custom];
  }

  static Future<CashbookCategory> addCategory(String name, {String icon = '🏷️'}) async {
    final raw = SettingsService.getString(_customCategoriesKey, defaultValue: '[]');
    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      list = [];
    }
    final cat = CashbookCategory(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      icon: icon,
    );
    list.add(cat.toJson());
    await SettingsService.setString(_customCategoriesKey, jsonEncode(list));
    return cat;
  }

  static CashbookCategory categoryById(String id) {
    return getCategories().firstWhere(
      (c) => c.id == id,
      orElse: () => CashbookCategory(id: id, name: id, icon: '🏷️'),
    );
  }

  /// Whether opening the Cashbook should demand fingerprint/PIN first —
  /// on by default since it's money data, same spirit as the Vault.
  static bool get lockEnabled => SettingsService.getBool(_lockEnabledKey, defaultValue: true);
  static Future<void> setLockEnabled(bool v) => SettingsService.setBool(_lockEnabledKey, v);

  // ── দৈনিক এন্ট্রি রিমাইন্ডার (কখন থেকে "আজকের হিসাব লেখো নি" নাগ শুরু হবে) ──
  static const _reminderEnabledKey = 'cashbook_reminder_enabled';
  static const _reminderHourKey = 'cashbook_reminder_hour';
  static const _reminderMinuteKey = 'cashbook_reminder_minute';

  static bool get reminderEnabled =>
      SettingsService.getBool(_reminderEnabledKey, defaultValue: true);
  static Future<void> setReminderEnabled(bool v) =>
      SettingsService.setBool(_reminderEnabledKey, v);

  /// ডিফল্ট রাত ৮:০০ — আগের ফিক্সড আচরণের সাথে ব্যাকওয়ার্ড-কম্প্যাটিবল।
  static int get reminderHour => SettingsService.getInt(_reminderHourKey, defaultValue: 20);
  static int get reminderMinute => SettingsService.getInt(_reminderMinuteKey, defaultValue: 0);
  static Future<void> setReminderTime(int hour, int minute) async {
    await SettingsService.setInt(_reminderHourKey, hour);
    await SettingsService.setInt(_reminderMinuteKey, minute);
  }

  // ── remembered account selection ─────────────────────
  // Persisted so the account switcher opens on whatever the person left
  // it on, across app restarts — not reset to a default every time.
  static const _lastAccountIdKey = 'cashbook_last_account_id';
  static int? get lastAccountId {
    final v = SettingsService.getInt(_lastAccountIdKey, defaultValue: 0);
    return v == 0 ? null : v;
  }
  static Future<void> setLastAccountId(int id) => SettingsService.setInt(_lastAccountIdKey, id);
}
