import 'package:flutter/material.dart';
import '../services/drive_service.dart';
import '../widgets/app_theme.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _loading = false;
  bool _checking = true;
  DateTime? _lastBackup;
  String? _status;
  bool _isError = false;

  @override
  void initState() { super.initState(); _checkStatus(); }

  Future<void> _checkStatus() async {
    setState(() => _checking = true);
    await DriveService.instance.signInSilently();
    if (DriveService.instance.isSignedIn) {
      _lastBackup = await DriveService.instance.getLastBackupTime();
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _signIn() async {
    setState(() => _loading = true);
    final ok = await DriveService.instance.signIn();
    if (ok) {
      _lastBackup = await DriveService.instance.getLastBackupTime();
      _setStatus('Google Account যুক্ত হয়েছে!', false);
    } else {
      _setStatus('Sign in ব্যর্থ হয়েছে।', true);
    }
    setState(() => _loading = false);
  }

  Future<void> _backup() async {
    setState(() { _loading = true; _status = null; });
    final result = await DriveService.instance.backupDatabase();
    switch (result) {
      case DriveBackupResult.success:
        _lastBackup = DateTime.now();
        _setStatus('✅ Backup সফল! Google Drive-এ সেভ হয়েছে।', false);
        break;
      case DriveBackupResult.notSignedIn:
        _setStatus('Google Account দিয়ে সাইন ইন করো।', true);
        break;
      case DriveBackupResult.failed:
        _setStatus('Backup ব্যর্থ! Internet আছে কিনা দেখো।', true);
        break;
      default:
        _setStatus('কিছু একটা হয়নি।', true);
    }
    setState(() => _loading = false);
  }

  Future<void> _restore() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bg3,
        title: const Text('Restore করবে?', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('Drive-এর backup দিয়ে সব local data replace হবে।\nএই কাজ undo করা যাবে না!',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('বাতিল')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            child: const Text('Restore করো'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() { _loading = true; _status = null; });
    final result = await DriveService.instance.restoreFromDrive();
    switch (result) {
      case DriveBackupResult.success:
        _setStatus('✅ Restore সফল! App restart করো।', false);
        break;
      case DriveBackupResult.noBackup:
        _setStatus('Drive-এ কোনো backup নেই।', true);
        break;
      case DriveBackupResult.notSignedIn:
        _setStatus('Google Account দিয়ে সাইন ইন করো।', true);
        break;
      default:
        _setStatus('Restore ব্যর্থ!', true);
    }
    setState(() => _loading = false);
  }

  void _setStatus(String msg, bool isError) {
    setState(() { _status = msg; _isError = isError; });
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = DriveService.instance.isSignedIn;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Google Drive Backup', style: TextStyle(color: AppTheme.textPrimary))),
      body: _checking
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // Account Card
                _sectionCard(
                  icon: Icons.account_circle_outlined,
                  iconColor: signedIn ? AppTheme.green : AppTheme.textMuted,
                  title: signedIn ? 'Google Account' : 'Account যুক্ত নেই',
                  subtitle: signedIn
                      ? DriveService.instance.userEmail ?? 'Connected'
                      : 'Backup করতে Google Account লাগবে',
                  trailing: signedIn
                      ? TextButton(
                          onPressed: _loading ? null : () async {
                            await DriveService.instance.signOut();
                            setState(() {});
                          },
                          child: const Text('Sign Out', style: TextStyle(color: AppTheme.red)),
                        )
                      : ElevatedButton.icon(
                          onPressed: _loading ? null : _signIn,
                          icon: const Icon(Icons.login, size: 16),
                          label: const Text('Sign In'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                        ),
                ),

                const SizedBox(height: 12),

                // Last backup info
                if (signedIn && _lastBackup != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.green.withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.cloud_done_outlined, color: AppTheme.green, size: 20),
                      const SizedBox(width: 10),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('সর্বশেষ Backup', style: TextStyle(color: AppTheme.green, fontSize: 12, fontWeight: FontWeight.w600)),
                        Text(_formatDate(_lastBackup!), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      ]),
                    ]),
                  ),

                const SizedBox(height: 20),

                // Backup Button
                _actionBtn(
                  icon: Icons.backup_outlined,
                  label: 'এখনই Backup করো',
                  sublabel: 'সব data → Google Drive',
                  color: AppTheme.accent,
                  enabled: signedIn && !_loading,
                  onTap: _backup,
                ),

                const SizedBox(height: 12),

                // Restore Button
                _actionBtn(
                  icon: Icons.restore_outlined,
                  label: 'Drive থেকে Restore করো',
                  sublabel: 'Drive backup → এই ফোনে',
                  color: AppTheme.yellow,
                  enabled: signedIn && !_loading,
                  onTap: _restore,
                ),

                const SizedBox(height: 20),

                // How it works
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.bg2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('ℹ️ কীভাবে কাজ করে', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    _infoRow('📤 Backup', 'সব project, idea, file → JSON → Drive/"MyManager_Backup" folder'),
                    _infoRow('📥 Restore', 'Drive-এর backup → ফোনে import (পুরনো data replace হবে)'),
                    _infoRow('🔄 Manual', 'যখন খুশি Backup বাটন চাপো — কোনো auto নেই'),
                    _infoRow('🔒 Privacy', 'শুধু তোমার Drive-এ যাবে, অন্য কেউ দেখতে পাবে না'),
                  ]),
                ),

                if (_loading) ...[
                  const SizedBox(height: 20),
                  const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
                ],

                if (_status != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (_isError ? AppTheme.red : AppTheme.green).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: (_isError ? AppTheme.red : AppTheme.green).withOpacity(0.4)),
                    ),
                    child: Text(_status!, style: TextStyle(
                        color: _isError ? AppTheme.red : AppTheme.green, fontSize: 13)),
                  ),
                ],
              ]),
            ),
    );
  }

  Widget _sectionCard({required IconData icon, required Color iconColor,
      required String title, required String subtitle, Widget? trailing}) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.bg2, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border)),
        child: Row(children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
            Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ])),
          if (trailing != null) trailing,
        ]),
      );

  Widget _actionBtn({required IconData icon, required String label,
      required String sublabel, required Color color,
      required bool enabled, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: enabled ? color.withOpacity(0.1) : AppTheme.bg3,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: enabled ? color.withOpacity(0.4) : AppTheme.border),
          ),
          child: Row(children: [
            Container(width: 44, height: 44,
              decoration: BoxDecoration(color: enabled ? color.withOpacity(0.2) : AppTheme.bg4,
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: enabled ? color : AppTheme.textMuted, size: 22)),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: enabled ? color : AppTheme.textMuted,
                  fontSize: 14, fontWeight: FontWeight.w700)),
              Text(sublabel, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ]),
            const Spacer(),
            Icon(Icons.arrow_forward_ios, size: 14, color: enabled ? color : AppTheme.textMuted),
          ]),
        ),
      );

  Widget _infoRow(String title, String desc) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(width: 8),
      Expanded(child: Text(desc, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12))),
    ]),
  );
}
