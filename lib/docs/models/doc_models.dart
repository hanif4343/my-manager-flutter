import 'dart:convert';
import '../../reminder/models/reminder.dart';

/// ক্যাটাগরি → (ইমোজি, নাম, সাধারণ ডকুমেন্টের নাম)
const docCategories = <String, (String, String, List<String>)>{
  'identity': ('🪪', 'পরিচয়', ['জাতীয় পরিচয়পত্র (NID)', 'জন্মনিবন্ধন সনদ', 'পাসপোর্ট', 'ড্রাইভিং লাইসেন্স', 'নাগরিকত্ব সনদ']),
  'education': ('🎓', 'শিক্ষা', ['JSC সনদ', 'SSC সনদ', 'HSC সনদ', 'স্নাতক সনদ', 'স্নাতকোত্তর সনদ']),
  'job': ('💼', 'চাকরি', ['অভিজ্ঞতার সনদ', 'কোটা সনদ', 'প্রত্যয়নপত্র', 'চারিত্রিক সনদ', 'আবেদন ফি-র রসিদ', 'প্রবেশপত্র']),
  'photo': ('🖼️', 'ছবি ও স্বাক্ষর', ['পাসপোর্ট সাইজ ছবি', 'স্ট্যাম্প সাইজ ছবি', 'স্বাক্ষর']),
  'property': ('🏠', 'সম্পত্তি ও আর্থিক', ['জমির দলিল', 'বীমা পলিসি', 'ব্যাংক স্টেটমেন্ট', 'টিন সনদ']),
  'medical': ('🩺', 'স্বাস্থ্য', ['প্রেসক্রিপশন', 'পরীক্ষার রিপোর্ট', 'টিকা কার্ড']),
  'other': ('📎', 'অন্যান্য', []),
};

// ───────────────────────── ডকুমেন্টের ধরন (টেমপ্লেট) ─────────────────────────

const kFront = 'সামনের দিক';
const kBack = 'পেছনের দিক';

class DocField {
  final String key; // 'number' | 'roll' | 'reg'
  final String label;
  const DocField(this.key, this.label);
}

/// একটা ধরনের ডকুমেন্টে কয়টা পাতা, প্রতিটার নাম কী, কোন কোন তথ্যের ঘর থাকবে।
/// [pageLabels] ফাঁকা মানে পাতার সংখ্যা ঠিক করা নেই (যত খুশি যোগ করা যায়)।
class DocTemplate {
  final String key;
  final String title;
  final String category;
  final String slug; // শেয়ার/আপলোডের ফাইলের নামে (ইংরেজি)
  final List<String> pageLabels;
  final List<DocField> fields;
  final bool hasExpiry;
  const DocTemplate({
    required this.key,
    required this.title,
    required this.category,
    required this.slug,
    this.pageLabels = const [],
    this.fields = const [],
    this.hasExpiry = false,
  });

  bool get isFree => pageLabels.isEmpty;
  bool get isCustom => key == 'other';
  String get emoji => (docCategories[category] ?? docCategories['other']!).$1;

  String get subtitle {
    if (isFree) return 'যত পাতা লাগে';
    if (pageLabels.length == 2 && pageLabels[0] == kFront) return 'সামনে + পেছনে';
    if (pageLabels.length == 1) {
      return fields.length > 1 ? '১ পাতা · রোল, রেজি.' : '১ পাতা';
    }
    return '${pageLabels.length} পাতা';
  }
}

const _numNid = DocField('number', 'NID নম্বর');
const _roll = DocField('roll', 'রোল নম্বর');
const _reg = DocField('reg', 'রেজিস্ট্রেশন নম্বর');

