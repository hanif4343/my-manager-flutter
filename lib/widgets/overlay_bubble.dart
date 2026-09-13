import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'app_theme.dart';
import '../db/db_helper.dart';
import '../models/idea.dart';
import '../models/project.dart';
import '../services/widget_service.dart';

/// Content shown inside the system-wide overlay window (the actual
/// Messenger-style chat head that floats over other apps / the home
/// screen). Runs in its own isolated Flutter engine, started from
/// `overlayMain()` in main.dart.
///
/// ── Why dragging is custom instead of native ────────────────────
/// The plugin's own built-in `enableDrag` was tried first, but on some
/// devices (reported: Vivo/OriginOS) its native touch handling could get
/// stuck mid-gesture — the bubble stopped responding to taps/moves *and*
/// blocked touches to the rest of the screen, bad enough to need a
/// device restart. Native drag is now always off. Moving the bubble is
/// done entirely in Flutter instead: 4 small invisible drag zones, one
/// at each corner, calling `moveOverlay()` directly and clamping the
/// result so it can never leave the screen. The center of the bubble
/// stays a plain tap-to-expand zone with no drag logic attached at all,
/// so there's no tap-vs-drag ambiguity.
///
/// Getting real screen bounds to clamp against, even from this tiny
/// 60x60 window, uses `View.of(context).display.size` — MediaQuery /
/// FlutterView.physicalSize here would only report this window's own
/// size, not the actual device screen.
class OverlayBubble extends StatefulWidget {
  const OverlayBubble({super.key});
  @override State<OverlayBubble> createState() => _OverlayBubbleState();
}

class _OverlayBubbleState extends State<OverlayBubble> {
  static const collapsedSize = 60;
  static const expandedWidth = 300;
  static const expandedHeight = 420;

  bool _expanded = false;
  bool _loadingProjects = true;
  bool _loadingIdeas = false;
  List<Project> _projects = [];
  List<Idea> _ideas = [];
  int? _selectedProjectId;

  final _newIdeaCtrl = TextEditingController();
  Idea? _editingIdea;
  final _editTitleCtrl = TextEditingController();
  final _editDescCtrl = TextEditingController();

