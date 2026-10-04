import 'package:flutter/material.dart';
import '../reminder/models/reminder.dart' show bn, weekdayBn;
import '../widgets/app_theme.dart';
import 'digital_wellbeing_guide_screen.dart';
import 'screen_time_service.dart';

/// স্ক্রিন টাইম: পড়াশোনায় কত সময় গেল আর অজেবাজে কাজে কত — আজ, গতকাল, ৭ দিন।
class ScreenTimeScreen extends StatefulWidget {
  const ScreenTimeScreen({super.key});
  @override State<ScreenTimeScreen> createState() => _ScreenTimeScreenState();
}

class _ScreenTimeScreenState extends State<ScreenTimeScreen> with WidgetsBindingObserver {
  bool _checking = true;
  bool _access = false;
  bool _loading = false;
  int _range = 0; // 0 আজ, 1 গতকাল, 2 ৭ দিন
  List<DayTotals> _days = [];
  Map<String, dynamic> _guard = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// সেটিংস থেকে অনুমতি দিয়ে ফিরে এলে নিজে আবার দেখে।
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_access) {
        _init();
      } else {
        _loadGuard(); // সেটিংস থেকে অনুমতি দিয়ে ফিরলে অবস্থা হালনাগাদ
      }
    }
  }

  Future<void> _init() async {
    final ok = await ScreenTimeService.hasAccess();
    if (!mounted) return;
    setState(() { _access = ok; _checking = false; });
    if (ok) {
      ScreenTimeService.syncConfig();
      await _load();
    }
  }

  Future<void> _loadGuard() async {
    final g = await ScreenTimeService.guardStatus();
    if (mounted) setState(() => _guard = g);
  }

  Future<void> _load() async {
    _loadGuard();
    setState(() => _loading = true);
    final now = DateTime.now();
    final days = <DayTotals>[];
    try {
      if (_range == 0) {
        days.add(await ScreenTimeService.day(now));
      } else if (_range == 1) {
        days.add(await ScreenTimeService.day(now.subtract(const Duration(days: 1))));
      } else {
        for (var i = 6; i >= 0; i--) {
          days.add(await ScreenTimeService.day(now.subtract(Duration(days: i))));
        }
      }
    } catch (_) {}
    if (mounted) setState(() { _days = days; _loading = false; });
  }

  // ───────────── একত্রিত হিসাব ─────────────

  int _sum(int Function(DayTotals) f) => _days.fold(0, (s, d) => s + f(d));

  List<AppUse> _mergedApps() {
    final map = <String, AppUse>{};
    for (final d in _days) {
      for (final a in d.apps) {
        final cur = map[a.pkg];
        map[a.pkg] = cur == null ? AppUse(a.pkg, a.label, a.ms, a.cat) : AppUse(a.pkg, a.label, cur.ms + a.ms, a.cat);
      }
    }
    final list = map.values.where((a) => a.group != StGroup.ignore).toList()
      ..sort((a, b) => b.ms.compareTo(a.ms));
    return list;
  }

  // ───────────── বিল্ড ─────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('স্ক্রিন টাইম'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'লক্ষ্য ও সতর্কবার্তা',
            onPressed: _access ? _goalsSheet : null,
          ),
        ],
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : (!_access ? _permissionBody() : _body()),
    );
  }

  Widget _permissionBody() {
    return ListView(padding: const EdgeInsets.all(20), children: [
      const SizedBox(height: 20),
      Icon(Icons.phone_android_rounded, size: 56, color: AppTheme.accent),
      const SizedBox(height: 16),
      Text('কোন অ্যাপে কত সময় যাচ্ছে জানতে অনুমতি লাগবে',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w800, height: 1.35)),
      const SizedBox(height: 12),
      Text(
        'Android-এর "Usage access" অনুমতি দিলে ফেসবুক, ইউটিউব, পড়ার অ্যাপ — প্রতিটায় কত সময় গেছে অ্যাপ হিসাব করে দেখাবে। '
        'শুধু সময়ের হিসাব; কী দেখছ বা পড়ছ তা পড়া হয় না, আর কিছু ফোনের বাইরে যায় না।',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.5, height: 1.5),
      ),
      const SizedBox(height: 18),
      _stepRow('১', 'নিচের বাটনে চাপো'),
      _stepRow('২', 'তালিকা থেকে "My Manager" বেছে নাও'),
      _stepRow('৩', '"Allow usage access" চালু করে ফিরে এসো'),
      const SizedBox(height: 20),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: AppTheme.accent, padding: const EdgeInsets.symmetric(vertical: 14)),
        onPressed: ScreenTimeService.openAccessSettings,
        icon: const Icon(Icons.settings_rounded),
        label: const Text('অনুমতি দিতে সেটিংস খোলো'),
      ),
    ]);
  }

  Widget _stepRow(String n, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Container(
            width: 26, height: 26, alignment: Alignment.center,
            decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.18), shape: BoxShape.circle),
            child: Text(n, style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(t, style: TextStyle(color: AppTheme.textPrimary, fontSize: 14))),
        ]),
      );

  Widget _body() {
    final study = _sum((d) => d.studyMs);
    final waste = _sum((d) => d.wasteMs);
    final neutral = _sum((d) => d.neutralMs);
    final apps = _mergedApps();
    final n = _days.isEmpty ? 1 : _days.length;

    return RefreshIndicator(
      color: AppTheme.accent,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Row(children: [
            _rangeChip(0, 'আজ'),
            _rangeChip(1, 'গতকাল'),
            _rangeChip(2, '৭ দিন'),
          ]),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppTheme.accent)))
          else ...[
            _summaryCard(study, waste, neutral, n),
            const SizedBox(height: 12),
            if (_range == 2) ...[_weekChart(), const SizedBox(height: 12)],
            if (_range == 0) _manualButton(),
            const SizedBox(height: 8),
            _sectionTitle('অ্যাপ (${bn(apps.length)}টা) — ট্যাপ করে ধরন বদলাও'),
            if (apps.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('এই সময়ে কোনো ব্যবহার পাওয়া যায়নি', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted)),
              )
            else
              for (final a in apps.take(15)) _appTile(a, study + waste + neutral),
            const SizedBox(height: 10),
            _guardCard(),
            const SizedBox(height: 10),
            _wellbeingCard(),
          ],
        ],
      ),
    );
  }

  Widget _rangeChip(int i, String label) {
    final sel = _range == i;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(color: sel ? Colors.white : AppTheme.textSecondary, fontWeight: FontWeight.w600)),
        selected: sel,
        showCheckmark: false,
        selectedColor: AppTheme.accent,
        backgroundColor: AppTheme.bg2,
        side: BorderSide(color: sel ? AppTheme.accent : AppTheme.border),
        onSelected: (_) {
          setState(() => _range = i);
          _load();
        },
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 0, 8),
        child: Text(t, style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5, fontWeight: FontWeight.w700)),
      );

  // ───────────── সারসংক্ষেপ কার্ড ─────────────

  Widget _summaryCard(int study, int waste, int neutral, int n) {
    final total = study + waste + neutral;
    final goalMs = ScreenTimeService.studyGoalMin * 60000 * n;
    final limitMs = ScreenTimeService.wasteLimitMin * 60000 * n;

    String verdict;
    Color vColor;
    if (total == 0) {
      verdict = 'এই সময়ে কোনো ব্যবহার নেই';
      vColor = AppTheme.textMuted;
    } else if (waste == 0 && study > 0) {
      verdict = '🌟 অপচয় নেই, শুধু পড়াশোনা — দারুণ!';
      vColor = AppTheme.green;
    } else if (waste > study * 2 && waste > 30 * 60000) {
      verdict = '😟 পড়ার চেয়ে ${(waste / (study == 0 ? 1 : study)).toStringAsFixed(1)} গুণ বেশি সময় অপচয়ে গেছে';
      vColor = AppTheme.red;
    } else if (waste > study) {
      verdict = '⚠️ অপচয় পড়ার চেয়ে বেশি — একটু কমাতে হবে';
      vColor = AppTheme.yellow;
    } else {
      verdict = '✅ পড়াশোনা অপচয়ের চেয়ে এগিয়ে';
      vColor = AppTheme.green;
    }

    Widget big(String label, int ms, Color c) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            const SizedBox(height: 4),
            Text(fmtMs(ms), style: TextStyle(color: c, fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          big('📚 পড়াশোনা', study, AppTheme.green),
          big('🗑️ অপচয়', waste, AppTheme.red),
          big('⚪ অন্যান্য', neutral, AppTheme.textSecondary),
        ]),
        const SizedBox(height: 12),
        _stackBar(study, waste, neutral),
        const SizedBox(height: 12),
        Text(verdict, style: TextStyle(color: vColor, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.35)),
        const SizedBox(height: 14),
        _goalBar('পড়ার লক্ষ্য', study, goalMs, AppTheme.green, higherIsBetter: true),
        const SizedBox(height: 10),
        _goalBar('অপচয়ের সীমা', waste, limitMs, AppTheme.red, higherIsBetter: false),
      ]),
    );
  }

  Widget _stackBar(int a, int b, int c) {
    final total = a + b + c;
    if (total == 0) {
      return Container(height: 10, decoration: BoxDecoration(color: AppTheme.bg3, borderRadius: BorderRadius.circular(6)));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 10,
        child: Row(children: [
          if (a > 0) Expanded(flex: a, child: Container(color: AppTheme.green)),
          if (b > 0) Expanded(flex: b, child: Container(color: AppTheme.red)),
          if (c > 0) Expanded(flex: c, child: Container(color: AppTheme.textMuted.withOpacity(0.5))),
        ]),
      ),
    );
  }

  Widget _goalBar(String label, int value, int target, Color color, {required bool higherIsBetter}) {
    final frac = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);
    final over = value > target;
    final c = higherIsBetter ? (value >= target ? AppTheme.green : color) : (over ? AppTheme.red : AppTheme.green);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5)),
        const Spacer(),
        Text('${fmtMs(value)} / ${fmtMs(target)}', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      ]),
      const SizedBox(height: 5),
      ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: LinearProgressIndicator(value: frac, minHeight: 7, backgroundColor: AppTheme.bg3, valueColor: AlwaysStoppedAnimation<Color>(c)),
      ),
    ]);
  }

  // ───────────── ৭ দিনের চার্ট ─────────────

  Widget _weekChart() {
    var maxMs = 1;
    for (final d in _days) {
      final t = d.studyMs + d.wasteMs;
      if (t > maxMs) maxMs = t;
    }
    const h = 110.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(color: AppTheme.bg2, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('দিনভিত্তিক', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
          const Spacer(),
          _legend(AppTheme.green, 'পড়া'),
          const SizedBox(width: 10),
          _legend(AppTheme.red, 'অপচয়'),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: h + 34,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final d in _days)
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(d.studyMs + d.wasteMs == 0 ? '' : '${((d.wasteMs) / 3600000).toStringAsFixed(1)}',
                      style: TextStyle(color: AppTheme.red, fontSize: 9.5)),
                  const SizedBox(height: 2),
                  Container(
                    width: 22,
                    height: h * (d.wasteMs / maxMs),
                    decoration: BoxDecoration(color: AppTheme.red, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                  ),
                  Container(width: 22, height: h * (d.studyMs / maxMs), color: AppTheme.green),
                  const SizedBox(height: 6),
                  Text(weekdayBn(d.day), maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(color: AppTheme.textMuted, fontSize: 9.5)),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _legend(Color c, String t) => Row(children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(t, style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
      ]);

  // ───────────── অ্যাপ তালিকা ─────────────

  Color _groupColor(StGroup g) {
    switch (g) {
      case StGroup.study: return AppTheme.green;
      case StGroup.waste: return AppTheme.red;
      default: return AppTheme.textMuted;
    }
  }

  Widget _appTile(AppUse a, int total) {
    final c = _groupColor(a.group);
    final cat = stCats[a.cat] ?? stCats['other']!;
    final frac = total <= 0 ? 0.0 : (a.ms / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _pickCategory(a),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
            child: Column(children: [
              Row(children: [
                Container(
                  width: 36, height: 36, alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.withOpacity(0.16), borderRadius: BorderRadius.circular(11)),
                  child: Text(cat.$1, style: const TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(cat.$2, style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ]),
                ),
                Text(fmtMs(a.ms), style: TextStyle(color: AppTheme.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: frac, minHeight: 4, backgroundColor: AppTheme.bg3, valueColor: AlwaysStoppedAnimation<Color>(c)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _pickCategory(AppUse a) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.bg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 14),
            Text(a.label, style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('এটা কী ধরনের অ্যাপ?', style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
            const SizedBox(height: 6),
            for (final e in stCats.entries)
              ListTile(
                leading: Text(e.value.$1, style: const TextStyle(fontSize: 22)),
                title: Text(e.value.$2, style: TextStyle(color: AppTheme.textPrimary)),
                subtitle: Text(
                  groupOf(e.key) == StGroup.study
                      ? 'পড়াশোনার সময়ে গোনা হবে'
                      : (groupOf(e.key) == StGroup.waste
                          ? 'অপচয় হিসেবে গোনা হবে'
                          : (e.key == 'ignore' ? 'কোনো হিসাবে ধরা হবে না' : 'আলাদা নিরপেক্ষ সময়')),
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
                trailing: a.cat == e.key ? Icon(Icons.check_rounded, color: AppTheme.accent) : null,
                onTap: () => Navigator.pop(ctx, e.key),
              ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
    if (picked != null && picked != a.cat) {
      await ScreenTimeService.setCategory(a.pkg, picked);
      await _load();
    }
  }

  // ───────────── হাতে পড়ার সময় ─────────────

  Widget _manualButton() {
    final m = ScreenTimeService.manualMinutes(DateTime.now());
    return OutlinedButton.icon(
      icon: const Icon(Icons.menu_book_rounded, size: 18),
      label: Text(m > 0 ? '📖 বই/খাতায় পড়া: ${fmtMs(m * 60000)} (আরও যোগ করো)' : '📖 বই/খাতায় পড়েছি — সময় যোগ করো'),
      onPressed: _addManual,
    );
  }

  Future<void> _addManual() async {
    final ctrl = TextEditingController();
    final min = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bg2,
        title: const Text('কত মিনিট পড়লে?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('কাগজের বই বা খাতায় পড়লে ফোন তা মাপতে পারে না — এখান থেকে যোগ করলে আজকের পড়ার হিসাবে ধরা হবে।',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final v in [15, 30, 45, 60, 90, 120])
              ActionChip(label: Text('${bn(v)} মি'), onPressed: () => Navigator.pop(ctx, v)),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'অন্য সময় (মিনিট)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
          TextButton(
            onPressed: () {
              final v = int.tryParse(_ascii(ctrl.text.trim())) ?? 0;
              if (v > 0 && v <= 1000) Navigator.pop(ctx, v);
            },
            child: Text('যোগ করো', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (min != null) {
      await ScreenTimeService.addManualMinutes(DateTime.now(), min);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('📖 ${bn(min)} মিনিট পড়ার সময় যোগ হয়েছে')));
      }
      await _load();
    }
  }

  String _ascii(String s) {
    const bnd = '০১২৩৪৫৬৭৮৯';
    final b = StringBuffer();
    for (final ch in s.runes) {
      final c = String.fromCharCode(ch);
      final i = bnd.indexOf(c);
      b.write(i >= 0 ? '$i' : c);
    }
    return b.toString();
  }

  // ───────────── স্ক্রিন প্রহরী ─────────────

  String _hm(int m) {
    final h = m ~/ 60, mm = m % 60;
    final ap = h < 4 ? 'রাত' : (h < 12 ? 'সকাল' : (h < 15 ? 'দুপুর' : (h < 18 ? 'বিকাল' : (h < 20 ? 'সন্ধ্যা' : 'রাত'))));
    return '${bn(h.toString().padLeft(2, '0'))}:${bn(mm.toString().padLeft(2, '0'))} ($ap)';
  }

  Future<void> _addWindow() async {
    final s = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0), helpText: 'পড়া শুরুর সময়');
    if (s == null || !mounted) return;
    final e = await showTimePicker(context: context, initialTime: TimeOfDay(hour: (s.hour + 3) % 24, minute: s.minute), helpText: 'পড়া শেষের সময়');
    if (e == null) return;
    final list = [...ScreenTimeService.windows, (s.hour * 60 + s.minute, e.hour * 60 + e.minute)];
    await ScreenTimeService.saveGuard(windows: list);
    if (mounted) setState(() {});
  }

  Widget _statusRow(bool ok, String label, VoidCallback onFix) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded, size: 20, color: ok ? AppTheme.green : AppTheme.yellow),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
        if (!ok) TextButton(onPressed: onFix, child: const Text('চালু করো')),
      ]),
    );
  }

  Widget _guardCard() {
    final acc = _guard['accessibility'] == true;
    final ov = _guard['overlay'] == true;
    final ready = acc && ov;
    final on = ScreenTimeService.blockOn;
    final blocked = (_guard['blocked'] as num?)?.toInt() ?? 0;
    final wins = ScreenTimeService.windows;
    final graceMax = ScreenTimeService.graceMax;
    final graceMin = ScreenTimeService.graceMin;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: on && ready ? AppTheme.green.withOpacity(0.6) : AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🛑', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Text('থামো স্ক্রিন (প্রহরী)',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          Switch(
            value: on,
            activeColor: AppTheme.accent,
            onChanged: (v) async {
              await ScreenTimeService.saveGuard(on: v);
              if (mounted) setState(() {});
            },
          ),
        ]),
        Text(
          'অপচয়ের সীমা পেরোলে, অথবা নিচের "পড়ার সময়ে", ফেসবুক-ইউটিউব-গেম খুললেই সামনে "থামো" স্ক্রিন আসবে — '
          'পড়তে যাওয়া, হোমে ফেরা, বা সীমিত বার কয়েক মিনিটের ছাড়পত্র (১০ সেকেন্ড ভেবে নিতে হয়)।',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5, height: 1.45),
        ),
        const SizedBox(height: 12),
        _statusRow(acc, 'Accessibility সেবা চালু (কোন অ্যাপ খুলল তা জানতে)', ScreenTimeService.openAccessibilitySettings),
        _statusRow(ov, '"অন্য অ্যাপের উপরে দেখানো" অনুমতি', ScreenTimeService.openOverlaySettings),
        if (!acc)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Accessibility সেটিংসে গিয়ে "ইনস্টল করা অ্যাপ/সেবা" থেকে "My Manager স্ক্রিন প্রহরী" বেছে চালু করো। '
              'এটা শুধু অ্যাপের নাম জানে — স্ক্রিনের লেখা পড়ে না, কিছু ফোনের বাইরে যায় না।',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.45),
            ),
          ),
        const Divider(height: 22),
        Row(children: [
          Expanded(
            child: Text('পড়ার সময় (এই সময়ে সবসময় থামাবে)',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
          TextButton.icon(onPressed: _addWindow, icon: const Icon(Icons.add, size: 18), label: const Text('সময়')),
        ]),
        if (wins.isEmpty)
          Text('কোনো নির্দিষ্ট সময় নেই — শুধু অপচয়ের সীমা পেরোলে থামাবে।',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
        for (var i = 0; i < wins.length; i++)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
            decoration: BoxDecoration(color: AppTheme.bg3, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Expanded(child: Text('${_hm(wins[i].$1)} – ${_hm(wins[i].$2)}',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 13))),
              IconButton(
                icon: Icon(Icons.close_rounded, size: 18, color: AppTheme.textMuted),
                onPressed: () async {
                  final l = [...wins]..removeAt(i);
                  await ScreenTimeService.saveGuard(windows: l);
                  if (mounted) setState(() {});
                },
              ),
            ]),
          ),
        const Divider(height: 22),
        Text('ছাড়পত্র: দিনে সর্বোচ্চ ${bn(graceMax)} বার, প্রতিবার ${bn(graceMin)} মিনিট',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('বার:', style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
          for (final v in [0, 1, 2, 3, 5])
            ChoiceChip(
              label: Text(bn(v)),
              selected: graceMax == v,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) async {
                await ScreenTimeService.saveGuard(graceMax: v);
                if (mounted) setState(() {});
              },
            ),
          const SizedBox(width: 8),
          Text('মিনিট:', style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
          for (final v in [3, 5, 10])
            ChoiceChip(
              label: Text(bn(v)),
              selected: graceMin == v,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) async {
                await ScreenTimeService.saveGuard(graceMin: v);
                if (mounted) setState(() {});
              },
            ),
        ]),
        const SizedBox(height: 10),
        Text(
          on && !ready
              ? '⚠️ প্রহরী চালু আছে কিন্তু ওপরের অনুমতি বাকি — ততক্ষণ থামানো কাজ করবে না।'
              : (blocked > 0 ? '🛑 আজ ${bn(blocked)} বার থামানো হয়েছে' : (on ? '✅ প্রস্তুত — এখন পর্যন্ত থামানোর দরকার হয়নি' : 'বন্ধ আছে')),
          style: TextStyle(color: on && !ready ? AppTheme.yellow : AppTheme.textSecondary, fontSize: 12.5),
        ),
      ]),
    );
  }

  // ───────────── Digital Wellbeing কার্ড ─────────────

  Widget _wellbeingCard() {
    return Material(
      color: AppTheme.bg2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DigitalWellbeingGuideScreen())),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.accent.withOpacity(0.5)),
          ),
          child: Row(children: [
            Icon(Icons.shield_moon_rounded, color: AppTheme.accent, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ফেসবুক ঠেকাতে Digital Wellbeing সেট করো',
                    style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text('তোমার ডাটা দেখে কোন অ্যাপে কত মিনিটের টাইমার দেবে — ধাপে ধাপে গাইড',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.35)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
          ]),
        ),
      ),
    );
  }

  // ───────────── লক্ষ্য ও সতর্কবার্তা ─────────────

  Future<void> _goalsSheet() async {
    var study = ScreenTimeService.studyGoalMin;
    var waste = ScreenTimeService.wasteLimitMin;
    var nudge = ScreenTimeService.nudgeOn;
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bg2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Widget stepper(String label, int value, int step, int min, int max, ValueChanged<int> on) {
          return Row(children: [
            Expanded(child: Text(label, style: TextStyle(color: AppTheme.textPrimary, fontSize: 14))),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: value - step >= min ? () => setS(() => on(value - step)) : null,
            ),
            SizedBox(
              width: 86,
              child: Text(fmtMs(value * 60000), textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w800, fontSize: 14)),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: value + step <= max ? () => setS(() => on(value + step)) : null,
            ),
          ]);
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('লক্ষ্য ও সতর্কবার্তা', style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('প্রথম সপ্তাহের গড় দেখে অপচয়ের সীমা বসাও, তারপর প্রতি সপ্তাহে একটু কমাও — একলাফে সব বন্ধ করতে গেলে টেকে না।',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.4)),
              const SizedBox(height: 14),
              stepper('দৈনিক পড়ার লক্ষ্য', study, 15, 30, 720, (v) => study = v),
              stepper('দৈনিক অপচয়ের সীমা', waste, 15, 15, 600, (v) => waste = v),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: nudge,
                activeColor: AppTheme.accent,
                title: Text('সতর্কবার্তা পাঠাও', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                subtitle: Text('সীমা পেরোলে, আর সন্ধ্যা ৬টার পর পড়া কম থাকলে নোটিফিকেশন',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                onChanged: (v) => setS(() => nudge = v),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.accent, padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () async {
                    await ScreenTimeService.saveGoals(studyMin: study, wasteMin: waste, nudge: nudge);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('সংরক্ষণ করো'),
                ),
              ),
            ]),
          ),
        );
      }),
    );
    if (mounted) setState(() {});
  }
}
