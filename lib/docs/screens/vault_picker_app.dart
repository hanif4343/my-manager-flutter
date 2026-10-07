import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../reminder/models/reminder.dart' show bn;
import '../../services/auth_service.dart';
import '../../widgets/app_theme.dart';
import '../models/doc_models.dart';
import '../services/docs_export_service.dart';
import '../services/docs_service.dart';

enum _Mode { loading, authFailed, pick, busy }

/// vaultPickEntryPoint()-এর রুট উইজেট (VaultPickActivity)।
///
/// যেকোনো সাইট/অ্যাপের "ফাইল বাছাই / Browse" পিকারে "ডকুমেন্ট ভল্ট" চাপলে এটা খোলে:
///  ১. ফিঙ্গারপ্রিন্ট/PIN যাচাই
///  ২. ভল্টের ডকুমেন্ট ও পাতা বাছা (একসাথে অনেক)
///  ৩. বাছা ফাইল আপলোড-ট্রেতে (১০ মিনিটের সাময়িক ডিক্রিপ্টেড কপি) রেখে বন্ধ — পিকার
///     তখন সেই ফাইলগুলো দেখায়, ট্যাপ করলেই আপলোড।
class VaultPickerApp extends StatefulWidget {
  const VaultPickerApp({super.key});
  @override
  State<VaultPickerApp> createState() => _VaultPickerAppState();
}

class _VaultPickerAppState extends State<VaultPickerApp> {
  static const _channel = MethodChannel('com.hanif.mymanager/vaultpick');

  _Mode _mode = _Mode.loading;
  List<VaultDoc> _docs = [];
  final Map<String, Set<int>> _sel = {}; // ডকুমেন্টের id → বাছা পাতার ইনডেক্স
  bool _asPdf = false;
  String? _owner; // null = সবার; '' = আমার
  final _search = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// বাতিল: RESULT_CANCELED দিয়ে বন্ধ।
  void _cancel() => SystemNavigator.pop();

  Future<void> _init() async {
    setState(() => _mode = _Mode.loading);
    final ok = await AuthService.authenticate(reason: 'ডকুমেন্ট ভল্ট খুলতে যাচাই করো');
    if (!ok) {
      if (mounted) setState(() => _mode = _Mode.authFailed);
      return;
    }
    try {
      final all = await DocsService.list();
      _docs = all.where((d) => d.pages.isNotEmpty).toList();
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _mode = _Mode.pick);
  }

  int get _selectedPages => _sel.values.fold(0, (a, s) => a + s.length);

