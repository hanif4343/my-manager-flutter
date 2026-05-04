import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../db/db_helper.dart';
import '../models/idea_file.dart';
import '../widgets/app_theme.dart';
import '../widgets/syntax_highlighter.dart';

class FileEditorScreen extends StatefulWidget {
  final IdeaFile file;
  const FileEditorScreen({super.key, required this.file});
  @override State<FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends State<FileEditorScreen> {
  late TextEditingController _ctrl;
  bool _modified = false;
  bool _previewMode = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.file.content ?? '');
    _ctrl.addListener(() { if (mounted) setState(() => _modified = true); });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    await DBHelper.updateFile(widget.file.copyWith(
        content: _ctrl.text, updatedAt: now()));
    if (mounted) {
      setState(() => _modified = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${widget.file.name} সেভ হয়েছে ✅'),
        backgroundColor: AppTheme.green, duration: const Duration(seconds: 2)));
    }
  }

  int get _lineCount => _ctrl.text.split('\n').length;

  @override
  Widget build(BuildContext context) {
    final hasHighlight = ['js','jsx','ts','tsx','dart','py','python',
      'html','css','scss','json','yml','yaml'].contains(widget.file.ext);

    return PopScope(
      canPop: !_modified,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final result = await showDialog<bool>(context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppTheme.bg3,
            title: const Text('সেভ করবে?', style: TextStyle(color: AppTheme.textPrimary)),
            content: const Text('পরিবর্তন হারিয়ে যাবে।',
                style: TextStyle(color: AppTheme.textSecondary)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false),
                  child: const Text('বাতিল')),
              TextButton(onPressed: () => Navigator.pop(context, true),
                  child: const Text('সেভ না করে বেরাই',
                      style: TextStyle(color: AppTheme.red))),
              ElevatedButton(
                onPressed: () async { await _save(); if (context.mounted) Navigator.pop(context, true); },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
                child: const Text('সেভ করো'),
              ),
            ],
          ),
        );
        if (result == true && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        appBar: AppBar(
          backgroundColor: const Color(0xFF161B22),
          title: Row(children: [
            Text(widget.file.name, style: const TextStyle(
                fontFamily: 'monospace', fontSize: 13, color: AppTheme.textPrimary)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4)),
              child: Text('v${widget.file.version}', style: const TextStyle(
                  color: AppTheme.accent, fontSize: 10,
                  fontWeight: FontWeight.w700, fontFamily: 'monospace')),
            ),
            if (_modified) ...[
              const SizedBox(width: 8),
              Container(width: 8, height: 8, decoration: const BoxDecoration(
                  color: AppTheme.yellow, shape: BoxShape.circle)),
            ],
          ]),
          actions: [
            if (hasHighlight)
              IconButton(
                onPressed: () => setState(() => _previewMode = !_previewMode),
                icon: Icon(_previewMode ? Icons.edit_outlined : Icons.visibility_outlined,
                    size: 18, color: _previewMode ? AppTheme.accent : AppTheme.textSecondary),
                tooltip: _previewMode ? 'Edit Mode' : 'Preview Mode',
              ),
            IconButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _ctrl.text));
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('কপি হয়েছে!'),
                        backgroundColor: AppTheme.green, duration: Duration(seconds: 2)));
              },
              icon: const Icon(Icons.copy_outlined, size: 18),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined, size: 18, color: AppTheme.accent),
                label: const Text('সেভ', style: TextStyle(
                    color: AppTheme.accent, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(28),
            child: Container(
              color: const Color(0xFF161B22),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Text('$_lineCount লাইন', style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 11, fontFamily: 'monospace')),
                const SizedBox(width: 12),
                Text('${_ctrl.text.length} chars', style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 11, fontFamily: 'monospace')),
                const Spacer(),
                if (_previewMode)
                  const Text('PREVIEW', style: TextStyle(
                      color: AppTheme.accent, fontSize: 10, fontWeight: FontWeight.w700))
                else
                  Text(widget.file.ext.toUpperCase(), style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11, fontFamily: 'monospace')),
              ]),
            ),
          ),
        ),
        body: _previewMode && hasHighlight
            ? Container(
                color: const Color(0xFF0D1117),
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: SyntaxHighlighter(
                      code: _ctrl.text, language: widget.file.ext),
                ),
              )
            : TextField(
                controller: _ctrl, maxLines: null, expands: true,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5,
                    color: Color(0xFFC9D1D9), height: 1.7),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                  hintText: 'এখানে কোড বা টেক্সট লিখো...',
                  hintStyle: TextStyle(color: AppTheme.textMuted, fontFamily: 'monospace'),
                  filled: true, fillColor: Color(0xFF0D1117),
                ),
              ),
      ),
    );
  }
}
