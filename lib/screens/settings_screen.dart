import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../widgets/app_theme.dart';
import 'pin_screen.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const SettingsScreen({super.key, required this.onThemeToggle});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isDark = SettingsService.isDark;
  bool _pinEnabled = SettingsService.pinEnabled;

  Future<void> _togglePin() async {
    if (_pinEnabled) {
      // Disable PIN
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.bg3,
          title: const Text('PIN বন্ধ করবে?',
              style: TextStyle(color: AppTheme.textPrimary)),
          content: const Text('PIN lock বন্ধ হবে।',
              style: TextStyle(color: AppTheme.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: const Text('বাতিল')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
              child: const Text('বন্ধ করো'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await SettingsService.disablePin();
        setState(() => _pinEnabled = false);
      }
    } else {
      // Enable PIN
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => PinScreen(
          isSetup: true,
          onSuccess: () => setState(() => _pinEnabled = true),
        ),
      ));
      setState(() => _pinEnabled = SettingsService.pinEnabled);
    }
  }

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
            title: _isDark ? 'ডার্ক মোড' : 'লাইট মোড',
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
          _sectionTitle('নিরাপত্তা'),
          _settingTile(
            icon: Icons.lock_outlined,
            iconColor: _pinEnabled ? AppTheme.green : AppTheme.textMuted,
            title: 'PIN Lock',
            subtitle: _pinEnabled ? 'PIN চালু আছে ✅' : 'App খুলতে PIN লাগবে',
            trailing: Switch(
              value: _pinEnabled,
              activeColor: AppTheme.green,
              onChanged: (_) => _togglePin(),
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle('অ্যাপ তথ্য'),
          _settingTile(
            icon: Icons.info_outline,
            iconColor: AppTheme.accent,
            title: 'My Manager',
            subtitle: 'Version 3.0.0 • Phase 4',
          ),
          _settingTile(
            icon: Icons.code,
            iconColor: AppTheme.textSecondary,
            title: 'Package',
            subtitle: 'com.hanif.mymanager',
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
        decoration: BoxDecoration(
            color: AppTheme.bg2, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border)),
        child: ListTile(
          leading: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          title: Text(title, style: const TextStyle(
              color: AppTheme.textPrimary, fontSize: 14,
              fontWeight: FontWeight.w600)),
          subtitle: subtitle != null ? Text(subtitle,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)) : null,
          trailing: trailing,
        ),
      );
}
