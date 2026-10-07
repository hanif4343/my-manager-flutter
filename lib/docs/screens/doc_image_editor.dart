import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../widgets/app_theme.dart';
import '../services/doc_image_ops.dart';

/// ছবি এডিটর খোলে; "সেভ" চাপলে নতুন (JPEG) বাইট ফেরত দেয়, বাতিল হলে null।
Future<Uint8List?> openImageEditor(BuildContext context, Uint8List bytes, {String title = 'ছবি এডিট'}) {
  return Navigator.push<Uint8List>(
    context,
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => DocImageEditor(bytes: bytes, title: title)),
  );
}

enum _Mode { crop, adjust }

enum _Handle { none, tl, tr, bl, br, left, right, top, bottom, move }

class DocImageEditor extends StatefulWidget {
  final Uint8List bytes;
  final String title;
  const DocImageEditor({super.key, required this.bytes, required this.title});
  @override
  State<DocImageEditor> createState() => _DocImageEditorState();
}

class _DocImageEditorState extends State<DocImageEditor> {
  static const double _pad = 22;
  static const double _minSize = 0.08;

  final EditParams _p = EditParams();
  ui.Image? _img;
  _Mode _mode = _Mode.crop;
  _Handle _h = _Handle.none;
  Size _disp = Size.zero;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    DocImageOps.decode(widget.bytes).then((i) {
      if (!mounted) {
        i.dispose();
        return;
      }
      setState(() => _img = i);
    }).catchError((e) {
      if (mounted) setState(() => _err = 'ছবি খোলা যায়নি');
    });
  }

  @override
  void dispose() {
    _img?.dispose();
    super.dispose();
  }

  double get _rw => (_p.quarterTurns.isOdd ? _img!.height : _img!.width).toDouble();
  double get _rh => (_p.quarterTurns.isOdd ? _img!.width : _img!.height).toDouble();

  // ───────── ঘোরানো (ক্রপ বাক্সও সাথে ঘোরে) ─────────

  void _rotate(bool clockwise) {
    setState(() {
      final c = _p.crop;
      if (clockwise) {
        _p.crop = Rect.fromLTRB(1 - c.bottom, c.left, 1 - c.top, c.right);
        _p.quarterTurns = (_p.quarterTurns + 1) % 4;
      } else {
        _p.crop = Rect.fromLTRB(c.top, 1 - c.right, c.bottom, 1 - c.left);
        _p.quarterTurns = (_p.quarterTurns + 3) % 4;
      }
    });
  }

  void _reset() {
    setState(() {
      _p.quarterTurns = 0;
      _p.crop = const Rect.fromLTWH(0, 0, 1, 1);
      _p.brightness = 0;
      _p.contrast = 1;
      _p.saturation = 1;
    });
  }

  // ───────── ক্রপ বাক্স টানা ─────────

  void _onPanStart(DragStartDetails d) {
    if (_mode != _Mode.crop || _disp.isEmpty) return;
    final p = d.localPosition - const Offset(_pad, _pad);
    final r = Rect.fromLTRB(_p.crop.left * _disp.width, _p.crop.top * _disp.height,
        _p.crop.right * _disp.width, _p.crop.bottom * _disp.height);
    const corner = 36.0, edge = 24.0;
    bool near(Offset a) => (p - a).distance < corner;
    if (near(r.topLeft)) {
      _h = _Handle.tl;
    } else if (near(r.topRight)) {
      _h = _Handle.tr;
    } else if (near(r.bottomLeft)) {
      _h = _Handle.bl;
    } else if (near(r.bottomRight)) {
      _h = _Handle.br;
    } else if ((p.dx - r.left).abs() < edge && p.dy > r.top && p.dy < r.bottom) {
      _h = _Handle.left;
    } else if ((p.dx - r.right).abs() < edge && p.dy > r.top && p.dy < r.bottom) {
      _h = _Handle.right;
    } else if ((p.dy - r.top).abs() < edge && p.dx > r.left && p.dx < r.right) {
      _h = _Handle.top;
    } else if ((p.dy - r.bottom).abs() < edge && p.dx > r.left && p.dx < r.right) {
      _h = _Handle.bottom;
    } else if (r.contains(p)) {
      _h = _Handle.move;
    } else {
      _h = _Handle.none;
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_h == _Handle.none || _disp.isEmpty) return;
    final dx = d.delta.dx / _disp.width;
    final dy = d.delta.dy / _disp.height;
    var l = _p.crop.left, t = _p.crop.top, r = _p.crop.right, b = _p.crop.bottom;

    if (_h == _Handle.move) {
      final w = r - l, h = b - t;
      l = (l + dx).clamp(0.0, 1 - w).toDouble();
      t = (t + dy).clamp(0.0, 1 - h).toDouble();
      r = l + w;
      b = t + h;
    } else {
      final moveL = _h == _Handle.tl || _h == _Handle.bl || _h == _Handle.left;
      final moveR = _h == _Handle.tr || _h == _Handle.br || _h == _Handle.right;
      final moveT = _h == _Handle.tl || _h == _Handle.tr || _h == _Handle.top;
      final moveB = _h == _Handle.bl || _h == _Handle.br || _h == _Handle.bottom;
      if (moveL) l = (l + dx).clamp(0.0, r - _minSize).toDouble();
      if (moveR) r = (r + dx).clamp(l + _minSize, 1.0).toDouble();
      if (moveT) t = (t + dy).clamp(0.0, b - _minSize).toDouble();
      if (moveB) b = (b + dy).clamp(t + _minSize, 1.0).toDouble();
    }
    setState(() => _p.crop = Rect.fromLTRB(l, t, r, b));
  }

  // ───────── সেভ / বাতিল ─────────

  Future<void> _apply() async {
    if (_p.isIdentity) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final out = await DocImageOps.render(widget.bytes, _p);
      if (mounted) Navigator.pop(context, out);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = 'সেভ করা যায়নি: $e';
        });
      }
    }
  }

  Future<bool> _confirmLeave() async {
    if (_busy) return false;
    if (_p.isIdentity) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bg2,
        title: const Text('পরিবর্তন বাদ দেবে?'),
        content: const Text('সেভ না করে বের হলে এডিটগুলো হারিয়ে যাবে।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('থাকো')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('বাদ দাও', style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    return ok == true;
  }

  // ───────── UI ─────────

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _confirmLeave,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(widget.title, style: const TextStyle(fontSize: 16)),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () async {
              if (await _confirmLeave() && mounted) Navigator.pop(context);
            },
          ),
          actions: [
            TextButton(
              onPressed: (_busy || _img == null) ? null : _apply,
              child: const Text('সেভ',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ],
        ),
        body: _img == null
            ? Center(
                child: _err != null
                    ? Text(_err!, style: const TextStyle(color: Colors.white70))
                    : const CircularProgressIndicator(color: AppTheme.accent))
            : Stack(children: [
                Column(children: [
                  Expanded(child: _canvas()),
                  _panel(),
                ]),
                if (_busy)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black54,
                      child: const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
                    ),
                  ),
              ]),
      ),
    );
  }

  Widget _canvas() {
    return LayoutBuilder(builder: (ctx, c) {
      final availW = (c.maxWidth - 2 * _pad).clamp(50.0, double.infinity).toDouble();
      final availH = (c.maxHeight - 2 * _pad).clamp(50.0, double.infinity).toDouble();
      final ar = _rw / _rh;
      double dw = availW, dh = availW / ar;
      if (dh > availH) {
        dh = availH;
        dw = availH * ar;
      }
      _disp = Size(dw, dh);

      Widget image = RotatedBox(
        quarterTurns: _p.quarterTurns,
        child: Image.memory(widget.bytes, fit: BoxFit.fill, gaplessPlayback: true),
      );
      if (_p.isColorChanged) {
        image = ColorFiltered(colorFilter: ColorFilter.matrix(_p.matrix), child: image);
      }

      return Center(
        child: SizedBox(
          width: dw + 2 * _pad,
          height: dh + 2 * _pad,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: (_) => _h = _Handle.none,
            child: Stack(children: [
              Positioned(left: _pad, top: _pad, width: dw, height: dh, child: image),
              Positioned(
                left: _pad,
                top: _pad,
                width: dw,
                height: dh,
                child: IgnorePointer(
                  child: CustomPaint(painter: _CropPainter(_p.crop, _mode == _Mode.crop)),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }

  Widget _panel() {
    return Container(
      color: const Color(0xFF111114),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_err != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(_err!, style: TextStyle(color: AppTheme.red, fontSize: 12)),
            ),
          if (_mode == _Mode.crop) _cropHint() else _adjustControls(),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _tool(Icons.crop_rounded, 'ক্রপ', _mode == _Mode.crop, () => setState(() => _mode = _Mode.crop)),
            _tool(Icons.rotate_left_rounded, 'বামে', false, () => _rotate(false)),
            _tool(Icons.rotate_right_rounded, 'ডানে', false, () => _rotate(true)),
            _tool(Icons.tune_rounded, 'অ্যাডজাস্ট', _mode == _Mode.adjust, () => setState(() => _mode = _Mode.adjust)),
            _tool(Icons.restart_alt_rounded, 'রিসেট', false, _reset),
          ]),
        ]),
      ),
    );
  }

  Widget _tool(IconData icon, String label, bool selected, VoidCallback onTap) {
    final color = selected ? Colors.white : Colors.white60;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent.withOpacity(0.85) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _cropHint() {
    return Row(children: [
      const Expanded(
        child: Text('কোণা বা কিনারা টেনে ক্রপ করো, ভেতরে টেনে সরাও',
            style: TextStyle(color: Colors.white60, fontSize: 12)),
      ),
      TextButton(
        onPressed: _p.isCropped ? () => setState(() => _p.crop = const Rect.fromLTWH(0, 0, 1, 1)) : null,
        child: const Text('পুরো ছবি'),
      ),
    ]);
  }

  Widget _adjustControls() {
    Widget slider(String label, double v, double min, double max, double neutral, ValueChanged<double> on) {
      return Row(children: [
        SizedBox(
          width: 92,
          child: GestureDetector(
            onDoubleTap: () => on(neutral),
            child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              activeTrackColor: AppTheme.accent,
              thumbColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(value: v.clamp(min, max).toDouble(), min: min, max: max, onChanged: on),
          ),
        ),
      ]);
    }

    void preset(double b, double c, double s) => setState(() {
          _p.brightness = b;
          _p.contrast = c;
          _p.saturation = s;
        });

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: 8, children: [
        _chip('মূল', () => preset(0, 1, 1)),
        _chip('স্ক্যান (সাদা-কালো)', () => preset(0.1, 1.45, 0)),
        _chip('উজ্জ্বল', () => preset(0.12, 1.1, 1.05)),
      ]),
      slider('উজ্জ্বলতা', _p.brightness, -0.5, 0.5, 0, (v) => setState(() => _p.brightness = v)),
      slider('কনট্রাস্ট', _p.contrast, 0.6, 1.6, 1, (v) => setState(() => _p.contrast = v)),
      slider('রঙের গাঢ়তা', _p.saturation, 0, 2, 1, (v) => setState(() => _p.saturation = v)),
    ]);
  }

  Widget _chip(String t, VoidCallback onTap) => ActionChip(
        label: Text(t, style: const TextStyle(fontSize: 11.5, color: Colors.white)),
        backgroundColor: Colors.white12,
        side: BorderSide.none,
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
      );
}

class _CropPainter extends CustomPainter {
  final Rect crop; // ০..১
  final bool active;
  _CropPainter(this.crop, this.active);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(
        crop.left * size.width, crop.top * size.height, crop.right * size.width, crop.bottom * size.height);

    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addRect(r)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = Colors.black.withOpacity(0.55));

    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 1.6 : 1
        ..color = Colors.white,
    );
    if (!active) return;

    final grid = Paint()
      ..strokeWidth = 0.7
      ..color = Colors.white38;
    for (var i = 1; i <= 2; i++) {
      final x = r.left + r.width * i / 3;
      final y = r.top + r.height * i / 3;
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), grid);
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
    }

    final dot = Paint()..color = Colors.white;
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      canvas.drawCircle(c, 8, dot);
    }
    for (final c in [r.centerLeft, r.centerRight, r.topCenter, r.bottomCenter]) {
      canvas.drawCircle(c, 4.5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) => old.crop != crop || old.active != active;
}
