import 'package:flutter/material.dart';
import '../../widgets/app_theme.dart';

/// পরিবার মডিউলের ছোট ছোট UI সহায়ক।

Widget fCard({required Widget child, VoidCallback? onTap, EdgeInsets? padding, VoidCallback? onLongPress}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: AppTheme.bg2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: double.infinity,
          padding: padding ?? const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: child,
        ),
      ),
    ),
  );
}

Widget fChip(String text, Color color, {VoidCallback? onTap}) {
  return InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    ),
  );
}

Widget fSection(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 0, 8),
      child: Text(t, style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5, fontWeight: FontWeight.w700)),
    );

/// ট্যাবের উপরের "শিরোনাম + যোগ করো" সারি।
Widget fHeader(String hint, String addLabel, VoidCallback onAdd) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(children: [
      Expanded(child: Text(hint, style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5, height: 1.4))),
      const SizedBox(width: 8),
      FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.accent,
          visualDensity: VisualDensity.compact,
        ),
        onPressed: onAdd,
        icon: const Icon(Icons.add, size: 18),
        label: Text(addLabel),
      ),
    ]),
  );
}

Widget fEmpty(IconData icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      child: Column(children: [
        Icon(icon, size: 42, color: AppTheme.textMuted),
        const SizedBox(height: 10),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13.5, height: 1.5)),
      ]),
    );

Future<DateTime?> fPickDate(BuildContext context, DateTime? initial, {DateTime? first, DateTime? last}) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: first ?? DateTime(1930),
    lastDate: last ?? DateTime(now.year + 30),
  );
}

Future<bool> fConfirm(BuildContext context, String title, String body) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.bg2,
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('না')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('হ্যাঁ', style: TextStyle(color: AppTheme.red)),
        ),
      ],
    ),
  );
  return ok == true;
}

/// নিচ থেকে ওঠা ফর্ম শিট; কীবোর্ড উঠলে নিজে উপরে ওঠে।
Future<void> fSheet(BuildContext context, String title,
    Widget Function(BuildContext ctx, StateSetter setS) body) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.bg2,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              body(ctx, setS),
            ]),
          ),
        ),
      );
    }),
  );
}

Widget fSaveButton(VoidCallback onPressed, {String label = 'সংরক্ষণ করো'}) => SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.accent,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );

Widget fError(String? e) => e == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(e, style: TextStyle(color: AppTheme.red, fontSize: 12.5)),
      );

/// বাংলা অঙ্কে টাইপ করলেও সংখ্যা পার্স হবে।
String fAsciiDigits(String s) {
  const bnd = '০১২৩৪৫৬৭৮৯';
  final b = StringBuffer();
  for (final ch in s.runes) {
    final c = String.fromCharCode(ch);
    final i = bnd.indexOf(c);
    b.write(i >= 0 ? '$i' : c);
  }
  return b.toString();
}

const _avatarColors = [
  Color(0xFF6C63FF), Color(0xFF00A6A6), Color(0xFFE85D75), Color(0xFFF29E4C),
  Color(0xFF3FA34D), Color(0xFF3A86FF), Color(0xFFB5179E), Color(0xFF8D6E63),
];

Color fColorFor(String s) {
  final h = s.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff);
  return _avatarColors[h % _avatarColors.length];
}

Widget fAvatar(String name, {double size = 44}) {
  final c = fColorFor(name);
  final first = name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();
  return Container(
    width: size, height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: c.withOpacity(0.18), borderRadius: BorderRadius.circular(size * 0.3)),
    child: Text(first, style: TextStyle(color: c, fontSize: size * 0.42, fontWeight: FontWeight.w800)),
  );
}
