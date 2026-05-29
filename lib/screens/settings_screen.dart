import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/notification_service.dart';
import '../widgets/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const SettingsScreen({super.key, required this.onThemeToggle});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isDark = SettingsService.isDark;
  bool _digestEnabled = true;
  int _digestHour = 8;
  int _digestMinute = 0;

  @override
  void initState() {
    super.initState();
    _loadDigestPrefs();
  }

  Future<void> _loadDigestPrefs() async {
    final enabled = SettingsService.getBool('digest_enabled', defaultValue: true);
    final hour = SettingsService.getInt('digest_hour', defaultValue: 8);
    final minute = SettingsService.getInt('digest_minute', defaultValue: 0);
    setState(() { _digestEnabled = enabled; _digestHour = hour; _digestMinute = minute; });
  }

  Future<void> _saveDigestPrefs() async {
    await SettingsService.setBool('digest_enabled', _digestEnabled);
    await SettingsService.setInt('digest_hour', _digestHour);
    await SettingsService.setInt('digest_minute', _digestMinute);
    if (_digestEnabled) {
      await NotificationService.scheduleDailyDigest(
          hour: _digestHour, minute: _digestMinute);
    } else {
      await NotificationService.cancelDailyDigest();
    }
  }

  Future<void> _pickDigestTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _digestHour, minute: _digestMinute),
      builder: (c, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme:
        const ColorScheme.dark(primary: AppTheme.accent, surface: AppTheme.bg3)),
        child: child!,
      ),
    );
    if (t == null) return;
    setState(() { _digestHour = t.hour; _digestMinute = t.minute; });
    await _saveDigestPrefs();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Daily digest ${t.format(context)} এ set হয়েছে ✅'),
      backgroundColor: AppTheme.green,
    ));
  }

  String _pad(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('সেটিংস', style: TextStyle(color: AppTheme.textPrimary)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('থিম'),
          _settingTile(
            icon: _isDark ? Icons.dark_mode : Icons.light_mode,
            iconColor: _isDark ? AppTheme.accent : AppTheme.yellow,
            title: _isDark ? 'ডার্ক মোড চালু' : 'লাইট মোড চালু',
            subtitle: 'থিম পরিবর্তন করো',
            trailing: Switch(
              value: _isDark,
              activeColor: AppTheme.accent,
              onChanged: (val) async {
                await SettingsService.setDark(val);
                setState(() => _isDark = val);
                widget.onThemeToggle();
              },
            ),
          ),
          const SizedBox(height: 16),

          _sectionTitle('Daily Digest Notification'),
          _settingTile(
            icon: Icons.notifications_outlined,
            iconColor: AppTheme.accent,
            title: 'Daily Digest',
            subtitle: 'প্রতিদিন সকালে pending task এর সারসংক্ষেপ',
            trailing: Switch(
              value: _digestEnabled,
              activeColor: AppTheme.accent,
              onChanged: (val) async {
                setState(() => _digestEnabled = val);
                await _saveDigestPrefs();
              },
            ),
          ),
          if (_digestEnabled)
            _settingTile(
              icon: Icons.access_time_outlined,
              iconColor: AppTheme.green,
              title: 'Digest সময়',
              subtitle: 'প্রতিদিন ${_pad(_digestHour)}:${_pad(_digestMinute)} তে notification আসবে',
              trailing: GestureDetector(
                onTap: _pickDigestTime,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.accent.withOpacity(0.5)),
                  ),
                  child: Text('${_pad(_digestHour)}:${_pad(_digestMinute)}',
                      style: const TextStyle(color: AppTheme.accent,
                          fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),
            ),
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppTheme.bg2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.info_outline, color: AppTheme.textMuted, size: 14),
                SizedBox(width: 6),
                Text('Digest এ কী থাকবে:', style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 6),
              ...['📋 মোট pending task সংখ্যা',
                '📅 আজকে ও কালকের deadline',
                '⚠️ Overdue task এর সংখ্যা'].map((s) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $s', style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 12)),
              )),
            ]),
          ),

          const SizedBox(height: 16),
          _sectionTitle('অ্যাপ তথ্য'),
          _settingTile(
            icon: Icons.rocket_launch_outlined, iconColor: AppTheme.accent,
            title: 'My Manager', subtitle: 'Version 5.0.0 — Deadline & Multi-select Update',
          ),
          _settingTile(
            icon: Icons.code, iconColor: AppTheme.textSecondary,
            title: 'Package', subtitle: 'com.hanif.mymanager',
          ),
          _settingTile(
            icon: Icons.storage_outlined, iconColor: AppTheme.green,
            title: 'Storage', subtitle: 'SQLite Local Database (v5)',
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text.toUpperCase(), style: const TextStyle(
        color: AppTheme.textMuted, fontSize: 11,
        fontWeight: FontWeight.w700, letterSpacing: 1)),
  );

  Widget _settingTile({required IconData icon, required Color iconColor,
      required String title, String? subtitle, Widget? trailing}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: AppTheme.bg2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border)),
        child: ListTile(
          leading: Container(width: 36, height: 36,
            decoration: BoxDecoration(color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: iconColor, size: 18)),
          title: Text(title, style: const TextStyle(
              color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: subtitle != null ? Text(subtitle,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)) : null,
          trailing: trailing,
        ),
      );
}
