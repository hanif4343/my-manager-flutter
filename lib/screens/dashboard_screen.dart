import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../db/db_helper.dart';
import '../models/project.dart';
import '../widgets/app_theme.dart';
import '../services/export_service.dart';
import 'project_detail_screen.dart';
import 'project_form_screen.dart';
import 'backup_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const DashboardScreen({super.key, required this.onThemeToggle});
  @override State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Project> _projects = [];
  Map<int, Map<String, int>> _stats = {};
  bool _loading = true;
  bool _importing = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final projects = await DBHelper.getProjects();
    final stats = <int, Map<String, int>>{};
    for (final p in projects) {
      if (p.id != null) stats[p.id!] = await DBHelper.getProjectStats(p.id!);
    }
    if (mounted) setState(() {
      _projects = projects; _stats = stats; _loading = false;
    });
  }

  Future<void> _importProject() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: false,
      );
      if (result == null || result.files.single.path == null) return;
      setState(() => _importing = true);
      final importResult = await ExportService.importProject(
          result.files.single.path!);
      if (mounted) {
        setState(() => _importing = false);
        if (importResult.isOk) {
          _load();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ Import সফল! ${importResult.ideaCount} আইডিয়া, ${importResult.fileCount} ফাইল'),
            backgroundColor: AppTheme.green,
            duration: const Duration(seconds: 3),
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('❌ ${importResult.error ?? 'Import ব্যর্থ'}'),
            backgroundColor: AppTheme.red,
            duration: const Duration(seconds: 3),
          ));
        }
      }
    } catch (e) {
      setState(() => _importing = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.red));
    }
  }

  Future<void> _delete(Project p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bg3,
        title: const Text('মুছে ফেলবে?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('"${p.name}" এবং সব ডেটা মুছে যাবে।',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('বাতিল')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('মুছো', style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    if (confirm == true && p.id != null) {
      await DBHelper.deleteProject(p.id!);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg2,
        title: Row(children: [
          const Text('🚀', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          const Text('My Manager', style: TextStyle(
              color: AppTheme.textPrimary, fontWeight: FontWeight.w800)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppTheme.bg3,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.border)),
            child: Text('${_projects.length} প্রজেক্ট',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ),
        ]),
        automaticallyImplyLeading: false,
        actions: [
          // Search
          IconButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SearchScreen())),
            icon: const Icon(Icons.search, size: 22),
            tooltip: 'খোঁজো',
          ),
          // Import ZIP
          _importing
              ? const Padding(padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: AppTheme.accent)))
              : IconButton(
                  onPressed: _importProject,
                  icon: const Icon(Icons.download_outlined, size: 22),
                  tooltip: 'ZIP Import',
                ),
          // Drive
          IconButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const BackupScreen())),
            icon: const Icon(Icons.cloud_outlined, size: 22),
            tooltip: 'Drive Backup',
          ),
          // Settings
          IconButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => SettingsScreen(
                    onThemeToggle: widget.onThemeToggle))),
            icon: const Icon(Icons.settings_outlined, size: 22),
            tooltip: 'সেটিংস',
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.border),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _projects.isEmpty ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _load, color: AppTheme.accent,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _projects.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _projectCard(_projects[i]),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ProjectFormScreen()));
          _load();
        },
        backgroundColor: AppTheme.accent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('নতুন প্রজেক্ট',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('🚀', style: TextStyle(fontSize: 56)),
      const SizedBox(height: 16),
      const Text('এখনো কোনো প্রজেক্ট নেই', style: TextStyle(
          color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      const Text('+ বাটনে চাপো অথবা ZIP import করো',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        onPressed: _importProject,
        icon: const Icon(Icons.download_outlined, color: AppTheme.accent),
        label: const Text('ZIP থেকে Import করো',
            style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppTheme.accent),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
      ),
    ]),
  );

  Widget _projectCard(Project p) {
    final st = _stats[p.id] ?? {'total':0,'done':0,'doing':0,'todo':0};
    final total = st['total']!;
    final done = st['done']!;
    final progress = total > 0 ? done / total : 0.0;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: p)));
          _load();
        },
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(height: 4, decoration: BoxDecoration(
            color: p.color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          )),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(p.name, style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 16,
                    fontWeight: FontWeight.w700))),
                _iconBtn(Icons.edit_outlined, () async {
                  await Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ProjectFormScreen(project: p)));
                  _load();
                }),
                const SizedBox(width: 4),
                _iconBtn(Icons.delete_outline, () => _delete(p),
                    color: AppTheme.red),
              ]),
              if (p.description != null && p.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(p.description!, style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              if (p.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4,
                    children: p.tags.map((t) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppTheme.bg3,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.border)),
                      child: Text(t, style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                    )).toList()),
              ],
              const SizedBox(height: 10),
              ClipRRect(borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress, minHeight: 5,
                  backgroundColor: AppTheme.bg3,
                  valueColor: AlwaysStoppedAnimation(p.color),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                _statChip('⭕ ${st['todo']}', AppTheme.textMuted),
                const SizedBox(width: 10),
                _statChip('⏳ ${st['doing']}', AppTheme.yellow),
                const SizedBox(width: 10),
                _statChip('✅ ${st['done']}', AppTheme.green),
                const Spacer(),
                Text('${(progress * 100).round()}%', style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13,
                    fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
        ]),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap,
      {Color color = AppTheme.textMuted}) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: AppTheme.bg3,
          borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, size: 16, color: color),
    ),
  );

  Widget _statChip(String text, Color color) => Text(text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600));
}
