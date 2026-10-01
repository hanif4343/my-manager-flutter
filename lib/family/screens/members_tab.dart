import 'package:flutter/material.dart';
import '../../jobs/services/app_launcher.dart';
import '../../reminder/models/reminder.dart' show bn, formatDateBn;
import '../../widgets/app_theme.dart';
import '../models/family_models.dart';
import '../services/family_service.dart';
import 'family_ui.dart';

class MembersTab extends StatefulWidget {
  final VoidCallback onOpenVault;
  const MembersTab({super.key, required this.onOpenVault});
  @override State<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<MembersTab> {
  List<FamilyMember> _list = [];
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
    final l = await FamilyService.members();
    if (mounted) setState(() { _list = l; _loading = false; });
  }

  Future<void> _call(String phone) async {
    final ok = await AppLauncher.dial(phone);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ডায়ালার খোলা যায়নি')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 40), children: [
      fHeader('পরিবারের সদস্যদের তথ্য। জন্মতারিখ দিলে জন্মদিনের রিমাইন্ডার নিজে বসে যাবে।',
          'সদস্য', () => _sheet()),
      fCard(
        onTap: () {
          Navigator.pop(context);
          widget.onOpenVault();
        },
        child: Row(children: [
          Icon(Icons.lock_outline_rounded, color: AppTheme.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text('NID বা জন্মনিবন্ধনের নম্বরের মতো স্পর্শকাতর তথ্য এখানে রাখা হয় না — ভল্টে নিরাপদে রাখো →',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.4)),
          ),
        ]),
      ),
      if (_list.isEmpty)
        fEmpty(Icons.family_restroom, 'এখনো কোনো সদস্য নেই।\nউপরের "সদস্য" বাটনে ট্যাপ করে শুরু করো।')
      else
        for (final m in _list) _memberCard(m),
    ]);
  }

  Widget _memberCard(FamilyMember m) {
    final age = m.ageLabel;
    final bdayDays = m.birthDate == null ? null : daysUntil(nextOccurrence(m.birthDate!));
    return fCard(
      onTap: () => _sheet(existing: m),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        fAvatar(m.name),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(m.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              fChip(m.relation, AppTheme.accent),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              if (age != null) fChip('বয়স $age', AppTheme.textSecondary),
              if (m.blood.isNotEmpty) fChip('🩸 ${m.blood}', AppTheme.red),
              if (bdayDays != null && bdayDays <= 30)
                fChip(bdayDays == 0 ? '🎂 আজ জন্মদিন!' : '🎂 ${bn(bdayDays)} দিন পরে', AppTheme.yellow),
            ]),
            if (m.birthDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('জন্ম: ${formatDateBn(m.birthDate!)}',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              ),
            if (m.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(m.note,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5, height: 1.35)),
              ),
          ]),
        ),
        Column(children: [
          if (m.phone.isNotEmpty)
            IconButton(
              icon: Icon(Icons.call_rounded, color: AppTheme.green),
              onPressed: () => _call(m.phone),
              tooltip: m.phone,
            ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 20, color: AppTheme.textMuted),
            onSelected: (v) async {
              if (v == 'edit') _sheet(existing: m);
              if (v == 'delete') {
                if (await fConfirm(context, 'মুছে ফেলবে?', '"${m.name}" ও তার জন্মদিনের রিমাইন্ডার মুছে যাবে।')) {
                  await FamilyService.deleteMember(m);
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
    );
  }

  Future<void> _sheet({FamilyMember? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final phone = TextEditingController(text: existing?.phone ?? '');
    final note = TextEditingController(text: existing?.note ?? '');
    String relation = existing?.relation ?? memberRelations.first;
    String blood = existing?.blood ?? '';
    DateTime? birth = existing?.birthDate;
    String? error;

    await fSheet(context, existing == null ? 'নতুন সদস্য' : 'সদস্যের তথ্য', (ctx, setS) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'নাম *')),
        const SizedBox(height: 14),
        Text('সম্পর্ক', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final r in memberRelations)
            ChoiceChip(
              label: Text(r, style: const TextStyle(fontSize: 12.5)),
              selected: relation == r,
              onSelected: (_) => setS(() => relation = r),
            ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.cake_outlined, size: 18),
              label: Text(birth == null ? 'জন্মতারিখ' : formatDateBn(birth!), overflow: TextOverflow.ellipsis),
              onPressed: () async {
                final d = await fPickDate(ctx, birth, last: DateTime.now());
                if (d != null) setS(() => birth = d);
              },
            ),
          ),
          if (birth != null)
            IconButton(
              icon: Icon(Icons.close_rounded, color: AppTheme.textMuted),
              onPressed: () => setS(() => birth = null),
            ),
        ]),
        const SizedBox(height: 14),
        Text('রক্তের গ্রুপ', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final b in bloodGroups)
            ChoiceChip(
              label: Text(b, style: const TextStyle(fontSize: 12.5)),
              selected: blood == b,
              onSelected: (_) => setS(() => blood = blood == b ? '' : b),
            ),
        ]),
        const SizedBox(height: 14),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'ফোন'),
        ),
        const SizedBox(height: 10),
        TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'নোট')),
        fError(error),
        const SizedBox(height: 16),
        fSaveButton(() async {
          if (name.text.trim().isEmpty) {
            setS(() => error = 'নাম দাও');
            return;
          }
          final m = existing ?? FamilyMember(name: '');
          m.name = name.text.trim();
          m.relation = relation;
          m.birthDate = birth;
          m.blood = blood;
          m.phone = fAsciiDigits(phone.text.trim());
          m.note = note.text.trim();
          await FamilyService.saveMember(m);
          if (ctx.mounted) Navigator.pop(ctx);
        }),
      ]);
    });
  }
}
