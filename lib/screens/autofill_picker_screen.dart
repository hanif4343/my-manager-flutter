import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_autofill_service/flutter_autofill_service.dart';
import '../models/vault_entry.dart';
import '../services/vault_service.dart';
import '../services/auth_service.dart';
import '../widgets/app_theme.dart';

/// autofillEntryPoint()-এর রুট উইজেট। অন্য অ্যাপে লগইন ফর্মে ট্যাপ করলে
/// (পাসওয়ার্ড বাছাই) অথবা নতুন লগইন সাবমিট করলে (সেভ সাজেশন) Android
/// এই স্ক্রিন খোলে। ভল্টের মতোই ফিঙ্গারপ্রিন্ট/PIN যাচাই লাগে।
class AutofillPickerApp extends StatefulWidget {
  const AutofillPickerApp({super.key});
  @override State<AutofillPickerApp> createState() => _AutofillPickerAppState();
}

class _AutofillPickerAppState extends State<AutofillPickerApp> {
  bool _loading = true;
  bool _authFailed = false;
  List<VaultEntry> _matches = [];
  List<VaultEntry> _all = [];
  bool _showAll = false;
  SaveInfoMetadata? _saveInfo;
  String? _saveSiteLabel;

  // সেভ ফর্মের কন্ট্রোলার state-এ রাখা হয়েছে (আগে build()-এ প্রতিবার নতুন
  // বানানো হতো, ফলে রিবিল্ডে টাইপ করা লেখা মুছে যেত)।
  final _titleCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  /// এই State-এর নিজের context MaterialApp-এর উপরে, তাই এখান থেকে
  /// Navigator.of(context) কাজ করে না (আগের ভার্সনে সেভ করার পর এটাই
  /// এক্সেপশন ছুঁড়ত)। Activity বন্ধ করতে সরাসরি SystemNavigator ব্যবহার।
  void _finish() {
    SystemNavigator.pop();
  }

  Future<void> _init() async {
    setState(() { _loading = true; _authFailed = false; });
    final ok = await AuthService.authenticate(reason: 'Autofill-এর জন্য যাচাই করো');
    if (!ok) {
      if (mounted) setState(() { _authFailed = true; _loading = false; });
      return;
    }
    await _load();
  }

  String _registrableDomain(String host) {
    final parts = host.toLowerCase().split('.');
    if (parts.length <= 2) return parts.join('.');
    // co.uk, com.bd ইত্যাদি দুই-স্তরের সাফিক্স
    const twoLevel = {'co', 'com', 'org', 'net', 'gov', 'edu', 'ac'};
    if (twoLevel.contains(parts[parts.length - 2]) && parts.last.length == 2) {
      return parts.sublist(parts.length - 3).join('.');
    }
    return parts.sublist(parts.length - 2).join('.');
  }

  String _hostOf(String url) {
    var u = url.toLowerCase().trim();
    u = u.replaceFirst(RegExp(r'^[a-z][a-z0-9+.-]*://'), '');
    u = u.split('/').first.split('?').first.split(':').first;
    return u;
  }

  /// com.facebook.katana → {facebook, katana}; সাধারণ শব্দ বাদ।
  Set<String> _packageTokens(String pkg) {
    const skip = {'com', 'org', 'net', 'android', 'app', 'apps', 'mobile', 'www',
      'google', 'the', 'lite', 'main', 'client', 'release', 'io', 'co'};
    return pkg.toLowerCase().split('.')
        .where((t) => t.length >= 4 && !skip.contains(t)).toSet();
  }

  Future<void> _load() async {
    AutofillMetadata? metadata;
    try {
      metadata = await AutofillService().autofillMetadata;
    } catch (_) {}

    final saveInfo = metadata?.saveInfo;
    if (saveInfo != null) {
      final domains = metadata?.webDomains?.map((d) => d.domain).toList() ?? const <String>[];
      final pkgs = metadata?.packageNames?.toList() ?? const <String>[];
      final label = domains.isNotEmpty ? domains.first : (pkgs.isNotEmpty ? pkgs.first : null);
      _titleCtrl.text = label ?? '';
      _usernameCtrl.text = saveInfo.username ?? '';
      if (mounted) setState(() {
        _saveInfo = saveInfo;
        _saveSiteLabel = label;
        _loading = false;
      });
      return;
    }

    final all = await VaultService.getAll();
    final logins = all.where((e) => e.type == 'login').toList();

    final pkgs = metadata?.packageNames ?? const <String>{};
    final domains = metadata?.webDomains?.map((d) => d.domain).toList() ?? const <String>[];
    final wantedDomains = domains.map(_registrableDomain).toSet();
    final wantedLabels = wantedDomains.map((d) => d.split('.').first).toSet();
    final pkgTokens = <String>{};
    for (final p in pkgs) { pkgTokens.addAll(_packageTokens(p)); }

    final matches = logins.where((e) {
      final url = (e.url ?? '').toLowerCase();
      final title = e.title.toLowerCase();
      for (final p in pkgs) {
        final needle = p.toLowerCase();
        if (url.contains(needle) || title.contains(needle)) return true;
      }
      for (final t in pkgTokens) {
        if (url.contains(t) || title.contains(t)) return true;
      }
      if (url.isNotEmpty && wantedDomains.isNotEmpty) {
        if (wantedDomains.contains(_registrableDomain(_hostOf(url)))) return true;
      }
      for (final l in wantedLabels) {
        if (l.length >= 4 && title.contains(l)) return true;
      }
      return false;
    }).toList();

    if (mounted) setState(() {
      _all = logins;
      _matches = matches;
      _loading = false;
    });
  }

