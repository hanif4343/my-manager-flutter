import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import '../db/db_helper.dart';
import '../models/project.dart';
import '../models/idea.dart';
import '../models/idea_file.dart';
import '../widgets/app_theme.dart';
import '../services/notification_service.dart';
import '../services/export_service.dart';
import 'idea_detail_screen.dart';
import 'project_version_screen.dart';
import 'file_grid_screen.dart';

class ProjectDetailScreen extends StatefulWidget {
  final Project project;
  const ProjectDetailScreen({super.key, required this.project});
  @override State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  List<Idea> _ideas = [];
  Map<String, int> _stats = {'total':0,'done':0,'doing':0,'todo':0};
  String _filter = 'all';
  String _sort = 'priority';
  bool _loading = true;
  bool _exporting = false;
  final _picker = ImagePicker();
  final _recorder = AudioRecorder();

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _recorder.dispose(); super.dispose(); }

  Future<void> _load() async {
    if (widget.project.id == null) return;
    final ideas = await DBHelper.getIdeas(widget.project.id!);
    final stats = await DBHelper.getProjectStats(widget.project.id!);
    if (mounted) setState(() { _ideas = ideas; _stats = stats; _loading = false; });
  }

  List<Idea> get _sorted {
    final list = _filter == 'all'
        ? List<Idea>.from(_ideas)
        : _ideas.where((i) => i.status == _filter).toList();
    if (_sort == 'priority') {
      const order = {'high':0,'medium':1,'low':2};
      list.sort((a,b) => (order[a.priority]??1).compareTo(order[b.priority]??1));
    } else if (_sort == 'status') {
      const order = {'doing':0,'todo':1,'done':2};
      list.sort((a,b) => (order[a.status]??1).compareTo(order[b.status]??1));
    }
    return list;
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    final result = await ExportService.exportProject(widget.project);
    if (mounted) {
      setState(() => _exporting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result != null ? '📦 Export সফল!' : '❌ Export ব্যর্থ'),
        backgroundColor: result != null ? AppTheme.green : AppTheme.red,
      ));
    }
  }

  // ─────────────────────────────────────────────────────────
  // IDEA FORM — with file/camera/voice attachment
  // ─────────────────────────────────────────────────────────
  Future<void> _showIdeaForm({Idea? idea}) async {
    final nameCtrl = TextEditingController(text: idea?.title ?? '');
    final descCtrl = TextEditingController(text: idea?.description ?? '');
    String priority = idea?.priority ?? 'medium';
    DateTime? reminder;

    // Attachments collected before saving
    final attachments = <_Attachment>[];
    bool isRecording = false;
    String? recordPath;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bg2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {

          // ── Voice recording helpers ──────────────────────
          Future<void> startRecording() async {
            final hasPermission = await _recorder.hasPermission();
            if (!hasPermission) return;
            final dir = await getTemporaryDirectory();
            recordPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
            await _recorder.start(const RecordConfig(), path: recordPath!);
            setS(() => isRecording = true);
          }

          Future<void> stopRecording() async {
            final path = await _recorder.stop();
            setS(() => isRecording = false);
            if (path != null) {
              final bytes = await File(path).readAsBytes();
              final b64 = base64Encode(bytes);
              final name = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
              setS(() => attachments.add(_Attachment(
                  name: name, type: 'audio', content: b64)));
            }
          }

          // ── Pick image ────────────────────────────────────
          Future<void> pickImage(ImageSource source) async {
            final picked = await _picker.pickImage(
                source: source, imageQuality: 85);
            if (picked == null) return;
            final bytes = await picked.readAsBytes();
            final b64 = base64Encode(bytes);
            final ext = picked.name.split('.').last.toLowerCase();
            final name = picked.name.toLowerCase().contains('icon')
                ? picked.name : 'image_${attachments.length + 1}.$ext';
            setS(() => attachments.add(
                _Attachment(name: name, type: 'image', content: b64)));
          }

          // ── Pick any file ─────────────────────────────────
          Future<void> pickFile() async {
            final result = await FilePicker.platform.pickFiles(
                type: FileType.any, allowMultiple: true, withData: true);
            if (result == null) return;
            for (final pf in result.files) {
              final bytes = pf.bytes ?? (pf.path != null
                  ? await File(pf.path!).readAsBytes() : null);
              if (bytes == null) continue;
              final dummy = IdeaFile(ideaId: 0, projectId: 0,
                  name: pf.name, type: 'binary', createdAt: 0, updatedAt: 0);
              final isText = dummy.isText;
              final content = isText
                  ? utf8.decode(bytes, allowMalformed: true)
                  : base64Encode(bytes);
              setS(() => attachments.add(_Attachment(
                  name: pf.name,
                  type: isText ? 'text' : 'binary',
                  content: content)));
            }
          }

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 16, right: 16, top: 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(child: Container(width: 40, height: 4,
                      decoration: BoxDecoration(color: AppTheme.border,
                          borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 12),

                  // Header
                  Row(children: [
                    Text(idea == null ? '💡 নতুন আইডিয়া' : '✏️ আইডিয়া এডিট',
                        style: const TextStyle(color: AppTheme.textPrimary,
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (idea != null)
                      GestureDetector(
                        onTap: () {
                          final text = [
                            idea.title,
                            if (idea.description != null &&
                                idea.description!.isNotEmpty)
                              idea.description!,
                          ].join('\n\n');
                          Clipboard.setData(ClipboardData(text: text));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('টেক্সট কপি হয়েছে! ✅'),
                                  backgroundColor: AppTheme.green,
                                  duration: Duration(seconds: 1)));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: AppTheme.bg3,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.border)),
                          child: const Row(children: [
                            Icon(Icons.copy_outlined, size: 13,
                                color: AppTheme.textSecondary),
                            SizedBox(width: 4),
                            Text('কপি', style: TextStyle(
                                color: AppTheme.textSecondary, fontSize: 12)),
                          ]),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 14),

                  // Title
                  _field(nameCtrl, 'আইডিয়ার শিরোনাম *'),
                  const SizedBox(height: 10),

                  // Description
                  _field(descCtrl, 'বিবরণ (ঐচ্ছিক)...', maxLines: 3),
                  const SizedBox(height: 12),

                  // Priority
                  const Text('অগ্রাধিকার:', style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12,
                      fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(children: ['high','medium','low'].map((k) {
                    final cfg = priorityConfig[k]!;
                    final sel = priority == k;
                    return Expanded(child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setS(() => priority = k),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: sel
                                ? (cfg['color'] as Color).withOpacity(0.15)
                                : AppTheme.bg3,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: sel
                                    ? cfg['color'] as Color
                                    : AppTheme.border,
                                width: sel ? 2 : 1),
                          ),
                          child: Text(cfg['label'] as String,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: cfg['color'] as Color,
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ));
                  }).toList()),
                  const SizedBox(height: 12),

                  // Reminder
                  const Text('রিমাইন্ডার:', style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12,
                      fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now().add(const Duration(days: 1)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        builder: (c, child) => Theme(
                          data: ThemeData.dark().copyWith(colorScheme:
                          const ColorScheme.dark(primary: AppTheme.accent,
                              surface: AppTheme.bg3)),
                          child: child!,
                        ),
                      );
                      if (d == null || !ctx.mounted) return;
                      final t = await showTimePicker(
                        context: ctx,
                        initialTime: const TimeOfDay(hour: 9, minute: 0),
                        builder: (c, child) => Theme(
                          data: ThemeData.dark().copyWith(colorScheme:
                          const ColorScheme.dark(primary: AppTheme.accent,
                              surface: AppTheme.bg3)),
                          child: child!,
                        ),
                      );
                      if (t == null) return;
                      setS(() => reminder = DateTime(
                          d.year, d.month, d.day, t.hour, t.minute));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: AppTheme.bg3,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: reminder != null
                                ? AppTheme.accent : AppTheme.border,
                            width: reminder != null ? 1.5 : 1),
                      ),
                      child: Row(children: [
                        Icon(Icons.alarm,
                            color: reminder != null
                                ? AppTheme.accent : AppTheme.textMuted,
                            size: 18),
                        const SizedBox(width: 10),
                        Text(
                          reminder != null
                              ? '${reminder!.day}/${reminder!.month}/${reminder!.year} ${reminder!.hour}:${reminder!.minute.toString().padLeft(2,'0')}'
                              : 'তারিখ ও সময় বেছে নাও',
                          style: TextStyle(
                              color: reminder != null
                                  ? AppTheme.textPrimary : AppTheme.textMuted,
                              fontSize: 13),
                        ),
                        const Spacer(),
                        if (reminder != null)
                          GestureDetector(
                              onTap: () => setS(() => reminder = null),
                              child: const Icon(Icons.close,
                                  color: AppTheme.textMuted, size: 16)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── ATTACHMENTS SECTION ──────────────────
                  const Text('ফাইল / ছবি / ভয়েস:', style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12,
                      fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),

                  // Action buttons row
                  Row(children: [
                    // File
                    _attachBtn(
                      icon: Icons.attach_file_outlined,
                      label: 'ফাইল',
                      color: AppTheme.accent,
                      onTap: pickFile,
                    ),
                    const SizedBox(width: 8),
                    // Gallery
                    _attachBtn(
                      icon: Icons.photo_library_outlined,
                      label: 'গ্যালারি',
                      color: AppTheme.green,
                      onTap: () => pickImage(ImageSource.gallery),
                    ),
                    const SizedBox(width: 8),
                    // Camera
                    _attachBtn(
                      icon: Icons.camera_alt_outlined,
                      label: 'ক্যামেরা',
                      color: AppTheme.yellow,
                      onTap: () => pickImage(ImageSource.camera),
                    ),
                    const SizedBox(width: 8),
                    // Voice record
                    Expanded(child: GestureDetector(
                      onTap: () => isRecording
                          ? stopRecording()
                          : startRecording(),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isRecording
                              ? AppTheme.red.withOpacity(0.15)
                              : AppTheme.bg3,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: isRecording
                                  ? AppTheme.red : AppTheme.border,
                              width: isRecording ? 2 : 1),
                        ),
                        child: Column(children: [
                          Icon(
                            isRecording ? Icons.stop_circle : Icons.mic_outlined,
                            color: isRecording ? AppTheme.red : AppTheme.textMuted,
                            size: 20,
                          ),
                          const SizedBox(height: 3),
                          Text(isRecording ? 'Stop' : 'ভয়েস',
                              style: TextStyle(
                                  color: isRecording
                                      ? AppTheme.red : AppTheme.textMuted,
                                  fontSize: 10, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    )),
                  ]),

                  // Attachment preview list
                  if (attachments.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ...attachments.asMap().entries.map((entry) {
                      final i = entry.key;
                      final a = entry.value;
                      final icon = a.type == 'image'
                          ? Icons.image_outlined
                          : a.type == 'audio'
                              ? Icons.mic
                              : Icons.insert_drive_file_outlined;
                      final color = a.type == 'image'
                          ? AppTheme.green
                          : a.type == 'audio'
                              ? AppTheme.red
                              : AppTheme.accent;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                            color: AppTheme.bg3,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: color.withOpacity(0.3))),
                        child: Row(children: [
                          Icon(icon, color: color, size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text(a.name,
                              style: const TextStyle(color: AppTheme.textPrimary,
                                  fontSize: 12, fontFamily: 'monospace'),
                              overflow: TextOverflow.ellipsis)),
                          GestureDetector(
                            onTap: () => setS(() => attachments.removeAt(i)),
                            child: const Icon(Icons.close,
                                color: AppTheme.textMuted, size: 16),
                          ),
                        ]),
                      );
                    }),
                  ],

                  const SizedBox(height: 14),

                  // Save button
                  SizedBox(width: double.infinity, child: ElevatedButton.icon(
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      final n = now();
                      int ideaId;
                      if (idea == null) {
                        ideaId = await DBHelper.insertIdea(Idea(
                          projectId: widget.project.id!,
                          title: nameCtrl.text.trim(),
                          description: descCtrl.text.trim().isEmpty
                              ? null : descCtrl.text.trim(),
                          priority: priority, createdAt: n, updatedAt: n,
                        ));
                      } else {
                        ideaId = idea.id!;
                        await DBHelper.updateIdea(idea.copyWith(
                          title: nameCtrl.text.trim(),
                          description: descCtrl.text.trim().isEmpty
                              ? null : descCtrl.text.trim(),
                          priority: priority, updatedAt: n,
                        ));
                      }

                      // Reminder
                      if (reminder != null &&
                          reminder!.isAfter(DateTime.now())) {
                        await NotificationService.scheduleNotification(
                          ideaId + 1000, '💡 ${nameCtrl.text.trim()}',
                          'এই আইডিয়ার কাজ করার সময় হয়েছে!', reminder!,
                        );
                      }

                      // Save attachments
                      for (final a in attachments) {
                        await DBHelper.insertFile(IdeaFile(
                          ideaId: ideaId,
                          projectId: widget.project.id!,
                          name: a.name, type: a.type,
                          content: a.content, createdAt: n, updatedAt: n,
                        ));
                      }

                      if (ctx.mounted) Navigator.pop(ctx);
                      _load();
                    },
                    icon: Icon(idea == null ? Icons.add : Icons.check,
                        size: 18, color: Colors.white),
                    label: Text(
                      idea == null
                          ? 'আইডিয়া যোগ করো'
                              + (attachments.isNotEmpty
                                  ? ' (${attachments.length} ফাইল)' : '')
                          : 'আপডেট করো',
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  )),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── idea card copy: title + description ──────────────────
  void _copyIdea(Idea idea) {
    final text = [
      idea.title,
      if (idea.description != null && idea.description!.isNotEmpty)
        idea.description!,
    ].join('\n\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('কপি হয়েছে! ✅'),
            backgroundColor: AppTheme.green,
            duration: Duration(seconds: 1)));
  }

  Future<void> _updateStatus(Idea idea, String status) async {
    await DBHelper.updateIdea(idea.copyWith(status: status, updatedAt: now()));
    _load();
  }

  Future<void> _delete(Idea idea) async {
    if (idea.id == null) return;
    final confirm = await showDialog<bool>(context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bg3,
        title: const Text('মুছবে?',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('"${idea.title}" মুছে যাবে।',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('বাতিল')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('মুছো',
                  style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    if (confirm == true) { await DBHelper.deleteIdea(idea.id!); _load(); }
  }

  @override
  Widget build(BuildContext context) {
    final total = _stats['total']!;
    final done = _stats['done']!;
    final progress = total > 0 ? done / total : 0.0;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(
              color: widget.project.color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.project.name,
              style: const TextStyle(color: AppTheme.textPrimary,
                  fontSize: 16, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          PopupMenuButton<String>(
            color: AppTheme.bg3,
            icon: const Icon(Icons.sort, color: AppTheme.textSecondary, size: 20),
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => [
              _menuItem('priority', Icons.flag_outlined, 'Priority অনুযায়ী'),
              _menuItem('status', Icons.timelapse, 'Status অনুযায়ী'),
              _menuItem('created', Icons.access_time, 'তারিখ অনুযায়ী'),
            ],
          ),
          _exporting
              ? const Padding(padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.accent)))
              : IconButton(onPressed: _export,
                  icon: const Icon(Icons.upload_outlined, size: 20),
                  tooltip: 'ZIP Export'),
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => FileGridScreen(project: widget.project))),
            icon: const Icon(Icons.grid_view_outlined, size: 20),
            tooltip: 'সব ফাইল',
          ),
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => ProjectVersionScreen(project: widget.project))),
            icon: const Icon(Icons.history, size: 20),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : Column(children: [
              Container(
                padding: const EdgeInsets.fromLTRB(12,12,12,10),
                color: AppTheme.bg2,
                child: Column(children: [
                  Row(children: [
                    _statBox('মোট', total.toString(), AppTheme.textSecondary),
                    _statBox('বাকি', _stats['todo'].toString(), AppTheme.textMuted),
                    _statBox('চলছে', _stats['doing'].toString(), AppTheme.yellow),
                    _statBox('শেষ', done.toString(), AppTheme.green),
                  ]),
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('অগ্রগতি', style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
                    Text('${(progress*100).round()}%', style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12,
                        fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: progress, minHeight: 6,
                      backgroundColor: AppTheme.bg3,
                      valueColor: AlwaysStoppedAnimation(widget.project.color)),
                  ),
                ]),
              ),
              Container(
                color: AppTheme.bg2,
                padding: const EdgeInsets.fromLTRB(12,0,12,10),
                child: SingleChildScrollView(scrollDirection: Axis.horizontal,
                  child: Row(children: ['all','todo','doing','done'].map((f) {
                    final label = f=='all' ? 'সব'
                        : statusConfig[f]!['label'] as String;
                    final sel = _filter == f;
                    final color = f=='all' ? AppTheme.accent
                        : statusConfig[f]!['color'] as Color;
                    return Padding(padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _filter = f),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: sel ? color.withOpacity(0.15) : AppTheme.bg3,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: sel ? color : AppTheme.border),
                          ),
                          child: Text(label, style: TextStyle(
                              color: sel ? color : AppTheme.textSecondary,
                              fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    );
                  }).toList()),
                ),
              ),
              const Divider(height: 1, color: AppTheme.border),
              Expanded(
                child: _sorted.isEmpty
                    ? Center(child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('💡', style: TextStyle(fontSize: 40)),
                          const SizedBox(height: 10),
                          const Text('কোনো আইডিয়া নেই', style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 15)),
                        ]))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _sorted.length,
                        separatorBuilder: (_,__) => const SizedBox(height: 8),
                        itemBuilder: (_,i) => _ideaCard(_sorted[i]),
                      ),
              ),
            ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showIdeaForm(),
        backgroundColor: AppTheme.accent,
        icon: const Icon(Icons.lightbulb_outline, color: Colors.white),
        label: const Text('আইডিয়া', style: TextStyle(
            fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }

  Widget _ideaCard(Idea idea) {
    final sc = statusConfig[idea.status]!;
    final pc = priorityConfig[idea.priority]!;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(
              builder: (_) => IdeaDetailScreen(
                  idea: idea, project: widget.project)));
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            GestureDetector(
              onTap: () {
                const next = {'todo':'doing','doing':'done','done':'todo'};
                _updateStatus(idea, next[idea.status]!);
              },
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: (sc['color'] as Color).withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: sc['color'] as Color, width: 2),
                ),
                child: Icon(
                  idea.status=='done' ? Icons.check_rounded
                      : idea.status=='doing'
                          ? Icons.timelapse_rounded
                          : Icons.radio_button_unchecked_rounded,
                  size: 18, color: sc['color'] as Color,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(idea.title,
                    style: TextStyle(
                        color: idea.status=='done'
                            ? AppTheme.textMuted : AppTheme.textPrimary,
                        fontSize: 14, fontWeight: FontWeight.w600,
                        decoration: idea.status=='done'
                            ? TextDecoration.lineThrough : null),
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
                // Copy title + description
                GestureDetector(
                  onTap: () => _copyIdea(idea),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(Icons.copy_outlined,
                        size: 14, color: AppTheme.textMuted),
                  ),
                ),
              ]),
              if (idea.description != null &&
                  idea.description!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(idea.description!, style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 6),
              Row(children: [
                _badge(pc['label'] as String, pc['color'] as Color),
                const SizedBox(width: 6),
                _badge(sc['label'] as String, sc['color'] as Color),
              ]),
            ])),
            const SizedBox(width: 8),
            Column(children: [
              _actionBtn(Icons.edit_outlined, AppTheme.accent,
                      () => _showIdeaForm(idea: idea)),
              const SizedBox(height: 6),
              _actionBtn(Icons.delete_outline, AppTheme.red,
                      () => _delete(idea)),
            ]),
          ]),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────
  Widget _attachBtn({required IconData icon, required String label,
      required Color color, required VoidCallback onTap}) =>
      Expanded(child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.bg3,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w600)),
          ]),
        ),
      ));

  PopupMenuItem<String> _menuItem(String val, IconData icon, String label) =>
      PopupMenuItem(value: val,
        child: Row(children: [
          Icon(icon, size: 16,
              color: _sort==val ? AppTheme.accent : AppTheme.textSecondary),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(
              color: _sort==val ? AppTheme.accent : AppTheme.textPrimary)),
        ]),
      );

  Widget _actionBtn(IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(onTap: onTap,
        child: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.3))),
          child: Icon(icon, size: 16, color: color),
        ),
      );

  Widget _statBox(String label, String val, Color color) => Expanded(
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: AppTheme.bg3,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border)),
      child: Column(children: [
        Text(val, style: TextStyle(
            color: color, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(
            color: AppTheme.textMuted, fontSize: 11)),
      ]),
    ),
  );

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(
        color: color, fontSize: 11, fontWeight: FontWeight.w600)),
  );

  Widget _field(TextEditingController ctrl, String hint,
      {int maxLines=1}) => TextField(
    controller: ctrl, maxLines: maxLines,
    style: const TextStyle(color: AppTheme.textPrimary),
    decoration: InputDecoration(
      hintText: hint, hintStyle: const TextStyle(color: AppTheme.textMuted),
      filled: true, fillColor: AppTheme.bg3,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.accent, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    ),
  );
}

class _Attachment {
  final String name, type, content;
  _Attachment({required this.name, required this.type, required this.content});
}
