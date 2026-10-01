import 'package:flutter/material.dart';
import '../family/services/family_service.dart';
import '../jobs/services/job_service.dart';
import '../reminder/models/reminder.dart' show bn, weekdayBn;
import '../reminder/services/reminder_service.dart';
import '../widgets/app_theme.dart';
import 'today_service.dart';

const _months = [
  'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
  'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর',
];

/// আজকের ম্যানেজার: সব মডিউল থেকে আজ কী কী জরুরি/আসছে — এক স্ক্রিনে।
/// আইটেমে ট্যাপ করলে ঠিক সেই মডিউলের ঠিক সেই ট্যাবে নিয়ে যায়।
class TodayScreen extends StatefulWidget {
  /// (এই স্ক্রিনের context, মডিউলের নাম, ট্যাব নম্বর)
  final void Function(BuildContext ctx, String module, int tab) onOpen;
  const TodayScreen({super.key, required this.onOpen});
  @override State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  TodaySummary? _s;

  @override
  void initState() {
    super.initState();
    ReminderService.changes.addListener(_load);
    JobService.changes.addListener(_load);
    FamilyService.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    ReminderService.changes.removeListener(_load);
    JobService.changes.removeListener(_load);
    FamilyService.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final s = await TodayService.build();
    if (mounted) setState(() => _s = s);
  }

  /// লক্ষ্য মডিউল ও ট্যাব (জব হাব: ০ ওভারভিউ/১ সার্কুলার, পরিবার: ২ তারিখ/৩ বিল)।
  (String, int) _route(TodayTarget t) {
    switch (t) {
      case TodayTarget.reminders: return ('রিমাইন্ডার', 0);
      case TodayTarget.jobs: return ('চাকরি হাব', 1);
      case TodayTarget.familyBills: return ('পরিবার', 3);
      case TodayTarget.familyDates: return ('পরিবার', 2);
      case TodayTarget.cashbook: return ('ক্যাশবুক', 0);
      case TodayTarget.projects: return ('প্রজেক্ট', 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('আজকের ম্যানেজার')),
      body: s == null
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : RefreshIndicator(
              color: AppTheme.accent,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  _header(s),
                  const SizedBox(height: 14),
                  if (s.items.isEmpty) _allClear(),
                  _section('🔴 আজ ও জরুরি', s.at(2)),
                  _section('🟡 শিগগির আসছে', s.at(1)),
                  _section('ℹ️ এক নজরে', s.at(0)),
                  if (s.items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('সকালের নোটিফিকেশনের সময় বদলাতে: সেটিংস → Daily digest',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _header(TodaySummary s) {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C6FF0)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(TodaySummary.greeting(now.hour),
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('${bn(now.day)} ${_months[now.month - 1]} ${bn(now.year)}, ${weekdayBn(now)}বার',
            style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13)),
        const SizedBox(height: 12),
        Text(
          s.urgentCount + s.soonCount == 0
              ? '✅ আজ কিছু জরুরি নেই'
              : [
                  if (s.urgentCount > 0) '🔴 ${bn(s.urgentCount)} টা জরুরি',
                  if (s.soonCount > 0) '🟡 ${bn(s.soonCount)} টা আসছে',
                ].join('   '),
          style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
      ]),
    );
  }

  Widget _allClear() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(children: [
          const Text('🎉', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 10),
          Text('সব পরিষ্কার! আজ কোনো ডেডলাইন, বিল বা রিমাইন্ডার নেই।',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5)),
          const SizedBox(height: 6),
          Text('এই সময়টা পড়াশোনায় লাগাও 📚',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        ]),
      );

  Widget _section(String title, List<TodayItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 0, 8),
        child: Text(title,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5, fontWeight: FontWeight.w700)),
      ),
      for (final i in items) _tile(i),
      const SizedBox(height: 6),
    ]);
  }

  Widget _tile(TodayItem i) {
    final color = i.level == 2 ? AppTheme.red : (i.level == 1 ? AppTheme.yellow : AppTheme.textMuted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            final (module, tab) = _route(i.target);
            widget.onOpen(context, module, tab);
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(0, 0, 8, 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: IntrinsicHeight(
              child: Row(children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(i.emoji, style: const TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(i.title,
                          style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600, height: 1.3)),
                      if (i.sub.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(i.sub, style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5, height: 1.3)),
                        ),
                    ]),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
