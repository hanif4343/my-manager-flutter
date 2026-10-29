import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as xls;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../reminder/models/reminder.dart' show bn;
import '../models/cashbook_entry.dart';
import '../models/cashbook_account.dart';
import '../services/cashbook_service.dart';

class CashbookExportService {
  static String _fmt(double v) {
    final n = v.round();
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final posFromEnd = s.length - i;
      if (i != 0 && posFromEnd % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '৳$buf';
  }

  static String _accName(List<CashbookAccount> accounts, int id) =>
      accounts.firstWhere((a) => a.id == id, orElse: () => CashbookAccount(name: '—', icon: '', createdAt: 0)).name;

  // ───────────────────────── PDF ─────────────────────────
  //
  // কেন ছবি-ভিত্তিক পেজ: `pdf` প্যাকেজ বাংলা যুক্তাক্ষর/কার-চিহ্ন ঠিকমতো সাজাতে পারে না, আর ফন্ট
  // ইন্টারনেট থেকে নামাতে হতো (অফলাইনে চুপচাপ ব্যর্থ)। এখন প্রতিটা পেজ ফ্লাটারের নিজের টেক্সট ইঞ্জিনে
  // (অ্যাপে যেভাবে বাংলা দেখায় ঠিক সেভাবে) আঁকা হয়, তারপর PDF-এ বসানো — ইন্টারনেট লাগে না।
  // এক সময়ে একটা হিসাব (মাস) এবং পেজ ধরে ধরে তৈরি, মাঝে UI-কে ছেড়ে দেওয়া হয়, তাই ফোন আটকায় না।
  // (ছবি-ভিত্তিক বলে PDF-এর লেখা সিলেক্ট/কপি করা যায় না — Excel এক্সপোর্টে ডেটা কপি করা যায়।)

  static const double _pageW = 595, _pageH = 842, _m = 32, _scale = 2.5;
  static const double _wDate = 66, _wCat = 100, _wIn = 94, _wOut = 94;
  static double get _wNote => _pageW - 2 * _m - _wDate - _wCat - _wIn - _wOut;
  static const double _hdrH = 24, _firstTop = 156, _otherTop = 32, _bottom = _pageH - 44;

  static const _ink = Color(0xFF1B1B1F);
  static const _muted = Color(0xFF6B6B73);
  static const _green = Color(0xFF1B7F3B);
  static const _red = Color(0xFFC62828);

  static TextStyle _style(double size, {bool bold = false, Color color = _ink}) => GoogleFonts.notoSansBengali(
        fontSize: size,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        color: color,
        height: 1.3,
      );

  static TextPainter _tp(String text, double size,
      {bool bold = false, Color color = _ink, double width = double.infinity, TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: _style(size, bold: bold, color: color)),
      textDirection: TextDirection.ltr,
      textAlign: align,
    );
    if (width.isFinite) {
      tp.layout(minWidth: width, maxWidth: width);
    } else {
      tp.layout();
    }
    return tp;
  }

  static String _fmtBn(double v) => bn(_fmt(v));

  static String _dateBn(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? bn(iso) : bn('${d.day}/${d.month}/${d.year}');
  }

