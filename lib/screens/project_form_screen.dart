import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../models/project.dart';
import '../widgets/app_theme.dart';
import '../services/notification_service.dart'; // সার্ভিসটি ইমপোর্ট করুন
import 'package:intl/intl.dart'; // তারিখ দেখানোর জন্য

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
  bool _saving = false;

  // রিমাইন্ডারের জন্য ভেরিয়েবল
  DateTime? _selectedReminder;

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

  // তারিখ ও সময় সিলেক্ট করার ফাংশন
  Future<void> _pickReminder() async {
    DateTime? date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date != null) {
      TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );

      if (time != null) {
        setState(() {
          _selectedReminder = DateTime(
            date.year, date.month, date.day, time.hour, time.minute);
        });
      }
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('প্রজেক্টের নাম দাও!')));
      return;
    }
    setState(() => _saving = true);
    final n = DateTime.now(); // changed from now() to DateTime.now()
    final tags = _tags.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    
    int projectId;
    Project projectObj;

    if (widget.project == null) {
      projectObj = Project(
        name: _name.text.trim(), 
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        colorValue: _colorValue, tags: tags, createdAt: n, updatedAt: n,
      );
      projectId = await DBHelper.insertProject(projectObj);
    } else {
      projectObj = widget.project!.copyWith(
        name: _name.text.trim(), 
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        colorValue: _colorValue, tags: tags, updatedAt: n,
      );
      await DBHelper.updateProject(projectObj);
      projectId = widget.project!.id!;
    }

    // যদি রিমাইন্ডার সিলেক্ট করা থাকে তবে নোটিফিকেশন সেট হবে
    if (_selectedReminder != null) {
      await NotificationService.scheduleNotification(
        projectId,
        "প্রজেক্ট রিমাইন্ডার: ${projectObj.name}",
        "আপনার এই প্রজেক্টের কাজটি শুরু করার সময় হয়েছে।",
        _selectedReminder!,
      );
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
                : const Text('সেভ', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w700, fontSize: 16)),
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
          InkWell(
            onTap: _pickReminder,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.bg3,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _selectedReminder != null ? AppTheme.accent : AppTheme.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.alarm, color: _selectedReminder != null ? AppTheme.accent : AppTheme.textMuted),
                  const SizedBox(width: 10),
                  Text(
                    _selectedReminder == null 
                        ? 'সময় নির্বাচন করো' 
                        : DateFormat('dd MMM, hh:mm a').format(_selectedReminder!),
                    style: TextStyle(
                      color: _selectedReminder != null ? AppTheme.textPrimary : AppTheme.textMuted,
                      fontSize: 15
                    ),
                  ),
                ],
              ),
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
                width: selected ? 40 : 36, height: selected ? 40 : 36,
                decoration: BoxDecoration(
                  color: c, shape: BoxShape.circle,
                  border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 3),
                  boxShadow: selected ? [BoxShadow(color: c.withOpacity(0.5), blurRadius: 10)] : [],
                ),
                child: selected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
              ),
            );
          }).toList()),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent, padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(isEdit ? 'আপডেট করো' : 'তৈরি করো',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12,
        fontWeight: FontWeight.w600, letterSpacing: 0.5)),
  );

  Widget _field(TextEditingController ctrl, String hint, {int maxLines = 1}) => TextField(
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
