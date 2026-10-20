import 'package:flutter/material.dart';
import '../../reminder/models/reminder.dart' show bn;
import '../../widgets/app_theme.dart';
import '../services/app_launcher.dart';
import 'phone_notif_service.dart';

/// "ফোন নোটিফিকেশন" শিট: অনুমতির অবস্থা, কোন অ্যাপ ট্র্যাক হবে, আর ধরা নোটিফিকেশনের তালিকা।
Future<void> showPhoneAlertsSheet(BuildContext context, {required VoidCallback onChanged}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.bg2,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _PhoneAlertsBody(onChanged: onChanged),
  );
}

class _PhoneAlertsBody extends StatefulWidget {
  final VoidCallback onChanged;
  const _PhoneAlertsBody({required this.onChanged});
  @override
  State<_PhoneAlertsBody> createState() => _PhoneAlertsBodyState();
}

class _PhoneAlertsBodyState extends State<_PhoneAlertsBody> with WidgetsBindingObserver {
  bool _enabled = false;
  List<String> _pkgs = [];
  List<AppInfo> _results = [];
  List<PhoneAlert> _alerts = [];
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _q.dispose();
    super.dispose();
  }

  // সেটিংস থেকে ফিরে এলে অবস্থা আবার দেখি
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final en = await PhoneNotifService.isEnabled();
    final pk = await PhoneNotifService.packages();
    await PhoneNotifService.sync();
    if (!mounted) return;
    setState(() {
      _enabled = en;
      _pkgs = pk;
      _alerts = PhoneNotifService.alerts();
    });
    widget.onChanged();
  }

  Future<void> _search() async {
    final r = await PhoneNotifService.searchApps(_q.text);
    if (mounted) setState(() => _results = r);
  }

  Future<void> _togglePkg(String pkg) async {
    final next = [..._pkgs];
    next.contains(pkg) ? next.remove(pkg) : next.add(pkg);
    await PhoneNotifService.setPackages(next);
    if (mounted) setState(() => _pkgs = next..sort());
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: h * 0.88),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('📱 ফোনের নোটিফিকেশন',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'শুধু তুমি যে অ্যাপগুলো বেছে দেবে সেগুলোর নোটিফিকেশনের শিরোনাম ও লেখা ধরা হয়। অন্য অ্যাপের কিছু পড়া হয় না। সবকিছু শুধু তোমার ফোনেই থাকে।',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 12),
          _card(
            Row(children: [
              Expanded(
                child: Text(_enabled ? '✅ নোটিফিকেশন অ্যাক্সেস চালু' : '⛔ নোটিফিকেশন অ্যাক্সেস বন্ধ',
                    style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
              ),
              if (!_enabled)
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
                  onPressed: PhoneNotifService.openSettings,
                  child: const Text('চালু করো'),
                ),
            ]),
          ),
          if (!_enabled)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'সেটিংসে "My Manager" খুঁজে চালু করো। Android ১৩+ এ APK থেকে ইনস্টল করা অ্যাপে অপশনটা ধূসর থাকলে: Settings → Apps → My Manager → ⋮ → "Allow restricted settings", তারপর আবার চেষ্টা করো।',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5, height: 1.45),
              ),
            ),
          const SizedBox(height: 16),
          Text('ট্র্যাক করা অ্যাপ', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (_pkgs.isEmpty)
            Text('এখনো কোনো অ্যাপ বাছা হয়নি — নিচে নাম লিখে খুঁজে যোগ করো।',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5))
          else
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final p in _pkgs)
                InputChip(label: Text(p, style: const TextStyle(fontSize: 11.5)), onDeleted: () => _togglePkg(p)),
            ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _q,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'অ্যাপের নাম (যেমন: bdjobs)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(onPressed: _search, icon: const Icon(Icons.search)),
          ]),
          for (final a in _results)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(a.label, style: TextStyle(color: AppTheme.textPrimary)),
              subtitle: Text(a.pkg, style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              trailing: Icon(_pkgs.contains(a.pkg) ? Icons.check_circle : Icons.add_circle_outline,
                  color: _pkgs.contains(a.pkg) ? AppTheme.green : AppTheme.textSecondary),
              onTap: () => _togglePkg(a.pkg),
            ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: Text('ধরা নোটিফিকেশন (${bn(_alerts.length)})',
                  style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w700)),
            ),
            if (_alerts.isNotEmpty)
              TextButton(
                onPressed: () async {
                  await PhoneNotifService.clear();
                  await _load();
                },
                child: const Text('সব মুছো'),
              ),
          ]),
          if (_alerts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('এখনো কিছু ধরা পড়েনি।', style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
            ),
          for (final a in _alerts) _alertCard(a),
        ]),
      ),
    );
  }

  Widget _alertCard(PhoneAlert a) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (a.match)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppTheme.green.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: Text('🎯 পদ মিলেছে', style: TextStyle(color: AppTheme.green, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          Expanded(
            child: Text('${bn(a.time.day)}/${bn(a.time.month)} · ${a.pkg}',
                overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ),
        ]),
        const SizedBox(height: 4),
        if (a.title.isNotEmpty)
          Text(a.title, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 13.5)),
        if (a.text.isNotEmpty)
          Text(a.text, maxLines: 4, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.4)),
        Row(children: [
          TextButton(
            onPressed: () => AppLauncher.openUrl(a.searchUrl),
            child: const Text('🔎 ওয়েবে খোঁজো'),
          ),
          TextButton(
            onPressed: () async {
              await PhoneNotifService.remove(a.key);
              await _load();
            },
            child: const Text('মুছো'),
          ),
        ]),
      ])),
    );
  }

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: child,
      );
}
