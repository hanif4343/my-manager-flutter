import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../models/project.dart';
import '../models/idea.dart';
import '../widgets/app_theme.dart';
import 'idea_detail_screen.dart';

class ProjectDetailScreen extends StatefulWidget {
  final Project project;
  const ProjectDetailScreen({super.key, required this.project});
  @override State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  List<Idea> _ideas = [];
  Map<String, int> _stats = {'total': 0, 'done': 0, 'doing': 0, 'todo': 0};
  String _filter = 'all';
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (widget.project.id == null) return;
    final ideas = await DBHelper.getIdeas(widget.project.id!);
    final stats = await DBHelper.getProjectStats(widget.project.id!);
    if (mounted) setState(() { _ideas = ideas; _stats = stats; _loading = false; });
  }

  List<Idea> get _filtered =>
      _filter == 'all' ? _ideas : _ideas.where((i) => i.status == _filter).toList();

  Future<void> _showIdeaForm({Idea? idea}) async {
    final nameCtrl = TextEditingController(text: idea?.title ?? '');
    final descCtrl = TextEditingController(text: idea?.description ?? '');
    String priority = idea?.priority ?? 'medium';

    await showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.bg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(idea == null ? 'নতুন আইডিয়া' : 'আইডিয়া এডিট',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          _field(nameCtrl, 'আইডিয়ার শিরোনাম *'),
          const SizedBox(height: 10),
          _field(descCtrl, 'বিবরণ (ঐচ্ছিক)', maxLines: 2),
          const SizedBox(height: 12),
          const Text('অগ্রাধিকার:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 8),
          Row(children: ['low', 'medium', 'high'].map((k) {
            final cfg = priorityConfig[k]!;
            final sel = priority == k;
            return Expanded(child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setS(() => priority = k),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? (cfg['color'] as Color).withOpacity(0.2) : AppTheme.bg3,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: sel ? cfg['color'] as Color : AppTheme.border, width: sel ? 2 : 1),
                  ),
                  child: Text(cfg['label'] as String,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cfg['color'] as Color, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ));
          }).toList()),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final n = now();
              if (idea == null) {
                await DBHelper.insertIdea(Idea(
                  projectId: widget.project.id!, title: nameCtrl.text.trim(),
                  description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  priority: priority, createdAt: n, updatedAt: n,
                ));
              } else {
                await DBHelper.updateIdea(idea.copyWith(
                  title: nameCtrl.text.trim(),
                  description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  priority: priority, updatedAt: n,
                ));
              }
              Navigator.pop(ctx);
              _load();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text(idea == null ? 'যোগ করো' : 'আপডেট করো',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          )),
          const SizedBox(height: 20),
        ]),
      )),
    );
  }

  Future<void> _updateStatus(Idea idea, String status) async {
    await DBHelper.updateIdea(idea.copyWith(status: status, updatedAt: now()));
    _load();
  }

  Future<void> _delete(Idea idea) async {
    if (idea.id == null) return;
    await DBHelper.deleteIdea(idea.id!);
    _load();
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
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis)),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : Column(children: [
              // Stats
              Container(
                padding: const EdgeInsets.all(16),
                color: AppTheme.bg2,
                child: Column(children: [
                  Row(children: [
                    _statBox('মোট', total.toString(), AppTheme.textSecondary),
                    _statBox('বাকি', _stats['todo'].toString(), AppTheme.textMuted),
                    _statBox('চলছে', _stats['doing'].toString(), AppTheme.yellow),
                    _statBox('শেষ', done.toString(), AppTheme.green),
                  ]),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('অগ্রগতি', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    Text('${(progress * 100).round()}%',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress, minHeight: 8,
                      backgroundColor: AppTheme.bg3,
                      valueColor: AlwaysStoppedAnimation(widget.project.color),
                    ),
                  ),
                ]),
              ),
              // Filter
              Container(
                color: AppTheme.bg2,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: ['all', 'todo', 'doing', 'done'].map((f) {
                    final label = f == 'all' ? 'সব' : statusConfig[f]!['label'] as String;
                    final sel = _filter == f;
                    final color = f == 'all' ? AppTheme.accent : statusConfig[f]!['color'] as Color;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _filter = f),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: sel ? color.withOpacity(0.15) : AppTheme.bg3,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: sel ? color : AppTheme.border),
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
              // Ideas list
              Expanded(
                child: _filtered.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Text('💡', style: TextStyle(fontSize: 40)),
                        const SizedBox(height: 12),
                        Text(_filter == 'all' ? 'কোনো আইডিয়া নেই' : 'এই ক্যাটাগরিতে কিছু নেই',
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                      ]))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _ideaCard(_filtered[i]),
                      ),
              ),
            ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showIdeaForm(),
        backgroundColor: AppTheme.accent,
        icon: const Icon(Icons.lightbulb_outline),
        label: const Text('আইডিয়া', style: TextStyle(fontWeight: FontWeight.w700)),
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
              builder: (_) => IdeaDetailScreen(idea: idea, project: widget.project)));
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              // Status cycle button
              GestureDetector(
                onTap: () {
                  const next = {'todo': 'doing', 'doing': 'done', 'done': 'todo'};
                  _updateStatus(idea, next[idea.status]!);
                },
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: (sc['color'] as Color).withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: sc['color'] as Color, width: 2),
                  ),
                  child: Icon(
                    idea.status == 'done' ? Icons.check : idea.status == 'doing' ? Icons.timelapse : Icons.circle_outlined,
                    size: 14, color: sc['color'] as Color,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(idea.title,
                  style: TextStyle(
                      color: idea.status == 'done' ? AppTheme.textMuted : AppTheme.textPrimary,
                      fontSize: 14, fontWeight: FontWeight.w600,
                      decoration: idea.status == 'done' ? TextDecoration.lineThrough : null))),
              GestureDetector(
                onTap: () => _showIdeaForm(idea: idea),
                child: const Icon(Icons.edit_outlined, size: 16, color: AppTheme.textMuted),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _delete(idea),
                child: const Icon(Icons.delete_outline, size: 16, color: AppTheme.red),
              ),
            ]),
            if (idea.description != null && idea.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 38),
                child: Text(idea.description!,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ],
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: Row(children: [
                _badge(pc['label'] as String, pc['color'] as Color),
                const SizedBox(width: 8),
                _badge(sc['label'] as String, sc['color'] as Color),
                const Spacer(),
                const Icon(Icons.chevron_right, size: 16, color: AppTheme.textMuted),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _statBox(String label, String val, Color color) => Expanded(
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: AppTheme.bg3, borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border)),
      child: Column(children: [
        Text(val, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      ]),
    ),
  );

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
  );

  Widget _field(TextEditingController ctrl, String hint, {int maxLines = 1}) => TextField(
    controller: ctrl, maxLines: maxLines,
    style: const TextStyle(color: AppTheme.textPrimary),
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
