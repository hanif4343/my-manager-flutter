import 'package:flutter/material.dart';
import 'package:flutter_autofill_service/flutter_autofill_service.dart';
import '../models/vault_entry.dart';
import '../services/vault_service.dart';
import '../services/auth_service.dart';
import '../widgets/app_theme.dart';

/// Root widget for the autofillEntryPoint() — this is what's on screen
/// when Android asks "does the user want to autofill this login form?"
/// (or "should this new login be saved?") and launches our app to find
/// out. Requires the same fingerprint/PIN check as opening the main
/// Vault screen, since this is a second route into the same secrets.
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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ok = await AuthService.authenticate(reason: 'Autofill-এর জন্য যাচাই করো');
    if (!ok) {
      setState(() { _authFailed = true; _loading = false; });
      return;
    }
    await _load();
  }

  /// Reduces a hostname to its "registrable" part for matching, so
  /// m.facebook.com / accounts.facebook.com / www.facebook.com all match
  /// a Vault entry saved against plain facebook.com. Not a full public-
  /// suffix-list implementation — just the last two dot-separated labels,
  /// which covers the vast majority of real sites.
  String _registrableDomain(String host) {
    final parts = host.toLowerCase().split('.');
    if (parts.length <= 2) return parts.join('.');
    return parts.sublist(parts.length - 2).join('.');
  }

  Future<void> _load() async {
    // NOTE: fillRequestedInteractive is just a bool ("was this launch
    // triggered by an interactive fill request") — the actual metadata
    // (which app/site, and any pending save info) comes from the
    // separate `autofillMetadata` property instead. An earlier version
    // of this screen mistakenly tried to read metadata off
    // fillRequestedInteractive, which meant matching never worked and
    // every launch silently fell back to showing the entire vault.
    AutofillMetadata? metadata;
    try {
      metadata = await AutofillService().autofillMetadata;
    } catch (_) {
      // Not fatal — we just won't be able to narrow down by app/site,
      // and will show every login instead.
    }

    final saveInfo = metadata?.saveInfo;
    if (saveInfo != null) {
      final domains = metadata?.webDomains?.map((d) => d.domain).toList() ?? const [];
      final pkgs = metadata?.packageNames?.toList() ?? const [];
      setState(() {
        _saveInfo = saveInfo;
        _saveSiteLabel = domains.isNotEmpty ? domains.first : (pkgs.isNotEmpty ? pkgs.first : null);
        _loading = false;
      });
      return; // Save flow doesn't need the login list at all.
    }

    final all = await VaultService.getAll();
    final logins = all.where((e) => e.type == 'login').toList();

    final pkgs = metadata?.packageNames ?? const <String>{};
    final domains = metadata?.webDomains?.map((d) => d.domain).toList() ?? const <String>[];
    final wantedRegistrableDomains = domains.map(_registrableDomain).toSet();

    List<VaultEntry> matches = logins.where((e) {
      final url = (e.url ?? '').toLowerCase();
      final title = e.title.toLowerCase();
      for (final p in pkgs) {
        final needle = p.toLowerCase();
        if (url.contains(needle) || title.contains(needle)) return true;
      }
      if (url.isNotEmpty && wantedRegistrableDomains.isNotEmpty) {
        // Pull a rough hostname out of the saved URL (works whether it
        // was stored with a scheme, with a path, or as a bare domain).
        final hostGuess = url.replaceFirst(RegExp(r'^[a-z]+://'), '').split('/').first;
        if (wantedRegistrableDomains.contains(_registrableDomain(hostGuess))) return true;
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
      // If returning the result fails for some reason, there's nothing
      // more we can do here — the calling app will just show no
      // suggestion, same as if the vault had nothing matching.
    }
  }

  Future<void> _saveNewLogin(String title, String username, String password) async {
    final n = DateTime.now().millisecondsSinceEpoch;
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
    try {
      await AutofillService().onSaveComplete();
    } catch (_) {
      // The save already succeeded in our own Vault regardless of
      // whether we could tell Android's autofill framework we're done.
    }
    if (mounted) Navigator.of(context).maybePop();
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
            ? Center(child: Text('যাচাই ব্যর্থ হয়েছে — আবার চেষ্টা করো',
                style: TextStyle(color: AppTheme.textMuted)))
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
    final usernameCtrl = TextEditingController(text: _saveInfo?.username ?? '');
    final titleCtrl = TextEditingController(text: _saveSiteLabel ?? '');
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('My Manager-এর ভল্টে এই লগইনটা সংরক্ষণ করবে?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 20),
        Text('নাম', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: titleCtrl, style: TextStyle(color: AppTheme.textPrimary)),
        const SizedBox(height: 16),
        Text('ইউজারনেম', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: usernameCtrl, style: TextStyle(color: AppTheme.textPrimary)),
        const SizedBox(height: 16),
        Text('পাসওয়ার্ড পাওয়া গেছে ✓', style: TextStyle(color: AppTheme.green, fontSize: 12)),
        const Spacer(),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                try { await AutofillService().onSaveComplete(); } catch (_) {}
                if (mounted) Navigator.of(context).maybePop();
              },
              child: const Text('না থাক'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.white),
              onPressed: () => _saveNewLogin(
                titleCtrl.text.trim().isEmpty ? 'নতুন লগইন' : titleCtrl.text.trim(),
                usernameCtrl.text.trim(),
                _saveInfo?.password ?? '',
              ),
              child: const Text('ভল্টে সংরক্ষণ করো'),
            ),
          ),
        ]),
      ]),
    );
  }
}
