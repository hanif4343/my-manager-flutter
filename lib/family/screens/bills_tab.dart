import 'package:flutter/material.dart';
import '../../cashbook/models/cashbook_account.dart';
import '../../reminder/models/reminder.dart' show bn;
import '../../widgets/app_theme.dart';
import '../models/family_models.dart';
import '../services/family_service.dart';
import 'family_ui.dart';

/// "পরিশোধ করেছি" ডায়ালগ — ওভারভিউ ট্যাব থেকেও ব্যবহার হয়।
Future<void> payBillDialog(BuildContext context, FamilyBill b) async {
  final accounts = await FamilyService.cashbookAccounts();
  if (accounts.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ক্যাশবুকে কোনো হিসাব (একাউন্ট) নেই — আগে ক্যাশবুক খুলে একটা বানাও')));
    }
    return;
  }
  if (!context.mounted) return;
  final amountCtrl = TextEditingController(text: b.amount > 0 ? '${b.amount}' : '');
  int accountId = accounts.any((a) => a.id == FamilyService.lastCashbookAccountId)
      ? FamilyService.lastCashbookAccountId!
      : accounts.first.id!;
  String? error;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      return AlertDialog(
        backgroundColor: AppTheme.bg2,
        title: Text('${b.emoji} ${b.title} — পরিশোধ'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: amountCtrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'কত টাকা দিলে', prefixText: '৳ '),
          ),
          if (accounts.length > 1) ...[
            const SizedBox(height: 14),
            Text('কোন হিসাব থেকে', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final CashbookAccount a in accounts)
                ChoiceChip(
                  label: Text('${a.icon} ${a.name}'),
                  selected: accountId == a.id,
                  onSelected: (_) => setD(() => accountId = a.id!),
                ),
            ]),
          ],
          const SizedBox(height: 10),
          Text('ক্যাশবুকে "বিল" ক্যাটাগরিতে খরচ হিসেবে যোগ হবে।',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          fError(error),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
          TextButton(
            onPressed: () {
              final v = int.tryParse(fAsciiDigits(amountCtrl.text.trim())) ?? 0;
              if (v <= 0) {
                setD(() => error = 'সঠিক টাকার অংক দাও');
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: Text('সংরক্ষণ', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      );
    }),
  );
  if (ok == true) {
    final v = int.tryParse(fAsciiDigits(amountCtrl.text.trim())) ?? 0;
    try {
      await FamilyService.payBill(b, amount: v, accountId: accountId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ ${b.title}: ৳${bn(v)} ক্যাশবুকে খরচ যোগ হয়েছে')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ব্যর্থ: $e')));
      }
    }
  }
}

/// বিলের অবস্থা চিপ: (লেখা, রঙ)
(String, Color) billStatus(FamilyBill b) {
  if (b.paidThisMonth) return ('✓ এ মাসে পরিশোধিত', AppTheme.green);
  final d = b.daysToDue;
  if (d < 0) return ('${bn(-d)} দিন বকেয়া', AppTheme.red);
  if (d == 0) return ('আজই শেষ দিন', AppTheme.red);
  if (d <= 3) return ('আর ${bn(d)} দিন', AppTheme.yellow);
  return ('আর ${bn(d)} দিন', AppTheme.textSecondary);
}

class BillsTab extends StatefulWidget {
  const BillsTab({super.key});
  @override State<BillsTab> createState() => _BillsTabState();
}

