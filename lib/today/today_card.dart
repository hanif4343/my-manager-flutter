import 'package:flutter/material.dart';
import '../family/services/family_service.dart';
import '../jobs/services/job_service.dart';
import '../reminder/models/reminder.dart' show bn;
import '../reminder/services/reminder_service.dart';
import '../widgets/app_theme.dart';
import 'today_service.dart';

/// হোমের উপরের ছোট কার্ড: আজ কয়টা জরুরি/আসছে + প্রথম দুটোর নাম। ট্যাপে পুরো স্ক্রিন।
class TodayCard extends StatefulWidget {
  final VoidCallback onTap;
  const TodayCard({super.key, required this.onTap});
  @override State<TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends State<TodayCard> {
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

  /// হোমে ফিরে আসার পর বাইরে থেকে রিফ্রেশ করা যায়।
  Future<void> reload() => _load();

  Future<void> _load() async {
    final s = await TodayService.build();
    if (mounted) setState(() => _s = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final act = s?.items.where((i) => i.level >= 1).take(2).toList() ?? const <TodayItem>[];
    final String headline;
    if (s == null) {
      headline = 'আজকের হিসাব দেখা হচ্ছে...';
    } else if (s.urgentCount + s.soonCount == 0) {
      headline = '✅ আজ কিছু জরুরি নেই';
    } else {
      headline = [
        if (s.urgentCount > 0) '🔴 ${bn(s.urgentCount)} টা জরুরি',
        if (s.soonCount > 0) '🟡 ${bn(s.soonCount)} টা আসছে',
      ].join('   ');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Material(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.accent.withOpacity(0.5)),
            ),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.today_rounded, color: AppTheme.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('আজকের ম্যানেজার',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(headline, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5)),
                  for (final i in act)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('${i.emoji} ${i.title}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                    ),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
            ]),
          ),
        ),
      ),
    );
  }
}
