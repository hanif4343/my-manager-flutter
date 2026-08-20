import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'app_theme.dart';
import '../db/db_helper.dart';
import '../models/idea.dart';
import '../models/project.dart';

/// Content shown inside the system-wide overlay window (the actual
/// Messenger-style chat head that floats over other apps / the home
/// screen). This runs in its own isolated Flutter engine — started from
/// `overlayMain()` in main.dart — completely separate from the main app
/// UI, which is why it has its own tiny widget tree here.
///
/// Two states:
///  - Collapsed: a small round bubble. The plugin handles dragging;
///    tapping it asks the native side to grow the window and switches
///    to the expanded state.
///  - Expanded: a compact "quick add idea" panel. Saving or closing
///    shrinks the window back down to the bubble.
class OverlayBubble extends StatefulWidget {
  const OverlayBubble({super.key});
  @override State<OverlayBubble> createState() => _OverlayBubbleState();
}

class _OverlayBubbleState extends State<OverlayBubble> {
  static const collapsedSize = 60;
  static const expandedWidth = 300;
  static const expandedHeight = 360;

  bool _expanded = false;
  bool _loading = true;
  List<Project> _projects = [];
  int? _selectedProjectId;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    try {
      final list = await DBHelper.getProjects();
      if (mounted) setState(() {
        _projects = list;
        _selectedProjectId = list.isNotEmpty ? list.first.id : null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _expand() async {
    await FlutterOverlayWindow.resizeOverlay(expandedWidth, expandedHeight, true);
    // focusPointer lets the TextField actually receive the keyboard.
    await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
    setState(() => _expanded = true);
  }

  Future<void> _collapse() async {
    await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
    await FlutterOverlayWindow.resizeOverlay(collapsedSize, collapsedSize, true);
    _ctrl.clear();
    setState(() => _expanded = false);
  }

  Future<void> _save() async {
    final title = _ctrl.text.trim();
    if (title.isEmpty || _selectedProjectId == null) return;
    final n = DateTime.now().millisecondsSinceEpoch;
    await DBHelper.insertIdea(Idea(
      projectId: _selectedProjectId!, title: title,
      createdAt: n, updatedAt: n,
    ));
    // Let the main app know something changed, in case it's open in the
    // background and wants to refresh its project list.
    await FlutterOverlayWindow.shareData('idea_added');
    await _collapse();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: _expanded ? _expandedPanel() : _collapsedBubble(),
      ),
    );
  }

  Widget _collapsedBubble() => GestureDetector(
    onTap: _expand,
    child: Container(
      width: collapsedSize.toDouble(),
      height: collapsedSize.toDouble(),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.35),
              blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: const Icon(Icons.lightbulb_outline, color: Colors.white, size: 26),
    ),
  );

  Widget _expandedPanel() => Center(
    child: Container(
      width: expandedWidth.toDouble(),
      height: expandedHeight.toDouble(),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.4),
              blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('⚡', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                const Expanded(child: Text('Quick Idea',
                    style: TextStyle(color: AppTheme.textPrimary,
                        fontSize: 16, fontWeight: FontWeight.w700))),
                GestureDetector(
                  onTap: _collapse,
                  child: const Icon(Icons.close, size: 20, color: AppTheme.textMuted),
                ),
              ]),
              const SizedBox(height: 12),
              if (_projects.isEmpty)
                const Expanded(child: Center(
                  child: Text('আগে অ্যাপে একটা প্রজেক্ট বানাও',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      textAlign: TextAlign.center),
                ))
              else ...[
                const Text('প্রজেক্ট:', style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                SizedBox(
                  height: 34,
                  child: ListView(scrollDirection: Axis.horizontal, children: _projects.map((p) {
                    final sel = _selectedProjectId == p.id;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedProjectId = p.id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: sel ? p.color.withOpacity(0.2) : AppTheme.bg3,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: sel ? p.color : AppTheme.border,
                                width: sel ? 2 : 1),
                          ),
                          child: Text(p.name, style: TextStyle(
                              color: sel ? p.color : AppTheme.textSecondary,
                              fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    );
                  }).toList()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ctrl, autofocus: true, maxLines: 3, minLines: 1,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'আইডিয়া লিখো...',
                    hintStyle: const TextStyle(color: AppTheme.textMuted),
                    filled: true, fillColor: AppTheme.bg3,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.accent, width: 2)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const Spacer(),
                SizedBox(width: double.infinity, child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.add, color: Colors.white, size: 16),
                  label: const Text('যোগ করো', style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                )),
              ],
            ]),
    ),
  );
}
