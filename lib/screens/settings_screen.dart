import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../widgets/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const SettingsScreen({super.key, required this.onThemeToggle});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isDark = SettingsService.isDark;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('সেটিংস',
            style: TextStyle(color: AppTheme.textPrimary)),
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
          _sectionTitle('অ্যাপ তথ্য'),
          _settingTile(
            icon: Icons.rocket_launch_outlined,
            iconColor: AppTheme.accent,
            title: 'My Manager',
            subtitle: 'Version 4.0.0 — Phase 1 (New)',
          ),
          _settingTile(
            icon: Icons.code,
            iconColor: AppTheme.textSecondary,
            title: 'Package',
            subtitle: 'com.hanif.mymanager',
          ),
          _settingTile(
            icon: Icons.storage_outlined,
            iconColor: AppTheme.green,
            title: 'Storage',
            subtitle: 'SQLite Local Database',
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
