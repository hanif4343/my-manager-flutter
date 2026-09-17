import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as xls;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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

  /// Builds a PDF statement and opens the system share/print sheet.
  /// Bengali text needs an embedded font — the default PDF fonts have no
  /// Bengali glyphs — so this pulls Noto Sans Bengali from Google Fonts
  /// at export time (needs the device to have internet just for this).
  static Future<void> exportPdf({
    required String title,
    required List<CashbookEntry> entries,
    required List<CashbookAccount> accounts,
  }) async {
    final font = await PdfGoogleFonts.notoSansBengaliRegular();
    final fontBold = await PdfGoogleFonts.notoSansBengaliBold();
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: fontBold));

    final sorted = [...entries]..sort((a, b) => b.date.compareTo(a.date));
    final totalIn = entries.where((e) => e.type == 'in').fold<double>(0, (s, e) => s + e.amount);
    final totalOut = entries.where((e) => e.type == 'out').fold<double>(0, (s, e) => s + e.amount);

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Text(title, style: pw.TextStyle(font: fontBold, fontSize: 20)),
        pw.SizedBox(height: 4),
        pw.Text('তৈরি হয়েছে: ${DateTime.now().toString().substring(0, 16)}',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 14),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          _summaryBox(fontBold, 'মোট জমা', _fmt(totalIn)),
          _summaryBox(fontBold, 'মোট খরচ', _fmt(totalOut)),
          _summaryBox(fontBold, 'নিট', _fmt(totalIn - totalOut)),
        ]),
        pw.SizedBox(height: 16),
        pw.Table.fromTextArray(
          headerStyle: pw.TextStyle(font: fontBold, fontSize: 10),
          cellStyle: pw.TextStyle(font: font, fontSize: 9.5),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellAlignments: {3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
          headers: ['তারিখ', 'হিসাব', 'ক্যাটাগরি', 'জমা', 'খরচ', 'নোট'],
          data: sorted.map((e) {
            final cat = CashbookService.categoryById(e.category);
            return [
              e.date,
              _accName(accounts, e.accountId),
              cat.name,
              e.type == 'in' ? _fmt(e.amount) : '',
              e.type == 'out' ? _fmt(e.amount) : '',
              e.note,
            ];
          }).toList(),
        ),
      ],
    ));

    await Printing.sharePdf(bytes: await doc.save(), filename: '${_safe(title)}.pdf');
  }

  static pw.Widget _summaryBox(pw.Font boldFont, String label, String value) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      pw.SizedBox(height: 2),
      pw.Text(value, style: pw.TextStyle(font: boldFont, fontSize: 14)),
    ]);
  }

  /// Builds an .xlsx workbook of the same entries and shares it as a file.
  static Future<void> exportExcel({
    required String title,
    required List<CashbookEntry> entries,
    required List<CashbookAccount> accounts,
  }) async {
    final book = xls.Excel.createExcel();
    final sheet = book['ক্যাশবুক'];
    book.setDefaultSheet('ক্যাশবুক');

    final headers = ['তারিখ', 'হিসাব', 'ধরন', 'ক্যাটাগরি', 'জমা', 'খরচ', 'নোট', 'পুনরাবৃত্তি', 'ভাউচার আছে'];
    sheet.appendRow(headers.map((h) => xls.TextCellValue(h)).toList());

    final sorted = [...entries]..sort((a, b) => b.date.compareTo(a.date));
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
    }

    final totalIn = entries.where((e) => e.type == 'in').fold<double>(0, (s, e) => s + e.amount);
    final totalOut = entries.where((e) => e.type == 'out').fold<double>(0, (s, e) => s + e.amount);
    sheet.appendRow([xls.TextCellValue(''), xls.TextCellValue(''), xls.TextCellValue(''), xls.TextCellValue('মোট'),
      xls.DoubleCellValue(totalIn), xls.DoubleCellValue(totalOut), xls.TextCellValue(''), xls.TextCellValue(''), xls.TextCellValue('')]);

    final bytes = book.encode();
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safe(title)}.xlsx');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], text: '📊 $title — My Manager Cashbook');
  }

  static String _safe(String s) =>
      s.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').replaceAll(RegExp(r'\s+'), '_');
}
