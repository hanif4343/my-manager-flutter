import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../family/screens/family_ui.dart';
import '../../reminder/models/reminder.dart' show bn, formatDateBn;
import '../../widgets/app_theme.dart';
import '../models/doc_models.dart';
import '../services/docs_crypto.dart';
import '../services/docs_service.dart';
import 'doc_form_sheet.dart';
import 'docs_home_screen.dart';

/// একটা ডকুমেন্টের বিস্তারিত: নম্বর (দেখাও/কপি), মেয়াদ, পাতাগুলো, শেয়ার, এডিট, মুছো।
class DocViewerScreen extends StatefulWidget {
  final VaultDoc doc;
  const DocViewerScreen({super.key, required this.doc});
  @override State<DocViewerScreen> createState() => _DocViewerScreenState();
}

class _DocViewerScreenState extends State<DocViewerScreen> {
  late VaultDoc _doc;
  String _number = '';
  bool _showNumber = false;
  final Map<String, Future<Uint8List>> _cache = {};

  @override
  void initState() {
    super.initState();
    _doc = widget.doc;
    _loadNumber();
  }

  Future<void> _loadNumber() async {
    final n = await DocsService.numberOf(_doc);
    if (mounted) setState(() => _number = n);
  }

  Future<Uint8List> _bytes(DocPage p) => _cache.putIfAbsent(p.fileId, () => DocsCrypto.readFile(p.fileId));

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<File> _tempFile(DocPage p) async {
    final dir = await getTemporaryDirectory();
    final ext = p.isPdf ? 'pdf' : (p.mime == 'image/png' ? 'png' : 'jpg');
    final f = File('${dir.path}/docs_tmp_${p.fileId}.$ext');
    await f.writeAsBytes(await _bytes(p), flush: true);
    return f;
  }

  Future<void> _share() async {
    if (_doc.pages.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bg2,
        title: const Text('শেয়ার করবে?'),
        content: const Text('ফাইলটা এনক্রিপশন ছাড়া সাধারণ ছবি/PDF হিসেবে বেরিয়ে যাবে। যার কাছে পাঠাবে সে সবার মতোই দেখতে পাবে।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('না')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('শেয়ার করো', style: TextStyle(color: AppTheme.accent))),
        ],
      ),
    );
    if (ok != true) return;
    DocsHomeScreen.suppressAutoLock = true;
    try {
      final files = <XFile>[];
      for (final p in _doc.pages) {
        files.add(XFile((await _tempFile(p)).path));
      }
      await Share.shareXFiles(files, text: _doc.title);
    } catch (e) {
      _snack('শেয়ার ব্যর্থ: $e');
    } finally {
      DocsHomeScreen.suppressAutoLock = false;
    }
  }

  Future<void> _edit() async {
    final saved = await showDocForm(context, existing: _doc);
    if (saved) {
      final list = await DocsService.list();
      final fresh = list.where((d) => d.id == _doc.id).toList();
      if (fresh.isNotEmpty && mounted) {
        _cache.clear();
        setState(() { _doc = fresh.first; _showNumber = false; });
        _loadNumber();
      }
    }
  }

  Future<void> _delete() async {
    if (!await fConfirm(context, 'মুছে ফেলবে?', '"${_doc.title}" ও এর সব ফাইল চিরতরে মুছে যাবে। ফেরানো যাবে না!')) return;
    await DocsService.delete(_doc);
    if (mounted) Navigator.pop(context, true);
  }

  Color _expColor(int d) => d < 0 ? AppTheme.red : (d <= 30 ? AppTheme.yellow : AppTheme.green);

  @override
  Widget build(BuildContext context) {
    final cat = docCategories[_doc.category] ?? docCategories['other']!;
    final d = _doc.daysToExpiry;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(_doc.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (_doc.pages.isNotEmpty) IconButton(icon: const Icon(Icons.ios_share_rounded), onPressed: _share, tooltip: 'শেয়ার'),
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _edit, tooltip: 'এডিট'),
          IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete, tooltip: 'মুছো'),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
        fCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(cat.$1, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Text(cat.$2, style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (d != null)
                fChip(
                  d < 0 ? 'মেয়াদ ${bn(-d)} দিন আগে শেষ' : (d == 0 ? 'আজ মেয়াদ শেষ' : 'মেয়াদ আর ${bn(d)} দিন'),
                  _expColor(d),
                ),
            ]),
            if (_doc.expiry != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('মেয়াদ শেষ: ${formatDateBn(_doc.expiry!)}',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
              ),
            if (_doc.numberEnc.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('ডকুমেন্ট নম্বর', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              const SizedBox(height: 2),
              Row(children: [
                Expanded(
                  child: Text(
                    _number.isEmpty ? '…' : (_showNumber ? _number : '•' * _number.length.clamp(6, 16)),
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, letterSpacing: _showNumber ? 0.5 : 2, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: Icon(_showNumber ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                  onPressed: () => setState(() => _showNumber = !_showNumber),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: _number.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: _number));
                          _snack('কপি হয়েছে — ৩০ সেকেন্ড পর ক্লিপবোর্ড সাফ হবে');
                          Future.delayed(const Duration(seconds: 30), () async {
                            final c = await Clipboard.getData('text/plain');
                            if (c?.text == _number) await Clipboard.setData(const ClipboardData(text: ''));
                          });
                        },
                ),
              ]),
            ],
            if (_doc.note.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_doc.note, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.45)),
            ],
          ]),
        ),
        if (_doc.pages.isEmpty)
          fEmpty(Icons.image_not_supported_outlined, 'কোনো ফাইল সংযুক্ত নেই।\nউপরের এডিট বাটনে ট্যাপ করে ছবি/PDF যোগ করো।')
        else ...[
          fSection('পাতা (${bn(_doc.pages.length)}টা)'),
          for (var i = 0; i < _doc.pages.length; i++) _pageTile(i),
        ],
      ]),
    );
  }

  Widget _pageTile(int i) {
    final p = _doc.pages[i];
    return fCard(
      padding: const EdgeInsets.all(8),
      onTap: () {
        if (p.isPdf) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => _PdfPageScreen(page: p, title: _doc.title, tempFile: _tempFile)));
        } else {
          final imgs = _doc.pages.where((x) => !x.isPdf).toList();
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => _ImagesScreen(title: _doc.title, pages: imgs, initial: imgs.indexOf(p), bytes: _bytes),
          ));
        }
      },
      child: p.isPdf
          ? Row(children: [
              Container(
                width: 54, height: 54,
                decoration: BoxDecoration(color: AppTheme.red.withOpacity(0.14), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.picture_as_pdf_rounded, color: AppTheme.red),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 14))),
              Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
            ])
          : ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: FutureBuilder<Uint8List>(
                future: _bytes(p),
                builder: (_, snap) {
                  if (!snap.hasData) {
                    return SizedBox(
                      height: 160,
                      child: Center(
                        child: snap.hasError
                            ? Text('খোলা যায়নি', style: TextStyle(color: AppTheme.red))
                            : const CircularProgressIndicator(color: AppTheme.accent),
                      ),
                    );
                  }
                  return Image.memory(snap.data!, height: 200, width: double.infinity, fit: BoxFit.cover, cacheWidth: 900);
                },
              ),
            ),
    );
  }

  @override
  void dispose() {
    // খোলা অবস্থায় বানানো সাময়িক ডিক্রিপ্টেড ফাইল সাফ।
    getTemporaryDirectory().then((dir) {
      try {
        for (final e in dir.listSync()) {
          if (e is File && e.uri.pathSegments.last.startsWith('docs_tmp_')) e.deleteSync();
        }
      } catch (_) {}
    });
    super.dispose();
  }
}

