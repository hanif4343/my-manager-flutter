import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../models/idea.dart';
import '../models/idea_file.dart';
import '../models/project.dart';
import '../widgets/app_theme.dart';

class CopyMoveScreen extends StatefulWidget {
  final IdeaFile file;
  final String mode; // 'copy' or 'move'
  final int currentIdeaId;
  const CopyMoveScreen({super.key, required this.file, required this.mode, required this.currentIdeaId});
  @override State<CopyMoveScreen> createState() => _CopyMoveScreenState();
}

class _CopyMoveScreenState extends State<CopyMoveScreen> {
  List<Project> _projects = [];
  Map<int, List<Idea>> _ideas = {};
  int? _selectedIdeaId;
  int? _selectedProjectId;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final projects = await DBHelper.getProjects();
    final ideasMap = <int, List<Idea>>{};
    for (final p in projects) {
      if (p.id != null) ideasMap[p.id!] = await DBHelper.getIdeas(p.id!);
    }
    if (mounted) setState(() { _projects = projects; _ideas = ideasMap; _loading = false; });
  }

  Future<void> _confirm() async {
    if (_selectedIdeaId == null || _selectedProjectId == null) return;
    setState(() => _saving = true);
    if (widget.mode == 'copy') {
      await DBHelper.copyFile(widget.file, _selectedIdeaId!, _selectedProjectId!);
    } else {
      if (widget.file.id != null) await DBHelper.moveFile(widget.file.id!, _selectedIdeaId!, _selectedProjectId!);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${widget.mode == 'copy' ? 'কপি' : 'মুভ'} সম্পন্ন!'),
        backgroundColor: AppTheme.green,
      ));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCopy = widget.mode == 'copy';
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Row(children: [
          Icon(isCopy ? Icons.copy_all_outlined : Icons.drive_file_move_outline,
              color: isCopy ? AppTheme.green : AppTheme.yellow, size: 20),
          const SizedBox(width: 8),
          Text('${isCopy ? 'Copy' : 'Move'}: ${widget.file.name}',
              style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
        ]),
        actions: [
          if (_selectedIdeaId != null)
            TextButton(
              onPressed: _saving ? null : _confirm,
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))
                  : Text(isCopy ? 'কপি করো' : 'মুভ করো',
                      style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _projects.isEmpty
              ? const Center(child: Text('কোনো প্রজেক্ট নেই', style: TextStyle(color: AppTheme.textSecondary)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _projects.length,
                  itemBuilder: (_, pi) {
                    final p = _projects[pi];
                    final ideas = _ideas[p.id] ?? [];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ExpansionTile(
                        leading: Container(width: 12, height: 12,
                            decoration: BoxDecoration(color: p.color, shape: BoxShape.circle)),
                        title: Text(p.name, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                        iconColor: AppTheme.textSecondary,
                        collapsedIconColor: AppTheme.textMuted,
                        children: ideas.map((idea) {
                          final isSame = idea.id == widget.currentIdeaId;
                          final selected = _selectedIdeaId == idea.id;
                          return ListTile(
                            enabled: !isSame,
                            leading: Icon(
                              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                              color: selected ? AppTheme.accent : AppTheme.textMuted, size: 18,
                            ),
                            title: Text(idea.title,
                                style: TextStyle(
                                    color: isSame ? AppTheme.textMuted : AppTheme.textPrimary,
                                    fontSize: 13)),
                            subtitle: isSame ? const Text('(বর্তমান)', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)) : null,
                            onTap: isSame ? null : () => setState(() {
                              _selectedIdeaId = idea.id;
                              _selectedProjectId = p.id;
                            }),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
    );
  }
}