  // Custom bounded drag — tracks the bubble's current absolute position
  // (screen coordinates), synced from the plugin once at startup, then
  // updated locally as the person drags.
  Offset? _pos;

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _syncPosition();
  }

  @override
  void dispose() {
    _newIdeaCtrl.dispose();
    _editTitleCtrl.dispose();
    _editDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _syncPosition() async {
    try {
      final p = await FlutterOverlayWindow.getOverlayPosition();
      if (mounted) setState(() => _pos = Offset(p.x, p.y));
    } catch (_) {
      // Not fatal — the first drag will just use whatever _pos ends up
      // defaulting to; worst case a small first-drag jump.
    }
  }

  /// Most-used projects first (most ideas, ties broken by recency) — the
  /// project you probably want is already selected when the panel opens.
  Future<void> _loadProjects() async {
    try {
      final list = await DBHelper.getProjectsSortedByUsage();
      if (!mounted) return;
      // Locked projects don't show up in the bubble at all — the bubble
      // can't reasonably prompt for fingerprint/PIN from its own tiny
      // overlay window, so the simplest safe answer is to just not
      // surface locked projects here rather than risk a weak bypass.
      final visible = list.where((p) => !p.isLocked).toList();
      setState(() {
        _projects = visible;
        _selectedProjectId = visible.isNotEmpty ? visible.first.id : null;
        _loadingProjects = false;
      });
      if (_selectedProjectId != null) _loadIdeas(_selectedProjectId!);
    } catch (_) {
      if (mounted) setState(() => _loadingProjects = false);
    }
  }

  /// Existing ideas for the selected project, most recently touched
  /// first — a reasonable stand-in for "most used" since there's no
  /// explicit usage counter on ideas.
  Future<void> _loadIdeas(int projectId) async {
    setState(() => _loadingIdeas = true);
    try {
      final list = await DBHelper.getIdeas(projectId);
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (mounted) setState(() { _ideas = list; _loadingIdeas = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingIdeas = false);
    }
  }

  void _selectProject(int id) {
    setState(() { _selectedProjectId = id; _editingIdea = null; });
    _loadIdeas(id);
  }

  Future<void> _addIdea() async {
    final title = _newIdeaCtrl.text.trim();
    if (title.isEmpty || _selectedProjectId == null) return;
    _newIdeaCtrl.clear();
    final n = DateTime.now().millisecondsSinceEpoch;
    await DBHelper.insertIdea(Idea(
      projectId: _selectedProjectId!, title: title,
      createdAt: n, updatedAt: n,
    ));
    await FlutterOverlayWindow.shareData('idea_added');
    WidgetService.update();
    // Stays open — quick-capture doesn't have to mean one-and-done.
    _loadIdeas(_selectedProjectId!);
  }

  void _startEdit(Idea idea) {
    setState(() {
      _editingIdea = idea;
      _editTitleCtrl.text = idea.title;
      _editDescCtrl.text = idea.description ?? '';
    });
  }

  void _cancelEdit() => setState(() => _editingIdea = null);

  Future<void> _commitEdit() async {
    final idea = _editingIdea;
    if (idea == null) return;
    final title = _editTitleCtrl.text.trim();
    if (title.isEmpty) return;
    await DBHelper.updateIdea(Idea(
      id: idea.id, projectId: idea.projectId, title: title,
      description: _editDescCtrl.text.trim().isEmpty ? null : _editDescCtrl.text.trim(),
      status: idea.status,
      priority: idea.priority, isArchived: idea.isArchived,
      deadline: idea.deadline, createdAt: idea.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    setState(() => _editingIdea = null);
    // Tells the main app engine a change happened, so it can refresh
    // immediately — matters because the overlay can float *over* the
    // main app without ever actually backgrounding it, so the app's own
    // "refresh when resumed" logic never fires in that case.
    await FlutterOverlayWindow.shareData('idea_updated');
    WidgetService.update();
    // Re-sorts to the top too, since it's now the most recently touched.
    _loadIdeas(idea.projectId);
  }

  /// Moves the bubble by [delta], clamped so it can never go past any
  /// edge of the real device screen. Uses `View.of(context).display.size`
  /// rather than MediaQuery — MediaQuery/physicalSize here would only
  /// report this tiny 60x60 window's own bounds, not the actual screen,
  /// so clamping against that would be meaningless. `display.size` is
  /// the one API that reports the true physical display regardless of
  /// how small the current window is — no fullscreen resize needed.
  void _dragBy(Offset delta) {
    if (_pos == null) return;
    final view = View.of(context);
    final dpr = view.devicePixelRatio;
    final screenW = view.display.size.width / dpr;
    final screenH = view.display.size.height / dpr;
    final next = Offset(
      (_pos!.dx + delta.dx).clamp(0.0, screenW - collapsedSize),
      (_pos!.dy + delta.dy).clamp(0.0, screenH - collapsedSize),
    );
    setState(() => _pos = next);
    FlutterOverlayWindow.moveOverlay(OverlayPosition(next.dx, next.dy))
        .catchError((_) {});
  }

  Future<void> _expand() async {
    try {
      await FlutterOverlayWindow.resizeOverlay(expandedWidth, expandedHeight, false);
      // focusPointer lets the TextField actually receive the keyboard.
      await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
      if (mounted) setState(() => _expanded = true);
    } catch (_) {
      // If the resize failed, stay collapsed rather than get stuck.
    }
  }

  Future<void> _collapse() async {
    try {
      await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
      // Drag is handled entirely by our own corner-handle logic, never
      // by the plugin's native drag — always false here.
      await FlutterOverlayWindow.resizeOverlay(collapsedSize, collapsedSize, false);
    } catch (_) {}
    setState(() { _expanded = false; _editingIdea = null; });
  }

  /// Brings the host app (My Manager itself) to the foreground.
  Future<void> _openMainApp() async {
    try {
      const intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.hanif.mymanager',
        componentName: 'com.hanif.mymanager.MainActivity',
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK, Flag.FLAG_ACTIVITY_REORDER_TO_FRONT],
      );
      await intent.launch();
    } catch (_) {
      // At worst nothing happens — the bubble itself keeps working.
    }
  }

  /// Hides the bubble for now — closes the window without touching the
  /// persisted "bubble_enabled" setting, so it comes right back the next
  /// time the app is opened. For a permanent turn-off, use the Settings
  /// toggle instead.
  Future<void> _hideForNow() async {
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
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

  Widget _collapsedBubble() => Stack(children: [
    // Center: a plain tap opens the quick-add panel. This zone doesn't
    // handle drag at all, so there's no tap-vs-drag ambiguity here.
    GestureDetector(
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35),
              blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: const Icon(Icons.lightbulb_outline, color: Colors.white, size: 26),
      ),
    ),
    // The 4 corners: press-and-drag here to move the bubble, bounded to
    // stay fully on-screen. Kept spatially separate from the center tap
    // zone on purpose — no ambiguity, no gesture-arena conflicts.
    _cornerHandle(top: 0, left: 0),
    _cornerHandle(top: 0, right: 0),
    _cornerHandle(bottom: 0, left: 0),
    _cornerHandle(bottom: 0, right: 0),
  ]);

  Widget _cornerHandle({double? top, double? bottom, double? left, double? right}) => Positioned(
    top: top, bottom: bottom, left: left, right: right,
    child: GestureDetector(
      onPanUpdate: (d) => _dragBy(d.delta),
      child: Container(
        width: 18, height: 18,
        color: Colors.transparent, // invisible hit area, no visual clutter
      ),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4),
            blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: _editingIdea != null
          ? _editIdeaView()
          : _loadingProjects
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header — no dedicated "save" icon here anymore; adding a
              // new idea has its own + button further down instead.
              Row(children: [
                const Text('⚡', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                 Expanded(child: Text('My Manager',
                    style: TextStyle(color: AppTheme.textPrimary,
                        fontSize: 15, fontWeight: FontWeight.w700))),
                _headerIcon(Icons.open_in_full, 'পুরো অ্যাপ খোলো', _openMainApp),
                const SizedBox(width: 4),
                _headerIcon(Icons.remove, 'ছোট করো (বাবলে ফিরে যাও)', _collapse),
                const SizedBox(width: 4),
                _headerIcon(Icons.visibility_off_outlined,
                    'এখনকার মতো লুকাও (অ্যাপ খুললে আবার আসবে)',
                    _hideForNow, color: AppTheme.danger),
              ]),
              const SizedBox(height: 10),
              if (_projects.isEmpty)
                 Expanded(child: Center(
                  child: Text('আগে অ্যাপে একটা প্রজেক্ট বানাও',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      textAlign: TextAlign.center),
                ))
              else ...[
                // Most-used project first.
                SizedBox(
                  height: 32,
                  child: ListView(scrollDirection: Axis.horizontal, children: _projects.map((p) {
                    final sel = _selectedProjectId == p.id;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => _selectProject(p.id!),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: sel ? AppTheme.accent.withOpacity(0.15) : AppTheme.bg3,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: sel ? AppTheme.accent : AppTheme.border,
                                width: sel ? 2 : 1),
                          ),
                          child: Text(p.name, style: TextStyle(
                              color: sel ? AppTheme.accent : AppTheme.textSecondary,
                              fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    );
                  }).toList()),
                ),
                const SizedBox(height: 10),
                // Quick-add row — its own dedicated + button.
                Row(children: [
                  Expanded(child: TextField(
                    controller: _newIdeaCtrl,
                    style:  TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'নতুন আইডিয়া লিখো...',
                      hintStyle:  TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      filled: true, fillColor: AppTheme.bg3,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                          borderSide:  BorderSide(color: AppTheme.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.accent, width: 2)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onSubmitted: (_) => _addIdea(),
                  )),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _addIdea,
                    child: Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.add, color: Colors.white, size: 18),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                 Text('সাম্প্রতিক আইডিয়া', style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Expanded(
                  child: _loadingIdeas
                      ? const Center(child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.accent))
                      : _ideas.isEmpty
                          ?  Center(child: Text('এখনো কোনো আইডিয়া নেই',
                              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)))
                          : ListView.builder(
                              itemCount: _ideas.length,
                              itemBuilder: (_, i) => _ideaRow(_ideas[i]),
                            ),
                ),
              ],
            ]),
    ),
  );

  Widget _ideaRow(Idea idea) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.bg3,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(children: [
          Icon(
            idea.status == 'done' ? Icons.check_circle
                : idea.status == 'doing' ? Icons.incomplete_circle_outlined
                : Icons.radio_button_unchecked,
            size: 16, color: AppTheme.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => _startEdit(idea),
              behavior: HitTestBehavior.opaque,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(idea.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: idea.status == 'done' ? AppTheme.textMuted : AppTheme.textPrimary,
                        fontSize: 13, fontWeight: FontWeight.w600,
                        decoration: idea.status == 'done' ? TextDecoration.lineThrough : null)),
                if (idea.description != null && idea.description!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(idea.description!, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                  ),
              ]),
            ),
          ),
          GestureDetector(
            onTap: () => _startEdit(idea),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.edit_note, size: 18, color: AppTheme.textMuted),
            ),
          ),
        ]),
      ),
    );
  }

  /// Full-content edit view — replaces the whole panel while active.
  /// This is what the pencil icon on an idea actually opens: editing the
  /// idea's title *and* its existing note/description, not just
  /// renaming it.
  Widget _editIdeaView() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      GestureDetector(
        onTap: _cancelEdit,
        child: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Icon(Icons.arrow_back, size: 18, color: AppTheme.textMuted),
        ),
      ),
      Expanded(child: Text('আইডিয়া এডিট করো', style: TextStyle(
          color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700))),
      GestureDetector(
        onTap: _commitEdit,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: AppTheme.accent,
              borderRadius: BorderRadius.circular(8)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check, size: 14, color: Colors.white),
            SizedBox(width: 4),
            Text('আপডেট', style: TextStyle(color: Colors.white,
                fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    ]),
    const SizedBox(height: 12),
    Text('শিরোনাম', style: TextStyle(
        color: AppTheme.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w700)),
    const SizedBox(height: 6),
    TextField(
      controller: _editTitleCtrl,
      style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        filled: true, fillColor: AppTheme.bg3,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppTheme.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.accent, width: 2)),
      ),
    ),
    const SizedBox(height: 12),
    Text('নোট / বিবরণ', style: TextStyle(
        color: AppTheme.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w700)),
    const SizedBox(height: 6),
    Expanded(
      child: TextField(
        controller: _editDescCtrl, maxLines: null, expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'এখানে বিস্তারিত লিখো বা আগের লেখা এডিট করো...',
          hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13),
          filled: true, fillColor: AppTheme.bg3,
          contentPadding: const EdgeInsets.all(12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.accent, width: 2)),
        ),
      ),
    ),
  ]);

  Widget _headerIcon(IconData icon, String tooltip, VoidCallback onTap, {Color? color}) =>
      Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 20, color: color ?? AppTheme.textMuted),
          ),
        ),
      );
}
