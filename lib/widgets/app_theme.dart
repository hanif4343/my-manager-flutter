import 'package:flutter/material.dart';

class AppTheme {
  static const bg = Color(0xFF0B0F1A);
  static const bg2 = Color(0xFF111827);
  static const bg3 = Color(0xFF1E2535);
  static const bg4 = Color(0xFF252D3D);
  static const border = Color(0xFF2A3347);
  static const textPrimary = Color(0xFFE2E8F0);
  static const textSecondary = Color(0xFF94A3B8);
  static const textMuted = Color(0xFF64748B);
  static const accent = Color(0xFF6366F1);
  static const green = Color(0xFF10B981);
  static const yellow = Color(0xFFF59E0B);
  static const red = Color(0xFFEF4444);

  static const projectColors = [
    Color(0xFF6366F1), Color(0xFFEC4899), Color(0xFFF59E0B),
    Color(0xFF10B981), Color(0xFF3B82F6), Color(0xFF8B5CF6),
    Color(0xFFEF4444), Color(0xFF14B8A6),
  ];

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: accent, surface: bg2, background: bg,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: bg2, elevation: 0,
          titleTextStyle: TextStyle(color: textPrimary,
              fontSize: 17, fontWeight: FontWeight.w700),
          iconTheme: IconThemeData(color: textSecondary),
        ),
        cardTheme: CardTheme(
          color: bg2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: border),
          ),
          margin: EdgeInsets.zero,
        ),
        dividerColor: border,
        fontFamily: 'Roboto',
      );

  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        colorScheme: const ColorScheme.light(
          primary: accent,
          surface: Colors.white,
          background: Color(0xFFF1F5F9),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white, elevation: 0,
          titleTextStyle: TextStyle(color: Color(0xFF1E293B),
              fontSize: 17, fontWeight: FontWeight.w700),
          iconTheme: IconThemeData(color: Color(0xFF64748B)),
        ),
        cardTheme: CardTheme(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          margin: EdgeInsets.zero,
        ),
        dividerColor: const Color(0xFFE2E8F0),
        fontFamily: 'Roboto',
      );
}

const statusConfig = {
  'todo':  {'label': 'বাকি',  'color': Color(0xFF94A3B8)},
  'doing': {'label': 'চলছে', 'color': Color(0xFFF59E0B)},
  'done':  {'label': 'শেষ',  'color': Color(0xFF10B981)},
};

const priorityConfig = {
  'low':    {'label': 'কম',    'color': Color(0xFF64748B)},
  'medium': {'label': 'মধ্যম', 'color': Color(0xFFF59E0B)},
  'high':   {'label': 'জরুরি', 'color': Color(0xFFEF4444)},
};

int now() => DateTime.now().millisecondsSinceEpoch;
