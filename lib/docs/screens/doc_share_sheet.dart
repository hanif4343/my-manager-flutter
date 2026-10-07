import 'package:flutter/material.dart';
import '../../reminder/models/reminder.dart' show bn;
import '../../widgets/app_theme.dart';
import '../models/doc_models.dart';
import '../services/docs_export_service.dart';

/// শেয়ার শিট: অন্য অ্যাপে পাঠানো, অথবা ব্রাউজার/ওয়েবসাইটের ফাইল-পিকারে
/// "ডকুমেন্ট ভল্ট" হিসেবে দেখানোর জন্য প্রস্তুত করা।
/// [only] দিলে শুধু সেই পাতাটা, না দিলে ডকুমেন্টের সব পাতা।
Future<void> showDocShareSheet(BuildContext context, VaultDoc doc, {DocPage? only}) async {
  final pages = only != null ? [only] : doc.pages;
  if (pages.isEmpty) return;
  final canPdf = DocsExport.hasImages(pages);
  final messenger = ScaffoldMessenger.of(context);

  void snack(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));

  Future<void> doShare(bool pdf) async {
    try {
      await DocsExport.share(doc, pages: pages, asPdf: pdf);
    } catch (e) {
      snack('শেয়ার ব্যর্থ: $e');
    }
  }

  Future<void> doPrepare(bool pdf) async {
    try {
      await DocsExport.prepareForUpload(doc, pages: pages, asPdf: pdf);
      if (!context.mounted) return;
      await _showReadyDialog(context);
    } catch (e) {
      snack('প্রস্তুত করা যায়নি: $e');
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.bg2,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) {
      Widget tile(IconData icon, String title, String sub, VoidCallback run) {
        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.accent, size: 21),
          ),
          title: Text(title, style: TextStyle(color: AppTheme.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w600)),
          subtitle: Text(sub, style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          onTap: () {
            Navigator.pop(ctx);
            run();
          },
        );
      }

      Widget head(String t) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
            child: Text(t, style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
          );

      final n = pages.length;
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(children: [
                Expanded(
                  child: Text(only != null ? 'এই পাতা পাঠাও' : '${doc.title} পাঠাও',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
            head('অন্য অ্যাপে পাঠাও (WhatsApp, ইমেইল…)'),
            tile(Icons.image_outlined, 'ছবি হিসেবে',
                n == 1 ? '১টা ফাইল' : '${bn(n)}টা ফাইল আলাদা আলাদা', () => doShare(false)),
            if (canPdf && n > 1)
              tile(Icons.picture_as_pdf_outlined, 'একটাই PDF', 'সব পাতা এক ফাইলে', () => doShare(true)),
            head('ওয়েবসাইট / ব্রাউজারে আপলোড'),
            tile(Icons.upload_file_rounded, 'ছবি আপলোডের জন্য প্রস্তুত করো',
                'ফাইল-পিকারে "ডকুমেন্ট ভল্ট" হিসেবে দেখাবে', () => doPrepare(false)),
            if (canPdf)
              tile(Icons.picture_as_pdf_rounded, 'PDF আপলোডের জন্য প্রস্তুত করো',
                  'এক ফাইলের PDF বানিয়ে পিকারে দেখাবে', () => doPrepare(true)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: Text(
                'মনে রেখো: পাঠানো/প্রস্তুত করা ফাইল এনক্রিপশন ছাড়া সাধারণ ছবি/PDF হয়ে যায়। আপলোডের জন্য প্রস্তুত ফাইল ১০ মিনিট পর নিজে মুছে যায়।',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5, height: 1.4),
              ),
            ),
          ]),
        ),
      );
    },
  );
}

Future<void> _showReadyDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.bg2,
      title: const Text('✅ আপলোডের জন্য প্রস্তুত'),
      content: Text(
        '১. ব্রাউজার/সাইটে "ফাইল বাছাই / Upload" চাপো\n'
        '২. ফাইল-পিকারে বাঁদিকের ☰ মেনু (বা "Browse") খোলো\n'
        '৩. "ডকুমেন্ট ভল্ট" চাপো — ফাইল বেছে নাও\n\n'
        '⏱ ১০ মিনিট পর ফাইল নিজে মুছে যাবে।',
        style: TextStyle(color: AppTheme.textSecondary, height: 1.5, fontSize: 13.5),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await DocsExport.clearTray();
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: Text('এখনই বন্ধ করো', style: TextStyle(color: AppTheme.red)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('ঠিক আছে', style: TextStyle(color: AppTheme.accent)),
        ),
      ],
    ),
  );
}
