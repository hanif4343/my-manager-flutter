import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../db/db_helper.dart';
import '../models/idea.dart';
import '../models/idea_file.dart';
import '../models/project.dart';
import '../widgets/app_theme.dart';

/// Shown when something is shared into My Manager from another app
/// (browser, gallery, WhatsApp, etc.) — pick a project, adjust the title,
/// and it's saved as a new idea. Any shared images/files are attached to
/// that idea automatically, the same way "Add file" already works.
class ShareIntakeScreen extends StatefulWidget {
  final List<SharedMediaFile> sharedFiles;
  const ShareIntakeScreen({super.key, required this.sharedFiles});
  @override State<ShareIntakeScreen> createState() => _ShareIntakeScreenState();
}

class _ShareIntakeScreenState extends State<ShareIntakeScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  List<Project> _projects = [];
  int? _selectedProjectId;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prefill();
    _loadProjects();
  }

  /// Text/URL shares arrive with the shared text sitting in `.path`
  /// (the plugin reuses the same model for text and files). File shares
  /// arrive with a real local file path there instead.
  bool get _isTextShare =>
      widget.sharedFiles.length == 1 &&
      widget.sharedFiles.first.type == SharedMediaType.text;

  void _prefill() {
    if (_isTextShare) {
      final text = widget.sharedFiles.first.path;
      _title.text = text.length > 60 ? '${text.substring(0, 60)}...' : text;
      _desc.text = text;
    } else if (widget.sharedFiles.isNotEmpty) {
      final names = widget.sharedFiles.map((f) => f.path.split('/').last);
      _title.text = widget.sharedFiles.length == 1
          ? names.first
          : '${names.first} + আরও ${widget.sharedFiles.length - 1}টা ফাইল';
    }
  }

  Future<void> _loadProjects() async {
    final list = await DBHelper.getProjects();
    if (mounted) setState(() {
      _projects = list;
      _selectedProjectId = list.isNotEmpty ? list.first.id : null;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _selectedProjectId == null || _saving) return;
    setState(() => _saving = true);
    final n = DateTime.now().millisecondsSinceEpoch;

    final ideaId = await DBHelper.insertIdea(Idea(
      projectId: _selectedProjectId!,
      title: _title.text.trim(),
      description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      createdAt: n, updatedAt: n,
    ));

    // Attach any shared files (skip for pure text/URL shares, which have
    // no real file to attach).
    if (!_isTextShare) {
      for (final f in widget.sharedFiles) {
        try {
          final file = File(f.path);
          if (!await file.exists()) continue;
          final bytes = await file.readAsBytes();
          final name = f.path.split('/').last;
          final dummy = IdeaFile(ideaId: 0, projectId: 0,
              name: name, type: 'binary', createdAt: 0, updatedAt: 0);
          final isText = dummy.isText;
          final content = isText
              ? utf8.decode(bytes, allowMalformed: true)
              : base64Encode(bytes);
          await DBHelper.insertFile(IdeaFile(
            ideaId: ideaId, projectId: _selectedProjectId!,
            name: name, type: isText ? 'text' : 'binary',
            content: content, createdAt: n, updatedAt: n,
          ));
        } catch (_) {
          // One bad file shouldn't block saving the rest.
        }
      }
    }

    ReceiveSharingIntent.instance.reset();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ আইডিয়া হিসেবে যোগ হয়েছে!'),
        backgroundColor: AppTheme.accent,
      ));
      Navigator.of(context).pop();
    }
  }

  void _cancel() {
    ReceiveSharingIntent.instance.reset();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('My Manager-এ শেয়ার করো'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: _cancel),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))
                : const Icon(Icons.check, size: 18, color: AppTheme.accent),
            label: const Text('সেভ', style: TextStyle(
                color: AppTheme.accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _projects.isEmpty
              ? Center(child: Text('আগে একটা প্রজেক্ট বানাও',
                  style: AppTheme.body()))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (!_isTextShare && widget.sharedFiles.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.bg2, borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(children: [
                          Icon(Icons.attach_file, size: 18, color: AppTheme.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(
                              '${widget.sharedFiles.length} ফাইল সংযুক্ত হবে',
                              style: AppTheme.body())),
                        ]),
                      ),
                    Text('প্রজেক্ট বাছো', style: AppTheme.caption(weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: _projects.map((p) {
                      final sel = _selectedProjectId == p.id;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedProjectId = p.id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: sel ? AppTheme.accent.withOpacity(0.15) : AppTheme.bg3,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: sel ? AppTheme.accent : AppTheme.border,
                                width: sel ? 2 : 1),
                          ),
                          child: Text(p.name, style: TextStyle(
                              color: sel ? AppTheme.accent : AppTheme.textSecondary,
                              fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                      );
                    }).toList()),
                    const SizedBox(height: 20),
                    Text('শিরোনাম', style: AppTheme.caption(weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _title, autofocus: true,
                      style: TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        filled: true, fillColor: AppTheme.bg3,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppTheme.border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppTheme.accent, width: 2)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('নোট (ঐচ্ছিক)', style: AppTheme.caption(weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _desc, maxLines: 5,
                      style: TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        filled: true, fillColor: AppTheme.bg3,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppTheme.border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppTheme.accent, width: 2)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ]),
                ),
    );
  }
}
