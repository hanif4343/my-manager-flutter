import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../db/db_helper.dart';
import '../models/project.dart';
import '../widgets/app_theme.dart';
import '../services/export_service.dart';
import '../services/drive_service.dart';
import 'project_detail_screen.dart';
import 'project_form_screen.dart';
import 'backup_screen.dart';

/// Dashboard tab — shows the project list. Search and Settings now live
/// in the bottom navigation, so this AppBar only keeps what's needed at
/// a glance (cloud sync status) plus a small overflow menu for the
/// less-frequent "Import ZIP" action.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Project> _projects = [];
  Map<int, Map<String, int>> _stats = {};
  bool _loading = true;
  bool _importing = false;
  bool _cloudConnected = false;

  @override
  void initState() { super.initState(); _load(); _checkCloud(); }

  Future<void> _checkCloud() async {
    // reflects real Drive connection: filled green cloud = সিংক্‌ড, empty = অফলাইন
    bool ok = DriveService.instance.isSignedIn;
    if (!ok) ok = await DriveService.instance.signInSilently();
    if (mounted) setState(() => _cloudConnected = ok);
  }

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
        title:  Text('মুছে ফেলবে?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('"${p.name}" এবং সব ডেটা মুছে যাবে।',
            style:  TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('বাতিল')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child:  Text('মুছো', style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    if (confirm == true && p.id != null) {
      await DBHelper.deleteProject(p.id!);
      _load();
    }
  }

  Future<void> _duplicate(Project p) async {
    if (p.id == null) return;
    final newId = await DBHelper.duplicateProject(p.id!);
    if (mounted && newId != null) {
      _load();
      ScaffoldMessenger.of(context).showSnackBar( SnackBar(
        content: Text('✅ প্রজেক্ট কপি হয়েছে'),
        backgroundColor: AppTheme.green,
        duration: Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg2,
        title: Row(children: [
          const Text('📓', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text('My Manager', style: AppTheme.display(size: 18)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppTheme.bg3,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.border)),
            child: Text('📁 ${_projects.length} প্রজেক্ট',
                style:  TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ),
        ]),
        automaticallyImplyLeading: false,
        actions: [
          // Drive — glanceable status, kept visible (ভরাট সবুজ = সিংক্‌ড, ফাঁকা = অফলাইন)
          IconButton(
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const BackupScreen()));
              _checkCloud();
            },
            icon: Icon(
              _cloudConnected ? Icons.cloud_rounded : Icons.cloud_outlined,
              size: 22,
              color: _cloudConnected ? AppTheme.green : AppTheme.textMuted,
            ),
            tooltip: _cloudConnected ? '☁️ সিংক্‌ড' : '☁️ অফলাইন — ট্যাপ করে কানেক্ট করো',
          ),
          // Everything else (Search & Settings now live in the bottom nav,
          // so only the occasional "Import ZIP" action needs a home here)
          _importing
              ? const Padding(padding: EdgeInsets.all(16),
                  child: SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: AppTheme.accent)))
              : PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 22),
                  color: AppTheme.bg2,
                  onSelected: (v) { if (v == 'import') _importProject(); },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'import', child: Row(children: [
                      Icon(Icons.download_outlined, size: 18, color: AppTheme.textSecondary),
                      SizedBox(width: 10),
                      Text('ZIP ইম্পোর্ট করো'),
                    ])),
                  ],
                ),
        ],
        bottom:  PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.border),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _projects.isEmpty ? _emptyState()
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: _projects.length,
                  proxyDecorator: (child, index, animation) => Material(
                    color: Colors.transparent,
                    elevation: 8,
                    shadowColor: Colors.black45,
                    borderRadius: BorderRadius.circular(12),
                    child: child,
                  ),
                  onReorder: (oldIndex, newIndex) async {
                    if (newIndex > oldIndex) newIndex--;
                    setState(() {
                      final item = _projects.removeAt(oldIndex);
                      _projects.insert(newIndex, item);
                    });
                    for (int i = 0; i < _projects.length; i++) {
                      await DBHelper.updateProjectOrder(_projects[i].id!, i);
                    }
                  },
                  itemBuilder: (_, i) => Padding(
                    key: ValueKey(_projects[i].id),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _projectCard(_projects[i]),
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
        label: const Text('✨ নতুন প্রজেক্ট',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('📓', style: TextStyle(fontSize: 56)),
      const SizedBox(height: 16),
      Text('এখনো কোনো প্রজেক্ট নেই', style: AppTheme.display(size: 18)),
      const SizedBox(height: 8),
       Text('+ বাটনে চাপো অথবা ZIP import করো',
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
                Expanded(child: Text(p.name, style: AppTheme.display(size: 16))),
                // Edit & Copy — the two most-used actions, kept visible.
                _iconBtn(Icons.edit_outlined, () async {
                  await Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ProjectFormScreen(project: p)));
                  _load();
                }, tooltip: 'এডিট'),
                const SizedBox(width: 4),
                _iconBtn(Icons.copy_outlined, () => _duplicate(p),
                    tooltip: 'কপি'),
                const SizedBox(width: 4),
                // Delete — tucked into a menu so it can't be tapped by accident.
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: AppTheme.bg3,
                        borderRadius: BorderRadius.circular(8)),
                    child:  Icon(Icons.more_vert, size: 16, color: AppTheme.textMuted),
                  ),
                  color: AppTheme.bg2,
                  onSelected: (v) { if (v == 'delete') _delete(p); },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'delete', child: Row(children: [
                      Icon(Icons.delete_outline, size: 18, color: AppTheme.red),
                      SizedBox(width: 10),
                      Text('মুছে ফেলো', style: TextStyle(color: AppTheme.red)),
                    ])),
                  ],
                ),
              ]),
              if (p.description != null && p.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(p.description!, style:  TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
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
                Text('${(progress * 100).round()}%', style:  TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13,
                    fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap,
      {Color? color, String? tooltip}) => Tooltip(
    message: tooltip ?? '',
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: AppTheme.bg3,
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 16, color: color ?? AppTheme.textMuted),
      ),
    ),
  );

  Widget _statChip(String text, Color color) => Text(text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600));
}
