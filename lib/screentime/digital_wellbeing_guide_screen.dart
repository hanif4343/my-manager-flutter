import 'dart:convert';
import 'package:flutter/material.dart';
import '../reminder/models/reminder.dart' show bn;
import '../services/settings_service.dart';
import '../widgets/app_theme.dart';
import 'screen_time_service.dart';

/// Digital Wellbeing সেটআপ গাইড। Android কোনো অ্যাপকে Digital Wellbeing-এর টাইমার/ফোকাস মোড
/// নিজে সেট করতে দেয় না — তাই এখানে তোমার আসল ব্যবহারের ডাটা দেখে ঠিক কোন অ্যাপে কত মিনিটের
/// টাইমার দেবে তা হিসাব করে দেওয়া হয়, আর প্রতিটা ধাপের সঠিক সেটিংসে এক ট্যাপে নিয়ে যায়।
class DigitalWellbeingGuideScreen extends StatefulWidget {
  const DigitalWellbeingGuideScreen({super.key});
  @override State<DigitalWellbeingGuideScreen> createState() => _DigitalWellbeingGuideScreenState();
}

class _WasteApp {
  final AppUse app;
  final int avgMin; // দিনে গড় মিনিট
  final int recMin; // প্রস্তাবিত টাইমার
  _WasteApp(this.app, this.avgMin, this.recMin);
}

class _DigitalWellbeingGuideScreenState extends State<DigitalWellbeingGuideScreen> {
  static const _kDone = 'dw_done_steps';
  List<_WasteApp> _waste = [];
  bool _loading = true;
  bool _access = true;
  Set<String> _done = {};

  @override
  void initState() {
    super.initState();
    try {
      _done = Set<String>.from(jsonDecode(SettingsService.getString(_kDone)) as List);
    } catch (_) {}
    _load();
  }

  Future<void> _load() async {
    final ok = await ScreenTimeService.hasAccess();
    final list = <_WasteApp>[];
    if (ok) {
      try {
        final now = DateTime.now();
        final apps = await ScreenTimeService.usage(now.subtract(const Duration(days: 7)), now);
        final waste = apps.where((a) => a.group == StGroup.waste).take(6);
        for (final a in waste) {
          final avg = (a.ms / 7 / 60000).round(); // ৭ দিনের গড়
          if (avg < 3) continue;
          // গড়ের ~৬০%, ৫ মিনিটের গুণিতকে; কমপক্ষে ১৫, গড়ের বেশি নয়।
          var rec = ((avg * 0.6) / 5).round() * 5;
          if (rec < 15) rec = 15;
          if (rec > avg) rec = avg < 15 ? 15 : avg;
          list.add(_WasteApp(a, avg, rec));
        }
      } catch (_) {}
    }
    if (mounted) setState(() { _waste = list; _access = ok; _loading = false; });
  }

  Future<void> _toggle(String id, bool v) async {
    setState(() => v ? _done.add(id) : _done.remove(id));
    await SettingsService.setString(_kDone, jsonEncode(_done.toList()));
  }