class _BillsTabState extends State<BillsTab> {
  List<FamilyBill> _list = [];
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
    final l = await FamilyService.bills();
    if (mounted) setState(() { _list = l; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
    final total = _list.fold<int>(0, (s, b) => s + b.amount);
    final remaining = _list.where((b) => !b.paidThisMonth).fold<int>(0, (s, b) => s + b.amount);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 40), children: [
      fHeader('ভাড়া, বিদ্যুৎ, গ্যাস, ইন্টারনেট, ফি, কিস্তি — প্রতি মাসের ডিউ ডেটে নিজে মনে করাবে।',
          'বিল', () => _sheet()),
      if (_list.isNotEmpty)
        fCard(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('মাসিক মোট', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                const SizedBox(height: 4),
                Text('৳${bn(total)}',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('এ মাসে বাকি', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                const SizedBox(height: 4),
                Text('৳${bn(remaining)}',
                    style: TextStyle(
                        color: remaining > 0 ? AppTheme.red : AppTheme.green,
                        fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
            ),
          ]),
        ),
      if (_list.isEmpty)
        fEmpty(Icons.receipt_long_outlined, 'কোনো নিয়মিত বিল নেই।\nউপরের "বিল" বাটনে ট্যাপ করে যোগ করো।')
      else
        for (final b in _list) _billCard(b),
    ]);
  }

  Widget _billCard(FamilyBill b) {
    final (label, color) = billStatus(b);
    return fCard(
      onTap: () => _sheet(existing: b),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(b.emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.title,
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('প্রতি মাসের ${bn(b.dueDay)} তারিখ${b.amount > 0 ? ' · ৳${bn(b.amount)}' : ''}',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
            ]),
          ),
          fChip(label, color),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 20, color: AppTheme.textMuted),
            onSelected: (v) async {
              if (v == 'edit') _sheet(existing: b);
              if (v == 'unpaid') await FamilyService.markUnpaid(b);
              if (v == 'delete') {
                if (await fConfirm(context, 'মুছে ফেলবে?', '"${b.title}" ও এর রিমাইন্ডার মুছে যাবে।')) {
                  await FamilyService.deleteBill(b);
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('✏️ এডিট')),
              if (b.paidThisMonth) const PopupMenuItem(value: 'unpaid', child: Text('↩️ অপরিশোধিত করো')),
              const PopupMenuItem(value: 'delete', child: Text('🗑️ মুছে ফেলো')),
            ],
          ),
        ]),
        if (!b.paidThisMonth) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('পরিশোধ করেছি'),
              onPressed: () => payBillDialog(context, b),
            ),
          ),
        ],
      ]),
    );
  }

  Future<void> _sheet({FamilyBill? existing}) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final amount = TextEditingController(text: (existing?.amount ?? 0) > 0 ? '${existing!.amount}' : '');
    final dueDay = TextEditingController(text: '${existing?.dueDay ?? 10}');
    final note = TextEditingController(text: existing?.note ?? '');
    String type = existing?.type ?? 'rent';
    String? error;

    await fSheet(context, existing == null ? 'নতুন বিল' : 'বিল এডিট', (ctx, setS) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final e in billTypes.entries)
            ChoiceChip(
              label: Text('${e.value.$1} ${e.value.$2}', style: const TextStyle(fontSize: 12.5)),
              selected: type == e.key,
              onSelected: (_) => setS(() {
                type = e.key;
                if (title.text.trim().isEmpty || billTypes.values.any((v) => v.$2 == title.text.trim())) {
                  title.text = e.value.$2;
                }
              }),
            ),
        ]),
        const SizedBox(height: 14),
        TextField(controller: title, decoration: const InputDecoration(labelText: 'নাম *')),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'আনুমানিক টাকা', prefixText: '৳ '),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: dueDay,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'মাসের কত তারিখ (১-২৮)'),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text('৩০/৩১ তারিখের বিল হলে ২৮ দাও — তাহলে সব মাসে মিলবে।',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
        const SizedBox(height: 10),
        TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'নোট (মিটার নম্বর, একাউন্ট নম্বর...)')),
        fError(error),
        const SizedBox(height: 16),
        fSaveButton(() async {
          if (title.text.trim().isEmpty) {
            setS(() => error = 'নাম দাও');
            return;
          }
          final day = int.tryParse(fAsciiDigits(dueDay.text.trim())) ?? 0;
          if (day < 1 || day > 28) {
            setS(() => error = 'তারিখ ১ থেকে ২৮-এর মধ্যে দাও');
            return;
          }
          final b = existing ?? FamilyBill(title: '');
          b.title = title.text.trim();
          b.type = type;
          b.amount = int.tryParse(fAsciiDigits(amount.text.trim())) ?? 0;
          b.dueDay = day;
          b.note = note.text.trim();
          await FamilyService.saveBill(b);
          if (ctx.mounted) Navigator.pop(ctx);
        }),
      ]);
    });
  }
}
