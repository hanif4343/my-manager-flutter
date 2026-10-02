import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../family/screens/family_ui.dart';
import '../../reminder/models/reminder.dart' show formatDateBn;
import '../../widgets/app_theme.dart';
import '../models/doc_models.dart';
import '../services/docs_service.dart';
import 'docs_picker.dart';

String _size(int b) => b >= 1024 * 1024 ? '${(b / 1024 / 1024).toStringAsFixed(1)} MB' : '${(b / 1024).round()} KB';

/// ডকুমেন্ট যোগ/এডিট ফর্ম। সেভ হলে true।
Future<bool> showDocForm(BuildContext context, {VaultDoc? existing, String? presetCategory}) async {
  final title = TextEditingController(text: existing?.title ?? '');
  final number = TextEditingController();
  final note = TextEditingController(text: existing?.note ?? '');
  String category = existing?.category ?? presetCategory ?? 'identity';
  DateTime? expiry = existing?.expiry;
  bool hideNumber = true;
  bool numberLoaded = existing == null || existing.numberEnc.isEmpty;
  final added = <NewDocPage>[];
  final removed = <DocPage>[];
  String? error;
  bool saving = false;
  bool saved = false;

  await fSheet(context, existing == null ? 'নতুন ডকুমেন্ট' : 'ডকুমেন্ট এডিট', (ctx, setS) {
    // এডিটে আগের নম্বর ডিক্রিপ্ট করে ঘরে বসানো (একবারই)।
    if (!numberLoaded) {
      numberLoaded = true;
      DocsService.numberOf(existing!).then((n) {
        number.text = n;
        if (ctx.mounted) setS(() {});
      });
    }

    final pages = [
      ...?existing?.pages.where((p) => !removed.contains(p)),
    ];

    Future<void> addFrom(Future<NewDocPage?> Function() pick) async {
      try {
        final p = await pick();
        if (p != null) setS(() => added.add(p));
      } on FormatException catch (e) {
        setS(() => error = e.message);
      } catch (e) {
        setS(() => error = 'পাতা যোগ করা যায়নি: $e');
      }
    }

    final suggestions = docCategories[category]!.$3;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final e in docCategories.entries)
          ChoiceChip(
            label: Text('${e.value.$1} ${e.value.$2}', style: const TextStyle(fontSize: 12.5)),
            selected: category == e.key,
            onSelected: (_) => setS(() => category = e.key),
          ),
      ]),
      const SizedBox(height: 14),
      TextField(controller: title, decoration: const InputDecoration(labelText: 'নাম *')),
      if (suggestions.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final s in suggestions)
            ActionChip(
              label: Text(s, style: const TextStyle(fontSize: 11.5)),
              visualDensity: VisualDensity.compact,
              onPressed: () => setS(() => title.text = s),
            ),
        ]),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: number,
        obscureText: hideNumber,
        decoration: InputDecoration(
          labelText: 'ডকুমেন্ট নম্বর (এনক্রিপ্টেড থাকবে)',
          suffixIcon: IconButton(
            icon: Icon(hideNumber ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
            onPressed: () => setS(() => hideNumber = !hideNumber),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.event_busy_outlined, size: 18),
            label: Text(expiry == null ? 'মেয়াদ শেষের তারিখ (ঐচ্ছিক)' : 'মেয়াদ: ${formatDateBn(expiry!)}',
                overflow: TextOverflow.ellipsis),
            onPressed: () async {
              final d = await fPickDate(ctx, expiry, first: DateTime(2000), last: DateTime(DateTime.now().year + 40));
              if (d != null) setS(() => expiry = d);
            },
          ),
        ),
        if (expiry != null)
          IconButton(
            icon: Icon(Icons.close_rounded, color: AppTheme.textMuted),
            onPressed: () => setS(() => expiry = null),
          ),
      ]),
      if (expiry != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('৯০, ৩০, ৭ দিন আগে আর শেষ দিনে সকাল ৮টায় রিমাইন্ডার আসবে।',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
        ),
      const SizedBox(height: 12),
      TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'নোট')),
      const SizedBox(height: 14),
      Text('পাতা / ফাইল (ছবি বা PDF, এনক্রিপ্ট হয়ে রাখা হবে)',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      const SizedBox(height: 6),
      for (final p in pages)
        _pageRow(p.isPdf, p.name, _size(p.size), () => setS(() => removed.add(p))),
      for (final a in added)
        _pageRow(a.mime == 'application/pdf', a.name, _size(a.bytes.length), () => setS(() => added.remove(a))),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: const Text('ক্যামেরা'),
            onPressed: saving ? null : () => addFrom(() => DocsPicker.image(ImageSource.camera)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: const Text('গ্যালারি'),
            onPressed: saving ? null : () => addFrom(() => DocsPicker.image(ImageSource.gallery)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.attach_file_rounded, size: 18),
            label: const Text('ফাইল'),
            onPressed: saving ? null : () => addFrom(DocsPicker.file),
          ),
        ),
      ]),
      fError(error),
      const SizedBox(height: 16),
      if (saving)
        const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(color: AppTheme.accent)))
      else
        fSaveButton(() async {
          if (title.text.trim().isEmpty) {
            setS(() => error = 'নাম দাও');
            return;
          }
          setS(() { saving = true; error = null; });
          try {
            final d = existing ??
                VaultDoc(id: DocsService.newId(), title: '', category: category);
            d.title = title.text.trim();
            d.category = category;
            d.expiry = expiry;
            d.note = note.text.trim();
            await DocsService.save(d,
                number: number.text.trim(), added: added, removed: removed);
            saved = true;
            if (ctx.mounted) Navigator.pop(ctx);
          } catch (e) {
            setS(() { saving = false; error = 'সেভ ব্যর্থ: $e'; });
          }
        }),
    ]);
  });
  return saved;
}

Widget _pageRow(bool isPdf, String name, String size, VoidCallback onRemove) {
  return Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
    decoration: BoxDecoration(color: AppTheme.bg3, borderRadius: BorderRadius.circular(10)),
    child: Row(children: [
      Icon(isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded, size: 20, color: AppTheme.accent),
      const SizedBox(width: 8),
      Expanded(
        child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
      ),
      Text(size, style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
      IconButton(
        icon: Icon(Icons.close_rounded, size: 18, color: AppTheme.textMuted),
        onPressed: onRemove,
      ),
    ]),
  );
}