  Future<void> _openWellbeing() async {
    final r = await ScreenTimeService.openWellbeing();
    if (r != 'wellbeing' && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(seconds: 6),
        content: Text('Digital Wellbeing সরাসরি পাওয়া যায়নি — সেটিংসে "Digital Wellbeing" খোঁজো (Samsung-এ "Digital Wellbeing and parental controls")'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final doneCount = _done.length;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Digital Wellbeing সেটআপ')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
              _intro(doneCount),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.accent, padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: _openWellbeing,
                  icon: const Icon(Icons.shield_moon_rounded),
                  label: const Text('Digital Wellbeing খোলো'),
                ),
              ),
              const SizedBox(height: 14),
              _stepCard('timers', '১. অ্যাপ টাইমার', _timersBody()),
              _stepCard('focus', '২. ফোকাস মোড (পড়ার সময়)', _focusBody()),
              _stepCard('notif', '৩. নোটিফিকেশন বন্ধ', _notifBody()),
              _stepCard('bed', '৪. বেডটাইম মোড', _bedBody()),
              _stepCard('tips', '৫. ছোট কিন্তু কার্যকর কৌশল', _tipsBody()),
            ]),
    );
  }

  Widget _intro(int doneCount) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accent.withOpacity(0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${bn(doneCount)}/৫ ধাপ শেষ', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(
          'Android কোনো অ্যাপকে Digital Wellbeing-এর টাইমার নিজে সেট করতে দেয় না। তাই আমি তোমার আসল ব্যবহার দেখে '
          'ঠিক কোন অ্যাপে কত মিনিটের টাইমার দেবে তা হিসাব করে দিয়েছি, আর প্রতি ধাপে সঠিক সেটিংসে নিয়ে যাচ্ছি — '
          'তুমি শুধু সংখ্যাটা বসাবে। টাইমার শেষ হলে ফোনই অ্যাপটা বন্ধ করে দেয়, তাই এটাই সবচেয়ে শক্ত আটকানো।',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.5),
        ),
      ]),
    );
  }

  Widget _stepCard(String id, String title, Widget body) {
    final done = _done.contains(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.bg2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: done ? AppTheme.green.withOpacity(0.6) : AppTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w800))),
            Checkbox(value: done, activeColor: AppTheme.green, onChanged: (v) => _toggle(id, v ?? false)),
          ]),
          body,
        ]),
      ),
    );
  }

  Widget _p(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5)),
      );

  Widget _noData() => _p(_access
      ? 'গত ৭ দিনে ফেসবুক/ইউটিউব/গেমের উল্লেখযোগ্য ব্যবহার পাওয়া যায়নি, বা অ্যাপগুলোর ধরন "অপচয়" করা নেই। স্ক্রিন টাইম স্ক্রিনে অ্যাপে ট্যাপ করে ধরন ঠিক করো।'
      : 'আগে স্ক্রিন টাইমে Usage access অনুমতি দাও, তাহলে তোমার আসল ব্যবহার দেখে হিসাব করে দিতে পারব।');

  // ধাপ ১
  Widget _timersBody() {
    if (_waste.isEmpty) return _noData();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _p('Digital Wellbeing → ড্যাশবোর্ড → অ্যাপের নামে ট্যাপ → টাইমার (⏳) → নিচের মিনিট বসাও। '
          '(Samsung: Digital Wellbeing → অ্যাপ টাইমার।) প্রস্তাবিত সময় গত ৭ দিনের গড়ের প্রায় ৬০% — ধীরে ধীরে আরও কমিও।'),
      for (final w in _waste)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppTheme.bg3, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(w.app.label, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('এখন গড়ে ${fmtMs(w.avgMin * 60000)}/দিন', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: AppTheme.green.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
              child: Text('টাইমার ${fmtMs(w.recMin * 60000)}',
                  style: TextStyle(color: AppTheme.green, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
          ]),
        ),
    ]);
  }

  // ধাপ ২
  Widget _focusBody() {
    final names = _waste.map((w) => w.app.label).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _p('পড়তে বসার সময় এই অ্যাপগুলো পুরো বন্ধ রাখতে: Digital Wellbeing → ফোকাস মোড → "Distracting apps" বেছে নাও → '
          '"Set a schedule" দিয়ে পড়ার সময়গুলো ঠিক করো (যেমন সকাল ৯–১২টা আর রাত ৮–১০টা)।'),
      if (names.isNotEmpty)
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final n in names)
            Chip(label: Text(n, style: const TextStyle(fontSize: 12)), visualDensity: VisualDensity.compact),
        ])
      else
        _noData(),
      const SizedBox(height: 6),
      _p('পড়ার মাঝে হঠাৎ দরকার হলে ফোকাস মোডে "Take a break" নেওয়া যায় (৫-১৫ মিনিট) — সীমিত, তাই লোভ কমে।'),
    ]);
  }

  // ধাপ ৩
  Widget _notifBody() {
    if (_waste.isEmpty) return _noData();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _p('ফেসবুকে ঢোকার বেশিরভাগ ইচ্ছা আসে নোটিফিকেশন দেখে। এই অ্যাপগুলোর নোটিফিকেশন বন্ধ করলে অর্ধেক সমস্যা শেষ:'),
      for (final w in _waste)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(child: Text(w.app.label, style: TextStyle(color: AppTheme.textPrimary, fontSize: 13.5))),
            TextButton(onPressed: () => ScreenTimeService.openAppNotifications(w.app.pkg), child: const Text('নোটিফিকেশন বন্ধ করো')),
          ]),
        ),
    ]);
  }

  // ধাপ ৪
  Widget _bedBody() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _p('রাতে শুয়ে শুয়ে ফোন দেখাই সবচেয়ে বড় সময়চোর। Digital Wellbeing → বেডটাইম মোড (বা Samsung-এ Bedtime mode) → '
          'ঘুমের সময় ঠিক করো (যেমন রাত ১১টা – সকাল ৬টা) → "Grayscale" ও "Do Not Disturb" চালু।'),
      _p('সাদা-কালো স্ক্রিনে ফেসবুক-ইউটিউব অনেক কম আকর্ষণীয় লাগে, ঘুমও ভালো হয় — সকালের পড়ার জন্য জরুরি।'),
    ]);
  }

  // ধাপ ৫
  Widget _tipsBody() {
    const tips = [
      'ফেসবুক অ্যাপ আনইন্সটল করে শুধু ব্রাউজারে খোলো — প্রতিবার লগইন/লোডের ঝামেলাই অভ্যাস ভাঙে।',
      'ফেসবুক/ইউটিউব হোম স্ক্রিন থেকে সরিয়ে শেষ পাতার ফোল্ডারে রাখো।',
      'পড়তে বসার আগে ফোন অন্য ঘরে বা ব্যাগে রাখো — চোখের আড়ালে থাকলে মনও আড়ালে থাকে।',
      'পড়ার ২৫ মিনিট + ৫ মিনিট বিরতি (পোমোডোরো)। বিরতিতে ফোন নয়, পানি বা হাঁটা।',
      'প্রতি সপ্তাহে অপচয়ের সীমা ১৫-২০% কমাও, সপ্তাহের শেষে স্ক্রিন টাইমে "৭ দিন" দেখে নিজেকে মিলিয়ে নাও।',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final t in tips)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('• ', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w800)),
            Expanded(child: Text(t, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5))),
          ]),
        ),
    ]);
  }
}
