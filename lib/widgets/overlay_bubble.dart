import 'dart:async';
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
/// ── Why dragging temporarily goes fullscreen ─────────────────────
/// The collapsed bubble's native window is only 60x60 — from inside that
/// tiny window, Flutter has no idea how big the actual device screen is,
/// so there's no way to know "the middle of the screen" or "just above
/// the nav bar" for the Messenger-style delete zone. The fix: the moment
/// a drag starts, the window is resized to cover the full screen
/// (transparent everywhere except the bubble itself), which makes
/// `MediaQuery` report real screen dimensions for as long as the drag
/// lasts. As soon as the drag ends, it shrinks back down to a normal
/// small bubble — a fullscreen window is only ever touch-capturing while
/// actively dragging, never while idle.
///
/// A `GlobalKey` keeps the same drag GestureDetector alive across that
/// resize (Flutter would otherwise treat the small-bubble and
/// fullscreen-bubble as different widgets and drop the in-progress
/// gesture). There's also a safety timer: if a drag ever stops receiving
/// updates (a lost gesture, for whatever reason) for 4 seconds, the
/// bubble force-collapses back to a small window on its own, so a broken
/// gesture can never leave a fullscreen touch-blocking window stuck over
/// the whole screen.
class OverlayBubble extends StatefulWidget {
  const OverlayBubble({super.key});
  @override State<OverlayBubble> createState() => _OverlayBubbleState();
}

class _OverlayBubbleState extends State<OverlayBubble> {
  static const collapsedSize = 60;
  static const expandedWidth = 300;
  static const expandedHeight = 320;
  static const _deleteZoneSize = 64.0;
  static const _deleteSnapDistance = 70.0;

  final GlobalKey _dragKey = GlobalKey();

  bool _expanded = false;
  bool _loading = true;
  List<Project> _projects = [];
  int? _selectedProjectId;
  final _ctrl = TextEditingController();

