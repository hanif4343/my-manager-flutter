import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../family/screens/family_ui.dart';
import '../../reminder/models/reminder.dart' show bn, formatDateBn;
import '../../widgets/app_theme.dart';
import '../models/doc_models.dart';
import '../services/docs_crypto.dart';
import '../services/docs_service.dart';
import 'doc_capture_flow.dart';
import 'doc_image_editor.dart';
import 'docs_picker.dart';

String _size(int b) => b >= 1024 * 1024 ? '${(b / 1024 / 1024).toStringAsFixed(1)} MB' : '${(b / 1024).round()} KB';

/// ফর্মের একেকটা পাতার ঘর: নাম (সামনের দিক…), আগের পাতা (এডিটে), নতুন ছবি।
class _Slot {
  String label;
  DocPage? old;
  NewDocPage? fresh;
  _Slot(this.label, {this.old, this.fresh});

  bool get filled => fresh != null || old != null;
  bool get isPdf => fresh != null ? fresh!.mime == 'application/pdf' : (old?.isPdf ?? false);
  int get size => fresh?.bytes.length ?? old?.size ?? 0;
  String get name => fresh?.name ?? old?.name ?? '';
}

/// ডকুমেন্ট যোগ/এডিট ফর্ম। সেভ হলে true।
/// নতুন যোগে [template] দিতে হয় (ধরন-বাছাই শিট থেকে); এডিটে ধরন নিজে ঠিক হয়।
Future<bool> showDocForm(
  BuildContext context, {
  VaultDoc? existing,
  String? presetCategory,
  DocTemplate? template,
}) async {
  final tpl = template ?? (existing != null ? resolveTemplate(existing) : docTemplates.last);
  final custom = tpl.isCustom;

  final title = TextEditingController(text: existing?.title ?? (custom ? '' : tpl.title));
  final note = TextEditingController(text: existing?.note ?? '');
  final fieldDefs = <DocField>[...tpl.fields];
  final ctrls = <String, TextEditingController>{for (final f in fieldDefs) f.key: TextEditingController()};
  String category = existing?.category ?? (custom ? (presetCategory ?? 'identity') : tpl.category);
  if (!docCategories.containsKey(category)) category = 'other';
  DateTime? expiry = existing?.expiry;
  bool hideNumber = true;
  bool fieldsLoaded = existing == null || existing.numberEnc.isEmpty;
  String? error;
  bool saving = false;
  bool saved = false;

  // ── পাতার ঘর ──
  final slots = <_Slot>[];
  final fixedCount = tpl.pageLabels.length;
  if (existing != null) {
    final pgs = existing.pages;
    for (var i = 0; i < pgs.length; i++) {
      final lbl = i < fixedCount
          ? tpl.pageLabels[i]
          : (pgs[i].label.isNotEmpty ? pgs[i].label : 'পাতা ${bn(i + 1)}');
      slots.add(_Slot(tpl.isFree && pgs[i].label.isNotEmpty ? pgs[i].label : lbl, old: pgs[i]));
    }
    for (var i = pgs.length; i < fixedCount; i++) {
      slots.add(_Slot(tpl.pageLabels[i]));
    }
  } else {
    for (final l in tpl.pageLabels) {
      slots.add(_Slot(l));
    }
  }

  final oldBytes = <String, Future<Uint8List>>{};
  Future<Uint8List> oldB(DocPage p) => oldBytes.putIfAbsent(p.fileId, () => DocsCrypto.readFile(p.fileId));

  await fSheet(context, existing == null ? 'নতুন: ${tpl.title}' : 'এডিট: ${existing.title}', (ctx, setS) {
    // এডিটে আগের নম্বর/রোল/রেজি. ডিক্রিপ্ট করে ঘরে বসানো (একবারই)।
    if (!fieldsLoaded) {
      fieldsLoaded = true;
      DocsService.fieldsOf(existing!).then((m) {
        m.forEach((k, v) {
          if (!ctrls.containsKey(k)) {
            fieldDefs.add(DocField(k, k == 'number' ? 'নম্বর' : k));
            ctrls[k] = TextEditingController();
          }
          ctrls[k]!.text = v;
        });
        if (ctx.mounted) setS(() {});
      });
    }

    void fail(String m) {
      if (ctx.mounted) setS(() => error = m);
    }

    // ── ছবি নেওয়া ──
    Future<void> captureAll(ImageSource src) async {
      setS(() => error = null);
      if (tpl.isFree) {
        final got = await DocCaptureFlow.run(ctx, src, startNumber: slots.length + 1);
        if (got.isNotEmpty && ctx.mounted) {
          setS(() {
            for (final g in got) {
              slots.add(_Slot(g.label, fresh: g.page));
            }
          });
        }
        return;
      }
      final empties = slots.where((s) => !s.filled).toList();
      final targets = empties.isNotEmpty ? empties : slots.take(fixedCount).toList();
      final got = await DocCaptureFlow.run(ctx, src, labels: targets.map((s) => s.label).toList());
      if (got.isNotEmpty && ctx.mounted) {
        setS(() {
          for (var i = 0; i < got.length && i < targets.length; i++) {
            targets[i].fresh = got[i].page;
          }
        });
      }
    }

    Future<void> slotPick(_Slot s, ImageSource src) async {
      try {
        final pg = await DocsPicker.image(src);
        if (pg != null && ctx.mounted) setS(() => s.fresh = pg);
      } on FormatException catch (e) {
        fail(e.message);
      } catch (e) {
        fail('ছবি নেওয়া যায়নি: $e');
      }
    }

    Future<void> slotEdit(_Slot s) async {
      try {
        final b = s.fresh != null ? s.fresh!.bytes : await oldB(s.old!);
        if (!ctx.mounted) return;
        final out = await openImageEditor(ctx, b, title: s.label);
        if (out != null && ctx.mounted) {
          final n = s.name;
          final base = n.contains('.') ? n.substring(0, n.lastIndexOf('.')) : (n.isEmpty ? 'page' : n);
          setS(() => s.fresh = NewDocPage(out, '$base.jpg', 'image/jpeg'));
        }
      } catch (e) {
        fail('এডিট করা যায়নি: $e');
      }
    }

    void slotClear(_Slot s) {
      setS(() {
        s.fresh = null;
        s.old = null;
        if (tpl.isFree || slots.indexOf(s) >= fixedCount) slots.remove(s);
      });
    }

    Future<void> addFile() async {
      try {
        final f = await DocsPicker.file();
        if (f == null || !ctx.mounted) return;
        setS(() {
          final empties = slots.where((s) => !s.filled).toList();
          if (empties.isNotEmpty) {
            empties.first.fresh = f;
          } else {
            slots.add(_Slot('পাতা ${bn(slots.length + 1)}', fresh: f));
          }
        });
      } on FormatException catch (e) {
        fail(e.message);
      } catch (e) {
        fail('ফাইল যোগ করা যায়নি: $e');
      }
    }

    // ── ছোট UI অংশ ──
    Widget thumb(_Slot s) {
      Widget box(Widget child) => ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(width: 62, height: 62, child: child),
          );
      if (!s.filled) {
        return Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: AppTheme.bg2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
          ),
          child: Icon(Icons.add_a_photo_outlined, color: AppTheme.textMuted, size: 22),
        );
      }
      if (s.isPdf) {
        return box(Container(color: AppTheme.red.withOpacity(0.14), child: Icon(Icons.picture_as_pdf_rounded, color: AppTheme.red)));
      }
      if (s.fresh != null) {
        return box(Image.memory(s.fresh!.bytes, fit: BoxFit.cover, cacheWidth: 200, gaplessPlayback: true));
      }
      return box(FutureBuilder<Uint8List>(
        future: oldB(s.old!),
        builder: (_, snap) => snap.hasData
            ? Image.memory(snap.data!, fit: BoxFit.cover, cacheWidth: 200, gaplessPlayback: true)
            : Container(color: AppTheme.bg2),
      ));
    }

    Widget slotRow(_Slot s) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
        decoration: BoxDecoration(color: AppTheme.bg3, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          GestureDetector(onTap: s.filled && !s.isPdf ? () => slotEdit(s) : null, child: thumb(s)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.label, style: TextStyle(color: AppTheme.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                s.filled ? '✓ ${_size(s.size)}' : 'এখনও ছবি নেই',
                style: TextStyle(color: s.filled ? AppTheme.green : AppTheme.textMuted, fontSize: 11.5),
              ),
            ]),
          ),
          if (!s.filled) ...[
            IconButton(
              tooltip: 'ক্যামেরা',
              icon: const Icon(Icons.photo_camera_outlined, size: 20),
              onPressed: saving ? null : () => slotPick(s, ImageSource.camera),
            ),
            IconButton(
              tooltip: 'গ্যালারি',
              icon: const Icon(Icons.photo_library_outlined, size: 20),
              onPressed: saving ? null : () => slotPick(s, ImageSource.gallery),
            ),
            if (tpl.isFree || slots.indexOf(s) >= fixedCount)
              IconButton(
                icon: Icon(Icons.close_rounded, size: 18, color: AppTheme.textMuted),
                onPressed: () => slotClear(s),
              ),
          ] else ...[
            if (!s.isPdf)
              IconButton(
                tooltip: 'এডিট (ক্রপ, ঘোরানো…)',
                icon: const Icon(Icons.tune_rounded, size: 20),
                onPressed: saving ? null : () => slotEdit(s),
              ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, size: 20, color: AppTheme.textMuted),
              onSelected: (v) {
                if (v == 'cam') slotPick(s, ImageSource.camera);
                if (v == 'gal') slotPick(s, ImageSource.gallery);
                if (v == 'del') slotClear(s);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'cam', child: Text('ক্যামেরায় আবার তোলো')),
                PopupMenuItem(value: 'gal', child: Text('গ্যালারি থেকে বদলাও')),
                PopupMenuItem(value: 'del', child: Text('মুছে ফেলো')),
              ],
            ),
          ],
        ]),
      );
    }

    final suggestions = docCategories[category]!.$3;
    final showExpiry = tpl.hasExpiry || existing?.expiry != null;
    final filledCount = slots.where((s) => s.filled).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (custom) ...[
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final e in docCategories.entries)
            ChoiceChip(
              label: Text('${e.value.$1} ${e.value.$2}', style: const TextStyle(fontSize: 12.5)),
              selected: category == e.key,
              onSelected: (_) => setS(() => category = e.key),
            ),
        ]),
        const SizedBox(height: 14),
      ],
      TextField(controller: title, decoration: const InputDecoration(labelText: 'নাম *')),
      if (custom && suggestions.isNotEmpty) ...[
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
      for (final f in fieldDefs) ...[
        const SizedBox(height: 12),
        TextField(
          controller: ctrls[f.key],
          obscureText: f.key == 'number' && hideNumber,
          decoration: InputDecoration(
            labelText: '${f.label} (এনক্রিপ্টেড থাকবে)',
            suffixIcon: f.key == 'number'
                ? IconButton(
                    icon: Icon(hideNumber ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                    onPressed: () => setS(() => hideNumber = !hideNumber),
                  )
                : null,
          ),
        ),
      ],
      if (showExpiry) ...[
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.event_busy_outlined, size: 18),
              label: Text(expiry == null ? 'মেয়াদ শেষের তারিখ (ঐচ্ছিক)' : 'মেয়াদ: ${formatDateBn(expiry!)}',
                  overflow: TextOverflow.ellipsis),
              onPressed: () async {
                final d = await fPickDate(ctx, expiry, first: DateTime(2000), last: DateTime(DateTime.now().year + 40));
                if (d != null && ctx.mounted) setS(() => expiry = d);
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
      ],
      const SizedBox(height: 12),
      TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'নোট')),
      const SizedBox(height: 18),

      // ── ছবি / পাতা ──
      Row(children: [
        Text('ছবি', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        if (!tpl.isFree)
          fChip('${bn(filledCount)}/${bn(fixedCount)}', filledCount >= fixedCount ? AppTheme.green : AppTheme.textMuted),
      ]),
      const SizedBox(height: 4),
      Text(
        tpl.isFree
            ? 'ক্যামেরায় একটার পর একটা তোলা যাবে, গ্যালারি থেকে একসাথে অনেক বাছা যাবে। এনক্রিপ্ট হয়ে রাখা হবে।'
            : (fixedCount > 1
                ? '${bn(fixedCount)}টা ছবি লাগবে: ${tpl.pageLabels.join(' → ')}। একটা বাটনে চাপলে ধাপে ধাপে বলে দেবে।'
                : '১টা ছবি তুলে বা বেছে নিলেই হবে। এনক্রিপ্ট হয়ে রাখা হবে।'),
        style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.4),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accent, padding: const EdgeInsets.symmetric(vertical: 13)),
            icon: const Icon(Icons.photo_camera_rounded, size: 19),
            label: const Text('ক্যামেরা'),
            onPressed: saving ? null : () => captureAll(ImageSource.camera),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13)),
            icon: const Icon(Icons.photo_library_rounded, size: 19),
            label: const Text('গ্যালারি'),
            onPressed: saving ? null : () => captureAll(ImageSource.gallery),
          ),
        ),
      ]),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: saving ? null : addFile,
          icon: const Icon(Icons.attach_file_rounded, size: 17),
          label: const Text('PDF / ফাইল থেকে যোগ করো', style: TextStyle(fontSize: 12.5)),
        ),
      ),
      const SizedBox(height: 4),
      for (final s in slots) slotRow(s),
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
          setS(() {
            saving = true;
            error = null;
          });
          try {
            final d = existing ?? VaultDoc(id: DocsService.newId(), title: '', category: category);
            d.title = title.text.trim();
            d.category = custom ? category : tpl.category;
            d.tpl = tpl.key;
            d.expiry = showExpiry ? expiry : null;
            d.note = note.text.trim();
            final entries = <DocPageEntry>[
              for (final s in slots)
                if (s.filled)
                  DocPageEntry(old: s.fresh == null ? s.old : null, fresh: s.fresh, label: s.label),
            ];
            await DocsService.saveEntries(
              d,
              fields: {for (final e in ctrls.entries) e.key: e.value.text.trim()},
              entries: entries,
            );
            saved = true;
            if (ctx.mounted) Navigator.pop(ctx);
          } catch (e) {
            if (ctx.mounted) {
              setS(() {
                saving = false;
                error = 'সেভ ব্যর্থ: $e';
              });
            }
          }
        }),
    ]);
  });
  return saved;
}
