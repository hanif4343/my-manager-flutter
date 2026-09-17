import 'package:flutter/material.dart';
import '../db/cashbook_db.dart';
import '../models/cashbook_debt.dart';
import '../widgets/bangla_digit_input_formatter.dart';
import '../../widgets/app_theme.dart';

/// Record a new দেনা-পাওনা (money someone owes the user, or the user owes
/// someone). Pops `true` when a record is saved.
class CashbookDebtSheet extends StatefulWidget {
  const CashbookDebtSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CashbookDebtSheet(),
    );
  }

  @override
  State<CashbookDebtSheet> createState() => _CashbookDebtSheetState();
}

class _CashbookDebtSheetState extends State<CashbookDebtSheet> {
  String _type = 'lend';
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final amount = BanglaDigitInputFormatter.parse(_amountCtrl.text);
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('নাম লেখো')));
      return;
    }
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('সঠিক পরিমাণ লেখো')));
      return;
    }
    await CashbookDB.insertDebt(CashbookDebt(
      name: name, type: _type, amount: amount, note: _noteCtrl.text.trim(),
      date: CashbookDB.todayIso(), createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            color: AppTheme.bg2,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 38, height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(99)))),
            Text('নতুন দেনা-পাওনা', style: AppTheme.title(size: 17)),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(color: AppTheme.bg3, borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.all(4),
              child: Row(children: [
                _typeOpt('আমি পাবো', 'lend', AppTheme.green),
                _typeOpt('আমি দেনা', 'borrow', AppTheme.red),
              ]),
            ),
            const SizedBox(height: 16),
            Text('নাম', style: AppTheme.caption()),
            const SizedBox(height: 6),
            TextField(controller: _nameCtrl, decoration: InputDecoration(
              hintText: 'কার সাথে হিসাব?', filled: true, fillColor: AppTheme.bg3,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            )),
            const SizedBox(height: 14),
            Text('পরিমাণ (৳)', style: AppTheme.caption()),
            const SizedBox(height: 6),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [BanglaDigitInputFormatter()],
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: '০', filled: true, fillColor: AppTheme.bg3,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            Text('নোট', style: AppTheme.caption()),
            const SizedBox(height: 6),
            TextField(controller: _noteCtrl, decoration: InputDecoration(
              hintText: 'কারণ (ঐচ্ছিক)', filled: true, fillColor: AppTheme.bg3,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            )),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('বাতিল'))),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.white),
                child: const Text('সেভ করো'),
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _typeOpt(String label, String value, Color color) {
    final selected = _type == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: selected ? color : Colors.transparent, borderRadius: BorderRadius.circular(9)),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: selected ? Colors.white : AppTheme.textSecondary)),
        ),
      ),
    );
  }
}