class _ImagesScreen extends StatefulWidget {
  final String title;
  final List<DocPage> pages;
  final int initial;
  final Future<Uint8List> Function(DocPage) bytes;
  const _ImagesScreen({required this.title, required this.pages, required this.initial, required this.bytes});
  @override State<_ImagesScreen> createState() => _ImagesScreenState();
}

class _ImagesScreenState extends State<_ImagesScreen> {
  late final PageController _pc = PageController(initialPage: widget.initial < 0 ? 0 : widget.initial);
  late int _i = widget.initial < 0 ? 0 : widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('${widget.title} · ${bn(_i + 1)}/${bn(widget.pages.length)}'),
      ),
      body: PageView.builder(
        controller: _pc,
        itemCount: widget.pages.length,
        onPageChanged: (v) => setState(() => _i = v),
        itemBuilder: (_, idx) => FutureBuilder<Uint8List>(
          future: widget.bytes(widget.pages[idx]),
          builder: (_, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
            return InteractiveViewer(minScale: 1, maxScale: 6, child: Center(child: Image.memory(snap.data!)));
          },
        ),
      ),
    );
  }
}

class _PdfPageScreen extends StatefulWidget {
  final DocPage page;
  final String title;
  final Future<File> Function(DocPage) tempFile;
  const _PdfPageScreen({required this.page, required this.title, required this.tempFile});
  @override State<_PdfPageScreen> createState() => _PdfPageScreenState();
}

class _PdfPageScreenState extends State<_PdfPageScreen> {
  String? _path;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.tempFile(widget.page).then((f) {
      if (mounted) setState(() => _path = f.path);
    }).catchError((e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: _error != null
          ? Center(child: Text('PDF খোলা যায়নি: $_error', style: TextStyle(color: AppTheme.red)))
          : (_path == null
              ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
              : PDFView(filePath: _path!, enableSwipe: true, autoSpacing: true, pageFling: true)),
    );
  }
}
