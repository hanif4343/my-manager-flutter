import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../db/db_helper.dart';
import '../models/project.dart';
import '../widgets/app_theme.dart';
import '../services/notification_service.dart';

class ProjectFormScreen extends StatefulWidget {
  final Project? project;
  const ProjectFormScreen({super.key, this.project});
  @override State<ProjectFormScreen> createState() => _ProjectFormScreenState();
}

class _ProjectFormScreenState extends State<ProjectFormScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _tags = TextEditingController();
  int _colorValue = AppTheme.projectColors[0].value;
  DateTime? _reminder;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.project != null) {
      final p = widget.project!;
      _name.text = p.name;
      _desc.text = p.description ?? '';
      _tags.text = p.tags.join(', ');
      _colorValue = p.colorValue;
    }
  }

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppTheme.accent, surface: AppTheme.bg3),
        ),
        child: child!,
      ),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppTheme.accent, surface: AppTheme.bg3),
        ),
        child: child!,
      ),
    );
    if (time == null) return;
    setState(() {
      _reminder = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('প্রজেক্টের নাম দাও!')));
      return;
    }
    setState(() => _saving = true);
    final n = now();
    final tags = _tags.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

    int projectId;
    if (widget.project == null) {
      projectId = await DBHelper.insertProject(Project(
        name: _name.text.trim(),
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        colorValue: _colorValue, tags: tags, createdAt: n, updatedAt: n,
      ));
    } else {
      projectId = widget.project!.id!;
      await DBHelper.updateProject(widget.project!.copyWith(
        name: _name.text.trim(),
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        colorValue: _colorValue, tags: tags, updatedAt: n,
      ));
    }

    // Schedule notification if reminder set
    if (_reminder != null && _reminder!.isAfter(DateTime.now())) {
      await NotificationService.scheduleNotification(
        projectId,
        '⏰ ${_name.text.trim()}',
        'এই প্রজেক্টের কাজ করার সময় হয়েছে!',
        _reminder!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Reminder সেট হয়েছে: ${_reminder!.day}/${_reminder!.month} ${_reminder!.hour}:${_reminder!.minute.toString().padLeft(2, '0')}'),
          backgroundColor: AppTheme.green,
        ));
      }
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
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))
                : const Text('সেভ',
                    style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w700, fontSize: 16)),
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

          const SizedBox(height: 16),
          _label('রিমাইন্ডার সেট করো (ঐচ্ছিক)'),
          GestureDetector(
            onTap: _pickReminder,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: AppTheme.bg3,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _reminder != null ? AppTheme.accent : AppTheme.border,
                    width: _reminder != null ? 1.5 : 1),
              ),
              child: Row(children: [
                Icon(Icons.alarm,
                    color: _reminder != null ? AppTheme.accent : AppTheme.textMuted, size: 20),
                const SizedBox(width: 10),
                Text(
                  _reminder != null
                      ? '${_reminder!.day}/${_reminder!.month}/${_reminder!.year} ${_reminder!.hour}:${_reminder!.minute.toString().padLeft(2, '0')}'
                      : 'সময় নির্বাচন করো',
                  style: TextStyle(
                      color: _reminder != null ? AppTheme.textPrimary : AppTheme.textMuted,
                      fontSize: 14),
                ),
                const Spacer(),
                if (_reminder != null)
                  GestureDetector(
                    onTap: () => setState(() => _reminder = null),
                    child: const Icon(Icons.close, color: AppTheme.textMuted, size: 16),
                  ),
              ]),
            ),
          ),

          const SizedBox(height: 16),
          _label('ট্যাগ (কমা দিয়ে আলাদা করো)'),
          _field(_tags, 'Flutter, Firebase, API'),

          const SizedBox(height: 20),
          _label('রঙ বেছে নাও'),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 12, children: AppTheme.projectColors.map((c) {
            final selected = _colorValue == c.value;
            return GestureDetector(
              onTap: () => setState(() => _colorValue = c.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: selected ? 52 : 46,
                height: selected ? 52 : 46,
                decoration: BoxDecoration(
                  color: c, shape: BoxShape.circle,
                  border: Border.all(
                      color: selected ? Colors.white : Colors.transparent, width: 3),
                  boxShadow: selected
                      ? [BoxShadow(color: c.withOpacity(0.6), blurRadius: 12, spreadRadius: 2)]
                      : [],
                ),
                child: selected
                    ? const Icon(Icons.check, color: Colors.white, size: 22)
                    : null,
              ),
            );
          }).toList()),

          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(_colorValue),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(isEdit ? 'আপডেট করো' : 'তৈরি করো',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(
        color: AppTheme.textSecondary, fontSize: 13,
        fontWeight: FontWeight.w600)),
  );

  Widget _field(TextEditingController ctrl, String hint, {int maxLines = 1}) =>
      TextField(
        controller: ctrl, maxLines: maxLines,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint, hintStyle: const TextStyle(color: AppTheme.textMuted),
          filled: true, fillColor: AppTheme.bg3,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.accent, width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );
}
