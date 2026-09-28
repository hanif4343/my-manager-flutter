import 'package:flutter/material.dart';
import '../../widgets/app_theme.dart';
import '../db/reminder_db.dart';
import '../models/reminder.dart';
import '../services/reminder_service.dart';
import 'reminder_form_screen.dart';

class ReminderScreen extends StatefulWidget {
  const ReminderScreen({super.key});
  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen>
    with WidgetsBindingObserver {
  List<Reminder> _all = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ReminderService.changes.addListener(_load);
    _load();
    ReminderService.requestPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ReminderService.changes.removeListener(_load);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // নোটিফিকেশন বার থেকে Done/Not yet দিলে ডাটা অন্য আইসোলেটে বদলায় —
    // অ্যাপে ফিরলে তাই নতুন করে পড়ি।
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final list = await ReminderDB.all();
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
  }

  Future<void> _openForm([Reminder? r]) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => ReminderFormScreen(existing: r)));
    _load();
  }

  Future<void> _done(Reminder r, DateTime today) async {
    // মেয়াদ-পেরোনো এক-বারের রিমাইন্ডারের নিজের তারিখটাই occurrence।
    final date = r.isOverdue(today) ? Reminder.ymd(r.date) : Reminder.ymd(today);
    await ReminderService.markDone(r.id!, date);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ "${r.title}" সম্পন্ন'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _confirmDelete(Reminder r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('মুছে ফেলবে?'),
        content: Text('"${r.title}" রিমাইন্ডারটা চিরতরে মুছে যাবে।'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('না')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('মুছো', style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    if (ok == true) await ReminderService.delete(r.id!);
  }

  int _firstMinutes(Reminder r) {
    if (r.times.isEmpty) return 0;
    final (h, m) = parseHm(r.times.first);
    return h * 60 + m;
  }

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());

    final due = _all
        .where((r) => r.isDueToday(today) || r.isOverdue(today))
        .toList()
      ..sort((a, b) {
        final ao = a.isOverdue(today) ? 0 : 1;
        final bo = b.isOverdue(today) ? 0 : 1;
        if (ao != bo) return ao - bo;
        return _firstMinutes(a).compareTo(_firstMinutes(b));
      });

    final upcoming = _all
        .where((r) =>
            !r.done && !r.isDueToday(today) && !r.isOverdue(today))
        .toList()
      ..sort((a, b) {
        final ad = a.nextDateAfter(today) ?? DateTime(9999);
        final bd = b.nextDateAfter(today) ?? DateTime(9999);
        final c = ad.compareTo(bd);
        return c != 0 ? c : _firstMinutes(a).compareTo(_firstMinutes(b));
      });

    final done = _all.where((r) => r.done).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          backgroundColor: AppTheme.bg,
          elevation: 0,
          title: Text('রিমাইন্ডার', style: AppTheme.title(size: 18)),
          bottom: TabBar(
            labelColor: AppTheme.accent,
            unselectedLabelColor: AppTheme.textMuted,
            indicatorColor: AppTheme.accent,
            tabs: [
              Tab(text: 'আজ${due.isEmpty ? '' : ' (${bn(due.length)})'}'),
              Tab(text: 'আসছে${upcoming.isEmpty ? '' : ' (${bn(upcoming.length)})'}'),
              Tab(text: 'সম্পন্ন${done.isEmpty ? '' : ' (${bn(done.length)})'}'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          onPressed: () => _openForm(),
          icon: const Icon(Icons.add),
          label: const Text('নতুন রিমাইন্ডার'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [
                _list(due, today, 'আজ কোনো কাজ বাকি নেই 🎉',
                    'নিচের বাটন থেকে নতুন রিমাইন্ডার যোগ করো'),
                _list(upcoming, today, 'আসছে কিছু নেই',
                    'ভবিষ্যতের কল, প্ল্যান বা পোস্ট এখানে জমা থাকবে'),
                _list(done, today, 'এখনো কিছু সম্পন্ন হয়নি',
                    'Done দিলে রিমাইন্ডার এখানে আসবে'),
              ]),
      ),
    );
  }

  Widget _list(List<Reminder> items, DateTime today, String emptyTitle,
      String emptySub) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.notifications_none, size: 56, color: AppTheme.textMuted),
            const SizedBox(height: 12),
            Text(emptyTitle,
                style: AppTheme.title(size: 15), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(emptySub,
                style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                textAlign: TextAlign.center),
          ]),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final r = items[i];
        return _ReminderCard(
          reminder: r,
          today: today,
          onTap: () => _openForm(r),
          onDone: () => _done(r, today),
          onUndo: () => ReminderService.undoDone(r),
          onStop: () => ReminderService.stopSeries(r),
          onDelete: () => _confirmDelete(r),
        );
      },
    );
  }
}

