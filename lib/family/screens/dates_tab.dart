import 'package:flutter/material.dart';
import '../../reminder/models/reminder.dart' show bn, formatDateBn;
import '../../widgets/app_theme.dart';
import '../models/family_models.dart';
import '../services/family_service.dart';
import 'family_ui.dart';

class DatesTab extends StatefulWidget {
  const DatesTab({super.key});
  @override State<DatesTab> createState() => _DatesTabState();
}

class _DatesTabState extends State<DatesTab> {
  List<UpcomingItem> _list = [];
  bool _loading = true;

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
    final l = await FamilyService.upcoming();
    if (mounted) setState(() { _list = l; _loading = false; });
  }

  Color _color(int d) => d <= 1 ? AppTheme.red : (d <= 7 ? AppTheme.yellow : AppTheme.textSecondary);

  String _label(int d) => d == 0 ? 'আজ' : (d == 1 ? 'কাল' : '${bn(d)} দিন পরে');

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 40), children: [
      fHeader('জন্মদিন (সদস্য ট্যাব থেকে নিজে আসে), বিবাহবার্ষিকী আর নিজের বানানো দিন। '
          'প্রতি বছর ৭ দিন আগে, ১ দিন আগে আর ওই দিন সকাল ৮টায় রিমাইন্ডার।',
          'তারিখ', () => _sheet()),
      if (_list.isEmpty)
        fEmpty(Icons.event_outlined,
            'কোনো তারিখ নেই।\nসদস্যের জন্মতারিখ দিলে বা এখানে তারিখ যোগ করলে এখানে আসবে।')
      else
        for (final it in _list)
          fCard(
            onTap: it.date == null ? null : () => _sheet(existing: it.date),
            child: Row(children: [
              Text(it.emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(it.title,
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(it.sub, style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5, height: 1.35)),
                  const SizedBox(height: 2),
                  Text(formatDateBn(it.next), style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                fChip(_label(it.daysLeft), _color(it.daysLeft)),
                if (it.date != null)
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, size: 20, color: AppTheme.textMuted),
                    onSelected: (v) async {
                      if (v == 'edit') _sheet(existing: it.date);
                      if (v == 'delete') {
                        if (await fConfirm(context, 'মুছে ফেলবে?', '"${it.title}" ও এর রিমাইন্ডার মুছে যাবে।')) {
                          await FamilyService.deleteDate(it.date!);
                        }
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('✏️ এডিট')),
                      PopupMenuItem(value: 'delete', child: Text('🗑️ মুছে ফেলো')),
                    ],
                  ),
              ]),
            ]),
          ),
    ]);
  }

  Future<void> _sheet({FamilyDate? existing}) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final note = TextEditingController(text: existing?.note ?? '');
    String kind = existing?.kind ?? 'anniversary';
    DateTime? date = existing?.date;
    String? error;

    await fSheet(context, existing == null ? 'নতুন তারিখ' : 'তারিখ এডিট', (ctx, setS) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, children: [
          ChoiceChip(
            label: const Text('💍 বিবাহবার্ষিকী'),
            selected: kind == 'anniversary',
            onSelected: (_) => setS(() => kind = 'anniversary'),
          ),
          ChoiceChip(
            label: const Text('📌 নিজের বানানো'),
            selected: kind == 'other',
            onSelected: (_) => setS(() => kind = 'other'),
          ),
        ]),
        const SizedBox(height: 14),
        TextField(
          controller: title,
          decoration: InputDecoration(
              labelText: kind == 'anniversary' ? 'নাম * (যেমন: আমাদের বিয়ের দিন)' : 'নাম * (যেমন: বাবার মৃত্যুবার্ষিকী)'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.event, size: 18),
          label: Text(date == null ? 'মূল তারিখ বাছো *' : formatDateBn(date!)),
          onPressed: () async {
            final d = await fPickDate(ctx, date);
            if (d != null) setS(() => date = d);
          },
        ),
        const SizedBox(height: 10),
        TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'নোট')),
        fError(error),
        const SizedBox(height: 16),
        fSaveButton(() async {
          if (title.text.trim().isEmpty) {
            setS(() => error = 'নাম দাও');
            return;
          }
          if (date == null) {
            setS(() => error = 'মূল তারিখ বাছো');
            return;
          }
          final d = existing ?? FamilyDate(title: '', date: date!);
          d.title = title.text.trim();
          d.kind = kind;
          d.date = date!;
          d.note = note.text.trim();
          await FamilyService.saveDate(d);
          if (ctx.mounted) Navigator.pop(ctx);
        }),
      ]);
    });
  }
}
