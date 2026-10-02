import 'dart:convert';
import '../../reminder/models/reminder.dart';

/// ক্যাটাগরি → (ইমোজি, নাম, সাধারণ ডকুমেন্টের নাম)
const docCategories = <String, (String, String, List<String>)>{
  'identity': ('🪪', 'পরিচয়', ['জাতীয় পরিচয়পত্র (NID)', 'জন্মনিবন্ধন সনদ', 'পাসপোর্ট', 'ড্রাইভিং লাইসেন্স', 'নাগরিকত্ব সনদ']),
  'education': ('🎓', 'শিক্ষা', ['SSC সনদ', 'SSC মার্কশিট', 'HSC সনদ', 'HSC মার্কশিট', 'স্নাতক সনদ', 'স্নাতক ট্রান্সক্রিপ্ট', 'স্নাতকোত্তর সনদ']),
  'job': ('💼', 'চাকরি', ['অভিজ্ঞতার সনদ', 'কোটা সনদ', 'প্রত্যয়নপত্র', 'চারিত্রিক সনদ', 'আবেদন ফি-র রসিদ', 'প্রবেশপত্র']),
  'photo': ('🖼️', 'ছবি ও স্বাক্ষর', ['পাসপোর্ট সাইজ ছবি', 'স্ট্যাম্প সাইজ ছবি', 'স্বাক্ষর']),
  'property': ('🏠', 'সম্পত্তি ও আর্থিক', ['জমির দলিল', 'বীমা পলিসি', 'ব্যাংক স্টেটমেন্ট', 'টিন সনদ']),
  'medical': ('🩺', 'স্বাস্থ্য', ['প্রেসক্রিপশন', 'পরীক্ষার রিপোর্ট', 'টিকা কার্ড']),
  'other': ('📎', 'অন্যান্য', []),
};

class DocPage {
  final String fileId; // এনক্রিপ্টেড ফাইলের নাম (.enc ছাড়া)
  final String name; // মূল ফাইলের নাম
  final String mime; // image/jpeg | application/pdf ...
  final int size;
  const DocPage(this.fileId, this.name, this.mime, this.size);

  bool get isPdf => mime == 'application/pdf';

  Map<String, dynamic> toJson() => {'f': fileId, 'n': name, 'm': mime, 's': size};
  factory DocPage.fromJson(Map<String, dynamic> j) =>
      DocPage(j['f'] as String, (j['n'] as String?) ?? '', (j['m'] as String?) ?? 'image/jpeg', (j['s'] as int?) ?? 0);
}

class VaultDoc {
  String id;
  String title;
  String category;
  String numberEnc; // ডকুমেন্ট নম্বর — এনক্রিপ্টেড (base64), ফাঁকা হলে নেই
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

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'category': category,
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
