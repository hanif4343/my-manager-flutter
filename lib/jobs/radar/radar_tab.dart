import 'package:flutter/material.dart';
import '../../reminder/models/reminder.dart' show bn, Reminder;
import '../../widgets/app_theme.dart';
import '../services/app_launcher.dart';
import '../services/job_service.dart';
import 'phone_alerts_sheet.dart';
import 'phone_notif_service.dart';
import 'radar_models.dart';
import 'radar_runner.dart';
import 'radar_service.dart';

/// চাকরি হাবের "রাডার" ট্যাব — Job Radar যে সার্কুলারগুলো তোমার যোগ্যতার সাথে মিলিয়ে
/// বেছেছে সেগুলো এখানে দেখায়। "নজরে নাও" চাপলে সার্কুলার ট্যাবে চলে যায় (রিমাইন্ডারসহ)।
class RadarTab extends StatefulWidget {
  /// সার্কুলার যোগ হলে হাব রিফ্রেশ করার কলব্যাক।
  final VoidCallback onSaved;
  const RadarTab({super.key, required this.onSaved});
  @override
  State<RadarTab> createState() => _RadarTabState();
}

class _RadarTabState extends State<RadarTab> {
  RadarFeed? _feed;
  bool _loading = false;
  bool _showHidden = false;
  String? _error;
  Set<String> _saved = {};

  @override
  void initState() {
    super.initState();
    _feed = RadarService.cached();
    _init();
  }

  Future<void> _init() async {
    await PhoneNotifService.sync();
    await RadarService.reload();
    _feed = RadarService.cached();
    await _loadSaved();
    if (mounted) setState(() {});
    // অ্যাপ খুললে: রাতের রিপোর্টের সময় পেরিয়ে থাকলে ও আজকের রিপোর্ট বাকি থাকলে এখনই করে দিই;
    // একেবারে প্রথমবার (ক্যাশ নেই) হলে একবার চালিয়ে দেখাই।
    if (RadarRunner.isDue()) {
      await _refresh(report: true);
    } else if (_feed == null) {
      await _refresh();
    }
  }

  Future<void> _loadSaved() async {
    final list = await JobService.circulars();
    _saved = list.map((c) => c.url).where((u) => u.isNotEmpty).toSet();
  }