  Future<void> _confirm() async {
    if (_selectedPages == 0) return;
    setState(() { _mode = _Mode.busy; _error = null; });
    try {
      for (final d in _docs) {
        final idx = _sel[d.id];
        if (idx == null || idx.isEmpty) continue;
        final pages = [for (final i in (idx.toList()..sort())) d.pages[i]];
        await DocsExport.prepareForUpload(d, pages: pages, asPdf: _asPdf && DocsExport.hasImages(pages));
      }
      await _channel.invokeMethod('done');
    } catch (e) {
      if (mounted) setState(() { _mode = _Mode.pick; _error = 'প্রস্তুত করা যায়নি: $e'; });
    }
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Builder(builder: (ctx) {
          final maxH = MediaQuery.of(ctx).size.height * 0.86;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _mode == _Mode.busy ? null : _cancel,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: GestureDetector(onTap: () {}, child: _sheet(maxH)),
            ),
          );
        }),
      ),
    );
  }

  Widget _sheet(double maxH) {
    final Widget body;
    switch (_mode) {
      case _Mode.loading:
      case _Mode.busy:
        body = _stateBox(
          const SizedBox(width: 26, height: 26,
              child: CircularProgressIndicator(strokeWidth: 3, color: AppTheme.accent)),
          _mode == _Mode.busy ? 'ফাইল প্রস্তুত হচ্ছে...' : 'যাচাই হচ্ছে...',
        );
        break;
      case _Mode.authFailed:
        body = _stateBox(
          Icon(Icons.lock_outline_rounded, size: 34, color: AppTheme.textMuted),
          'যাচাই সম্পন্ন হয়নি',
          action: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: _init,
            icon: const Icon(Icons.fingerprint, size: 20),
            label: const Text('আবার চেষ্টা করো'),
          ),
        );
        break;
      case _Mode.pick:
        body = _docs.isEmpty
            ? _stateBox(
                Icon(Icons.folder_off_outlined, size: 34, color: AppTheme.textMuted),
                'ডকুমেন্ট ভল্টে এখনো কোনো ফাইল নেই।\nঅ্যাপে "ডকুমেন্ট ও সনদ" থেকে যোগ করো।')
            : _buildPick();
        break;
    }

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: AppTheme.border)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 38, height: 4,
              decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 8, 4),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [AppTheme.accent, Color(0xFF8B7CFF)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(Icons.folder_special_rounded, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('ডকুমেন্ট ভল্ট',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 16.5, fontWeight: FontWeight.w800)),
                  Text('যে ফাইল আপলোড করতে চাও সেটা বাছো',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                ]),
              ),
              if (_mode != _Mode.busy)
                IconButton(icon: Icon(Icons.close_rounded, color: AppTheme.textMuted), onPressed: _cancel),
            ]),
          ),
          Flexible(child: body),
        ]),
      ),
    );
  }

  Widget _stateBox(Widget top, String text, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 30),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        top,
        const SizedBox(height: 12),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5)),
        if (action != null) ...[const SizedBox(height: 14), action],
      ]),
    );
  }

  Widget _ownerChip(String? key, String label) {
    final sel = _owner == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label,
            style: TextStyle(color: sel ? Colors.white : AppTheme.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
        selected: sel,
        showCheckmark: false,
        selectedColor: AppTheme.accent,
        backgroundColor: AppTheme.bg3,
        side: BorderSide(color: sel ? AppTheme.accent : AppTheme.border),
        onSelected: (_) => setState(() => _owner = key),
      ),
    );
  }

  Widget _buildPick() {
    final q = _search.text.trim().toLowerCase();
    final owners = <String>{for (final d in _docs) d.owner.trim()}.toList()
      ..sort((a, b) => a.isEmpty ? -1 : (b.isEmpty ? 1 : a.compareTo(b)));
    final list = _docs.where((d) {
      if (_owner != null && d.owner.trim() != _owner) return false;
      if (q.isNotEmpty && !d.title.toLowerCase().contains(q) && !d.ownerLabel.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
    final n = _selectedPages;
    final anyImage = _docs.any((d) => (_sel[d.id] ?? {}).any((i) => !d.pages[i].isPdf));
    final multi = n > 1 && anyImage;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (owners.length > 1)
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
            children: [
              _ownerChip(null, 'সবার'),
              for (final o in owners) _ownerChip(o, o.isEmpty ? '🙋 $kSelfOwnerLabel' : '👤 $o'),
            ],
          ),
        ),
      if (_docs.length > 6)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'খোঁজো',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              isDense: true,
              filled: true,
              fillColor: AppTheme.bg3,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
      Flexible(
        child: list.isEmpty
            ? _stateBox(Icon(Icons.search_off_rounded, size: 30, color: AppTheme.textMuted), 'কিছু পাওয়া যায়নি')
            : ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                children: [for (final d in list) _docTile(d)],
              ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
          child: Text(_error!, style: TextStyle(color: AppTheme.red, fontSize: 12.5)),
        ),
      if (multi)
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18),
          activeColor: AppTheme.accent,
          title: Text('ছবিগুলো একটাই PDF করো',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600)),
          value: _asPdf,
          onChanged: (v) => setState(() => _asPdf = v),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: n == 0 ? null : _confirm,
            child: Text(n == 0 ? 'ফাইল বাছো' : '${bn(n)}টা ফাইল দাও',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
        child: Text('বাছা ফাইল ১০ মিনিটের জন্য সাধারণ (এনক্রিপশন ছাড়া) কপি হিসেবে পিকারে দেখাবে, তারপর নিজে মুছে যাবে।',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.4)),
      ),
    ]);
  }

  Widget _docTile(VaultDoc d) {
    final sel = _sel[d.id] ?? <int>{};
    final all = sel.length == d.pages.length;
    final cat = docCategories[d.category] ?? docCategories['other']!;
    void toggleAll() => setState(() {
          if (all) {
            _sel.remove(d.id);
          } else {
            _sel[d.id] = {for (var i = 0; i < d.pages.length; i++) i};
          }
        });
    void togglePage(int i) => setState(() {
          final s = _sel.putIfAbsent(d.id, () => <int>{});
          s.contains(i) ? s.remove(i) : s.add(i);
          if (s.isEmpty) _sel.remove(d.id);
        });

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bg3,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: sel.isEmpty ? Colors.transparent : AppTheme.accent.withOpacity(0.6)),
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: d.pages.length == 1 ? toggleAll : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(children: [
              Text(cat.$1, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                  Text('${d.isMine ? '' : '👤 ${d.owner.trim()} · '}${bn(d.pages.length)}টা পাতা',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
                ]),
              ),
              if (d.pages.length == 1)
                Checkbox(value: all, activeColor: AppTheme.accent, onChanged: (_) => toggleAll())
              else
                TextButton(
                  onPressed: toggleAll,
                  child: Text(all ? 'বাদ দাও' : 'সব পাতা',
                      style: TextStyle(color: AppTheme.accent, fontSize: 12.5)),
                ),
            ]),
          ),
        ),
        if (d.pages.length > 1)
          for (var i = 0; i < d.pages.length; i++)
            CheckboxListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.only(left: 44, right: 8),
              activeColor: AppTheme.accent,
              controlAffinity: ListTileControlAffinity.trailing,
              title: Text('${d.pageLabel(i)}${d.pages[i].isPdf ? ' (PDF)' : ''}',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              value: sel.contains(i),
              onChanged: (_) => togglePage(i),
            ),
      ]),
    );
  }
}
