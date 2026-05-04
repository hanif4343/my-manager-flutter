import 'package:flutter/material.dart';

class SyntaxHighlighter extends StatelessWidget {
  final String code;
  final String language;
  const SyntaxHighlighter({super.key, required this.code, required this.language});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SelectableText.rich(
        TextSpan(children: _highlight(code, language)),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.7),
      ),
    );
  }

  List<TextSpan> _highlight(String code, String lang) {
    switch (lang) {
      case 'js': case 'jsx': case 'ts': case 'tsx':
        return _highlightJs(code);
      case 'dart':
        return _highlightDart(code);
      case 'py': case 'python':
        return _highlightPython(code);
      case 'html':
        return _highlightHtml(code);
      case 'css': case 'scss':
        return _highlightCss(code);
      case 'json':
        return _highlightJson(code);
      case 'yaml': case 'yml':
        return _highlightYaml(code);
      default:
        return [TextSpan(text: code, style: const TextStyle(color: Color(0xFFC9D1D9)))];
    }
  }

  // ── COLORS ────────────────────────────────────────────
  static const _keyword   = Color(0xFFFF7B72);
  static const _string    = Color(0xFFA5D6FF);
  static const _comment   = Color(0xFF8B949E);
  static const _number    = Color(0xFFD29922);
  static const _func      = Color(0xFFD2A8FF);
  static const _type      = Color(0xFFFFA657);
  static const _operator  = Color(0xFFFF7B72);
  static const _tag       = Color(0xFF7EE787);
  static const _attr      = Color(0xFFF78166);
  static const _plain     = Color(0xFFC9D1D9);
  static const _prop      = Color(0xFF79C0FF);

  // ── JS/TS ──────────────────────────────────────────────
  List<TextSpan> _highlightJs(String code) {
    final keywords = {'const','let','var','function','return','if','else',
      'for','while','class','import','export','from','default','async',
      'await','try','catch','throw','new','this','typeof','instanceof',
      'true','false','null','undefined','switch','case','break','continue',
      'of','in','extends','super','static'};
    return _tokenize(code, keywords: keywords);
  }

  List<TextSpan> _highlightDart(String code) {
    final keywords = {'var','final','const','dynamic','void','int','double',
      'String','bool','List','Map','Set','return','if','else','for','while',
      'class','import','export','async','await','try','catch','throw','new',
      'this','true','false','null','switch','case','break','continue','extends',
      'implements','super','static','abstract','override','required','late',
      'enum','mixin','on','get','set','factory','typedef','is','as','in'};
    return _tokenize(code, keywords: keywords);
  }

  List<TextSpan> _highlightPython(String code) {
    final keywords = {'def','class','import','from','return','if','elif',
      'else','for','while','try','except','finally','with','as','pass',
      'break','continue','True','False','None','and','or','not','in',
      'is','lambda','yield','global','nonlocal','raise','del','assert'};
    return _tokenize(code, keywords: keywords);
  }

  // ── HTML ───────────────────────────────────────────────
  List<TextSpan> _highlightHtml(String code) {
    final spans = <TextSpan>[];
    int i = 0;
    while (i < code.length) {
      if (code[i] == '<') {
        int end = code.indexOf('>', i);
        if (end == -1) end = code.length - 1;
        final tag = code.substring(i, end + 1);
        // Comment
        if (tag.startsWith('<!--')) {
          final cEnd = code.indexOf('-->', i);
          final c = cEnd == -1 ? code.substring(i) : code.substring(i, cEnd + 3);
          spans.add(TextSpan(text: c, style: const TextStyle(color: _comment)));
          i += c.length; continue;
        }
        spans.add(TextSpan(text: '<', style: const TextStyle(color: _plain)));
        // Parse tag name and attributes
        final inner = tag.substring(1, tag.length - 1);
        final parts = inner.split(RegExp(r'(?<=\w)(?=\s)'));
        if (parts.isNotEmpty) {
          spans.add(TextSpan(text: parts[0].replaceAll('/', ''),
              style: const TextStyle(color: _tag)));
          if (parts.length > 1) {
            spans.add(TextSpan(text: parts.sublist(1).join(' '),
                style: const TextStyle(color: _attr)));
          }
        }
        if (tag.endsWith('/>')) spans.add(const TextSpan(text: '/>',
            style: TextStyle(color: _plain)));
        else spans.add(const TextSpan(text: '>',
            style: TextStyle(color: _plain)));
        i = end + 1;
      } else if (code[i] == '"' || code[i] == "'") {
        final q = code[i];
        final end = code.indexOf(q, i + 1);
        if (end == -1) { spans.add(TextSpan(text: code.substring(i), style: const TextStyle(color: _string))); break; }
        spans.add(TextSpan(text: code.substring(i, end + 1), style: const TextStyle(color: _string)));
        i = end + 1;
      } else {
        int next = code.indexOf('<', i);
        if (next == -1) next = code.length;
        spans.add(TextSpan(text: code.substring(i, next), style: const TextStyle(color: _plain)));
        i = next;
      }
    }
    return spans;
  }

  // ── CSS ───────────────────────────────────────────────
  List<TextSpan> _highlightCss(String code) {
    final spans = <TextSpan>[];
    int i = 0;
    while (i < code.length) {
      // Comment
      if (i + 1 < code.length && code[i] == '/' && code[i+1] == '*') {
        final end = code.indexOf('*/', i + 2);
        final c = end == -1 ? code.substring(i) : code.substring(i, end + 2);
        spans.add(TextSpan(text: c, style: const TextStyle(color: _comment)));
        i += c.length; continue;
      }
      // Selector / property
      if (code[i] == '{') {
        spans.add(TextSpan(text: '{', style: const TextStyle(color: _plain)));
        i++; continue;
      }
      if (code[i] == '}') {
        spans.add(TextSpan(text: '}', style: const TextStyle(color: _plain)));
        i++; continue;
      }
      if (code[i] == ':') {
        spans.add(TextSpan(text: ':', style: const TextStyle(color: _operator)));
        i++; continue;
      }
      if (code[i] == '"' || code[i] == "'") {
        final q = code[i];
        final end = code.indexOf(q, i + 1);
        if (end == -1) { spans.add(TextSpan(text: code.substring(i), style: const TextStyle(color: _string))); break; }
        spans.add(TextSpan(text: code.substring(i, end + 1), style: const TextStyle(color: _string)));
        i = end + 1; continue;
      }
      // Numbers
      if (RegExp(r'\d').hasMatch(code[i])) {
        int end = i;
        while (end < code.length && RegExp(r'[\d.%pxremvhw]').hasMatch(code[end])) end++;
        spans.add(TextSpan(text: code.substring(i, end), style: const TextStyle(color: _number)));
        i = end; continue;
      }
      // Color hex
      if (code[i] == '#' && i + 1 < code.length && RegExp(r'[0-9a-fA-F]').hasMatch(code[i+1])) {
        int end = i + 1;
        while (end < code.length && RegExp(r'[0-9a-fA-F]').hasMatch(code[end])) end++;
        spans.add(TextSpan(text: code.substring(i, end), style: const TextStyle(color: _number)));
        i = end; continue;
      }
      spans.add(TextSpan(text: code[i], style: const TextStyle(color: _plain)));
      i++;
    }
    return spans;
  }

  // ── JSON ──────────────────────────────────────────────
  List<TextSpan> _highlightJson(String code) {
    final spans = <TextSpan>[];
    int i = 0;
    while (i < code.length) {
      if (code[i] == '"') {
        final end = code.indexOf('"', i + 1);
        if (end == -1) break;
        final str = code.substring(i, end + 1);
        // Check if key (followed by :)
        int j = end + 1;
        while (j < code.length && (code[j] == ' ' || code[j] == '\t')) j++;
        final isKey = j < code.length && code[j] == ':';
        spans.add(TextSpan(text: str, style: TextStyle(color: isKey ? _prop : _string)));
        i = end + 1; continue;
      }
      if (RegExp(r'\d').hasMatch(code[i])) {
        int end = i;
        while (end < code.length && RegExp(r'[\d.\-e+]').hasMatch(code[end])) end++;
        spans.add(TextSpan(text: code.substring(i, end), style: const TextStyle(color: _number)));
        i = end; continue;
      }
      if (code.startsWith('true', i) || code.startsWith('false', i) || code.startsWith('null', i)) {
        final kw = code.startsWith('true', i) ? 'true' : code.startsWith('false', i) ? 'false' : 'null';
        spans.add(TextSpan(text: kw, style: const TextStyle(color: _keyword)));
        i += kw.length; continue;
      }
      spans.add(TextSpan(text: code[i], style: const TextStyle(color: _plain)));
      i++;
    }
    return spans;
  }

  // ── YAML ──────────────────────────────────────────────
  List<TextSpan> _highlightYaml(String code) {
    final spans = <TextSpan>[];
    for (final line in code.split('\n')) {
      if (line.trimLeft().startsWith('#')) {
        spans.add(TextSpan(text: '$line\n', style: const TextStyle(color: _comment)));
      } else if (line.contains(':')) {
        final idx = line.indexOf(':');
        spans.add(TextSpan(text: line.substring(0, idx), style: const TextStyle(color: _prop)));
        spans.add(const TextSpan(text: ':', style: TextStyle(color: _operator)));
        spans.add(TextSpan(text: '${line.substring(idx + 1)}\n', style: const TextStyle(color: _string)));
      } else {
        spans.add(TextSpan(text: '$line\n', style: const TextStyle(color: _plain)));
      }
    }
    return spans;
  }

  // ── GENERIC TOKENIZER ─────────────────────────────────
  List<TextSpan> _tokenize(String code, {required Set<String> keywords}) {
    final spans = <TextSpan>[];
    int i = 0;
    while (i < code.length) {
      // Single-line comment
      if (i + 1 < code.length && code[i] == '/' && code[i+1] == '/') {
        final end = code.indexOf('\n', i);
        final c = end == -1 ? code.substring(i) : code.substring(i, end);
        spans.add(TextSpan(text: c, style: const TextStyle(color: _comment)));
        i += c.length; continue;
      }
      // Multi-line comment
      if (i + 1 < code.length && code[i] == '/' && code[i+1] == '*') {
        final end = code.indexOf('*/', i + 2);
        final c = end == -1 ? code.substring(i) : code.substring(i, end + 2);
        spans.add(TextSpan(text: c, style: const TextStyle(color: _comment)));
        i += c.length; continue;
      }
      // String (double)
      if (code[i] == '"' || code[i] == '`') {
        final q = code[i];
        int end = i + 1;
        while (end < code.length) {
          if (code[end] == '\\') { end += 2; continue; }
          if (code[end] == q) { end++; break; }
          end++;
        }
        spans.add(TextSpan(text: code.substring(i, end), style: const TextStyle(color: _string)));
        i = end; continue;
      }
      // String (single)
      if (code[i] == "'") {
        int end = i + 1;
        while (end < code.length) {
          if (code[end] == '\\') { end += 2; continue; }
          if (code[end] == "'") { end++; break; }
          end++;
        }
        spans.add(TextSpan(text: code.substring(i, end), style: const TextStyle(color: _string)));
        i = end; continue;
      }
      // Number
      if (RegExp(r'\d').hasMatch(code[i]) &&
          (i == 0 || !RegExp(r'[a-zA-Z_]').hasMatch(code[i-1]))) {
        int end = i;
        while (end < code.length && RegExp(r'[\d.xXa-fA-F]').hasMatch(code[end])) end++;
        spans.add(TextSpan(text: code.substring(i, end), style: const TextStyle(color: _number)));
        i = end; continue;
      }
      // Word (keyword / identifier)
      if (RegExp(r'[a-zA-Z_$]').hasMatch(code[i])) {
        int end = i;
        while (end < code.length && RegExp(r'[a-zA-Z0-9_$]').hasMatch(code[end])) end++;
        final word = code.substring(i, end);
        // Check if function call (followed by '(')
        bool isFunc = end < code.length && code[end] == '(';
        Color color;
        if (keywords.contains(word)) color = _keyword;
        else if (isFunc) color = _func;
        else if (word[0] == word[0].toUpperCase() && word[0] != word[0].toLowerCase()) color = _type;
        else color = _plain;
        spans.add(TextSpan(text: word, style: TextStyle(color: color)));
        i = end; continue;
      }
      // Operators
      if (RegExp(r'[=+\-*/<>!&|^~%]').hasMatch(code[i])) {
        spans.add(TextSpan(text: code[i], style: const TextStyle(color: _operator)));
        i++; continue;
      }
      spans.add(TextSpan(text: code[i], style: const TextStyle(color: _plain)));
      i++;
    }
    return spans;
  }
}