  /// এখনই সাইট থেকে পড়ে নতুন করে যাচাই (হাতে রিফ্রেশ — নোটিফিকেশন দেয় না)।
  Future<void> _refresh({bool report = false}) async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      final r = await RadarRunner.run(report: report);
      await RadarService.reload();
      await _loadSaved();
      if (mounted) {
        setState(() {
          _feed = RadarService.cached();
          _loading = false;
          _error = r.error;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'রাডার চালানো যায়নি: $e'; });
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _watch(RadarItem it) async {
    await JobService.saveCircular(RadarService.toCircular(it));
    _saved.add(it.url);
    widget.onSaved();
    if (mounted) {
      setState(() {});
      _snack('সার্কুলার ট্যাবে যোগ হয়েছে — শেষ তারিখের রিমাইন্ডারও সেট হয়েছে');
    }
  }

  Color _urgency(int d) => d <= 3 ? AppTheme.red : (d <= 7 ? AppTheme.yellow : AppTheme.green);

  String _stamp(DateTime d) =>
      '${bn(d.day)}/${bn(d.month)} ${bn(d.hour.toString().padLeft(2, '0'))}:${bn(d.minute.toString().padLeft(2, '0'))}';

  // ───────────────────────── বিল্ড ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final hidden = RadarService.dismissed();
    final all = (_feed?.items ?? const <RadarItem>[])
        .where((i) => i.daysLeft == null || i.daysLeft! >= 0)
        .toList();
    final items = _showHidden ? all : all.where((i) => !hidden.contains(i.url)).toList();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
        child: Row(children: [
          Expanded(
            child: Text(
              _feed?.generatedAt != null
                  ? 'শেষ খোঁজা: ${_stamp(_feed!.generatedAt!)} · প্রতি রাত ${bn(RadarService.reportHour)}:${bn(RadarService.reportMinute.toString().padLeft(2, '0'))}-এ রিপোর্ট'
                  : 'রাডার',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ),
          if (hidden.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _showHidden = !_showHidden),
              child: Text(_showHidden ? 'লুকানো বাদ দাও' : 'লুকানো ${bn(hidden.length)}টি'),
            ),
          IconButton(
            tooltip: 'রিফ্রেশ',
            icon: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.refresh, color: AppTheme.textSecondary),
            onPressed: _refresh,
          ),
          IconButton(
            tooltip: 'ফোনের নোটিফিকেশন',
            icon: Badge(
              isLabelVisible: PhoneNotifService.alerts().any((a) => a.match),
              smallSize: 8,
              child: Icon(Icons.notifications_active_outlined, color: AppTheme.textSecondary),
            ),
            onPressed: () => showPhoneAlertsSheet(context, onChanged: () {
              if (mounted) setState(() {});
            }),
          ),
          IconButton(
            tooltip: 'সেটিংস',
            icon: Icon(Icons.tune, color: AppTheme.textSecondary),
            onPressed: _settingsSheet,
          ),
        ]),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text('⚠️ $_error', style: TextStyle(color: AppTheme.red, fontSize: 12.5)),
        ),
      Expanded(
        child: _feed == null
            ? Center(child: Text(_loading ? 'সার্কুলার খোঁজা হচ্ছে…' : 'রিফ্রেশ চাপো', style: TextStyle(color: AppTheme.textMuted)))
            : RefreshIndicator(
                onRefresh: _refresh,
                child: items.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 80),
                        Icon(Icons.radar, size: 44, color: AppTheme.textMuted),
                        const SizedBox(height: 12),
                        Center(
                          child: Text('এখন তোমার মতো কোনো চলমান সার্কুলার নেই',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                        ),
                      ])
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                        children: items.map(_itemCard).toList(),
                      ),
              ),
      ),
    ]);
  }

  Widget _itemCard(RadarItem it) {
    final ok = it.verdict == 'ok';
    final dl = it.daysLeft;
    final saved = _saved.contains(it.url);
    final hidden = RadarService.dismissed().contains(it.url);
    final accent = ok ? AppTheme.green : AppTheme.yellow;
    return Opacity(
      opacity: hidden ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.bg2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 6, children: [
              _chip(ok ? '🟢 সম্ভাব্য যোগ্য' : '🟡 যাচাই বাকি', accent),
              if (_feed?.newUrls.contains(it.url) ?? false) _chip('🆕 নতুন', AppTheme.accent),
              if (dl != null) _chip(dl == 0 ? 'আজই শেষ' : 'আর ${bn(dl)} দিন', _urgency(dl)),
            ]),
            const SizedBox(height: 8),
            Text(it.title,
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
            if (it.org.isNotEmpty)
              Text(it.org, style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
            for (final p in it.posts.take(4)) ...[
              const SizedBox(height: 10),
              Text('📌 ${p.title}${p.count != null ? ' (${bn(p.count!)}টি)' : ''}',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              for (final c in p.checks)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('${c.icon} ${c.msg}',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.35)),
                ),
            ],
            if (it.method.isNotEmpty || it.fee.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                [if (it.method.isNotEmpty) '📝 ${it.method}', if (it.fee.isNotEmpty) '💰 ${it.fee}'].join('   '),
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              saved
                  ? _chip('✔ নজরে আছে', AppTheme.textSecondary)
                  : FilledButton.tonal(onPressed: () => _watch(it), child: const Text('নজরে নাও')),
              TextButton(
                onPressed: () async {
                  final ok = await AppLauncher.openUrl(it.url);
                  if (!ok) _snack('লিংক খোলা যায়নি');
                },
                child: const Text('🔗 বিস্তারিত'),
              ),
              TextButton(
                onPressed: () async {
                  hidden ? await RadarService.restore(it.url) : await RadarService.dismiss(it.url);
                  if (mounted) setState(() {});
                },
                child: Text(hidden ? 'ফিরিয়ে আনো' : 'লুকাও'),
              ),
            ]),
            const SizedBox(height: 2),
            Text('স্বয়ংক্রিয় যাচাই — মূল বিজ্ঞপ্তিই চূড়ান্ত।',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ]),
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );

  // ───────────────────────── সেটিংস ও প্রোফাইল ─────────────────────────

  Future<void> _settingsSheet() async {
    final subject = TextEditingController(text: RadarService.subject);
    final typBn = TextEditingController(text: RadarService.typingBn.toString());
    final typEn = TextEditingController(text: RadarService.typingEn.toString());
    var dob = RadarService.dob;
    var edu = RadarService.eduLevel;
    if (!RadarService.eduLevels.containsKey(edu)) edu = 'degree_pass';
    var daily = RadarService.dailyOn;
    var time = RadarService.reportTime;

    InputDecoration deco(String label, {String? hint}) => InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        );

    Future<void> persist() => SettingsPersist.save({
          RadarService.kDob: dob,
          RadarService.kEdu: edu,
          RadarService.kSubject: subject.text.trim(),
          RadarService.kTypBn: _num(typBn.text, 20).toString(),
          RadarService.kTypEn: _num(typEn.text, 20).toString(),
          RadarService.kDaily: daily ? '1' : '0',
          RadarService.kReportTime: time,
        });

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('রাডার সেটিংস',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Text('রাতের রিপোর্ট', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w700)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('প্রতি রাতে একবার জানাও', style: TextStyle(color: AppTheme.textPrimary)),
                subtitle: Text('সারাদিনের সব উপযুক্ত সার্কুলারের তালিকা — একটাই নোটিফিকেশনে',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                value: daily,
                onChanged: (v) => setS(() => daily = v),
              ),
              OutlinedButton(
                onPressed: !daily
                    ? null
                    : () async {
                        final parts = time.split(':');
                        final t = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay(
                              hour: int.tryParse(parts.first) ?? 21, minute: int.tryParse(parts.last) ?? 0),
                        );
                        if (t != null) {
                          setS(() => time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                        }
                      },
                child: Text('রিপোর্টের সময়: ${bn(time.split(':').first)}:${bn(time.split(':').last)}'),
              ),
              const SizedBox(height: 4),
              Text('অ্যান্ড্রয়েড ব্যাকগ্রাউন্ড কাজ ঠিক মিনিটে না-ও চালাতে পারে; কিছুক্ষণ দেরি হওয়া স্বাভাবিক।',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5, height: 1.4)),
              const SizedBox(height: 18),
              Text('তোমার যোগ্যতা', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  final init = DateTime.tryParse(dob) ?? DateTime(1999, 1, 1);
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: init,
                    firstDate: DateTime(1960),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setS(() => dob = Reminder.ymd(d));
                },
                child: Text('জন্মতারিখ: ${_dobBn(dob)}'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: edu,
                decoration: deco('সর্বোচ্চ শিক্ষাগত যোগ্যতা'),
                items: RadarService.eduLevels.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setS(() => edu = v ?? edu),
              ),
              const SizedBox(height: 10),
              TextField(controller: subject, decoration: deco('বিষয়/বিভাগ (ঐচ্ছিক)', hint: 'যেমন: বাংলা')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: typBn,
                    keyboardType: TextInputType.number,
                    decoration: deco('বাংলা টাইপিং (WPM)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: typEn,
                    keyboardType: TextInputType.number,
                    decoration: deco('ইংরেজি টাইপিং (WPM)'),
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
                  onPressed: () async {
                    await persist();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('সংরক্ষণ'),
                ),
              ),
            ]),
          ),
        );
      }),
    );

    for (final c in [subject, typBn, typEn]) {
      c.dispose();
    }
    if (mounted) setState(() {});
    await RadarRunner.markStale();
    await _refresh(); // প্রোফাইল বদলালে নতুন করে যাচাই
  }

  static int _num(String s, int fallback) {
    const d = '০১২৩৪৫৬৭৮৯';
    final en = s.replaceAllMapped(RegExp('[০-৯]'), (m) => d.indexOf(m[0]!).toString());
    final n = int.tryParse(en.trim());
    return (n == null || n <= 0) ? fallback : n;
  }

  static String _dobBn(String ymd) {
    final d = DateTime.tryParse(ymd);
    return d == null ? ymd : '${bn(d.day)}/${bn(d.month)}/${bn(d.year)}';
  }
}
