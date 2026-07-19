import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ── "খাতা" (Notebook) design system ─────────────────────────────
/// A warm, tactile paper palette: cream backgrounds, ink text,
/// coral accents, moss green for success, mustard for in-progress.
class AppTheme {
  static const bg = Color(0xFFF4ECD8);       // paper
  static const bg2 = Color(0xFFFBF6E9);      // card / surface
  static const bg3 = Color(0xFFEFE4CB);      // inputs, chips, track
  static const bg4 = Color(0xFFE7DCC2);      // pressed / deeper surface
  static const border = Color(0xFFD9C9A3);
  static const textPrimary = Color(0xFF3A2E22);   // ink
  static const textSecondary = Color(0xFF7A6A52);  // ink2
  static const textMuted = Color(0xFF9C8B6E);
  static const accent = Color(0xFFE2683F);   // coral
  static const green = Color(0xFF5C7A4F);    // moss
  static const yellow = Color(0xFFD69F2E);   // mustard
  static const red = Color(0xFFC1443A);      // brick red
  static const tape = Color(0xFFF2C6C0);     // washi-tape pink, for decorative accents

  static const projectColors = [
    Color(0xFFE2683F), Color(0xFF5C7A4F), Color(0xFFD69F2E),
    Color(0xFF3A6EA5), Color(0xFF8B5CF6), Color(0xFFC1447F),
    Color(0xFF2F9E8F), Color(0xFF9C6B3E),
  ];

  static TextTheme _textTheme(Brightness b) =>
      GoogleFonts.hindSiliguriTextTheme(
        b == Brightness.dark
            ? ThemeData.dark().textTheme
            : ThemeData.light().textTheme,
      );

  static ThemeData get dark => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.light(
          primary: accent, surface: bg2, background: bg,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: bg2, elevation: 0,
          titleTextStyle: GoogleFonts.hindSiliguri(
              color: textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
          iconTheme: const IconThemeData(color: textSecondary),
        ),
        cardTheme: CardTheme(
          color: bg2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: border),
          ),
          margin: EdgeInsets.zero,
        ),
        dividerColor: border,
        textTheme: _textTheme(Brightness.light),
        fontFamily: GoogleFonts.hindSiliguri().fontFamily,
      );

  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.light(
          primary: accent,
          surface: bg2,
          background: bg,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: bg2, elevation: 0,
          titleTextStyle: GoogleFonts.hindSiliguri(
              color: textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
          iconTheme: const IconThemeData(color: textSecondary),
        ),
        cardTheme: CardTheme(
          color: bg2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: border),
          ),
          margin: EdgeInsets.zero,
        ),
        dividerColor: border,
        textTheme: _textTheme(Brightness.light),
        fontFamily: GoogleFonts.hindSiliguri().fontFamily,
      );

  /// Playful rounded display font for titles / headings — use sparingly.
  static TextStyle display({double size = 20, FontWeight weight = FontWeight.w800, Color color = textPrimary}) =>
      GoogleFonts.hindSiliguri(fontSize: size, fontWeight: weight, color: color);
}

const statusConfig = {
  'todo':  {'label': '⭕ বাকি',  'color': AppTheme.textSecondary},
  'doing': {'label': '⏳ চলছে', 'color': AppTheme.yellow},
  'done':  {'label': '✅ শেষ',  'color': AppTheme.green},
};

const priorityConfig = {
  'low':    {'label': '🟢 কম',    'color': AppTheme.green},
  'medium': {'label': '🟡 মধ্যম', 'color': AppTheme.yellow},
  'high':   {'label': '🔴 জরুরি', 'color': AppTheme.red},
};

int now() => DateTime.now().millisecondsSinceEpoch;
