import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'app_theme.dart';
import '../db/db_helper.dart';
import '../models/idea.dart';
import '../models/project.dart';

/// Content shown inside the system-wide overlay window (the actual
/// Messenger-style chat head that floats over other apps / the home
/// screen). Runs in its own isolated Flutter engine, started from
/// `overlayMain()` in main.dart.
///
/// Deliberately kept simple: earlier versions tried to replicate
/// Messenger's exact "drag down to an X to remove" gesture using a
/// custom fullscreen-resize-mid-drag trick. That turned out to be too
/// fragile to get right without testing on a real device — it kept
/// causing crashes. Moving is now handled entirely by the overlay
/// plugin's own built-in dragging (`enableDrag: true`), which is
/// reliable and well-tested by the plugin itself. Dragging is only ever
/// enabled while collapsed — it's turned off while the quick-add panel
/// is open, which is what fixed the original "dragging while picking a
/// project" bug. Turning the bubble off entirely is done from the
/// Settings toggle, not a drag gesture.
class OverlayBubble extends StatefulWidget {
  const OverlayBubble({super.key});
  @override State<OverlayBubble> createState() => _OverlayBubbleState();
}

class _OverlayBubbleState extends State<OverlayBubble> {
  static const collapsedSize = 60;
  static const expandedWidth = 300;
  static const expandedHeight = 320;

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
      await FlutterOverlayWindow.resizeOverlay(collapsedSize, collapsedSize, true);
    } catch (_) {}
    _ctrl.clear();
    if (mounted) setState(() => _expanded = false);
  }

  Future<void> _save() async {
    final title = _ctrl.text.trim();
    if (title.isEmpty || _selectedProjectId == null) return;
    final n = DateTime.now().millisecondsSinceEpoch;
    await DBHelper.insertIdea(Idea(
      projectId: _selectedProjectId!, title: title,
      createdAt: n, updatedAt: n,
    ));
    await FlutterOverlayWindow.shareData('idea_added');
    await _collapse();
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
    // Small "hide for now" badge — a plain tap target (no drag), sitting
    // at the corner. The native overlay window here is exactly 60x60, so
    // this has to stay fully inside those bounds or it gets clipped.
    // Session-only close — comes back automatically next time the app
    // is opened (permanent off is a separate Settings toggle).
    Positioned(
      top: 0, right: 0,
      child: GestureDetector(
        onTap: _hideForNow,
        child: Container(
          width: 18, height: 18,
          decoration: BoxDecoration(
            color: AppTheme.danger,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: const Icon(Icons.close, size: 11, color: Colors.white),
        ),
      ),
    ),
  ]);

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
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header — Save lives here, at the top, so the on-screen
              // keyboard can never cover it.
              Row(children: [
                const Text('⚡', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                const Expanded(child: Text('Quick Idea',
                    style: TextStyle(color: AppTheme.textPrimary,
                        fontSize: 16, fontWeight: FontWeight.w700))),
                _headerIcon(Icons.open_in_full, 'পুরো অ্যাপ খোলো', _openMainApp),
                const SizedBox(width: 6),
                _headerIcon(Icons.check_circle, 'সেভ করো', _save, color: AppTheme.green),
                const SizedBox(width: 6),
                _headerIcon(Icons.remove, 'ছোট করো (বাবলে ফিরে যাও)', _collapse),
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
                const SizedBox(height: 12),
                Expanded(
                  child: TextField(
                    controller: _ctrl, autofocus: true, maxLines: null,
                    expands: true, textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'আইডিয়া লিখো...',
                      hintStyle: const TextStyle(color: AppTheme.textMuted),
                      filled: true, fillColor: AppTheme.bg3,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.accent, width: 2)),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ),
              ],
            ]),
    ),
  );

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
