import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Rect, Canvas, Paint, Color, ColorFilter, Offset, FilterQuality, BlendMode;
import 'package:image/image.dart' as img;

/// এডিটের সব সেটিং। প্রিভিউ আর চূড়ান্ত রেন্ডার একই [colorMatrix] ব্যবহার করে,
/// তাই যা দেখা যায় ঠিক তাই সেভ হয়।
class EditParams {
  int quarterTurns; // ঘড়ির কাঁটার দিকে ৯০° × n
  Rect crop; // ঘোরানোর পরের ছবির উপর, ০..১ স্কেলে
  double brightness; // -0.5 .. 0.5
  double contrast; // 0.6 .. 1.6
  double saturation; // 0 .. 2

  EditParams({
    this.quarterTurns = 0,
    this.crop = const Rect.fromLTWH(0, 0, 1, 1),
    this.brightness = 0,
    this.contrast = 1,
    this.saturation = 1,
  });

  bool get isCropped =>
      crop.left > 0.001 || crop.top > 0.001 || crop.right < 0.999 || crop.bottom < 0.999;
  bool get isColorChanged => brightness != 0 || contrast != 1 || saturation != 1;
  bool get isIdentity => quarterTurns % 4 == 0 && !isCropped && !isColorChanged;

  List<double> get matrix => DocImageOps.colorMatrix(brightness, contrast, saturation);
}

class DocImageOps {
  /// সরল ম্যাট্রিক্স: স্যাচুরেশন → কনট্রাস্ট → উজ্জ্বলতা (০–২৫৫ স্কেলে অফসেট)।
  static List<double> colorMatrix(double brightness, double contrast, double saturation) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final s = saturation;
    final c = contrast;
    final t = (0.5 - 0.5 * c) * 255 + brightness * 255;
    return <double>[
      c * (lr * (1 - s) + s), c * (lg * (1 - s)), c * (lb * (1 - s)), 0, t,
      c * (lr * (1 - s)), c * (lg * (1 - s) + s), c * (lb * (1 - s)), 0, t,
      c * (lr * (1 - s)), c * (lg * (1 - s)), c * (lb * (1 - s) + s), 0, t,
      0, 0, 0, 1, 0,
    ];
  }

  static Future<ui.Image> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  /// ঘোরানো + ক্রপ + রঙ বদল করে JPEG বাইট দেয়।
  static Future<Uint8List> render(Uint8List src, EditParams p, {int quality = 90}) async {
    final image = await decode(src);
    final q = p.quarterTurns % 4;
    final rw = (q.isOdd ? image.height : image.width).toDouble();
    final rh = (q.isOdd ? image.width : image.height).toDouble();

    final c = p.crop;
    final left = (c.left * rw).roundToDouble();
    final top = (c.top * rh).roundToDouble();
    final outW = ((c.width * rw).round()).clamp(1, rw.toInt()).toInt();
    final outH = ((c.height * rh).round()).clamp(1, rh.toInt()).toInt();

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()));
    canvas.drawColor(const Color(0xFFFFFFFF), BlendMode.src);
    canvas.translate(-left, -top);
    switch (q) {
      case 1:
        canvas.translate(image.height.toDouble(), 0);
        canvas.rotate(1.5707963267948966);
        break;
      case 2:
        canvas.translate(image.width.toDouble(), image.height.toDouble());
        canvas.rotate(3.141592653589793);
        break;
      case 3:
        canvas.translate(0, image.width.toDouble());
        canvas.rotate(4.71238898038469);
        break;
    }
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;
    if (p.isColorChanged) paint.colorFilter = ColorFilter.matrix(p.matrix);
    canvas.drawImage(image, Offset.zero, paint);

    final out = await rec.endRecording().toImage(outW, outH);
    final bd = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    out.dispose();
    if (bd == null) throw StateError('ছবি রেন্ডার করা যায়নি');
    final rgba = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
    return Isolate.run(() => _encodeJpg(rgba, outW, outH, quality));
  }

  static Uint8List _encodeJpg(Uint8List rgba, int w, int h, int quality) {
    final im = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: Uint8List.fromList(rgba).buffer,
      numChannels: 4,
    );
    return Uint8List.fromList(img.encodeJpg(im, quality: quality));
  }
}
