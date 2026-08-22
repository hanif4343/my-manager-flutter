import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../models/project.dart';
import '../widgets/app_theme.dart';

class ProjectFormScreen extends StatefulWidget {
  final Project? project;
  const ProjectFormScreen({super.key, this.project});
  @override State<ProjectFormScreen> createState() => _ProjectFormScreenState();
}

class _ProjectFormScreenState extends State<ProjectFormScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  // Default color — not user-selectable in new project form
  int _colorValue = AppTheme.projectColors[0].value;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.project != null) {
      final p = widget.project!;
      _name.text = p.name;
      _desc.text = p.description ?? '';
      _colorValue = p.colorValue;
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('প্রজেক্টের নাম দাও!')));
      return;
    }
    setState(() => _saving = true);
    final n = now();
    if (widget.project == null) {
      await DBHelper.insertProject(Project(
        name: _name.text.trim(),
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        colorValue: _colorValue, createdAt: n, updatedAt: n,
      ));
    } else {
      await DBHelper.updateProject(widget.project!.copyWith(
        name: _name.text.trim(),
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        colorValue: _colorValue, updatedAt: n,
      ));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.project != null;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(isEdit ? 'প্রজেক্ট এডিট' : 'নতুন প্রজেক্ট'),
        // Save/Update lives here at the top — always visible, never hidden
        // by the keyboard the way a bottom button would be.
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: TextButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))
                  : const Icon(Icons.check, size: 18, color: AppTheme.accent),
              label: Text(isEdit ? 'আপডেট' : 'সেভ',
                  style: const TextStyle(color: AppTheme.accent,
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('প্রজেক্টের নাম *'),
          _field(_name, 'যেমন: Weather App, Portfolio Site'),
          const SizedBox(height: 16),
          _label('বিবরণ (ঐচ্ছিক)'),
          _field(_desc, 'প্রজেক্ট সম্পর্কে কিছু লিখো...', maxLines: 3),
        ]),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style:  TextStyle(
        color: AppTheme.textSecondary, fontSize: 13,
        fontWeight: FontWeight.w600)),
  );

  Widget _field(TextEditingController ctrl, String hint,
      {int maxLines = 1}) => TextField(
    controller: ctrl, maxLines: maxLines,
    style:  TextStyle(color: AppTheme.textPrimary, fontSize: 15),
    decoration: InputDecoration(
      hintText: hint, hintStyle:  TextStyle(color: AppTheme.textMuted),
      filled: true, fillColor: AppTheme.bg3,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:  BorderSide(color: AppTheme.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:  BorderSide(color: AppTheme.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.accent, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );
}
