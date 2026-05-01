import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../db/db_helper.dart';
import '../models/idea.dart';
import '../models/project.dart';
import '../models/idea_file.dart';
import '../widgets/app_theme.dart';
import 'file_editor_screen.dart';

class IdeaDetailScreen extends StatefulWidget {
  final Idea idea;
  final Project project;
  const IdeaDetailScreen({super.key, required this.idea, required this.project});
  @override State<IdeaDetailScreen> createState() => _IdeaDetailScreenState();
}

class _IdeaDetailScreenState extends State<IdeaDetailScreen> {
  List<IdeaFile> _files = [];
  late Idea _idea;
  bool _loading = true;

  @override
  void initState() { super.initState(); _idea = widget.idea; _load(); }

  Future<void> _load() async {
    if (_idea.id == null) return;
    final files = await DBHelper.getFiles(_idea.id!);
    if (mounted) setState(() { _files = files; _loading = false; });
  }

  Future<void> _cycleStatus() async {
    const next = {'todo': 'doing', 'doing': 'done', 'done': 'todo'};
    final newStatus = next[_idea.status]!;
    final updated = _idea.copyWith(status: newStatus, updatedAt: now());
    await DBHelper.updateIdea(updated);
    setState(() => _idea = updated);
  }

  Future<void> _addTextFile() async {
    final nameCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    await showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.bg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('নতুন ফাইল', style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          _field(nameCtrl, 'ফাইলের নাম: index.js, style.css, README.md'),
          const SizedBox(height: 10),
          _field(contentCtrl, 'কোড বা টেক্সট লিখো (ঐচ্ছিক)...', maxLines: 5, mono: true),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final n = now();
              await DBHelper.insertFile(IdeaFile(
                ideaId: _idea.id!, projectId: widget.project.id!,
                name: nameCtrl.text.trim(), type: 'text',
                content: contentCtrl.text, createdAt: n, updatedAt: n,
              ));
              Navigator.pop(ctx);
              _load();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('যোগ করো', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          )),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Future<void> _deleteFile(IdeaFile file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bg3,
        title: const Text('ফাইল মুছবে?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('"${file.name}" মুছে যাবে।', style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('বাতিল')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('মুছো', style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    if (confirm == true && file.id != null) {
      await DBHelper.deleteFile(file.id!);
      _load();
    }
  }

  Future<void> _shareFile(IdeaFile file) async {
    if (file.content == null) return;
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/${file.name}');
    await f.writeAsString(file.content!);
    await Share.shareXFiles([XFile(f.path)], text: file.name);
  }

  Future<void> _copyContent(IdeaFile file) async {
    if (file.content == null) return;
    await Clipboard.setData(ClipboardData(text: file.content!));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${file.name} কপি হয়েছে!'),
              backgroundColor: AppTheme.green, duration: const Duration(seconds: 2)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sc = statusConfig[_idea.status]!;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(
              color: widget.project.color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(_idea.title,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          GestureDetector(
            onTap: _cycleStatus,
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (sc['color'] as Color).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sc['color'] as Color),
              ),
              child: Text(sc['label'] as String,
                  style: TextStyle(color: sc['color'] as Color, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_idea.description != null && _idea.description!.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  color: AppTheme.bg2,
                  child: Text(_idea.description!,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5)),
                ),
              // Files header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(children: [
                  const Icon(Icons.folder_outlined, size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text('ফাইলসমূহ (${_files.length})',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13,
                          fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                  const Spacer(),
                  GestureDetector(
                    onTap: _addTextFile,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(8)),
                      child: const Row(children: [
                        Icon(Icons.add, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text('ফাইল যোগ', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ]),
              ),
              // Files list
              Expanded(
                child: _files.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Text('📄', style: TextStyle(fontSize: 40)),
                        const SizedBox(height: 12),
                        const Text('কোনো ফাইল নেই', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                        const SizedBox(height: 6),
                        const Text('উপরের + বাটনে চাপো', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                      ]))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        itemCount: _files.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _fileCard(_files[i]),
                      ),
              ),
            ]),
    );
  }

  Widget _fileCard(IdeaFile file) {
    final extColor = _extColor(file.ext);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(
              builder: (_) => FileEditorScreen(file: file)));
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: extColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10)),
              child: Center(child: Text(file.ext.toUpperCase().substring(0, file.ext.length.clamp(0, 3)),
                  style: TextStyle(color: extColor, fontSize: 11, fontWeight: FontWeight.w800))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(file.name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14,
                  fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4)),
                  child: Text('v${file.version}', style: const TextStyle(
                      color: AppTheme.accent, fontSize: 10, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                ),
                const SizedBox(width: 8),
                Text('${file.lineCount} লাইন',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              ]),
            ])),
            // Actions
            PopupMenuButton<String>(
              color: AppTheme.bg3,
              icon: const Icon(Icons.more_vert, color: AppTheme.textMuted, size: 18),
              onSelected: (v) async {
                if (v == 'edit') {
                  await Navigator.push(context, MaterialPageRoute(
                      builder: (_) => FileEditorScreen(file: file)));
                  _load();
                } else if (v == 'copy') {
                  _copyContent(file);
                } else if (v == 'share') {
                  _shareFile(file);
                } else if (v == 'delete') {
                  _deleteFile(file);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 16, color: AppTheme.accent), SizedBox(width: 8), Text('এডিট করো')])),
                const PopupMenuItem(value: 'copy', child: Row(children: [Icon(Icons.copy, size: 16, color: AppTheme.textSecondary), SizedBox(width: 8), Text('কপি করো')])),
                const PopupMenuItem(value: 'share', child: Row(children: [Icon(Icons.share, size: 16, color: AppTheme.green), SizedBox(width: 8), Text('শেয়ার করো')])),
                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: AppTheme.red), SizedBox(width: 8), Text('মুছো', style: TextStyle(color: AppTheme.red))])),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Color _extColor(String ext) {
    const map = {
      'js': Color(0xFFF7DF1E), 'jsx': Color(0xFF61DAFB), 'ts': Color(0xFF3178C6),
      'tsx': Color(0xFF61DAFB), 'dart': Color(0xFF54C5F8), 'py': Color(0xFF3776AB),
      'html': Color(0xFFE34F26), 'css': Color(0xFF264DE4), 'scss': Color(0xFFCC6699),
      'json': Color(0xFF5BC8F5), 'yml': Color(0xFFCB171E), 'yaml': Color(0xFFCB171E),
      'md': Color(0xFF083FA1), 'java': Color(0xFFED8B00), 'kt': Color(0xFF7F52FF),
      'svg': Color(0xFFFFB13B), 'xml': Color(0xFFF16529),
    };
    return map[ext] ?? AppTheme.textSecondary;
  }

  Widget _field(TextEditingController ctrl, String hint, {int maxLines = 1, bool mono = false}) =>
      TextField(
        controller: ctrl, maxLines: maxLines,
        style: TextStyle(color: AppTheme.textPrimary, fontFamily: mono ? 'monospace' : null, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint, hintStyle: const TextStyle(color: AppTheme.textMuted),
          filled: true, fillColor: AppTheme.bg3,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.accent, width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      );
}