  /// [entries] অবশ্যই একটা হিসাবের (মাসের) এন্ট্রি। PDF ফাইল বানিয়ে ফেরত দেয় (শেয়ার আলাদা: [sharePdf])।
  /// [onProgress] — "পৃষ্ঠা ২/৫…" ধরনের বার্তা (প্রগ্রেস দেখাতে)।
  static Future<File> exportPdf({
    required String title,
    String subtitle = '',
    required List<CashbookEntry> entries,
    required List<CashbookAccount> accounts,
    void Function(String)? onProgress,
  }) async {
    if (entries.isEmpty) throw 'এই হিসাবে কোনো এন্ট্রি নেই';
    onProgress?.call('ফন্ট প্রস্তুত হচ্ছে…');
    try {
      // অ্যাপের ফন্ট (Noto Sans Bengali) ক্যাশে না থাকলে নামিয়ে নেওয়ার চেষ্টা; না পারলে সিস্টেমের বাংলা ফন্ট
      await GoogleFonts.pendingFonts([
        GoogleFonts.notoSansBengali(),
        GoogleFonts.notoSansBengali(fontWeight: FontWeight.w700),
      ]).timeout(const Duration(seconds: 8));
    } catch (_) {}

    final sorted = [...entries]..sort((a, b) {
        final c = a.date.compareTo(b.date);
        return c != 0 ? c : (a.id ?? 0).compareTo(b.id ?? 0);
      });
    final totalIn = sorted.where((e) => e.type == 'in').fold<double>(0, (s, e) => s + e.amount);
    final totalOut = sorted.where((e) => e.type == 'out').fold<double>(0, (s, e) => s + e.amount);

    // ── সারির উচ্চতা আগে মেপে নিই (নোট লম্বা হলে একাধিক লাইন) ──
    final rows = <_Row>[];
    for (final e in sorted) {
      final cat = CashbookService.categoryById(e.category);
      final date = _tp(_dateBn(e.date), 9, width: _wDate - 6);
      final catP = _tp('${cat.icon} ${cat.name}', 9, width: _wCat - 6);
      final note = _tp(e.note.isEmpty ? '' : e.note, 9, width: _wNote - 6);
      final inP = _tp(e.type == 'in' ? _fmtBn(e.amount) : '', 9, bold: true, color: _green, width: _wIn - 8, align: TextAlign.right);
      final outP = _tp(e.type == 'out' ? _fmtBn(e.amount) : '', 9, bold: true, color: _red, width: _wOut - 8, align: TextAlign.right);
      final h = [date.height, catP.height, note.height, inP.height, outP.height].reduce((a, b) => a > b ? a : b) + 9;
      rows.add(_Row(date, catP, note, inP, outP, h));
    }

    // ── পেজে ভাগ ──
    const totalsH = 28.0;
    final pages = <List<_Row>>[];
    var cur = <_Row>[];
    var y = _firstTop + _hdrH;
    for (final r in rows) {
      if (y + r.h > _bottom && cur.isNotEmpty) {
        pages.add(cur);
        cur = [];
        y = _otherTop + _hdrH;
      }
      cur.add(r);
      y += r.h;
    }
    if (y + totalsH > _bottom) {
      pages.add(cur);
      cur = []; // মোট সারির জন্য আলাদা শেষ পেজ
    }
    pages.add(cur); // শেষ পেজ (মোট সারিসহ)
    final pageCount = pages.length;

    // ── প্রতিটা পেজ আঁকা → PNG → PDF ──
    final doc = pw.Document();
    for (var i = 0; i < pageCount; i++) {
      onProgress?.call('পৃষ্ঠা ${bn(i + 1)}/${bn(pageCount)} তৈরি হচ্ছে…');
      await Future<void>.delayed(const Duration(milliseconds: 20)); // UI-কে শ্বাস নিতে দিই
      final png = await _renderPage(
        pageIndex: i,
        pageCount: pageCount,
        rows: pages[i],
        isFirst: i == 0,
        isLast: i == pageCount - 1,
        title: title,
        subtitle: subtitle,
        totalIn: totalIn,
        totalOut: totalOut,
        count: sorted.length,
      );
      final img = pw.MemoryImage(png);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.FullPage(ignoreMargins: true, child: pw.Image(img, fit: pw.BoxFit.fill)),
      ));
    }
    onProgress?.call('PDF সেভ হচ্ছে…');
    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safe(title)}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// বানানো PDF শেয়ার/সেভ/প্রিন্টের শিট খুলে দেখায়।
  static Future<void> sharePdf(File file, String title) =>
      Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')], text: '📄 $title — My Manager Cashbook');

  static Future<Uint8List> _renderPage({
    required int pageIndex,
    required int pageCount,
    required List<_Row> rows,
    required bool isFirst,
    required bool isLast,
    required String title,
    required String subtitle,
    required double totalIn,
    required double totalOut,
    required int count,
  }) async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, Rect.fromLTWH(0, 0, _pageW * _scale, _pageH * _scale));
    canvas.scale(_scale);
    canvas.drawRect(const Rect.fromLTWH(0, 0, _pageW, _pageH), Paint()..color = Colors.white);

    var y = _otherTop;
    if (isFirst) {
      _tp(title, 20, bold: true).paint(canvas, const Offset(_m, 32));
      final sub = [
        if (subtitle.isNotEmpty) subtitle,
        'এন্ট্রি: ${bn(count)}টি',
        'তৈরি: ${bn(DateTime.now().toString().substring(0, 16))}',
      ].join('  ·  ');
      _tp(sub, 9.5, color: _muted).paint(canvas, const Offset(_m, 64));

      // সারাংশ বক্স: মোট জমা / মোট খরচ / নিট
      const boxY = 90.0, boxH = 54.0, gap = 10.0;
      final boxW = (_pageW - 2 * _m - 2 * gap) / 3;
      final boxes = [
        ('মোট জমা', _fmtBn(totalIn), _green),
        ('মোট খরচ', _fmtBn(totalOut), _red),
        ('নিট', _fmtBn(totalIn - totalOut), totalIn - totalOut >= 0 ? _green : _red),
      ];
      for (var i = 0; i < 3; i++) {
        final x = _m + i * (boxW + gap);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, boxY, boxW, boxH), const Radius.circular(8)),
          Paint()..color = const Color(0xFFF2F3F5),
        );
        _tp(boxes[i].$1, 9, color: _muted).paint(canvas, Offset(x + 10, boxY + 8));
        _tp(boxes[i].$2, 15, bold: true, color: boxes[i].$3).paint(canvas, Offset(x + 10, boxY + 24));
      }
      y = _firstTop;
    }

    // টেবিল হেডার
    canvas.drawRect(Rect.fromLTWH(_m, y, _pageW - 2 * _m, _hdrH), Paint()..color = const Color(0xFFE3E5E8));
    final xs = <double>[_m, _m + _wDate, _m + _wDate + _wCat, _m + _wDate + _wCat + _wNote, _m + _wDate + _wCat + _wNote + _wIn];
    _tp('তারিখ', 9.5, bold: true).paint(canvas, Offset(xs[0] + 4, y + 4));
    _tp('ক্যাটাগরি', 9.5, bold: true).paint(canvas, Offset(xs[1] + 4, y + 4));
    _tp('নোট', 9.5, bold: true).paint(canvas, Offset(xs[2] + 4, y + 4));
    _tp('জমা', 9.5, bold: true, width: _wIn - 8, align: TextAlign.right).paint(canvas, Offset(xs[3], y + 4));
    _tp('খরচ', 9.5, bold: true, width: _wOut - 8, align: TextAlign.right).paint(canvas, Offset(xs[4], y + 4));
    y += _hdrH;

    final line = Paint()
      ..color = const Color(0xFFDDDEE2)
      ..strokeWidth = 0.5;
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (i.isOdd) {
        canvas.drawRect(Rect.fromLTWH(_m, y, _pageW - 2 * _m, r.h), Paint()..color = const Color(0xFFF8F8FA));
      }
      r.date.paint(canvas, Offset(xs[0] + 4, y + 4));
      r.cat.paint(canvas, Offset(xs[1] + 4, y + 4));
      r.note.paint(canvas, Offset(xs[2] + 4, y + 4));
      r.inAmt.paint(canvas, Offset(xs[3], y + 4));
      r.outAmt.paint(canvas, Offset(xs[4], y + 4));
      y += r.h;
      canvas.drawLine(Offset(_m, y), Offset(_pageW - _m, y), line);
    }

    if (isLast) {
      y += 6;
      canvas.drawRect(Rect.fromLTWH(_m, y, _pageW - 2 * _m, 24), Paint()..color = const Color(0xFFE3E5E8));
      _tp('মোট', 10, bold: true).paint(canvas, Offset(xs[2] + 4, y + 3));
      _tp(_fmtBn(totalIn), 10, bold: true, color: _green, width: _wIn - 8, align: TextAlign.right).paint(canvas, Offset(xs[3], y + 3));
      _tp(_fmtBn(totalOut), 10, bold: true, color: _red, width: _wOut - 8, align: TextAlign.right).paint(canvas, Offset(xs[4], y + 3));
    }

    // ফুটার
    _tp('পৃষ্ঠা ${bn(pageIndex + 1)}/${bn(pageCount)}  ·  My Manager Cashbook', 8,
            color: _muted, width: _pageW, align: TextAlign.center)
        .paint(canvas, const Offset(0, _pageH - 28));

    final pic = rec.endRecording();
    final img = await pic.toImage((_pageW * _scale).round(), (_pageH * _scale).round());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (data == null) throw 'পেজের ছবি বানানো যায়নি';
    return data.buffer.asUint8List();
  }

  // ───────────────────────── Excel ─────────────────────────

  static const _xlHeaders = ['তারিখ', 'হিসাব', 'ধরন', 'ক্যাটাগরি', 'জমা', 'খরচ', 'নোট', 'পুনরাবৃত্তি', 'ভাউচার আছে'];

  /// Excel শিটের নামে বাদ-যাওয়া চিহ্ন সরিয়ে ≤৩১ অক্ষরে আনে (Excel-এর নিয়ম)।
  static String _sheetName(String raw, Set<String> used) {
    var n = raw.replaceAll(RegExp(r'[\\/*?:\[\]]'), '-').trim();
    if (n.isEmpty) n = 'হিসাব';
    if (n.length > 31) n = n.substring(0, 31);
    var out = n;
    var i = 2;
    while (used.contains(out.toLowerCase())) {
      final suffix = ' ($i)';
      out = (n.length + suffix.length > 31 ? n.substring(0, 31 - suffix.length) : n) + suffix;
      i++;
    }
    used.add(out.toLowerCase());
    return out;
  }

  /// এক শিটে হেডার + সারি + শেষে মোট। বড় হলে মাঝে মাঝে UI-কে ছেড়ে দেয়।
  static Future<void> _fillSheet(xls.Sheet sheet, List<CashbookEntry> entries, List<CashbookAccount> accounts) async {
    sheet.appendRow(_xlHeaders.map((h) => xls.TextCellValue(h)).toList());
    final sorted = [...entries]..sort((a, b) {
        final c = a.date.compareTo(b.date);
        return c != 0 ? c : (a.id ?? 0).compareTo(b.id ?? 0);
      });
    var n = 0;
    for (final e in sorted) {
      final cat = CashbookService.categoryById(e.category);
      sheet.appendRow([
        xls.TextCellValue(e.date),
        xls.TextCellValue(_accName(accounts, e.accountId)),
        xls.TextCellValue(e.type == 'in' ? 'জমা' : 'খরচ'),
        xls.TextCellValue(cat.name),
        e.type == 'in' ? xls.DoubleCellValue(e.amount) : xls.TextCellValue(''),
        e.type == 'out' ? xls.DoubleCellValue(e.amount) : xls.TextCellValue(''),
        xls.TextCellValue(e.note),
        xls.TextCellValue(e.recurring ? 'হ্যাঁ' : ''),
        xls.TextCellValue(e.voucherImage != null ? 'হ্যাঁ' : ''),
      ]);
      if (++n % 250 == 0) await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final totalIn = sorted.where((e) => e.type == 'in').fold<double>(0, (s, e) => s + e.amount);
    final totalOut = sorted.where((e) => e.type == 'out').fold<double>(0, (s, e) => s + e.amount);
    sheet.appendRow([
      xls.TextCellValue(''), xls.TextCellValue(''), xls.TextCellValue(''), xls.TextCellValue('মোট'),
      xls.DoubleCellValue(totalIn), xls.DoubleCellValue(totalOut), xls.TextCellValue(''), xls.TextCellValue(''), xls.TextCellValue(''),
    ]);
    try {
      const widths = [12.0, 18.0, 8.0, 18.0, 12.0, 12.0, 36.0, 12.0, 12.0];
      for (var i = 0; i < widths.length; i++) {
        sheet.setColumnWidth(i, widths[i]);
      }
    } catch (_) {}
  }

  /// ডিফল্ট ফাঁকা শিটটাকে [name] নামে বদলে ফেরত দেয় (বাড়তি "Sheet1" যেন না থাকে)।
  static xls.Sheet _firstSheet(xls.Excel book, String name) {
    try {
      final def = book.getDefaultSheet();
      if (def != null && def != name) {
        book.rename(def, name);
        return book[name];
      }
    } catch (_) {}
    return book[name];
  }

  static Future<File> _saveBook(xls.Excel book, String fileTitle) async {
    final bytes = book.encode();
    if (bytes == null) throw 'Excel ফাইল বানানো যায়নি';
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safe(fileTitle)}.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// শুধু একটা হিসাব/মাসের Excel — ফাইল ও শিটের নামে মাসের নাম থাকে।
  static Future<File> exportExcelMonth({
    required String accountName,
    required List<CashbookEntry> entries,
    required List<CashbookAccount> accounts,
    void Function(String)? onProgress,
  }) async {
    if (entries.isEmpty) throw 'এই হিসাবে কোনো এন্ট্রি নেই';
    onProgress?.call('Excel সাজানো হচ্ছে…');
    final book = xls.Excel.createExcel();
    final sheet = _firstSheet(book, _sheetName(accountName, <String>{}));
    await _fillSheet(sheet, entries, accounts);
    onProgress?.call('ফাইল সেভ হচ্ছে…');
    return _saveBook(book, 'ক্যাশবুক — $accountName');
  }

  /// Export All: শুরুতে "সারাংশ" শিট (প্রতি হিসাবের মোট), তারপর প্রতি হিসাব/মাসের আলাদা শিট।
  static Future<File> exportExcelAll({
    required List<CashbookEntry> entries,
    required List<CashbookAccount> accounts,
    void Function(String)? onProgress,
  }) async {
    if (entries.isEmpty) throw 'কোনো এন্ট্রি নেই';
    final book = xls.Excel.createExcel();
    final used = <String>{};

    // হিসাব অনুযায়ী ভাগ (হিসাবের ক্রম বজায় রেখে)
    final byAcc = <int, List<CashbookEntry>>{};
    for (final e in entries) {
      byAcc.putIfAbsent(e.accountId, () => []).add(e);
    }
    final order = <int>[
      for (final a in accounts)
        if (a.id != null && byAcc.containsKey(a.id)) a.id!,
      for (final id in byAcc.keys)
        if (!accounts.any((a) => a.id == id)) id,
    ];

    // সারাংশ শিট
    final summary = _firstSheet(book, _sheetName('সারাংশ', used));
    summary.appendRow(['হিসাব / মাস', 'এন্ট্রি', 'মোট জমা', 'মোট খরচ', 'নিট'].map((h) => xls.TextCellValue(h)).toList());
    var gIn = 0.0, gOut = 0.0, gCount = 0;
    for (final id in order) {
      final list = byAcc[id]!;
      final tin = list.where((e) => e.type == 'in').fold<double>(0, (s, e) => s + e.amount);
      final tout = list.where((e) => e.type == 'out').fold<double>(0, (s, e) => s + e.amount);
      gIn += tin;
      gOut += tout;
      gCount += list.length;
      summary.appendRow([
        xls.TextCellValue(_accName(accounts, id)),
        xls.IntCellValue(list.length),
        xls.DoubleCellValue(tin),
        xls.DoubleCellValue(tout),
        xls.DoubleCellValue(tin - tout),
      ]);
    }
    summary.appendRow([
      xls.TextCellValue('সর্বমোট'),
      xls.IntCellValue(gCount),
      xls.DoubleCellValue(gIn),
      xls.DoubleCellValue(gOut),
      xls.DoubleCellValue(gIn - gOut),
    ]);
    try {
      const w = [26.0, 10.0, 14.0, 14.0, 14.0];
      for (var i = 0; i < w.length; i++) {
        summary.setColumnWidth(i, w[i]);
      }
    } catch (_) {}

    // প্রতি হিসাবের আলাদা শিট
    var done = 0;
    for (final id in order) {
      done++;
      final name = _accName(accounts, id);
      onProgress?.call('Excel সাজানো হচ্ছে… ($done/${order.length}) $name');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await _fillSheet(book[_sheetName(name, used)], byAcc[id]!, accounts);
    }
    onProgress?.call('ফাইল সেভ হচ্ছে…');
    return _saveBook(book, 'ক্যাশবুক — সব হিসাব');
  }

  static Future<void> shareExcel(File file, String title) => Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
        text: '📊 $title — My Manager Cashbook',
      );

  static String _safe(String s) =>
      s.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').replaceAll(RegExp(r'\s+'), '_');
}

class _Row {
  final TextPainter date, cat, note, inAmt, outAmt;
  final double h;
  _Row(this.date, this.cat, this.note, this.inAmt, this.outAmt, this.h);
}
