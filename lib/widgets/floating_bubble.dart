import 'package:flutter/material.dart';
import '../widgets/app_theme.dart';
import '../db/db_helper.dart';
import '../models/idea.dart';
import '../models/project.dart';

class FloatingBubble extends StatefulWidget {
  final Widget child;
  const FloatingBubble({super.key, required this.child});
  @override State<FloatingBubble> createState() => _FloatingBubbleState();
}

class _FloatingBubbleState extends State<FloatingBubble>
    with SingleTickerProviderStateMixin {
  Offset _position = const Offset(20, 120);
  bool _isDragging = false;
  bool _isExpanded = false;
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;
  List<Project> _projects = [];
  int? _selectedProjectId;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _scaleAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack);
    _loadProjects();
  }

  @override
  void dispose() { _animCtrl.dispose(); super.dispose(); }

  Future<void> _loadProjects() async {
    final list = await DBHelper.getProjects();
    if (mounted) setState(() => _projects = list);
  }

  void _toggle() {
    setState(() => _isExpanded = !_isExpanded);
    if (_isExpanded) _animCtrl.forward();
    else _animCtrl.reverse();
  }

  void _close() {
    setState(() => _isExpanded = false);
    _animCtrl.reverse();
  }

  Future<void> _quickAddIdea(String title, int projectId) async {
    if (title.trim().isEmpty) return;
    final n = now();
    await DBHelper.insertIdea(Idea(
      projectId: projectId, title: title.trim(),
      createdAt: n, updatedAt: n,
    ));
    _close();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('💡 "$title" যোগ হয়েছে!'),
        backgroundColor: AppTheme.green,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  void _showQuickAdd() {
    if (_projects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('আগে একটা প্রজেক্ট বানাও!'),
              backgroundColor: AppTheme.red));
      _close();
      return;
    }
    _selectedProjectId ??= _projects.first.id;
    final ctrl = TextEditingController();

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppTheme.bg2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 16, right: 16, top: 16),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 12),
            const Row(children: [
              Text('⚡', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Text('Quick Idea', style: TextStyle(color: AppTheme.textPrimary,
                  fontSize: 17, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 14),
            // Project selector
            const Text('প্রজেক্ট:', style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 12,
                fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: _projects.map((p) {
                final sel = _selectedProjectId == p.id;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setS(() => _selectedProjectId = p.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel ? p.color.withOpacity(0.2) : AppTheme.bg3,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: sel ? p.color : AppTheme.border,
                            width: sel ? 2 : 1),
                      ),
                      child: Row(children: [
                        Container(width: 8, height: 8,
                            decoration: BoxDecoration(
                                color: p.color, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(p.name, style: TextStyle(
                            color: sel ? p.color : AppTheme.textSecondary,
                            fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                );
              }).toList()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl, autofocus: true,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'আইডিয়া লিখো...',
                hintStyle: const TextStyle(color: AppTheme.textMuted),
                filled: true, fillColor: AppTheme.bg3,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: AppTheme.accent, width: 2)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
              onSubmitted: (val) {
                Navigator.pop(ctx);
                if (_selectedProjectId != null) {
                  _quickAddIdea(val, _selectedProjectId!);
                }
              },
            ),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                if (_selectedProjectId != null) {
                  _quickAddIdea(ctrl.text, _selectedProjectId!);
                }
              },
              icon: const Icon(Icons.add, color: Colors.white, size: 16),
              label: const Text('যোগ করো', style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            )),
            const SizedBox(height: 20),
          ]),
        ),
      ),
    ).then((_) => _close());
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      // Backdrop when expanded
      if (_isExpanded)
        Positioned.fill(child: GestureDetector(
          onTap: _close,
          child: Container(color: Colors.black.withOpacity(0.3)),
        )),
      // Draggable bubble
      Positioned(
        left: _position.dx,
        top: _position.dy,
        child: GestureDetector(
          onPanStart: (_) => setState(() => _isDragging = true),
          onPanUpdate: (d) {
            setState(() {
              final size = MediaQuery.of(context).size;
              _position = Offset(
                (_position.dx + d.delta.dx).clamp(0, size.width - 56),
                (_position.dy + d.delta.dy).clamp(
                    MediaQuery.of(context).padding.top, size.height - 80),
              );
            });
          },
          onPanEnd: (_) {
            setState(() => _isDragging = false);
            // Snap to edge
            final size = MediaQuery.of(context).size;
            final snapX = _position.dx < size.width / 2 ? 12.0 : size.width - 68;
            setState(() => _position = Offset(snapX, _position.dy));
          },
          onTap: _showQuickAdd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 56, height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(
                      _isDragging ? 0.6 : 0.4),
                  blurRadius: _isDragging ? 20 : 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.lightbulb_outline,
                color: Colors.white, size: 24),
          ),
        ),
      ),
    ]);
  }
}
