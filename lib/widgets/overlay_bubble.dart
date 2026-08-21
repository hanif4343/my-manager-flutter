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
/// screen). This runs in its own isolated Flutter engine — started from
/// `overlayMain()` in main.dart — completely separate from the main app
/// UI, which is why it has its own tiny widget tree here.
///
/// Design notes (read before changing the drag logic):
///  - The plugin's own native `enableDrag` is kept OFF everywhere. When it
///    was on, dragging inside the *expanded* quick-add panel (e.g. tapping
///    a project chip) was being captured as a window-drag instead of a
///    button tap. Instead, dragging is done entirely in Flutter via a
///    small dedicated handle + `moveOverlay()`, which only exists on the
///    collapsed bubble — so it can never interfere with the form.
///  - "Drag down to remove" is approximated using the *cumulative distance
///    dragged downward from where the drag started*, not the bubble's
///    actual position on the screen. The overlay's own Flutter engine only
///    knows the size of its own tiny window (60x60 / 320x?), not the full
///    device screen, so there's no reliable way to detect "you're now near
///    the bottom of the screen" from in here. This is a practical
///    approximation, not pixel-perfect Messenger behavior — worth testing
///    on your device and tweaking `_deleteThreshold` if it feels off.
class OverlayBubble extends StatefulWidget {
  const OverlayBubble({super.key});
  @override State<OverlayBubble> createState() => _OverlayBubbleState();
}

class _OverlayBubbleState extends State<OverlayBubble> {
  static const collapsedSize = 60;
  static const expandedWidth = 300;
  static const expandedHeight = 320;
  static const _deleteThreshold = 380.0; // px of cumulative downward drag

  bool _expanded = false;
  bool _loading = true;
  List<Project> _projects = [];
  int? _selectedProjectId;
  final _ctrl = TextEditingController();

  // Custom drag state (collapsed bubble only)
  Offset? _pos;
  double _dragCumulativeDy = 0;
  bool _showDeleteHint = false;

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _syncPosition();
  }

  Future<void> _syncPosition() async {
    try {
      final p = await FlutterOverlayWindow.getOverlayPosition();
      if (mounted) setState(() => _pos = Offset(p.x.toDouble(), p.y.toDouble()));
    } catch (_) {
      // Not fatal — we just won't have an initial position to drag from
      // until the first successful call.
    }
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
    await FlutterOverlayWindow.resizeOverlay(expandedWidth, expandedHeight, false);
    // focusPointer lets the TextField actually receive the keyboard.
    await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
    setState(() => _expanded = true);
  }

  Future<void> _collapse() async {
    await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
    await FlutterOverlayWindow.resizeOverlay(collapsedSize, collapsedSize, false);
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

  /// Brings the host app (My Manager itself) to the foreground.
  Future<void> _openMainApp() async {
    try {
      const intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.hanif.mymanager',
        componentName: 'com.hanif.mymanager.MainActivity',
        flags: [
          Flag.FLAG_ACTIVITY_NEW_TASK,
          Flag.FLAG_ACTIVITY_REORDER_TO_FRONT,
        ],
      );
      await intent.launch();
    } catch (_) {
      // If this fails on some device/launcher combo, at worst nothing
      // happens — the bubble itself keeps working either way.
    }
  }

  // ── Custom drag (collapsed bubble's handle only) ─────────────────
  void _onHandlePanStart(DragStartDetails d) {
    setState(() { _dragCumulativeDy = 0; _showDeleteHint = false; });
  }

  Future<void> _onHandlePanUpdate(DragUpdateDetails d) async {
    if (_pos == null) return;
    final next = _pos! + d.delta;
    setState(() {
      _pos = next;
      _dragCumulativeDy = (_dragCumulativeDy + d.delta.dy)
          .clamp(0.0, _deleteThreshold + 100);
      _showDeleteHint = _dragCumulativeDy >= _deleteThreshold;
    });
    try {
      await FlutterOverlayWindow.moveOverlay(OverlayPosition(next.dx, next.dy));
    } catch (_) {/* best-effort */}
  }

  Future<void> _onHandlePanEnd(DragEndDetails d) async {
    final shouldDelete = _showDeleteHint;
    setState(() { _dragCumulativeDy = 0; _showDeleteHint = false; });
    if (shouldDelete) {
      // Session-only close: doesn't touch the persisted "bubble_enabled"
      // setting, so the bubble comes back next time the app is opened.
      await FlutterOverlayWindow.closeOverlay();
    }
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
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: _showDeleteHint
                ? [AppTheme.red, const Color(0xFFB91C1C)]
                : const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.35),
                blurRadius: 10, offset: const Offset(0, 3)),
          ],
        ),
        child: Icon(
          _showDeleteHint ? Icons.delete_outline : Icons.lightbulb_outline,
          color: Colors.white, size: 26,
        ),
      ),
    ),
    // Small drag handle — this is the *only* part of the collapsed bubble
    // that moves the window. Tapping the rest of the circle expands it.
    Positioned(
      right: 0, bottom: 0,
      child: GestureDetector(
        onPanStart: _onHandlePanStart,
        onPanUpdate: _onHandlePanUpdate,
        onPanEnd: _onHandlePanEnd,
        child: Container(
          width: 20, height: 20,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.6), width: 1),
          ),
          child: const Icon(Icons.open_with, size: 12, color: Colors.white),
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
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.4),
              blurRadius: 16, offset: const Offset(0, 6)),
        ],
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
                _headerIcon(Icons.close, 'বন্ধ করো', _collapse),
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
