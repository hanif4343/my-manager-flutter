import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../family/screens/family_ui.dart';
import '../../reminder/models/reminder.dart' show bn;
import '../../services/auth_service.dart';
import '../../widgets/app_theme.dart';
import '../models/doc_models.dart';
import '../services/docs_service.dart';
import 'doc_form_sheet.dart';
import 'doc_viewer_screen.dart';
import '../services/docs_export_service.dart';
import 'docs_backup_sheet.dart';
import 'doc_type_picker.dart';

/// ডকুমেন্ট ও সনদের এনক্রিপ্টেড ভল্ট। ঢুকতে ফিঙ্গারপ্রিন্ট/PIN লাগে; অ্যাপ
/// ব্যাকগ্রাউন্ডে গেলে নিজে বন্ধ হয় (ভল্টের মতো)।
class DocsHomeScreen extends StatefulWidget {
  /// ক্যামেরা/ফাইল পিকার/শেয়ারের মতো বাইরের স্ক্রিন খোলার সময় true — তখন অটো-লক চলে না।
  static bool suppressAutoLock = false;
  const DocsHomeScreen({super.key});
  @override State<DocsHomeScreen> createState() => _DocsHomeScreenState();
}

class _DocsHomeScreenState extends State<DocsHomeScreen> with WidgetsBindingObserver {
  bool _authed = false;
  bool _authFailed = false;
  bool _loading = true;
  List<VaultDoc> _docs = [];
  int _tray = 0; // আপলোডের জন্য প্রস্তুত ফাইলের সংখ্যা
  String _cat = 'all';
  String? _owner; // null = সবার; '' = আমার; নইলে নির্দিষ্ট ব্যক্তি
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DocsService.changes.addListener(_load);
    DocsExport.trayChanges.addListener(_loadTray);
    _auth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DocsService.changes.removeListener(_load);
    DocsExport.trayChanges.removeListener(_loadTray);
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && mounted && !DocsHomeScreen.suppressAutoLock) {
      // উপরে ভিউয়ার/শিট খোলা থাকলেও সব বন্ধ হয়ে হোমে ফেরে।
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _auth() async {
    setState(() { _authFailed = false; });
    final ok = await AuthService.authenticate(reason: 'ডকুমেন্ট ভল্ট খুলতে যাচাই করো');
    if (!ok) {
      if (mounted) setState(() => _authFailed = true);
      return;
    }
    _authed = true;
    // আগের সেশনের সাময়িক ডিক্রিপ্টেড ফাইল (থাকলে) সাফ।
    try {
      final dir = await getTemporaryDirectory();
      for (final e in dir.listSync()) {
        if (e is File && e.uri.pathSegments.last.startsWith('docs_tmp_')) e.deleteSync();
      }
    } catch (_) {}
    // আগের শেয়ারের সাময়িক কপি সাফ; মেয়াদ-শেষ আপলোড-ট্রের ফাইলও।
    await DocsExport.cleanShareTemp();
    await _load();
  }

  Future<void> _loadTray() async {
    if (!_authed) return;
    final n = await DocsExport.trayCount();
    if (mounted) setState(() => _tray = n);
  }

  Future<void> _load() async {
    if (!_authed) return;
    final l = await DocsService.list();
    if (mounted) setState(() { _docs = l; _loading = false; });
    _loadTray();
  }

  Color _expColor(int d) => d < 0 ? AppTheme.red : (d <= 30 ? AppTheme.yellow : AppTheme.textSecondary);

  Future<void> _add() async {
    final t = await showDocTypePicker(context);
    if (t == null || !mounted) return;
    await showDocForm(context, template: t, presetCategory: _cat == 'all' ? null : _cat, presetOwner: _owner);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('ডকুমেন্ট ও সনদ'),
        actions: [
          if (_authed)
            IconButton(
              icon: const Icon(Icons.enhanced_encryption_outlined),
              tooltip: 'ব্যাকআপ / রিস্টোর',
              onPressed: () => showDocsBackupSheet(context),
            ),
        ],
      ),
      floatingActionButton: _authed
          ? FloatingActionButton(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              onPressed: _add,
              child: const Icon(Icons.add),
            )
          : null,
      body: !_authed ? _lockedBody() : (_loading ? const Center(child: CircularProgressIndicator(color: AppTheme.accent)) : _body()),
    );
  }

  Widget _lockedBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline_rounded, size: 46, color: AppTheme.textMuted),
          const SizedBox(height: 12),
          Text(_authFailed ? 'যাচাই সম্পন্ন হয়নি' : 'যাচাই করা হচ্ছে...',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
          if (_authFailed) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
              onPressed: _auth,
              icon: const Icon(Icons.fingerprint),
              label: const Text('আবার চেষ্টা করো'),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _body() {
    final q = _search.text.trim().toLowerCase();
    final list = _docs.where((d) {
      if (_cat != 'all' && d.category != _cat) return false;
      if (_owner != null && d.owner.trim() != _owner) return false;
      if (q.isNotEmpty &&
          !d.title.toLowerCase().contains(q) &&
          !d.note.toLowerCase().contains(q) &&
          !d.ownerLabel.toLowerCase().contains(q)) return false;
      return true;
    }).toList();

    final expiring = _docs.where((d) => d.daysToExpiry != null && d.daysToExpiry! <= 30).length;
    final cats = docCategories.keys.where((k) => _docs.any((d) => d.category == k)).toList();
    // কার কার ডকুমেন্ট আছে ('' = আমি সবার আগে)। একজনের হলে ফিল্টার দেখানো হয় না।
    final owners = <String>{for (final d in _docs) d.owner.trim()}.toList()
      ..sort((a, b) => a.isEmpty ? -1 : (b.isEmpty ? 1 : a.compareTo(b)));

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 90), children: [
      fCard(
        child: Row(children: [
          Icon(Icons.shield_rounded, color: AppTheme.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text('ফাইল AES-256 এনক্রিপ্টেড, ফোনের বাইরে যায় না। ফোন হারানোর ঝুঁকি এড়াতে ⋮-এর পাশের 🔐 থেকে পাসওয়ার্ড-সুরক্ষিত ব্যাকআপ নাও।',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.4)),
          ),
        ]),
      ),
      if (_tray > 0)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.upload_file_rounded, color: AppTheme.accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${bn(_tray)}টা ফাইল ব্রাউজার/সাইটে আপলোডের জন্য প্রস্তুত (ফাইল-পিকারে "ডকুমেন্ট ভল্ট")। ১০ মিনিট পর নিজে মুছবে।',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.35)),
            ),
            TextButton(
              onPressed: () async {
                await DocsExport.clearTray();
                _loadTray();
              },
              child: Text('বন্ধ করো', style: TextStyle(color: AppTheme.red, fontSize: 12.5)),
            ),
          ]),
        ),
      if (expiring > 0)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.yellow.withOpacity(0.13), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.event_busy_outlined, color: AppTheme.yellow, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${bn(expiring)}টা ডকুমেন্টের মেয়াদ ৩০ দিনের মধ্যে শেষ হচ্ছে বা শেষ হয়ে গেছে',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5)),
            ),
          ]),
        ),
      if (_docs.length > 6)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'খোঁজো',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              isDense: true,
              filled: true,
              fillColor: AppTheme.bg2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
      if (owners.length > 1)
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            _ownerChip(null, 'সবার'),
            for (final o in owners)
              _ownerChip(o, '${o.isEmpty ? '🙋 $kSelfOwnerLabel' : '👤 $o'} ${bn(_docs.where((d) => d.owner.trim() == o).length)}'),
          ]),
        ),
      if (cats.length > 1)
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            _chip('all', 'সব ${bn(_docs.length)}'),
            for (final k in cats)
              _chip(k, '${docCategories[k]!.$1} ${docCategories[k]!.$2} ${bn(_docs.where((d) => d.category == k).length)}'),
          ]),
        ),
      if (_docs.isEmpty)
        fEmpty(Icons.folder_special_outlined,
            'কোনো ডকুমেন্ট নেই।\nনিচের + বাটনে ট্যাপ করে NID, জন্মনিবন্ধন, SSC/HSC সনদ, ছবি, স্বাক্ষর যোগ করো — ক্যামেরা বা গ্যালারি থেকে।')
      else if (list.isEmpty)
        fEmpty(Icons.search_off_rounded, 'কিছু পাওয়া যায়নি')
      else
        for (final d in list) _docCard(d),
    ]);
  }

  Widget _ownerChip(String? key, String label) {
    final sel = _owner == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 6),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(color: sel ? Colors.white : AppTheme.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
        selected: sel,
        showCheckmark: false,
        selectedColor: AppTheme.accent,
        backgroundColor: AppTheme.bg2,
        side: BorderSide(color: sel ? AppTheme.accent : AppTheme.border),
        onSelected: (_) => setState(() => _owner = key),
      ),
    );
  }

  Widget _chip(String key, String label) {
    final sel = _cat == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 6),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(color: sel ? Colors.white : AppTheme.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
        selected: sel,
        showCheckmark: false,
        selectedColor: AppTheme.accent,
        backgroundColor: AppTheme.bg2,
        side: BorderSide(color: sel ? AppTheme.accent : AppTheme.border),
        onSelected: (_) => setState(() => _cat = key),
      ),
    );
  }

  Widget _docCard(VaultDoc d) {
    final days = d.daysToExpiry;
    final cat = docCategories[d.category] ?? docCategories['other']!;
    return fCard(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => DocViewerScreen(doc: d)));
        _load();
      },
      child: Row(children: [
        Container(
          width: 46, height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.13), borderRadius: BorderRadius.circular(14)),
          child: Text(cat.$1, style: const TextStyle(fontSize: 22)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text('${d.isMine ? '' : '👤 ${d.owner.trim()} · '}${cat.$2} · ${d.pages.isEmpty ? 'ফাইল নেই' : '${bn(d.pages.length)}টা পাতা'}${d.numberEnc.isNotEmpty ? ' · 🔢 নম্বর আছে' : ''}',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          ]),
        ),
        if (days != null)
          fChip(days < 0 ? 'মেয়াদ শেষ' : (days <= 90 ? '${bn(days)} দিন' : '✓ মেয়াদ আছে'), _expColor(days)),
      ]),
    );
  }
}
