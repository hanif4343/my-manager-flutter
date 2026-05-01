import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:archive/archive_io.dart';
import 'dart:io';
import 'dart:convert';
import '../db/db_helper.dart';
import '../models/idea.dart';
import '../models/project.dart';
import '../models/idea_file.dart';
import '../widgets/app_theme.dart';
import 'file_editor_screen.dart';
import 'image_viewer_screen.dart';
import 'copy_move_screen.dart';

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
  final _picker = ImagePicker();

  @override
  void initState() { super.initState(); _idea = widget.idea; _load(); }

  Future<void> _load() async {
    if (_idea.id == null) return;
    final files = await DBHelper.getFiles(_idea.id!);
    if (mounted) setState(() { _files = files; _loading = false; });
  }

  Future<void> _cycleStatus() async {
    const next = {'todo': 'doing', 'doing': 'done', 'done': 'todo'};
    final updated = _idea.copyWith(status: next[_idea.status]!, updatedAt: now());
    await DBHelper.updateIdea(updated);
    setState(() => _idea = updated);
  }

  // ── ADD TEXT FILE ──────────────────────────────────────
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
          _field(contentCtrl, 'কোড বা টেক্সট (ঐচ্ছিক)...', maxLines: 4, mono: true),
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
              if (ctx.mounted) Navigator.pop(ctx);
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

  // ── ADD IMAGE ─────────────────────────────────────────
  Future<void> _addImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final b64 = base64Encode(bytes);
      final ext = picked.name.split('.').last.toLowerCase();
      // auto name: icon if image, else original name
      final name = picked.name.toLowerCase().contains('icon') ? picked.name : 'icon.$ext';
      final n = now();
      await DBHelper.insertFile(IdeaFile(
        ideaId: _idea.id!, projectId: widget.project.id!,
        name: name, type: 'image', content: b64, createdAt: n, updatedAt: n,
      ));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.red));
    }
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context, backgroundColor: AppTheme.bg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        _sheetTile(Icons.code, 'কোড / টেক্সট ফাইল', AppTheme.accent, () { Navigator.pop(context); _addTextFile(); }),
        _sheetTile(Icons.photo_camera, 'ক্যামেরা থেকে ছবি', AppTheme.green, () { Navigator.pop(context); _addImage(ImageSource.camera); }),
        _sheetTile(Icons.photo_library, 'গ্যালারি থেকে ছবি', AppTheme.yellow, () { Navigator.pop(context); _addImage(ImageSource.gallery); }),
        const SizedBox(height: 16),
      ])),
    );
  }

  // ── ZIP EXPORT ────────────────────────────────────────
  Future<void> _exportZip() async {
    if (_files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('কোনো ফাইল নেই!'), backgroundColor: AppTheme.red));
      return;
    }
    final archive = Archive();
    for (final f in _files) {
      if (f.content == null) continue;
      List<int> bytes;
      if (f.isImage) {
        bytes = base64Decode(f.content!);
      } else {
        bytes = utf8.encode(f.content!);
      }
      archive.addFile(ArchiveFile(f.name, bytes.length, bytes));
    }
    final dir = await getTemporaryDirectory();
    final zipName = '${_idea.title.replaceAll(' ', '_')}_v${_files.length}.zip';
    final zipFile = File('${dir.path}/$zipName');
    final encoder = ZipEncoder();
    final encoded = encoder.encode(archive);
    if (encoded == null) return;
    await zipFile.writeAsBytes(encoded);
    await Share.shareXFiles([XFile(zipFile.path)], text: zipName);
  }

  // ── FILE ACTIONS ──────────────────────────────────────
  Future<void> _renameFile(IdeaFile file) async {
    final ctrl = TextEditingController(text: file.name);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bg3,
        title: const Text('ফাইল রিনেম', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'monospace'),
          decoration: InputDecoration(
            filled: true, fillColor: AppTheme.bg4,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.accent, width: 2)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('বাতিল')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            child: const Text('রিনেম'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && file.id != null) {
      await DBHelper.renameFile(file.id!, result);
      _load();
    }
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
    if (file.isImage) {
      await f.writeAsBytes(base64Decode(file.content!));
    } else {
      await f.writeAsString(file.content!);
    }
    await Share.shareXFiles([XFile(f.path)], text: file.name);
  }

  Future<void> _copyContent(IdeaFile file) async {
    if (file.content == null || file.isImage) return;
    await Clipboard.setData(ClipboardData(text: file.content!));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${file.name} কপি হয়েছে!'),
            backgroundColor: AppTheme.green, duration: const Duration(seconds: 2)));
  }

  void _showFileMenu(IdeaFile file) {
    showModalBottomSheet(
      context: context, backgroundColor: AppTheme.bg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Text(file.name, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
              child: Text('v${file.version}', style: const TextStyle(color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.w700))),
          ]),
        ),
        if (!file.isImage) _sheetTile(Icons.edit_outlined, 'এডিট করো', AppTheme.accent, () async {
          Navigator.pop(context);
          await Navigator.push(context, MaterialPageRoute(builder: (_) => FileEditorScreen(file: file)));
          _load();
        }),
        if (!file.isImage) _sheetTile(Icons.copy_outlined, 'কোড কপি করো', AppTheme.textSecondary, () { Navigator.pop(context); _copyContent(file); }),
        if (file.isImage) _sheetTile(Icons.image_outlined, 'ছবি দেখো', AppTheme.accent, () async {
          Navigator.pop(context);
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ImageViewerScreen(file: file)));
        }),
        _sheetTile(Icons.drive_file_rename_outline, 'রিনেম করো', AppTheme.yellow, () { Navigator.pop(context); _renameFile(file); }),
        _sheetTile(Icons.copy_all_outlined, 'Copy To...', AppTheme.green, () async {
          Navigator.pop(context);
          await Navigator.push(context, MaterialPageRoute(
              builder: (_) => CopyMoveScreen(file: file, mode: 'copy', currentIdeaId: _idea.id!)));
          _load();
        }),
        _sheetTile(Icons.drive_file_move_outline, 'Move To...', AppTheme.yellow, () async {
          Navigator.pop(context);
          await Navigator.push(context, MaterialPageRoute(
              builder: (_) => CopyMoveScreen(file: file, mode: 'move', currentIdeaId: _idea.id!)));
          _load();
        }),
        _sheetTile(Icons.share_outlined, 'শেয়ার করো', AppTheme.textSecondary, () { Navigator.pop(context); _shareFile(file); }),
        _sheetTile(Icons.delete_outline, 'মুছো', AppTheme.red, () { Navigator.pop(context); _deleteFile(file); }),
        const SizedBox(height: 8),
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sc = statusConfig[_idea.status]!;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: widget.project.color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(_idea.title,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          // ZIP export
          IconButton(
            onPressed: _exportZip,
            icon: const Icon(Icons.folder_zip_outlined, size: 20),
            tooltip: 'ZIP Export',
          ),
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
                Container(width: double.infinity, padding: const EdgeInsets.all(14),
                    color: AppTheme.bg2,
                    child: Text(_idea.description!, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5))),
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
                    onTap: _showAddOptions,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(8)),
                      child: const Row(children: [
                        Icon(Icons.add, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text('যোগ করো', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ]),
              ),
              Expanded(
                child: _files.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Text('📄', style: TextStyle(fontSize: 40)),
                        const SizedBox(height: 12),
                        const Text('কোনো ফাইল নেই', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                        const SizedBox(height: 6),
                        const Text('+ যোগ করো বাটনে চাপো', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                      ]))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        itemCount: _files.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _fileCard(_files[i]),
                      ),
              ),
            ]),
      floatingActionButton: _files.isEmpty ? null : FloatingActionButton(
        onPressed: _showAddOptions,
        backgroundColor: AppTheme.accent, mini: true,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _fileCard(IdeaFile file) {
    final extColor = _extColor(file.ext);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showFileMenu(file),
        onLongPress: () {
          if (!file.isImage) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => FileEditorScreen(file: file)))
                .then((_) => _load());
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            // Thumbnail for image, icon for text
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: extColor.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
              clipBehavior: Clip.antiAlias,
              child: file.isImage && file.content != null
                  ? Image.memory(base64Decode(file.content!), fit: BoxFit.cover)
                  : Center(child: Text(
                      file.ext.isEmpty ? '?' : file.ext.toUpperCase().substring(0, file.ext.length.clamp(0, 4)),
                      style: TextStyle(color: extColor, fontSize: 11, fontWeight: FontWeight.w800))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(file.name,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14,
                      fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Row(children: [
                _versionBadge('v${file.version}'),
                const SizedBox(width: 8),
                if (!file.isImage)
                  Text('${file.lineCount} লাইন',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 11))
                else
                  Text('image', style: TextStyle(color: AppTheme.yellow.withOpacity(0.8), fontSize: 11)),
              ]),
            ])),
            Icon(Icons.more_vert, size: 18, color: AppTheme.textMuted),
          ]),
        ),
      ),
    );
  }

  Widget _versionBadge(String v) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
    child: Text(v, style: const TextStyle(color: AppTheme.accent, fontSize: 10,
        fontWeight: FontWeight.w700, fontFamily: 'monospace')),
  );

  Widget _sheetTile(IconData icon, String label, Color color, VoidCallback onTap) =>
      ListTile(leading: Icon(icon, color: color, size: 20),
          title: Text(label, style: TextStyle(color: color, fontSize: 14)),
          onTap: onTap, dense: true);

  Color _extColor(String ext) {
    const map = {
      'js': Color(0xFFF7DF1E), 'jsx': Color(0xFF61DAFB), 'ts': Color(0xFF3178C6),
      'tsx': Color(0xFF61DAFB), 'dart': Color(0xFF54C5F8), 'py': Color(0xFF3776AB),
      'html': Color(0xFFE34F26), 'css': Color(0xFF264DE4), 'scss': Color(0xFFCC6699),
      'json': Color(0xFF5BC8F5), 'yml': Color(0xFFCB171E), 'yaml': Color(0xFFCB171E),
      'md': Color(0xFF083FA1), 'java': Color(0xFFED8B00), 'kt': Color(0xFF7F52FF),
      'svg': Color(0xFFFFB13B), 'xml': Color(0xFFF16529),
      'png': Color(0xFF10B981), 'jpg': Color(0xFF10B981), 'jpeg': Color(0xFF10B981),
      'gif': Color(0xFF10B981), 'webp': Color(0xFF10B981),
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