const docTemplates = <DocTemplate>[
  DocTemplate(
    key: 'nid', title: 'জাতীয় পরিচয়পত্র (NID)', category: 'identity', slug: 'nid',
    pageLabels: [kFront, kBack], fields: [_numNid],
  ),
  DocTemplate(
    key: 'birth', title: 'জন্মনিবন্ধন সনদ', category: 'identity', slug: 'birth_certificate',
    pageLabels: [kFront, kBack], fields: [DocField('number', 'জন্মনিবন্ধন নম্বর')],
  ),
  DocTemplate(
    key: 'citizen', title: 'নাগরিকত্ব সনদ', category: 'identity', slug: 'citizenship_certificate',
    pageLabels: ['সনদ'], fields: [DocField('number', 'সনদ নম্বর')],
  ),
  DocTemplate(
    key: 'jsc', title: 'JSC সনদ', category: 'education', slug: 'jsc',
    pageLabels: ['সনদ'], fields: [_roll, _reg],
  ),
  DocTemplate(
    key: 'ssc', title: 'SSC সনদ', category: 'education', slug: 'ssc',
    pageLabels: ['সনদ'], fields: [_roll, _reg],
  ),
  DocTemplate(
    key: 'hsc', title: 'HSC সনদ', category: 'education', slug: 'hsc',
    pageLabels: ['সনদ'], fields: [_roll, _reg],
  ),
  DocTemplate(
    key: 'degree', title: 'স্নাতক সনদ', category: 'education', slug: 'degree',
    pageLabels: ['সনদ'], fields: [_roll, _reg],
  ),
  DocTemplate(
    key: 'masters', title: 'স্নাতকোত্তর সনদ', category: 'education', slug: 'masters',
    pageLabels: ['সনদ'], fields: [_roll, _reg],
  ),
  DocTemplate(
    key: 'passport', title: 'পাসপোর্ট', category: 'identity', slug: 'passport',
    pageLabels: ['ডাটা পেজ'], fields: [DocField('number', 'পাসপোর্ট নম্বর')], hasExpiry: true,
  ),
  DocTemplate(
    key: 'driving', title: 'ড্রাইভিং লাইসেন্স', category: 'identity', slug: 'driving_license',
    pageLabels: [kFront, kBack], fields: [DocField('number', 'লাইসেন্স নম্বর')], hasExpiry: true,
  ),
  DocTemplate(
    key: 'photo', title: 'পাসপোর্ট সাইজ ছবি', category: 'photo', slug: 'photo',
    pageLabels: ['ছবি'],
  ),
  DocTemplate(
    key: 'sign', title: 'স্বাক্ষর', category: 'photo', slug: 'signature',
    pageLabels: ['স্বাক্ষর'],
  ),
  DocTemplate(
    key: 'other', title: 'অন্যান্য গুরুত্বপূর্ণ ডকুমেন্ট', category: 'other', slug: 'document',
    fields: [DocField('number', 'ডকুমেন্ট নম্বর')], hasExpiry: true,
  ),
];

DocTemplate? templateByKey(String? key) {
  if (key == null || key.isEmpty) return null;
  for (final t in docTemplates) {
    if (t.key == key) return t;
  }
  return null;
}

/// পুরনো ডকুমেন্ট (tpl নেই) হলে নাম মিলিয়ে ধরন বের করা; না মিললে "অন্যান্য"।
DocTemplate resolveTemplate(VaultDoc d) {
  final byKey = templateByKey(d.tpl);
  if (byKey != null) return byKey;
  for (final t in docTemplates) {
    if (!t.isCustom && t.title == d.title) return t;
  }
  return docTemplates.last;
}

/// তথ্যের ঘরগুলো (নম্বর, রোল, রেজি.) এনক্রিপ্ট করার আগের সাধারণ লেখায় রূপ।
/// শুধু 'number' থাকলে আগের মতোই সরল লেখা — তাই পুরনো ডকুমেন্ট ও ব্যাকআপের সাথে মেলে।
class DocFields {
  static String encode(Map<String, String> m) {
    final clean = <String, String>{};
    m.forEach((k, v) {
      if (v.trim().isNotEmpty) clean[k] = v.trim();
    });
    if (clean.isEmpty) return '';
    if (clean.length == 1 && clean.containsKey('number')) return clean['number']!;
    return jsonEncode(clean);
  }

