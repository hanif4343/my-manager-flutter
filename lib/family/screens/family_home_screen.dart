import 'package:flutter/material.dart';
import '../../reminder/models/reminder.dart' show bn;
import '../../services/drive_service.dart' show DriveBackupResult;
import '../../widgets/app_theme.dart';
import '../models/family_models.dart';
import '../services/family_backup_service.dart';
import '../services/family_service.dart';
import 'bills_tab.dart';
import 'contacts_tab.dart';
import 'dates_tab.dart';
import 'family_ui.dart';
import 'members_tab.dart';

/// পরিবার: সদস্য, গুরুত্বপূর্ণ তারিখ, নিয়মিত বিল, জরুরি তথ্য — আর উপরে
/// "আজকের ওভারভিউ"।
class FamilyHomeScreen extends StatefulWidget {
  final VoidCallback onOpenVault;
  const FamilyHomeScreen({super.key, required this.onOpenVault});
  @override State<FamilyHomeScreen> createState() => _FamilyHomeScreenState();
}

class _FamilyHomeScreenState extends State<FamilyHomeScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('পরিবার'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppTheme.accent,
          labelColor: AppTheme.accent,
          unselectedLabelColor: AppTheme.textMuted,
          tabs: const [
            Tab(text: 'ওভারভিউ'),
            Tab(text: 'সদস্য'),
            Tab(text: 'তারিখ'),
            Tab(text: 'বিল'),
            Tab(text: 'জরুরি'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _OverviewTab(onGoTab: (i) => _tab.animateTo(i)),
          MembersTab(onOpenVault: widget.onOpenVault),
          const DatesTab(),
          const BillsTab(),
          const ContactsTab(),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatefulWidget {
  final void Function(int) onGoTab;
  const _OverviewTab({required this.onGoTab});
  @override State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  List<UpcomingItem> _upcoming = [];
  List<FamilyBill> _bills = [];
  List<FamilyContact> _contacts = [];
  int _members = 0;
  bool _loading = true;
  bool _bkBusy = false;
  String? _bkStatus;
  bool _bkError = false;

  @override
  void initState() {
    super.initState();
    FamilyService.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    FamilyService.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final up = await FamilyService.upcoming();
    final bills = await FamilyService.bills();
    final contacts = await FamilyService.contacts();
    final members = await FamilyService.members();
    if (mounted) {
      setState(() {
        _upcoming = up;
        _bills = bills;
        _contacts = contacts;
        _members = members.length;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppTheme.accent));

    final soon = _upcoming.where((u) => u.daysLeft <= 30).take(3).toList();
    final dueBills = _bills.where((b) => !b.paidThisMonth && b.daysToDue <= 7).toList()
      ..sort((a, b) => a.daysToDue.compareTo(b.daysToDue));
    final emergency = _contacts.where((c) => c.kind == 'emergency').take(3).toList();
    final unpaidTotal = _bills.where((b) => !b.paidThisMonth).fold<int>(0, (s, b) => s + b.amount);

    final nothing = _members == 0 && _bills.isEmpty && _contacts.isEmpty && _upcoming.isEmpty;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 40), children: [
      Row(children: [
        Expanded(child: _stat('👨‍👩‍👧', 'সদস্য', bn(_members), () => widget.onGoTab(1))),
        const SizedBox(width: 10),
        Expanded(child: _stat('🧾', 'এ মাসে বাকি', '৳${bn(unpaidTotal)}', () => widget.onGoTab(3))),
      ]),
      const SizedBox(height: 10),
      if (nothing)
        fEmpty(Icons.family_restroom,
            'শুরু করতে "সদস্য" ট্যাবে পরিবারের মানুষ যোগ করো।\nজন্মদিন, বিল আর জরুরি নম্বর ধাপে ধাপে বসাতে পারবে।')
      else ...[
        fSection('আসন্ন তারিখ (৩০ দিন)'),
        if (soon.isEmpty)
          fCard(
            onTap: () => widget.onGoTab(2),
            child: Text('আগামী ৩০ দিনে কোনো জন্মদিন বা বিশেষ দিন নেই',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          )
        else
          for (final u in soon)
            fCard(
              onTap: () => widget.onGoTab(2),
              child: Row(children: [
                Text(u.emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(u.title,
                      style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                ),
                fChip(
                  u.daysLeft == 0 ? 'আজ' : (u.daysLeft == 1 ? 'কাল' : '${bn(u.daysLeft)} দিন পরে'),
                  u.daysLeft <= 1 ? AppTheme.red : (u.daysLeft <= 7 ? AppTheme.yellow : AppTheme.textSecondary),
                ),
              ]),
            ),
        fSection('বিল (৭ দিনের মধ্যে / বকেয়া)'),
        if (dueBills.isEmpty)
          fCard(
            onTap: () => widget.onGoTab(3),
            child: Text(_bills.isEmpty ? 'কোনো নিয়মিত বিল যোগ করা নেই' : '✓ এখন কোনো বিল বাকি বা জরুরি নেই',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          )
        else
          for (final b in dueBills) _dueBillCard(b),
        if (emergency.isNotEmpty) ...[
          fSection('জরুরি নম্বর'),
          for (final c in emergency)
            fCard(
              child: Row(children: [
                Text(c.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.name, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                    Text(c.phone, style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
                  ]),
                ),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: AppTheme.green),
                  icon: const Icon(Icons.call_rounded, color: Colors.white),
                  onPressed: () => dialNumber(context, c.phone),
                ),
              ]),
            ),
        ],
      ],
      fSection('ব্যাকআপ'),
      _backupCard(),
    ]);
  }

  Widget _stat(String emoji, String label, String value, VoidCallback onTap) {
    return fCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$emoji $label', style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _dueBillCard(FamilyBill b) {
    final (label, color) = billStatus(b);
    return fCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(b.emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.title, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
              if (b.amount > 0)
                Text('৳${bn(b.amount)}', style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
            ]),
          ),
          fChip(label, color),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('পরিশোধ করেছি'),
            onPressed: () => payBillDialog(context, b),
          ),
        ),
      ]),
    );
  }

  Widget _backupCard() {
    final last = FamilyBackupService.lastBackupAt;
    return fCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.cloud_done_outlined, color: AppTheme.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'সদস্য, তারিখ, বিল ও জরুরি তথ্য Google Drive-এ নিজে সেভ হয় (সাইন-ইন থাকলে)।'
              '${last != null ? '\nএই সেশনে শেষ ব্যাকআপ: ${last.hour}:${last.minute.toString().padLeft(2, '0')}' : ''}',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.4),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _bkBusy ? null : _backupNow,
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: const Text('এখনই ব্যাকআপ'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _bkBusy ? null : _restore,
              icon: const Icon(Icons.cloud_download_outlined, size: 18),
              label: const Text('ফিরিয়ে আনো'),
            ),
          ),
        ]),
        if (_bkBusy)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: LinearProgressIndicator(color: AppTheme.accent),
          ),
        if (_bkStatus != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_bkStatus!,
                style: TextStyle(
                    color: _bkError ? AppTheme.red : AppTheme.green, fontSize: 12.5, height: 1.4)),
          ),
      ]),
    );
  }

  Future<void> _backupNow() async {
    setState(() { _bkBusy = true; _bkStatus = null; });
    String msg;
    var err = false;
    try {
      final r = await FamilyBackupService.backupNow();
      switch (r) {
        case DriveBackupResult.success:
          msg = '✅ Google Drive-এ ব্যাকআপ হয়েছে';
          break;
        case DriveBackupResult.notSignedIn:
          msg = 'Google Account দিয়ে সাইন ইন করা যায়নি';
          err = true;
          break;
        default:
          msg = 'ব্যাকআপ ব্যর্থ — ইন্টারনেট আছে কিনা দেখো';
          err = true;
      }
    } catch (e) {
      msg = 'ব্যাকআপ ব্যর্থ: $e';
      err = true;
    }
    if (mounted) setState(() { _bkBusy = false; _bkStatus = msg; _bkError = err; });
  }

  Future<void> _restore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bg2,
        title: const Text('Drive থেকে ফিরিয়ে আনবে?'),
        content: const Text('ব্যাকআপের তথ্য বর্তমান ডাটার সাথে মার্জ হবে — বর্তমান কিছু মুছবে না। জন্মদিন, তারিখ ও বিলের রিমাইন্ডার নতুন করে বসবে।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('ফিরিয়ে আনো', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() { _bkBusy = true; _bkStatus = null; });
    String msg;
    var err = false;
    try {
      final r = await FamilyBackupService.restoreFromDrive();
      if (r == null) {
        msg = 'Drive-এ পরিবারের ব্যাকআপ পাওয়া যায়নি, বা সাইন-ইন হয়নি';
        err = true;
      } else {
        msg = '✅ ফিরে এসেছে: ${bn(r.members)}টা সদস্য, ${bn(r.dates)}টা তারিখ, '
            '${bn(r.bills)}টা বিল, ${bn(r.contacts)}টা জরুরি তথ্য';
      }
    } catch (e) {
      msg = 'রিস্টোর ব্যর্থ: $e';
      err = true;
    }
    await _load();
    if (mounted) setState(() { _bkBusy = false; _bkStatus = msg; _bkError = err; });
  }
}
