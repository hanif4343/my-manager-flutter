import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../reminder/models/reminder.dart' show bn;
import '../../widgets/app_theme.dart';
import '../models/doc_models.dart';
import '../services/doc_image_ops.dart';
import '../services/docs_service.dart';
import 'doc_image_editor.dart';
import 'doc_share_sheet.dart';

/// পুরো স্ক্রিনের ছবি-দেখা: সোয়াইপে পাতা বদল, পিঞ্চ/ডাবল-ট্যাপে জুম,
/// নিচে এডিট (ক্রপ, ঘোরানো, অ্যাডজাস্ট) ও শেয়ার।
/// এডিট করলে ডকুমেন্টের আসল পাতা বদলে যায় ([doc] নিজেই আপডেট হয়)।
class DocImageViewer extends StatefulWidget {
  final VaultDoc doc;
  final List<DocPage> pages; // শুধু ছবির পাতা
  final int initial;
  final Future<Uint8List> Function(DocPage) bytes;
  const DocImageViewer({
    super.key,
    required this.doc,
    required this.pages,
    required this.initial,
    required this.bytes,
  });
  @override
  State<DocImageViewer> createState() => _DocImageViewerState();
}

class _DocImageViewerState extends State<DocImageViewer> {
  late final PageController _pc;
  late List<DocPage> _pages;
  late int _i;
  bool _zoomed = false;
  bool _busy = false;
  final Map<String, int> _rev = {}; // এডিটের পর ছবি নতুন করে লোড করাতে

  @override
  void initState() {
    super.initState();
    _pages = [...widget.pages];
    _i = widget.initial < 0 ? 0 : widget.initial;
    _pc = PageController(initialPage: _i);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  DocPage get _cur => _pages[_i];

  String get _label {
    final idx = widget.doc.pages.indexWhere((p) => p.fileId == _cur.fileId);
    return idx < 0 ? 'পাতা' : widget.doc.pageLabel(idx);
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _replace(Uint8List out) async {
    final fresh = await DocsService.replacePage(widget.doc, _cur, out);
    if (!mounted) return;
    setState(() {
      _pages[_i] = fresh;
      _rev[fresh.fileId] = (_rev[fresh.fileId] ?? 0) + 1;
      _zoomed = false;
    });
  }

  Future<void> _edit() async {
    try {
      final b = await widget.bytes(_cur);
      if (!mounted) return;
      final out = await openImageEditor(context, b, title: _label);
      if (out == null || !mounted) return;
      setState(() => _busy = true);
      await _replace(out);
      _snack('এডিট সেভ হয়েছে');
    } catch (e) {
      _snack('এডিট ব্যর্থ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// এক চাপে ৯০° ঘুরিয়ে সেভ (উল্টো ছবির জন্য সবচেয়ে দ্রুত)।
  Future<void> _quickRotate() async {
    setState(() => _busy = true);
    try {
      final b = await widget.bytes(_cur);
      final out = await DocImageOps.render(b, EditParams(quarterTurns: 1));
      await _replace(out);
    } catch (e) {
      _snack('ঘোরানো যায়নি: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('$_label · ${bn(_i + 1)}/${bn(_pages.length)}', style: const TextStyle(fontSize: 16)),
      ),
      body: Stack(children: [
        PageView.builder(
          controller: _pc,
          physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
          itemCount: _pages.length,
          onPageChanged: (v) => setState(() {
            _i = v;
            _zoomed = false;
          }),
          itemBuilder: (_, idx) {
            final p = _pages[idx];
            return _ZoomPage(
              key: ValueKey('${p.fileId}_${_rev[p.fileId] ?? 0}'),
              future: widget.bytes(p),
              onZoom: (z) {
                if (idx == _i && z != _zoomed) setState(() => _zoomed = z);
              },
            );
          },
        ),
        if (_busy)
          Positioned.fill(
            child: Container(
              color: Colors.black45,
              child: const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
            ),
          ),
      ]),
      bottomNavigationBar: Container(
        color: Colors.black,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _action(Icons.tune_rounded, 'এডিট', _busy ? null : _edit),
              _action(Icons.rotate_right_rounded, 'ঘোরাও', _busy ? null : _quickRotate),
              _action(Icons.ios_share_rounded, 'পাঠাও', _busy ? null : () => showDocShareSheet(context, widget.doc, only: _cur)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap) {
    final c = onTap == null ? Colors.white30 : Colors.white;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: c, size: 24),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(color: c, fontSize: 11.5)),
        ]),
      ),
    );
  }
}

class _ZoomPage extends StatefulWidget {
  final Future<Uint8List> future;
  final ValueChanged<bool> onZoom;
  const _ZoomPage({super.key, required this.future, required this.onZoom});
  @override
  State<_ZoomPage> createState() => _ZoomPageState();
}

class _ZoomPageState extends State<_ZoomPage> {
  final TransformationController _tc = TransformationController();
  Offset _tap = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _tc.addListener(() {
      final z = _tc.value.getMaxScaleOnAxis() > 1.02;
      if (z != _zoomed) {
        _zoomed = z;
        widget.onZoom(z);
      }
    });
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (_zoomed) {
      _tc.value = Matrix4.identity();
    } else {
      const s = 2.6;
      _tc.value = Matrix4.identity()
        ..translate(-_tap.dx * (s - 1), -_tap.dy * (s - 1))
        ..scale(s);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: widget.future,
      builder: (_, snap) {
        if (snap.hasError) {
          return Center(child: Text('খোলা যায়নি', style: TextStyle(color: AppTheme.red)));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
        }
        return GestureDetector(
          onDoubleTapDown: (d) => _tap = d.localPosition,
          onDoubleTap: _toggleZoom,
          child: InteractiveViewer(
            transformationController: _tc,
            minScale: 1,
            maxScale: 6,
            child: Center(
              child: Image.memory(
                snap.data!,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
                gaplessPlayback: true,
              ),
            ),
          ),
        );
      },
    );
  }
}