  static Map<String, String> decode(String plain) {
    if (plain.isEmpty) return {};
    if (plain.startsWith('{')) {
      try {
        final j = jsonDecode(plain) as Map;
        return j.map((k, v) => MapEntry('$k', '$v'));
      } catch (_) {}
    }
    return {'number': plain};
  }
}

// ───────────────────────── পাতা ও ডকুমেন্ট ─────────────────────────

class DocPage {
  final String fileId; // এনক্রিপ্টেড ফাইলের নাম (.enc ছাড়া)
  final String name; // মূল ফাইলের নাম
  final String mime; // image/jpeg | application/pdf ...
  final int size;
  final String label; // "সামনের দিক" / "পেছনের দিক" / ফাঁকা
  const DocPage(this.fileId, this.name, this.mime, this.size, {this.label = ''});

  bool get isPdf => mime == 'application/pdf';

  DocPage withLabel(String l) => DocPage(fileId, name, mime, size, label: l);

  Map<String, dynamic> toJson() => {
        'f': fileId,
        'n': name,
        'm': mime,
        's': size,
        if (label.isNotEmpty) 'l': label,
      };
  factory DocPage.fromJson(Map<String, dynamic> j) => DocPage(
        j['f'] as String,
        (j['n'] as String?) ?? '',
        (j['m'] as String?) ?? 'image/jpeg',
        (j['s'] as int?) ?? 0,
        label: (j['l'] as String?) ?? '',
      );
}

class VaultDoc {
  String id;
  String title;
  String category;
  String tpl; // DocTemplate.key (পুরনো ডকুমেন্টে ফাঁকা)
  String numberEnc; // নম্বর/রোল/রেজি. — এনক্রিপ্টেড (base64), ফাঁকা হলে নেই
  DateTime? expiry;
  String note;
  List<DocPage> pages;
  List<int> rem;
  int createdAt;
  int updatedAt;

  VaultDoc({
    required this.id,
    required this.title,
    this.category = 'other',
    this.tpl = '',
    this.numberEnc = '',
    this.expiry,
    this.note = '',
    List<DocPage>? pages,
    List<int>? rem,
    int? createdAt,
    int? updatedAt,
  })  : pages = pages ?? [],
        rem = rem ?? [],
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  String get emoji => (docCategories[category] ?? docCategories['other']!).$1;

  int? get daysToExpiry =>
      expiry == null ? null : dateOnly(expiry!).difference(dateOnly(DateTime.now())).inDays;

  /// i-তম পাতার দেখানোর নাম।
  String pageLabel(int i) {
    final l = pages[i].label;
    if (l.isNotEmpty) return l;
    return pages.length == 1 ? 'পাতা' : 'পাতা ${i + 1}';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'category': category,
        'tpl': tpl,
        'number_enc': numberEnc,
        'expiry': expiry == null ? null : Reminder.ymd(expiry!),
        'note': note,
        'pages': jsonEncode(pages.map((p) => p.toJson()).toList()),
        'rem': rem.join(','),
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory VaultDoc.fromMap(Map<String, dynamic> m) {
    List<DocPage> pages = [];
    try {
      pages = (jsonDecode((m['pages'] as String?) ?? '[]') as List)
          .map((e) => DocPage.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {}
    final exp = m['expiry'] as String?;
    return VaultDoc(
      id: m['id'] as String,
      title: m['title'] as String,
      category: (m['category'] as String?) ?? 'other',
      tpl: (m['tpl'] as String?) ?? '',
      numberEnc: (m['number_enc'] as String?) ?? '',
      expiry: (exp == null || exp.isEmpty) ? null : Reminder.parseYmd(exp),
      note: (m['note'] as String?) ?? '',
      pages: pages,
      rem: (m['rem'] as String? ?? '')
          .split(',')
          .where((e) => e.trim().isNotEmpty)
          .map(int.parse)
          .toList(),
      createdAt: m['created_at'] as int?,
      updatedAt: m['updated_at'] as int?,
    );
  }
}
