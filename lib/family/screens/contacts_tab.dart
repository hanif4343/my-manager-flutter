import 'package:flutter/material.dart';
import '../../jobs/services/app_launcher.dart';
import '../../widgets/app_theme.dart';
import '../models/family_models.dart';
import '../services/family_service.dart';
import 'family_ui.dart';

Future<void> dialNumber(BuildContext context, String phone) async {
  final ok = await AppLauncher.dial(phone);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ডায়ালার খোলা যায়নি')));
  }
}

class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key});
  @override State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  List<FamilyContact> _list = [];
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
    final l = await FamilyService.contacts();
    if (mounted) setState(() { _list = l; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 40), children: [
      fHeader('জরুরি নম্বর, পরিচিত ডাক্তার, রক্তদাতা — দরকারের সময় এক ট্যাপে কল।',
          'নম্বর', () => _sheet()),
      if (_list.isEmpty)
        fEmpty(Icons.contact_phone_outlined, 'কোনো জরুরি তথ্য নেই।\nউপরের "নম্বর" বাটনে ট্যাপ করে যোগ করো।')
      else
        for (final kind in contactKinds.keys)
          if (_list.any((c) => c.kind == kind)) ...[
            fSection('${contactKinds[kind]!.$1} ${contactKinds[kind]!.$2}'),
            for (final c in _list.where((c) => c.kind == kind)) _contactCard(c),
          ],
    ]);
  }

  Widget _contactCard(FamilyContact c) {
    return fCard(
      onTap: () => _sheet(existing: c),
      child: Row(children: [
        fAvatar(c.name),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(c.phone, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.5)),
            if (c.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(c.note,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.35)),
              ),
          ]),
        ),
        IconButton.filled(
          style: IconButton.styleFrom(backgroundColor: AppTheme.green),
          icon: const Icon(Icons.call_rounded, color: Colors.white),
          onPressed: () => dialNumber(context, c.phone),
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, size: 20, color: AppTheme.textMuted),
          onSelected: (v) async {
            if (v == 'edit') _sheet(existing: c);
            if (v == 'delete') {
              if (await fConfirm(context, 'মুছে ফেলবে?', '"${c.name}"')) {
                await FamilyService.deleteContact(c);
              }
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('✏️ এডিট')),
            PopupMenuItem(value: 'delete', child: Text('🗑️ মুছে ফেলো')),
          ],
        ),
      ]),
    );
  }

  Future<void> _sheet({FamilyContact? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final phone = TextEditingController(text: existing?.phone ?? '');
    final note = TextEditingController(text: existing?.note ?? '');
    String kind = existing?.kind ?? 'emergency';
    String? error;

    await fSheet(context, existing == null ? 'নতুন জরুরি তথ্য' : 'তথ্য এডিট', (ctx, setS) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final e in contactKinds.entries)
            ChoiceChip(
              label: Text('${e.value.$1} ${e.value.$2}', style: const TextStyle(fontSize: 12.5)),
              selected: kind == e.key,
              onSelected: (_) => setS(() => kind = e.key),
            ),
        ]),
        const SizedBox(height: 14),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'নাম * (যেমন: ডাঃ রহমান, ৯৯৯)')),
        const SizedBox(height: 10),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'ফোন নম্বর *'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: note,
          maxLines: 2,
          decoration: InputDecoration(
              labelText: kind == 'doctor'
                  ? 'নোট (বিশেষজ্ঞ, চেম্বার, সময়)'
                  : (kind == 'blood' ? 'নোট (রক্তের গ্রুপ, এলাকা)' : 'নোট')),
        ),
        fError(error),
        const SizedBox(height: 16),
        fSaveButton(() async {
          if (name.text.trim().isEmpty) {
            setS(() => error = 'নাম দাও');
            return;
          }
          final p = fAsciiDigits(phone.text.trim());
          if (p.isEmpty) {
            setS(() => error = 'ফোন নম্বর দাও');
            return;
          }
          final c = existing ?? FamilyContact(name: '');
          c.name = name.text.trim();
          c.kind = kind;
          c.phone = p;
          c.note = note.text.trim();
          await FamilyService.saveContact(c);
          if (ctx.mounted) Navigator.pop(ctx);
        }),
      ]);
    });
  }
}
