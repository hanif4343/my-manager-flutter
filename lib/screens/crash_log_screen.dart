import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/crash_log_service.dart';
import '../widgets/app_theme.dart';

/// Reached from Settings. Shown on demand rather than as an automatic
/// popup, since a crash severe or early enough (e.g. the Android system
/// failing to even bind a declared <service>) can kill the app before
/// Flutter's engine boots far enough to show a dialog — a page the
/// person can open whenever they remember to check is more reliable
/// than a one-shot popup that might get missed.
class CrashLogScreen extends StatefulWidget {
  const CrashLogScreen({super.key});
  @override State<CrashLogScreen> createState() => _CrashLogScreenState();
}

class _CrashLogScreenState extends State<CrashLogScreen> {
  String? _text;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await CrashLogService.read();
    if (mounted) setState(() { _text = t; _loading = false; });
  }

  Future<void> _copy() async {
    if (_text == null) return;
    await Clipboard.setData(ClipboardData(text: _text!));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('কপি হয়েছে')));
    }
  }

  Future<void> _clear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('লগ মুছে ফেলবে?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('বাতিল')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('মুছে ফেলো')),
        ],
      ),
    );
    if (confirm == true) {
      await CrashLogService.clear();
      if (mounted) setState(() { _text = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('ক্র্যাশ লগ'),
        actions: [
          if (_text != null) IconButton(icon: const Icon(Icons.copy), onPressed: _copy),
          if (_text != null) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clear),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () { setState(() => _loading = true); _load(); }),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _text == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check_circle_outline, size: 40, color: AppTheme.green),
                      const SizedBox(height: 12),
                      Text('কোনো ক্র্যাশ রেকর্ড নেই', style: AppTheme.body()),
                      const SizedBox(height: 4),
                      Text('অ্যাপ ক্র্যাশ করলে সেটার বিস্তারিত এখানে দেখা যাবে',
                          style: AppTheme.caption(), textAlign: TextAlign.center),
                    ]),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('একের অধিক ক্র্যাশ হলে সবগুলো নিচে সময়ক্রম অনুযায়ী জমা আছে —',
                        style: AppTheme.caption()),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppTheme.bg2, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
                        child: SingleChildScrollView(
                          child: SelectableText(_text!,
                              style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _copy,
                          icon: const Icon(Icons.copy),
                          label: const Text('পুরোটা কপি করো'),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.white),
                        ),
                      ),
                    ]),
                  ]),
                ),
    );
  }
}
