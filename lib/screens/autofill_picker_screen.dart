import 'package:flutter/material.dart';
import 'package:flutter_autofill_service/flutter_autofill_service.dart';
import '../models/vault_entry.dart';
import '../services/vault_service.dart';
import '../services/auth_service.dart';
import '../widgets/app_theme.dart';

/// Root widget for the autofillEntryPoint() — this is what's on screen
/// when Android asks "does the user want to autofill this login form?"
/// and launches our app to find out. Requires the same fingerprint/PIN
/// check as opening the main Vault screen, since this is a second route
/// into the same secrets.
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

  Future<void> _load() async {
    AutofillMetadata? metadata;
    try {
      metadata = await AutofillService().fillRequestedInteractive;
    } catch (_) {
      // Not fatal — we just won't be able to narrow down by app/site,
      // and will show every login instead.
    }

    final all = await VaultService.getAll();
    final logins = all.where((e) => e.type == 'login').toList();

    final pkgs = metadata?.packageNames ?? const <String>[];
    final domains = metadata?.webDomains?.map((d) => d.domain).toList() ?? const <String>[];

    List<VaultEntry> matches = logins.where((e) {
      final url = (e.url ?? '').toLowerCase();
      final title = e.title.toLowerCase();
      for (final p in pkgs) {
        final needle = p.toLowerCase();
        if (url.contains(needle) || title.contains(needle)) return true;
      }
      for (final d in domains) {
        if (url.contains(d.toLowerCase())) return true;
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(title: const Text('My Manager থেকে বাছো')),
        body: _authFailed
            ? Center(child: Text('যাচাই ব্যর্থ হয়েছে — আবার চেষ্টা করো',
                style: TextStyle(color: AppTheme.textMuted)))
            : _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
                : _buildList(),
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
}
