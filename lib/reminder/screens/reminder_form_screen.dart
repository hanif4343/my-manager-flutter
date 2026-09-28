import 'package:flutter/material.dart';
import '../../widgets/app_theme.dart';
import '../db/reminder_db.dart';
import '../models/reminder.dart';
import '../services/reminder_service.dart';

class ReminderFormScreen extends StatefulWidget {
  final Reminder? existing;
  const ReminderFormScreen({super.key, this.existing});
  @override
  State<ReminderFormScreen> createState() => _ReminderFormScreenState();
}

class _ReminderFormScreenState extends State<ReminderFormScreen> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  String _kind = 'note';
  String _repeat = 'none';
  late DateTime _date;
  List<String> _times = [];
  bool _saving = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _title.text = e.title;
      _note.text = e.note;
      _kind = e.kind;
      _repeat = e.repeat;
      _date = e.date;
      _times = List.of(e.times);
    } else {
      _date = dateOnly(DateTime.now());
      // পরের পূর্ণ ঘণ্টাকে ডিফল্ট সময় ধরি।
      final n = DateTime.now().add(const Duration(hours: 1));
      _times = [hmString(n.hour, 0)];
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = dateOnly(DateTime.now());
    final first = _date.isBefore(today) ? _date : today;
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: first,
      lastDate: DateTime(today.year + 5),
    );
    if (d != null) setState(() => _date = dateOnly(d));
  }

  Future<void> _addTime() async {
    if (_times.length >= ReminderService.maxTimesPerReminder) {
      _snack('একটা রিমাইন্ডারে সর্বোচ্চ ${bn(ReminderService.maxTimesPerReminder)}টা সময় দেওয়া যায়');
      return;
    }
    final t = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
    if (t == null) return;
    final s = hmString(t.hour, t.minute);
    if (_times.contains(s)) return;
    setState(() => _times = ([..._times, s])..sort());
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _snack('হেডিং লেখো');
      return;
    }
    if (_times.isEmpty) {
      _snack('অন্তত একটা রিমাইন্ডার সময় দাও');
      return;
    }
    final now = DateTime.now();
    if (_repeat == 'none' && !(widget.existing?.done ?? false)) {
      final last = _times.last;
      final (h, m) = parseHm(last);
      final lastAt = DateTime(_date.year, _date.month, _date.day, h, m);
      if (!lastAt.isAfter(now)) {
        _snack('সব সময় পেরিয়ে গেছে — তারিখ বা সময় বদলাও');
        return;
      }
    }

    setState(() => _saving = true);
    final e = widget.existing;
    final r = Reminder(
      id: e?.id,
      title: title,
      note: _note.text.trim(),
      kind: _kind,
      date: _date,
      times: List.of(_times)..sort(),
      repeat: _repeat,
      done: e?.done ?? false,
      lastDoneDate: _repeat == 'none' ? null : e?.lastDoneDate,
      createdAt: e?.createdAt,
    );
    try {
      if (e == null) {
        r.id = await ReminderDB.insert(r);
      } else {
        await ReminderDB.update(r);
      }
      await ReminderService.rearm(r);
      ReminderService.changes.value++;
      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('সেভ করা যায়নি: $err');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        title: Text(_editing ? 'রিমাইন্ডার এডিট' : 'নতুন রিমাইন্ডার',
            style: AppTheme.title(size: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'হেডিং',
              hintText: 'যেমন: ফেসবুক পেজ, রহিমকে কল',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _note,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'নোট / ক্যাপশন',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          _label('ধরন'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in reminderKinds)
              ChoiceChip(
                label: Text('${k.emoji} ${k.label}'),
                selected: _kind == k.key,
                onSelected: (_) => setState(() => _kind = k.key),
              ),
          ]),
          const SizedBox(height: 18),
          _label(_repeat == 'none' ? 'তারিখ' : 'শুরুর তারিখ'),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.bg2,
                border: Border.all(color: AppTheme.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(Icons.event, color: AppTheme.accent, size: 20),
                const SizedBox(width: 10),
                Text('${formatDateBn(_date)} • ${bn(_date.day)}/${bn(_date.month)}/${bn(_date.year)}',
                    style: AppTheme.body(size: 14)),
                const Spacer(),
                Icon(Icons.edit_calendar, size: 18, color: AppTheme.textMuted),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          _label('রিপিট'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in reminderRepeats.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _repeat == e.key,
                onSelected: (_) => setState(() => _repeat = e.key),
              ),
          ]),
          const SizedBox(height: 18),
          _label('রিমাইন্ডার সময় (একাধিক দেওয়া যায়)'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in _times)
              InputChip(
                avatar: const Icon(Icons.alarm, size: 16),
                label: Text(formatTimeBn(t)),
                onDeleted: () => setState(() => _times.remove(t)),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('সময় যোগ করো'),
              onPressed: _addTime,
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            'নোটিফিকেশনে Done / Not yet বাটন থাকবে। Done দিলে আর মনে করাবে না, '
            'Not yet দিলে ${bn(ReminderService.snoozeMinutes)} মিনিট পর আবার মনে করাবে।',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: Text(_editing ? 'আপডেট করো' : 'সেভ করো'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary)),
      );
}
