import 'dart:async';
import 'package:flutter/material.dart';
import '../db/cashbook_db.dart';
import '../models/cashbook_account.dart';
import '../models/cashbook_entry.dart';
import '../models/cashbook_budget.dart';
import '../models/cashbook_debt.dart';
import '../services/cashbook_service.dart';
import '../services/cashbook_backup_service.dart';
import '../services/cashbook_notification_service.dart';
import '../services/cashbook_export_service.dart';
import '../widgets/bangla_digit_input_formatter.dart';
import 'cashbook_entry_sheet.dart';
import 'cashbook_debt_sheet.dart';
import '../../widgets/app_theme.dart';

const _monthNames = ['জানুয়ারি','ফেব্রুয়ারি','মার্চ','এপ্রিল','মে','জুন',
  'জুলাই','আগস্ট','সেপ্টেম্বর','অক্টোবর','নভেম্বর','ডিসেম্বর'];
String _monthLabel(String isoDate) {
  final d = DateTime.parse(isoDate);
  return '${_monthNames[d.month - 1]} ${d.year}';
}
String _fmt(double v) {
  final n = v.round();
  final s = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final posFromEnd = s.length - i;
    if (i != 0 && posFromEnd % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '৳$buf';
}

class CashbookScreen extends StatefulWidget {
  const CashbookScreen({super.key});
  @override
  State<CashbookScreen> createState() => _CashbookScreenState();
}

class _CashbookScreenState extends State<CashbookScreen> {
  int _tab = 0; // 0 entries, 1 budget, 2 report, 3 debts
  List<CashbookAccount> _accounts = [];
  List<CashbookEntry> _entries = [];
  List<CashbookBudget> _budgets = [];
  List<CashbookDebt> _debts = [];
  int? _activeAccountId;
  String _filter = 'all';
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await CashbookDB.processRecurring();
      final accounts = await CashbookDB.getAccounts();
      final entries = await CashbookDB.getEntries();
      final budgets = await CashbookDB.getBudgets();
      final debts = await CashbookDB.getDebts();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _entries = entries;
        _budgets = budgets;
        _debts = debts;
        _activeAccountId ??= accounts.isNotEmpty ? accounts.first.id : null;
        _loading = false;
        _loadError = null;
      });
      // The 8pm reminder and the always-on backup both re-check
      // themselves every time the Cashbook is opened — fire-and-forget,
      // never allowed to block the UI or the screen from showing.
      unawaited(CashbookNotificationService.refresh()
          .catchError((e) => debugPrint('Cashbook reminder refresh failed: $e')));
      unawaited(CashbookBackupService.backupSilently()
          .catchError((e) => debugPrint('Cashbook backup failed: $e')));
    } catch (e, st) {
      debugPrint('Cashbook load failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _afterMutation() async {
    await _load();
    CashbookBackupService.backupSilently();
  }

  // ── account ───────────────────────────────────────────
  Future<void> _addAccount() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('নতুন হিসাব'),
        content: TextField(controller: ctrl, autofocus: true,
            decoration: const InputDecoration(hintText: 'যেমন: সঞ্চয়, ক্রেডিট কার্ড')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('বাতিল')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('যোগ করো')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      final id = await CashbookDB.insertAccount(CashbookAccount(
        name: name, icon: '👛', sortOrder: _accounts.length,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      _activeAccountId = id;
      await _afterMutation();
    }
  }

  // ── entries tab helpers ───────────────────────────────
  List<CashbookEntry> get _visibleEntries {
    final q = _searchCtrl.text.trim().toLowerCase();
    final isGlobalSearch = _searchOpen && q.isNotEmpty;
    var list = isGlobalSearch
        ? _entries
        : _entries.where((e) => e.accountId == _activeAccountId).toList();
    if (!isGlobalSearch && _filter != 'all') {
      list = list.where((e) => e.type == _filter).toList();
    }
    if (isGlobalSearch) {
      list = list.where((e) {
        final cat = CashbookService.categoryById(e.category);
        return e.note.toLowerCase().contains(q) ||
            cat.name.toLowerCase().contains(q) ||
            e.amount.toString().contains(q);
      }).toList();
    }
    list.sort((a, b) {
      final d = b.date.compareTo(a.date);
      return d != 0 ? d : (b.id ?? 0).compareTo(a.id ?? 0);
    });
    return list;
  }

  bool get _isGlobalSearch => _searchOpen && _searchCtrl.text.trim().isNotEmpty;

  Future<void> _openEntrySheet({CashbookEntry? entry}) async {
    if (_activeAccountId == null) return;
    final changed = await CashbookEntrySheet.show(context,
        accountId: entry?.accountId ?? _activeAccountId!, entry: entry);
    if (changed == true) await _afterMutation();
  }

  Future<void> _openDebtSheet() async {
    final changed = await CashbookDebtSheet.show(context);
    if (changed == true) await _afterMutation();
  }

  Future<void> _exportPdf() async {
    await CashbookExportService.exportPdf(
        title: 'ক্যাশবুক রিপোর্ট', entries: _entries, accounts: _accounts);
  }

  Future<void> _exportExcel() async {
    await CashbookExportService.exportExcel(
        title: 'ক্যাশবুক রিপোর্ট', entries: _entries, accounts: _accounts);
  }

  // ── build ─────────────────────────────────────────────
  static const _titles = ['ক্যাশবুক', 'বাজেট', 'রিপোর্ট', 'দেনা-পাওনা'];

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(title: const Text('ক্যাশবুক')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(title: const Text('ক্যাশবুক')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.error_outline, size: 40, color: AppTheme.red),
              const SizedBox(height: 12),
              Text('ক্যাশবুক লোড করতে সমস্যা হয়েছে', style: AppTheme.title(size: 15)),
              const SizedBox(height: 8),
              Text(_loadError!, style: AppTheme.caption(), textAlign: TextAlign.center),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () {
                  setState(() { _loading = true; _loadError = null; });
                  _load();
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.white),
                child: const Text('আবার চেষ্টা করো'),
              ),
            ]),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          if (_tab == 0)
            IconButton(
              icon: Icon(_searchOpen ? Icons.search_off : Icons.search),
              onPressed: () => setState(() {
                _searchOpen = !_searchOpen;
                if (!_searchOpen) _searchCtrl.clear();
              }),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') _exportPdf();
              if (v == 'excel') _exportExcel();
              if (v == 'account') _addAccount();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'pdf', child: Text('📄 PDF এক্সপোর্ট')),
              const PopupMenuItem(value: 'excel', child: Text('📊 Excel এক্সপোর্ট')),
              const PopupMenuItem(value: 'account', child: Text('➕ নতুন হিসাব যোগ')),
            ],
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: [
        _buildEntriesTab(),
        _buildBudgetTab(),
        _buildReportTab(),
        _buildDebtsTab(),
      ]),
      floatingActionButton: _tab == 2 ? null : FloatingActionButton(
        backgroundColor: AppTheme.accent,
        onPressed: () {
          if (_tab == 0) _openEntrySheet();
          if (_tab == 1) _addOrEditBudget();
          if (_tab == 3) _openDebtSheet();
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: AppTheme.bg2,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'এন্ট্রি'),
          NavigationDestination(icon: Icon(Icons.track_changes_outlined), selectedIcon: Icon(Icons.track_changes), label: 'বাজেট'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), selectedIcon: Icon(Icons.pie_chart), label: 'রিপোর্ট'),
          NavigationDestination(icon: Icon(Icons.handshake_outlined), selectedIcon: Icon(Icons.handshake), label: 'দেনা-পাওনা'),
        ],
      ),
    );
  }

  // ── ENTRIES TAB ───────────────────────────────────────
  Widget _buildEntriesTab() {
    final activeAccount = _accounts.firstWhere(
        (a) => a.id == _activeAccountId,
        orElse: () => CashbookAccount(name: '—', icon: '👛', createdAt: 0));
    final ownEntries = _entries.where((e) => e.accountId == _activeAccountId).toList();
    final balance = ownEntries.fold<double>(0, (s, e) => s + (e.type == 'in' ? e.amount : -e.amount));
    final thisMonth = CashbookDB.todayIso().substring(0, 7);
    final monthOwn = ownEntries.where((e) => e.date.startsWith(thisMonth));
    final inSum = monthOwn.where((e) => e.type == 'in').fold<double>(0, (s, e) => s + e.amount);
    final outSum = monthOwn.where((e) => e.type == 'out').fold<double>(0, (s, e) => s + e.amount);

    final visible = _visibleEntries;

    return Column(children: [
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            ..._accounts.map((a) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${a.icon} ${a.name}'),
                selected: a.id == _activeAccountId,
                onSelected: (_) => setState(() => _activeAccountId = a.id),
                selectedColor: AppTheme.accent,
                backgroundColor: AppTheme.bg2,
                labelStyle: TextStyle(
                    color: a.id == _activeAccountId ? Colors.white : AppTheme.textSecondary,
                    fontWeight: FontWeight.w600, fontSize: 12.5),
                side: BorderSide(color: AppTheme.border),
              ),
            )),
            ActionChip(
              label: const Text('+ নতুন হিসাব'),
              onPressed: _addAccount,
              backgroundColor: Colors.transparent,
              side: BorderSide(color: AppTheme.border),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.bg2, borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${activeAccount.name} — মোট ব্যালেন্স', style: AppTheme.caption()),
            const SizedBox(height: 4),
            Text(_fmt(balance), style: AppTheme.display(size: 28, color: AppTheme.green)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _balancePill('এই মাসে জমা', _fmt(inSum), AppTheme.textPrimary)),
              const SizedBox(width: 10),
              Expanded(child: _balancePill('এই মাসে খরচ', _fmt(outSum), AppTheme.red)),
            ]),
          ]),
        ),
      ),
      if (_searchOpen)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'সব হিসাব থেকে নোট/ক্যাটাগরি/টাকা খুঁজুন...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true, fillColor: AppTheme.bg2,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text('গ্লোবাল সার্চ — সব হিসাব একসাথে', style: AppTheme.caption()),
            ),
          ]),
        ),
      if (!_isGlobalSearch)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Row(children: [
            _filterChip('সব', 'all'),
            const SizedBox(width: 8),
            _filterChip('জমা', 'in'),
            const SizedBox(width: 8),
            _filterChip('খরচ', 'out'),
          ]),
        ),
      Expanded(child: _buildEntriesList(visible)),
    ]);
  }

  Widget _balancePill(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppTheme.bg3, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppTheme.caption(size: 10.5)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: valueColor)),
      ]),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.textPrimary : AppTheme.bg2,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(label, style: TextStyle(
            fontWeight: FontWeight.w600, fontSize: 12.5,
            color: selected ? AppTheme.bg : AppTheme.textSecondary)),
      ),
    );
  }

  Widget _buildEntriesList(List<CashbookEntry> list) {
    if (list.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🗒️', style: TextStyle(fontSize: 34)),
          const SizedBox(height: 8),
          Text('এখনো কোনো এন্ট্রি নেই', style: AppTheme.body()),
        ]),
      );
    }
    final widgets = <Widget>[];
    String? lastMonth;
    for (final e in list) {
      final m = _monthLabel(e.date);
      if (m != lastMonth) {
        widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: Text(m, style: AppTheme.caption(weight: FontWeight.w700)),
        ));
        lastMonth = m;
      }
      final cat = CashbookService.categoryById(e.category);
      final accIcon = _accounts.firstWhere((a) => a.id == e.accountId,
          orElse: () => CashbookAccount(name: '', icon: '👛', createdAt: 0)).icon;
      widgets.add(ListTile(
        onTap: () => _openEntrySheet(entry: e),
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: AppTheme.bg2, borderRadius: BorderRadius.circular(11)),
          alignment: Alignment.center,
          child: Text(cat.icon, style: const TextStyle(fontSize: 17)),
        ),
        title: Text(e.note, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.title(size: 13.5)),
        subtitle: Text(
          [
            cat.name,
            if (_isGlobalSearch) '$accIcon ${_accounts.firstWhere((a) => a.id == e.accountId, orElse: () => CashbookAccount(name: "", icon: "", createdAt: 0)).name}',
            e.date,
            if (e.voucherImage != null) '📎',
            if (e.recurring) '🔁',
          ].join(' · '),
          style: AppTheme.caption(),
        ),
        trailing: Text(
          '${e.type == 'in' ? '+' : '−'} ${_fmt(e.amount)}',
          style: TextStyle(fontWeight: FontWeight.w700, color: e.type == 'in' ? AppTheme.green : AppTheme.red),
        ),
      ));
    }
    return ListView(padding: const EdgeInsets.only(bottom: 90), children: widgets);
  }

  // ── BUDGET TAB ────────────────────────────────────────
  Widget _buildBudgetTab() {
    return FutureBuilder<List<double>>(
      future: Future.wait(_budgets.map((b) => CashbookDB.spentThisMonth(b.category))),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final spentList = snap.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
          children: [
            Text('মাসিক বাজেট', style: AppTheme.title(size: 15)),
            const SizedBox(height: 4),
            Text('প্রতিটা ক্যাটাগরিতে এই মাসে কত খরচ হয়েছে, লিমিটের তুলনায়', style: AppTheme.caption()),
            const SizedBox(height: 14),
            if (_budgets.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Center(child: Text('এখনো কোনো বাজেট সেট করা হয়নি', style: AppTheme.body())),
              ),
            for (int i = 0; i < _budgets.length; i++)
              _budgetCard(_budgets[i], spentList[i]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addOrEditBudget,
              icon: const Icon(Icons.add),
              label: const Text('নতুন বাজেট লিমিট যোগ করো'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: BorderSide(color: AppTheme.border, style: BorderStyle.solid),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _budgetCard(CashbookBudget b, double spent) {
    final cat = CashbookService.categoryById(b.category);
    final pct = (spent / b.monthlyLimit).clamp(0, 1.2);
    final over = pct >= 1.0;
    final warn = pct >= 0.8 && !over;
    return GestureDetector(
      onTap: () => _addOrEditBudget(existing: b),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.bg2, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${cat.icon} ${cat.name}', style: AppTheme.title(size: 13.5)),
            Text('${_fmt(spent)} / ${_fmt(b.monthlyLimit)}', style: AppTheme.caption()),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: pct.toDouble().clamp(0, 1).toDouble(),
              minHeight: 8,
              backgroundColor: AppTheme.bg3,
              color: over ? AppTheme.red : (warn ? AppTheme.yellow : AppTheme.accent),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _addOrEditBudget({CashbookBudget? existing}) async {
    final categories = CashbookService.getCategories();
    String selectedCat = existing?.category ?? categories.first.id;
    final limitCtrl = TextEditingController(text: existing?.monthlyLimit.toStringAsFixed(0) ?? '1000');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) => AlertDialog(
        title: Text(existing == null ? 'নতুন বাজেট' : 'বাজেট এডিট করো'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (existing == null)
            DropdownButtonFormField<String>(
              value: selectedCat,
              items: categories.map((c) => DropdownMenuItem(value: c.id, child: Text('${c.icon} ${c.name}'))).toList(),
              onChanged: (v) => setSt(() => selectedCat = v ?? selectedCat),
            )
          else
            Align(alignment: Alignment.centerLeft,
                child: Text(CashbookService.categoryById(existing.category).name, style: AppTheme.title(size: 14))),
          const SizedBox(height: 12),
          TextField(
            controller: limitCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [BanglaDigitInputFormatter()],
            decoration: const InputDecoration(labelText: 'মাসিক লিমিট (৳)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('সেভ করো')),
        ],
      )),
    );
    if (result == true) {
      final limit = BanglaDigitInputFormatter.parse(limitCtrl.text);
      if (limit != null && limit > 0) {
        await CashbookDB.upsertBudget(CashbookBudget(category: selectedCat, monthlyLimit: limit));
        await _afterMutation();
      }
    }
  }

  // ── REPORT TAB ────────────────────────────────────────
  Widget _buildReportTab() {
    final thisMonth = CashbookDB.todayIso().substring(0, 7);
    final outsThisMonth = _entries.where((e) => e.type == 'out' && e.date.startsWith(thisMonth)).toList();
    final byCat = <String, double>{};
    for (final e in outsThisMonth) {
      byCat[e.category] = (byCat[e.category] ?? 0) + e.amount;
    }
    final rows = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final now = DateTime.now();
    final lastMonthDate = DateTime(now.year, now.month - 1, 1);
    final lastMonthKey = '${lastMonthDate.year}-${lastMonthDate.month.toString().padLeft(2, '0')}';
    final lastMonthTotal = _entries.where((e) => e.type == 'out' && e.date.startsWith(lastMonthKey))
        .fold<double>(0, (s, e) => s + e.amount);
    final thisMonthTotal = outsThisMonth.fold<double>(0, (s, e) => s + e.amount);

    final trend = <MapEntry<String, double>>[];
    for (int i = 5; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      final total = _entries.where((e) => e.type == 'out' && e.date.startsWith(key)).fold<double>(0, (s, e) => s + e.amount);
      trend.add(MapEntry(_monthNames[d.month - 1].substring(0, 3), total));
    }
    final maxTrend = trend.map((e) => e.value).fold<double>(1, (a, b) => a > b ? a : b);

    String insight;
    if (lastMonthTotal > 0) {
      final diff = ((thisMonthTotal - lastMonthTotal) / lastMonthTotal * 100).round();
      if (diff > 5) insight = '📈 গত মাসের চেয়ে এই মাসে খরচ $diff% বেশি হয়েছে।';
      else if (diff < -5) insight = '📉 গত মাসের চেয়ে এই মাসে খরচ ${diff.abs()}% কম হয়েছে — চমৎকার!';
      else insight = '📊 এই মাসের খরচ গত মাসের কাছাকাছিই আছে।';
    } else {
      insight = '📊 আরও কয়েক মাসের হিসাব হলে তুলনা দেখাতে পারবো।';
    }

    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 30), children: [
      Text('খরচের চিত্র (এই মাস)', style: AppTheme.title(size: 15)),
      const SizedBox(height: 14),
      if (rows.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text('এই মাসে এখনো কোনো খরচ নেই', style: AppTheme.body()))
      else
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(
            width: 120, height: 120,
            child: CustomPaint(painter: _PieChartPainter(rows.map((e) => e.value).toList())),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(rows.length, (i) {
                final cat = CashbookService.categoryById(rows[i].key);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(children: [
                    Container(width: 10, height: 10,
                        decoration: BoxDecoration(color: _chartColors[i % _chartColors.length], borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${cat.icon} ${cat.name}', style: AppTheme.body(size: 12.5))),
                    Text(_fmt(rows[i].value), style: AppTheme.title(size: 12.5)),
                  ]),
                );
              }),
            ),
          ),
        ]),
      const SizedBox(height: 22),
      Text('গত ৬ মাসের খরচ', style: AppTheme.title(size: 15)),
      const SizedBox(height: 14),
      SizedBox(
        height: 120,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end,
          children: trend.map((t) {
            final isNow = t == trend.last;
            final h = maxTrend == 0 ? 6.0 : (t.value / maxTrend * 96).clamp(6, 96).toDouble();
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Container(height: h, decoration: BoxDecoration(
                      color: isNow ? AppTheme.red : AppTheme.accent,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(5)))),
                  const SizedBox(height: 6),
                  Text(t.key, style: AppTheme.caption(size: 10)),
                ]),
              ),
            );
          }).toList(),
        ),
      ),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: AppTheme.bg3, borderRadius: BorderRadius.circular(14)),
        child: Text(insight, style: AppTheme.body(size: 12.5)),
      ),
    ]);
  }

  // ── DEBTS TAB ─────────────────────────────────────────
  Widget _buildDebtsTab() {
    if (_debts.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🤝', style: TextStyle(fontSize: 34)),
          const SizedBox(height: 8),
          Text('কোনো দেনা-পাওনা নেই', style: AppTheme.body()),
        ]),
      );
    }
    final sorted = [..._debts]..sort((a, b) {
      if (a.cleared != b.cleared) return a.cleared ? 1 : -1;
      return b.date.compareTo(a.date);
    });
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
      children: [
        Text('দেনা-পাওনা', style: AppTheme.title(size: 15)),
        const SizedBox(height: 4),
        Text('কাউকে ধার দিয়েছো বা কারো থেকে ধার নিয়েছো — সব একজায়গায়', style: AppTheme.caption()),
        const SizedBox(height: 14),
        for (final d in sorted) _debtCard(d),
      ],
    );
  }

  Widget _debtCard(CashbookDebt d) {
    return Opacity(
      opacity: d.cleared ? 0.45 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: AppTheme.bg2, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
        child: Row(children: [
          CircleAvatar(backgroundColor: AppTheme.bg3, foregroundColor: AppTheme.textPrimary,
              child: Text(d.name.isNotEmpty ? d.name[0] : '?')),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.name, style: AppTheme.title(size: 13.5)),
              Text([d.type == 'lend' ? 'আমি পাবো' : 'আমি দেনা', if (d.note.isNotEmpty) d.note].join(' · '),
                  style: AppTheme.caption(), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Text(_fmt(d.amount), style: TextStyle(fontWeight: FontWeight.w700, color: d.type == 'lend' ? AppTheme.green : AppTheme.red)),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () async {
              await CashbookDB.setDebtCleared(d.id!, !d.cleared);
              await _afterMutation();
            },
            child: Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: d.cleared ? AppTheme.green : Colors.transparent,
                border: Border.all(color: d.cleared ? AppTheme.green : AppTheme.border, width: 1.4),
              ),
              child: d.cleared ? const Icon(Icons.check, size: 15, color: Colors.white) : null,
            ),
          ),
        ]),
      ),
    );
  }
}

const _chartColors = [
  Color(0xFF4F46E5), Color(0xFFDC4C4C), Color(0xFFFBBF24), Color(0xFF4ADE80),
  Color(0xFF38BDF8), Color(0xFFF472B6), Color(0xFFA78BFA), Color(0xFFF97316),
];

class _PieChartPainter extends CustomPainter {
  final List<double> values;
  _PieChartPainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    double start = -3.14159 / 2;
    for (int i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 3.14159 * 2;
      final paint = Paint()..color = _chartColors[i % _chartColors.length]..style = PaintingStyle.fill;
      canvas.drawArc(rect, start, sweep, true, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) => oldDelegate.values != values;
}
