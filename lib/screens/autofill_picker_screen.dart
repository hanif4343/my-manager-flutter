import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_autofill_service/flutter_autofill_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // দ্রুত করার জন্য: সাম্প্রতিক যাচাইয়ের পর এই সময়ের মধ্যে আবার
  // ফিঙ্গারপ্রিন্ট/PIN চাইবে না।
  static const _authGraceSeconds = 120;
  static const _lastAuthKey = 'af_last_auth_ms';
  final _searchCtrl = TextEditingController();
  String _siteKey = '';
  String? _lastUsedId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _usernameCtrl.dispose();
    _searchCtrl.dispose();
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

    AutofillMetadata? metadata;
    try {
      metadata = await AutofillService().autofillMetadata;
    } catch (_) {}

    // সেভ ফ্লো-তে ভল্টের কিছু দেখানো হয় না, শুধু নতুন এন্ট্রি যোগ হয় —
    // তাই এখানে যাচাই ছাড়াই সরাসরি সেভ স্ক্রিন, এক ধাপ কম।
    if (metadata?.saveInfo != null) {
      _showSave(metadata!);
      return;
    }

    // পাসওয়ার্ড বাছাইয়ের আগে যাচাই — তবে ২ মিনিটের মধ্যে আগেই যাচাই
    // হয়ে থাকলে আবার নয়।
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final last = prefs.getInt(_lastAuthKey) ?? 0;
    final fresh = DateTime.now().millisecondsSinceEpoch - last < _authGraceSeconds * 1000;
    if (!fresh) {
      final ok = await AuthService.authenticate(reason: 'Autofill-এর জন্য যাচাই করো');
      if (!ok) {
        if (mounted) setState(() { _authFailed = true; _loading = false; });
        return;
      }
      await prefs.setInt(_lastAuthKey, DateTime.now().millisecondsSinceEpoch);
    }
    await _load(metadata, prefs);
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

  void _showSave(AutofillMetadata metadata) {
    final saveInfo = metadata.saveInfo!;
    final domains = metadata.webDomains?.map((d) => d.domain).toList() ?? const <String>[];
    final pkgs = metadata.packageNames?.toList() ?? const <String>[];
    final label = domains.isNotEmpty ? domains.first : (pkgs.isNotEmpty ? pkgs.first : null);
    _titleCtrl.text = label ?? '';
    _usernameCtrl.text = saveInfo.username ?? '';
    if (mounted) setState(() {
      _saveInfo = saveInfo;
      _saveSiteLabel = label;
      _loading = false;
    });
  }

  Future<void> _load(AutofillMetadata? metadata, SharedPreferences prefs) async {
    final all = await VaultService.getAll();
    final logins = all.where((e) => e.type == 'login').toList();

    final pkgs = metadata?.packageNames ?? const <String>{};
    final domains = metadata?.webDomains?.map((d) => d.domain).toList() ?? const <String>[];
    final wantedDomains = domains.map(_registrableDomain).toSet();
    final wantedLabels = wantedDomains.map((d) => d.split('.').first).toSet();
    final pkgTokens = <String>{};
    for (final p in pkgs) { pkgTokens.addAll(_packageTokens(p)); }

    _siteKey = wantedDomains.isNotEmpty
        ? wantedDomains.first
        : (pkgs.isNotEmpty ? pkgs.first : '');
    _lastUsedId = _siteKey.isEmpty ? null : prefs.getString('af_last_$_siteKey');

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

    // সবচেয়ে আগে: এই সাইটে শেষবার যেটা ব্যবহার হয়েছিল; তারপর নতুন আপডেট
    // হওয়াগুলো।
    int rank(VaultEntry e) => e.id == _lastUsedId ? 0 : 1;
    int cmp(VaultEntry a, VaultEntry b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : b.updatedAt.compareTo(a.updatedAt);
    }
    matches.sort(cmp);
    logins.sort(cmp);

    _all = logins;
    _matches = matches;

    // মাত্র একটাই মিল থাকলে কোনো ট্যাপ ছাড়াই সরাসরি ফিল।
    if (matches.length == 1) {
      final ok = await _select(matches.first);
      if (ok) return;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<bool> _select(VaultEntry e) async {
    try {
      if (_siteKey.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('af_last_$_siteKey', e.id);
      }
      await AutofillService().resultWithDatasets([
        PwDataset(label: e.title, username: e.username ?? '', password: e.secret),
      ]);
      return true;
    } catch (_) {
      return false;
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
    final base = _showAll || _matches.isEmpty ? _all : _matches;
    final q = _searchCtrl.text.trim().toLowerCase();
    final list = q.isEmpty
        ? base
        : _all.where((e) =>
            e.title.toLowerCase().contains(q) ||
            (e.username ?? '').toLowerCase().contains(q) ||
            (e.url ?? '').toLowerCase().contains(q)).toList();
    if (_all.isEmpty) {
      return Center(child: Text('ভল্টে কোনো লগইন নেই',
          style: TextStyle(color: AppTheme.textMuted)));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'খোঁজো (নাম / ইউজারনেম)...',
            hintStyle: TextStyle(color: AppTheme.textMuted),
            prefixIcon: Icon(Icons.search, color: AppTheme.textMuted, size: 20),
            isDense: true,
            filled: true, fillColor: AppTheme.bg2,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.border)),
          ),
        ),
      ),
      if (q.isEmpty && _matches.isNotEmpty && !_showAll && _matches.length < _all.length)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            Expanded(child: Text('এই অ্যাপ/সাইটের সাথে মিলে যাওয়া এন্ট্রি',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12))),
            TextButton(
              onPressed: () => setState(() => _showAll = true),
              child: Text('সব দেখাও', style: TextStyle(color: AppTheme.accent, fontSize: 12)),
            ),
          ]),
        ),
      if (q.isEmpty && _matches.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('মিলে যাওয়া এন্ট্রি নেই — সব লগইন দেখানো হচ্ছে',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ),
      Expanded(
        child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) {
            final e = list[i];
            final isLast = e.id == _lastUsedId;
            return ListTile(
              dense: true,
              leading: Icon(isLast ? Icons.history : Icons.lock_outline,
                  color: isLast ? AppTheme.accent : AppTheme.textSecondary),
              title: Text(e.title, style: TextStyle(color: AppTheme.textPrimary)),
              subtitle: Text(
                  '${e.username ?? ''}${isLast ? '  · শেষবার ব্যবহৃত' : ''}',
                  style: TextStyle(color: AppTheme.textMuted)),
              onTap: () async {
                final ok = await _select(e);
                if (!ok) _finish();
              },
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
