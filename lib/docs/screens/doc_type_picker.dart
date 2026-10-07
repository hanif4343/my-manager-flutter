import 'package:flutter/material.dart';
import '../../widgets/app_theme.dart';
import '../models/doc_models.dart';

/// "কোন ডকুমেন্ট যোগ করবে?" — NID, জন্মনিবন্ধন, SSC… বেছে নেওয়ার শিট।
/// বাছাইয়ের পর ফর্মে পাতা (সামনে/পেছনে) ও তথ্যের ঘর নিজে ঠিক হয়ে যায়।
Future<DocTemplate?> showDocTypePicker(BuildContext context) {
  return showModalBottomSheet<DocTemplate>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.bg2,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('কোন ডকুমেন্ট যোগ করবে?',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (_, c) {
            final w = (c.maxWidth - 10) / 2;
            return Wrap(spacing: 10, runSpacing: 10, children: [
              for (final t in docTemplates) SizedBox(width: w, child: _card(ctx, t)),
            ]);
          }),
        ]),
      ),
    ),
  );
}

Widget _card(BuildContext ctx, DocTemplate t) {
  return Material(
    color: AppTheme.bg3,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.pop(ctx, t),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Text(t.emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w700, height: 1.25)),
              const SizedBox(height: 3),
              Text(t.subtitle, style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ]),
          ),
        ]),
      ),
    ),
  );
}
