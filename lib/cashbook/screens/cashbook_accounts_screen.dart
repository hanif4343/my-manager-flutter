import 'package:flutter/material.dart';
import '../db/cashbook_db.dart';
import '../models/cashbook_account.dart';
import '../../widgets/app_theme.dart';

String _fmt(double v) {
  final n = v.round();
  final neg = n < 0;
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final posFromEnd = s.length - i;
    if (i != 0 && posFromEnd % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '${neg ? '−' : ''}৳$buf';
}

/// All accounts/ledgers at a glance with their running balance — handy
/// once you've got dozens of month-ledgers like this person's imported
/// history. Tapping a row switches to it; the ⋮ menu renames or deletes.
class CashbookAccountsScreen extends StatefulWidget {
  final int? activeAccountId;
  const CashbookAccountsScreen({super.key, this.activeAccountId});

  @override
  State<CashbookAccountsScreen> createState() => _CashbookAccountsScreenState();
}

class _CashbookAccountsScreenState extends State<CashbookAccountsScreen> {
  List<CashbookAccount> _accounts = [];
  Map<int, double> _balances = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await CashbookDB.getAccounts();
    final balances = await CashbookDB.getAllBalances();
    if (!mounted) return;
    setState(() { _accounts = accounts; _balances = balances; _loading = false; });
  }

  Future<void> _rename(CashbookAccount a) async {
    final ctrl = TextEditingController(text: a.name);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('নাম পরিবর্তন'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('বাতিল')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('সেভ করো')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && a.id != null) {
      await CashbookDB.renameAccount(a.id!, name);
      _load();
    }
  }

  Future<void> _delete(CashbookAccount a) async {
    final entryCount = (await CashbookDB.getEntries(accountId: a.id)).length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('হিসাব মুছে ফেলবে?'),
        content: Text('"${a.name}" আর এর ভেতরের $entryCount টা এন্ট্রি স্থায়ীভাবে মুছে যাবে।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('বাতিল')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: Text('মুছে ফেলো', style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    if (confirm == true && a.id != null) {
      await CashbookDB.deleteAccount(a.id!);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalBalance = _balances.values.fold<double>(0, (s, v) => s + v);
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('সব হিসাব')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppTheme.bg2, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('সব হিসাব মিলিয়ে', style: AppTheme.caption()),
                    Text(_fmt(totalBalance), style: AppTheme.title(size: 18, color: totalBalance >= 0 ? AppTheme.green : AppTheme.red)),
                  ]),
                ),
                const SizedBox(height: 12),
                for (final a in _accounts)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: a.id == widget.activeAccountId ? AppTheme.accent.withOpacity(0.12) : AppTheme.bg2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: a.id == widget.activeAccountId ? AppTheme.accent : AppTheme.border),
                    ),
                    child: ListTile(
                      onTap: () => Navigator.pop(context, a.id),
                      leading: Text(a.icon, style: const TextStyle(fontSize: 20)),
                      title: Text(a.name, style: AppTheme.title(size: 13.5)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_fmt(_balances[a.id] ?? 0),
                            style: TextStyle(fontWeight: FontWeight.w700,
                                color: (_balances[a.id] ?? 0) >= 0 ? AppTheme.green : AppTheme.red)),
                        PopupMenuButton<String>(
                          onSelected: (v) { if (v == 'rename') _rename(a); if (v == 'delete') _delete(a); },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'rename', child: Text('✏️ নাম পরিবর্তন')),
                            PopupMenuItem(value: 'delete', child: Text('🗑️ মুছে ফেলো')),
                          ],
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
    );
  }
}