class _ReminderCard extends StatelessWidget {
  final Reminder reminder;
  final DateTime today;
  final VoidCallback onTap;
  final VoidCallback onDone;
  final VoidCallback onUndo;
  final VoidCallback onStop;
  final VoidCallback onDelete;

  const _ReminderCard({
    required this.reminder,
    required this.today,
    required this.onTap,
    required this.onDone,
    required this.onUndo,
    required this.onStop,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final kind = kindOf(r.kind);
    final overdue = r.isOverdue(today);
    final dueToday = r.isDueToday(today);
    final now = DateTime.now();
    final next = r.nextDateAfter(today);

    // কোন তারিখ দেখাবো
    String dateText;
    if (r.done) {
      dateText = formatDateBn(r.date);
    } else if (overdue) {
      dateText = 'বাকি — ${formatDateBn(r.date)}';
    } else if (dueToday) {
      dateText = 'আজ';
    } else if (next != null) {
      dateText = '${formatDateBn(next)} • ${weekdayBn(next)}বার';
    } else {
      dateText = formatDateBn(r.date);
    }

    return Material(
      color: AppTheme.bg2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: overdue ? AppTheme.red.withOpacity(0.6) : AppTheme.border),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: AppTheme.bg3, shape: BoxShape.circle),
              child: Text(kind.emoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.title(size: 15).copyWith(
                        decoration:
                            r.done ? TextDecoration.lineThrough : null)),
                if (r.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(r.note.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5, color: AppTheme.textSecondary)),
                ],
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final t in r.times)
                    _chip(
                      formatTimeBn(t),
                      Icons.access_time,
                      (dueToday || overdue) && _passed(t, now, overdue)
                          ? AppTheme.red
                          : AppTheme.textSecondary,
                    ),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.event, size: 13, color: overdue ? AppTheme.red : AppTheme.textMuted),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(dateText,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: overdue ? AppTheme.red : AppTheme.textMuted)),
                  ),
                  if (r.repeats) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.repeat, size: 13, color: AppTheme.textMuted),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(r.repeatLabel,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
                    ),
                  ],
                ]),
              ]),
            ),
            Column(children: [
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 20, color: AppTheme.textMuted),
                onSelected: (v) {
                  switch (v) {
                    case 'edit':
                      onTap();
                      break;
                    case 'undo':
                      onUndo();
                      break;
                    case 'stop':
                      onStop();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('এডিট')),
                  if (r.done)
                    const PopupMenuItem(value: 'undo', child: Text('আবার চালু করো')),
                  if (!r.done && r.repeats)
                    const PopupMenuItem(value: 'stop', child: Text('সিরিজ বন্ধ করো')),
                  PopupMenuItem(
                      value: 'delete',
                      child: Text('মুছো', style: TextStyle(color: AppTheme.red))),
                ],
              ),
              if (dueToday || overdue)
                IconButton(
                  tooltip: 'Done',
                  onPressed: onDone,
                  icon: Icon(Icons.check_circle_outline, color: AppTheme.green),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  bool _passed(String hm, DateTime now, bool overdue) {
    if (overdue) return true;
    final (h, m) = parseHm(hm);
    return DateTime(now.year, now.month, now.day, h, m).isBefore(now);
  }

  Widget _chip(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.bg3,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}