  Future<void> _select(VaultEntry e) async {
    try {
      await AutofillService().resultWithDatasets([
        PwDataset(label: e.title, username: e.username ?? '', password: e.secret),
      ]);
    } catch (_) {
      _finish();
    }
  }

  Future<void> _saveNewLogin() async {
    final password = _saveInfo?.password ?? '';
    if (password.isEmpty || _saving) return;
    setState(() => _saving = true);
    final title = _titleCtrl.text.trim().isEmpty ? 'নতুন লগইন' : _titleCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final n = DateTime.now().millisecondsSinceEpoch;
    try {
      // একই সাইট + একই ইউজারনেম আগে থেকে থাকলে ডুপ্লিকেট না বানিয়ে
      // পাসওয়ার্ডটা আপডেট করা হবে।
      final all = await VaultService.getAll();
      VaultEntry? existing;
      for (final e in all) {
        if (e.type != 'login') continue;
        final sameSite = _saveSiteLabel != null && (e.url ?? '') == _saveSiteLabel;
        final sameUser = (e.username ?? '') == username;
        if (sameSite && sameUser) { existing = e; break; }
      }
      if (existing != null) {
        await VaultService.update(existing.copyWith(secret: password, updatedAt: n));
      } else {
        await VaultService.insert(VaultEntry(
          id: 'v_$n',
          type: 'login',
          title: title,
          username: username.isEmpty ? null : username,
          secret: password,
          url: _saveSiteLabel,
          createdAt: n,
          updatedAt: n,
        ));
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    try {
      await AutofillService().onSaveComplete();
    } catch (_) {}
    _finish();
  }

  Future<void> _dismissSave() async {
    try { await AutofillService().onSaveComplete(); } catch (_) {}
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(title: Text(_saveInfo != null ? 'নতুন লগইন সংরক্ষণ' : 'My Manager থেকে বাছো')),
        body: _authFailed
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('যাচাই ব্যর্থ হয়েছে', style: TextStyle(color: AppTheme.textMuted)),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _init, child: const Text('আবার চেষ্টা করো')),
              ]))
            : _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
                : (_saveInfo != null ? _buildSaveFlow() : _buildList()),
      ),
    );
  }

  Widget _buildList() {
    final list = _showAll || _matches.isEmpty ? _all : _matches;
    if (list.isEmpty) {
      return Center(child: Text('ভল্টে কোনো লগইন নেই',
          style: TextStyle(color: AppTheme.textMuted)));
    }
    return Column(children: [
      if (_matches.isNotEmpty && !_showAll)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: Text('এই অ্যাপ/সাইটের সাথে মিলে যাওয়া এন্ট্রি',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12))),
            TextButton(
              onPressed: () => setState(() => _showAll = true),
              child: Text('সব দেখাও', style: TextStyle(color: AppTheme.accent, fontSize: 12)),
            ),
          ]),
        ),
      if (_matches.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('মিলে যাওয়া এন্ট্রি পাওয়া যায়নি — সব লগইন দেখানো হচ্ছে',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ),
      Expanded(
        child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) {
            final e = list[i];
            return ListTile(
              leading: Icon(Icons.lock_outline, color: AppTheme.textSecondary),
              title: Text(e.title, style: TextStyle(color: AppTheme.textPrimary)),
              subtitle: Text(e.username ?? '', style: TextStyle(color: AppTheme.textMuted)),
              onTap: () => _select(e),
            );
          },
        ),
      ),
    ]);
  }

  Widget _buildSaveFlow() {
    final hasPassword = (_saveInfo?.password ?? '').isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('My Manager-এর ভল্টে এই লগইনটা সংরক্ষণ করবে?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 20),
        Text('নাম', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _titleCtrl, style: TextStyle(color: AppTheme.textPrimary)),
        const SizedBox(height: 16),
        Text('ইউজারনেম', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _usernameCtrl, style: TextStyle(color: AppTheme.textPrimary)),
        const SizedBox(height: 16),
        Text(hasPassword ? 'পাসওয়ার্ড পাওয়া গেছে ✓' : 'পাসওয়ার্ড পাওয়া যায়নি',
            style: TextStyle(color: hasPassword ? AppTheme.green : AppTheme.red, fontSize: 12)),
        const SizedBox(height: 32),
        Row(children: [
          Expanded(
            child: OutlinedButton(onPressed: _dismissSave, child: const Text('না থাক')),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.white),
              onPressed: hasPassword && !_saving ? _saveNewLogin : null,
              child: Text(_saving ? 'সংরক্ষণ হচ্ছে...' : 'ভল্টে সংরক্ষণ করো'),
            ),
          ),
        ]),
      ]),
    );
  }
}
