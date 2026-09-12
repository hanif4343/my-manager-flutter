import 'dart:math';

class PasswordGenerator {
  static const _lower = 'abcdefghijklmnopqrstuvwxyz';
  static const _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const _numbers = '0123456789';
  static const _symbols = '!@#\$%^&*()_-+=?';

  static String generate({
    int length = 16,
    bool uppercase = true,
    bool lowercase = true,
    bool numbers = true,
    bool symbols = true,
  }) {
    var chars = '';
    if (lowercase) chars += _lower;
    if (uppercase) chars += _upper;
    if (numbers) chars += _numbers;
    if (symbols) chars += _symbols;
    if (chars.isEmpty) chars = _lower + _numbers;

    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  /// A short label + a 0.0–1.0 score for a simple visual strength bar.
  /// This is a local heuristic, not a breach/entropy service — good
  /// enough to nudge toward longer, more varied passwords.
  static (String, double) strength(String password) {
    if (password.isEmpty) return ('', 0);
    var score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (password.length >= 16) score++;
    if (RegExp(r'[A-Z]').hasMatch(password)) score++;
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[!@#\$%^&*()_\-+=?]').hasMatch(password)) score++;

    if (score <= 2) return ('দুর্বল', 0.3);
    if (score <= 4) return ('মাঝারি', 0.6);
    return ('শক্তিশালী', 1.0);
  }
}