  // Drag state
  bool _dragMode = false;
  Offset _pos = const Offset(0, 300); // top-left of the 60x60 bubble, screen coords
  bool _belowMiddle = false;
  bool _nearDelete = false;
  Timer? _safetyTimer;

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _syncPosition();
  }

  @override
  void dispose() {
    _safetyTimer?.cancel();
    super.dispose();
  }

  Future<void> _syncPosition() async {
    try {
      final p = await FlutterOverlayWindow.getOverlayPosition();
      if (mounted) setState(() => _pos = Offset(p.x, p.y));
    } catch (_) {
      // Falls back to the default Offset above — not fatal.
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

  // ── Drag lifecycle ────────────────────────────────────────────
  Future<void> _onDragStart(DragStartDetails d) async {
    setState(() { _dragMode = true; _belowMiddle = false; _nearDelete = false; });
    _armSafetyTimer();
    // Temporarily cover the whole screen so we can read real screen
    // dimensions and place the delete zone exactly like Messenger does.
    await FlutterOverlayWindow.resizeOverlay(
        WindowSize.matchParent, WindowSize.fullCover, false);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_dragMode) return;
    _armSafetyTimer();
    final size = MediaQuery.of(context).size;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    setState(() {
      _pos = Offset(
        (_pos.dx + d.delta.dx).clamp(0.0, size.width - collapsedSize),
        (_pos.dy + d.delta.dy).clamp(0.0, size.height - collapsedSize),
      );
      // The delete zone only appears once the bubble crosses the middle
      // of the screen — exactly like Messenger.
      _belowMiddle = (_pos.dy + collapsedSize / 2) > size.height / 2;
      if (_belowMiddle) {
        final bubbleCenter = Offset(_pos.dx + collapsedSize / 2, _pos.dy + collapsedSize / 2);
        final deleteCenter = Offset(size.width / 2, size.height - bottomInset - 64);
        _nearDelete = (bubbleCenter - deleteCenter).distance < _deleteSnapDistance;
      } else {
        _nearDelete = false;
      }
    });
  }

  Future<void> _onDragEnd(DragEndDetails d) async {
    _safetyTimer?.cancel();
    final shouldDelete = _nearDelete;
    if (shouldDelete) {
      // Session-only close — doesn't touch the persisted "bubble_enabled"
      // setting, so the bubble comes back next time the app is opened.
      await FlutterOverlayWindow.closeOverlay();
      return;
    }
    await _snapBackToBubble();
  }

  Future<void> _snapBackToBubble() async {
    final size = MediaQuery.of(context).size;
    final snapX = (_pos.dx + collapsedSize / 2 > size.width / 2)
        ? size.width - collapsedSize - 12
        : 12.0;
    final finalPos = Offset(snapX, _pos.dy);
    await FlutterOverlayWindow.resizeOverlay(collapsedSize, collapsedSize, false);
    await FlutterOverlayWindow.moveOverlay(OverlayPosition(finalPos.dx, finalPos.dy));
    if (mounted) setState(() {
      _pos = finalPos;
      _dragMode = false;
      _belowMiddle = false;
      _nearDelete = false;
    });
  }

  /// If a drag gesture ever stops delivering updates (e.g. a dropped
  /// pointer event), this forces the window back to a small bubble after
  /// 4 idle seconds, so it can never get stuck full-screen and block the
  /// rest of the device.
  void _armSafetyTimer() {
    _safetyTimer?.cancel();
    _safetyTimer = Timer(const Duration(seconds: 4), () {
      if (_dragMode) _snapBackToBubble();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: _expanded
            ? _expandedPanel()
            : (_dragMode ? _dragOverlay() : _collapsedBubble()),
      ),
    );
  }

  Widget _bubbleVisual({required bool danger}) => Container(
    width: collapsedSize.toDouble(),
    height: collapsedSize.toDouble(),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: danger
            ? const [AppTheme.danger, Color(0xFFB91C1C)]
            : const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
      ),
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35),
          blurRadius: 10, offset: const Offset(0, 3))],
    ),
    child: Icon(danger ? Icons.delete_outline : Icons.lightbulb_outline,
        color: Colors.white, size: 26),
  );

  Widget _collapsedBubble() => Stack(children: [
    GestureDetector(
      onTap: _expand,
      child: _bubbleVisual(danger: false),
    ),
    // Small drag handle — the only part of the collapsed bubble that
    // starts a move. Tapping the rest of the circle expands it instead.
    Positioned(
      right: 0, bottom: 0,
      child: GestureDetector(
        key: _dragKey,
        onPanStart: _onDragStart,
        onPanUpdate: _onDragUpdate,
        onPanEnd: _onDragEnd,
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

  Widget _dragOverlay() {
    final size = MediaQuery.of(context).size;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final deleteCenter = Offset(size.width / 2, size.height - bottomInset - 64);
    return Stack(children: [
      // Delete zone — hidden until the bubble crosses the vertical
      // middle of the screen, then fades in near the nav bar.
      AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: _belowMiddle ? 1 : 0,
        child: Positioned(
          left: deleteCenter.dx - _deleteZoneSize / 2,
          top: deleteCenter.dy - _deleteZoneSize / 2,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 120),
            scale: _nearDelete ? 1.15 : 1.0,
            child: Container(
              width: _deleteZoneSize, height: _deleteZoneSize,
              decoration: BoxDecoration(
                color: _nearDelete ? AppTheme.danger : Colors.black.withOpacity(0.55),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.7), width: 1.5),
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 28),
            ),
          ),
        ),
      ),
      Positioned(
        left: _pos.dx, top: _pos.dy,
        child: GestureDetector(
          key: _dragKey,
          onPanUpdate: _onDragUpdate,
          onPanEnd: _onDragEnd,
          child: _bubbleVisual(danger: _nearDelete),
        ),
      ),
    ]);
  }

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
                 Expanded(child: Text('Quick Idea',
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
                 Expanded(child: Center(
                  child: Text('আগে অ্যাপে একটা প্রজেক্ট বানাও',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      textAlign: TextAlign.center),
                ))
              else ...[
                 Text('প্রজেক্ট:', style: TextStyle(
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
                            border: Border.all(
                                color: sel ? AppTheme.accent : AppTheme.border,
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
                    style:  TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'আইডিয়া লিখো...',
                      hintStyle:  TextStyle(color: AppTheme.textMuted),
                      filled: true, fillColor: AppTheme.bg3,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                          borderSide:  BorderSide(color: AppTheme.border)),
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
