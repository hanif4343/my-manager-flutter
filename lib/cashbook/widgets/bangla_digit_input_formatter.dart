import 'package:flutter/services.dart';

/// Bangla numerals (০-৯) typed on a Bangla keyboard get converted to
/// English digits (0-9) as the user types, so every amount field ends up
/// storing a plain parseable number no matter which keyboard was used.
/// Also strips anything that isn't a digit or a single decimal point.
class BanglaDigitInputFormatter extends TextInputFormatter {
  static const _bn = '০১২৩৪৫৬৭৮৯';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final buf = StringBuffer();
    for (final ch in newValue.text.characters) {
      final bnIndex = _bn.indexOf(ch);
      if (bnIndex != -1) {
        buf.write(bnIndex.toString());
      } else if (RegExp(r'[0-9.]').hasMatch(ch)) {
        buf.write(ch);
      }
      // any other character (letters, ৳ symbol, spaces) is dropped
    }
    var text = buf.toString();
    // keep only the first decimal point
    final firstDot = text.indexOf('.');
    if (firstDot != -1) {
      text = text.substring(0, firstDot + 1) +
          text.substring(firstDot + 1).replaceAll('.', '');
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  static double? parse(String text) {
    if (text.trim().isEmpty) return null;
    return double.tryParse(text.trim());
  }
}

extension _Characters on String {
  Iterable<String> get characters sync* {
    for (int i = 0; i < length; i++) {
      yield this[i];
    }
  }
}
