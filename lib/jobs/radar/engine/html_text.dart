const _ent = {
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ', 'ndash': '–', 'mdash': '—', 'hellip': '…',
};

String decodeEntities(String s) {
  return s
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)))
      .replaceAllMapped(RegExp(r'&([a-zA-Z]+);'), (m) => _ent[m[1]!.toLowerCase()] ?? m[0]!);
}

/// HTML → লাইনভিত্তিক টেক্সট। হেডিং হয় "## ..." লাইন, টেবিলের ঘর "|" দিয়ে আলাদা।
String htmlToText(String html) {
  var s = html
      .replaceAll(RegExp(r'<(script|style|noscript|svg|template)[\s\S]*?</\1>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
      .replaceAll(RegExp(r'<h[1-6][^>]*>', caseSensitive: false), '\n## ')
      .replaceAll(
          RegExp(r'</(h[1-6]|p|div|li|tr|table|section|ul|ol|article|header|footer|blockquote)>', caseSensitive: false),
          '\n')
      .replaceAll(RegExp(r'<(br|hr)\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</t[dh]>', caseSensitive: false), ' | ')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  s = decodeEntities(s);
  final ws = RegExp('[\\s\u00a0\u200b]+');
  return s
      .split('\n')
      .map((l) => l.replaceAll(ws, ' ').trim())
      .where((l) => l.isNotEmpty)
      .join('\n');
}

String titleOf(String html) {
  final m = RegExp(r'<h1[^>]*>([\s\S]*?)</h1>', caseSensitive: false).firstMatch(html) ??
      RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(html);
  if (m == null) return '';
  return decodeEntities(m[1]!.replaceAll(RegExp(r'<[^>]+>'), '')).replaceAll(RegExp(r'\s+'), ' ').trim();
}
