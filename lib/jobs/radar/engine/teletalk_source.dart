import 'dart:convert';
import 'package:http/http.dart' as http;
import 'bdgovtjob_source.dart' show httpGet;

const _site = 'https://alljobs.teletalk.com.bd';
const _api = '$_site/api/v1/published-jobs/search';

/// Teletalk AllJobs-এর সরকারি চাকরির এন্ট্রি (খোলা JSON API থেকে)।
class TeletalkJob {
  final int primaryId; // 15024 — বিস্তারিত API-র আইডি
  final int? orgId; // 1165
  final String jobId; // GJOB15024
  final String titleEn;
  final String titleBn;
  final int? vacancy;
  final String applyUrl;
  final DateTime? published; // আবেদন শুরু (বাংলাদেশ সময়ের তারিখ, UTC-মধ্যরাত)
  final DateTime? deadline; // শেষ তারিখ (বাংলাদেশ সময়ের তারিখ, UTC-মধ্যরাত)
  final String orgName;
  final String orgNameBn;
  final String shortName;

  const TeletalkJob({
    this.primaryId = 0,
    this.orgId,
    required this.jobId,
    required this.titleEn,
    required this.titleBn,
    this.vacancy,
    required this.applyUrl,
    this.published,
    this.deadline,
    required this.orgName,
    required this.orgNameBn,
    required this.shortName,
  });

  static String? _ymd(DateTime? d) =>
      d == null ? null : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? _fromYmd(Object? s) {
    final p = (s ?? '').toString().split('-');
    if (p.length != 3) return null;
    final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
    return (y == null || m == null || d == null) ? null : DateTime.utc(y, m, d);
  }

  /// ক্যাশে রাখার সংক্ষিপ্ত রূপ।
  /// Teletalk সাইটে এই চাকরির বিস্তারিত পেজ।
  String get detailsUrl => orgId == null || primaryId == 0
      ? '$_site/jobs?orgid=1'
      : '$_site/jobs/government/$orgId?jobId=$primaryId';

  Map<String, dynamic> toMap() => {
        'pid': primaryId, 'oid': orgId,
        'id': jobId, 'en': titleEn, 'bn': titleBn, 'vac': vacancy, 'url': applyUrl,
        'pub': _ymd(published), 'dl': _ymd(deadline), 'org': orgName, 'orgBn': orgNameBn, 'short': shortName,
      };

  factory TeletalkJob.fromCache(Map<String, dynamic> m) => TeletalkJob(
        primaryId: (m['pid'] as num?)?.toInt() ?? 0,
        orgId: (m['oid'] as num?)?.toInt(),
        jobId: (m['id'] ?? '').toString(),
        titleEn: (m['en'] ?? '').toString(),
        titleBn: (m['bn'] ?? '').toString(),
        vacancy: (m['vac'] as num?)?.toInt(),
        applyUrl: (m['url'] ?? '').toString(),
        published: _fromYmd(m['pub']),
        deadline: _fromYmd(m['dl']),
        orgName: (m['org'] ?? '').toString(),
        orgNameBn: (m['orgBn'] ?? '').toString(),
        shortName: (m['short'] ?? '').toString(),
      );

  /// "2026-11-14T10:00:00.000Z" → বাংলাদেশ সময়ের তারিখ (UTC-মধ্যরাত রূপে)।
  static DateTime? _bdDate(Object? iso) {
    final d = DateTime.tryParse((iso ?? '').toString());
    if (d == null) return null;
    final t = d.toUtc().add(const Duration(hours: 6));
    return DateTime.utc(t.year, t.month, t.day);
  }

  factory TeletalkJob.fromMap(Map<String, dynamic> m) => TeletalkJob(
        primaryId: (m['job_primary_id'] as num?)?.toInt() ?? 0,
        orgId: (m['organization_id'] as num?)?.toInt(),
        jobId: (m['job_id'] ?? '').toString(),
        titleEn: (m['job_title'] ?? '').toString().trim(),
        titleBn: (m['job_title_bn'] ?? '').toString().trim(),
        vacancy: int.tryParse((m['vacancy'] ?? '').toString()),
        applyUrl: (m['application_site_url'] ?? '').toString().trim(),
        published: _bdDate(m['published_date']),
        deadline: _bdDate(m['deadline_date']),
        orgName: (m['org_name'] ?? '').toString().trim(),
        orgNameBn: (m['org_name_bn'] ?? '').toString().trim(),
        shortName: (m['short_name'] ?? '').toString().trim(),
      );
}

/// সব চলমান সরকারি চাকরি (পেজ ধরে ধরে; ২০টা করে — যে মান যাচাই করা হয়েছে)। দিনে একবার চলে।
Future<List<TeletalkJob>> fetchTeletalkJobs({int maxPages = 15}) async {
  final out = <TeletalkJob>[];
  var total = 0;
  for (var page = 1; page <= maxPages; page++) {
    final body = await httpGet('$_api?page=$page&limit=20&org=1', json: true);
    final m = Map<String, dynamic>.from(jsonDecode(body) as Map);
    total = (m['count'] as num?)?.toInt() ?? total;
    final list = (m['govtJobs'] as List?) ?? const [];
    if (list.isEmpty) break;
    for (final e in list) {
      out.add(TeletalkJob.fromMap(Map<String, dynamic>.from(e as Map)));
    }
    if (total > 0 && out.length >= total) break;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return out;
}

/// বিস্তারিত API থেকে পাওয়া শর্ত: বয়স, বিজ্ঞপ্তি নং, বিজ্ঞপ্তির PDF-এর পাথ।
class TeletalkDetail {
  final int? minAge;
  final int? maxAge;
  final String adNo;
  final String adFile; // "public/uploads/governments/jobs/advertisement-….pdf"
  const TeletalkDetail({this.minAge, this.maxAge, this.adNo = '', this.adFile = ''});

  factory TeletalkDetail.fromMap(Map<String, dynamic> m) => TeletalkDetail(
        minAge: (m['min_age'] as num?)?.toInt(),
        maxAge: (m['max_age'] as num?)?.toInt(),
        adNo: (m['advertisement_no'] ?? '').toString().trim(),
        adFile: (m['advertisement_file'] ?? '').toString().trim(),
      );
}

Future<TeletalkDetail> fetchTeletalkDetail(int primaryId) async {
  final body = await httpGet('$_site/api/v1/govt-jobs/public-details?id=$primaryId', json: true);
  final m = Map<String, dynamic>.from(jsonDecode(body) as Map);
  return TeletalkDetail.fromMap(Map<String, dynamic>.from((m['details'] as Map?) ?? {}));
}

/// "public/uploads/…/advertisement-….pdf" পাথ থেকে সম্ভাব্য ডাউনলোড ঠিকানার তালিকা (সম্ভাবনা অনুযায়ী সাজানো)।
/// সাইট কোন পাথে ফাইল দেয় তা নিশ্চিত না — তাই একাধিক ঠিকানা; ভিউয়ার একটা একটা করে চেষ্টা করে PDF চিনে নেয়।
List<String> teletalkAdvertisementCandidates(String path) {
  final p0 = path.trim();
  if (p0.isEmpty) return const [];
  if (p0.startsWith('http://') || p0.startsWith('https://')) return [p0];
  final p = p0.replaceFirst(RegExp(r'^/+'), '');
  final noPublic = p.replaceFirst(RegExp(r'^public/'), '');
  return <String>{
    '$_site/$p',
    '$_site/$noPublic',
    '$_site/api/$p',
    '$_site/api/v1/$p',
    '$_site/api/v1/$noPublic',
    '$_site/api/$noPublic',
    '$_site/api/v1/files/$noPublic',
    '$_site/files/$noPublic',
    '$_site/static/$noPublic',
    '$_site/storage/$noPublic',
  }.toList();
}

/// বিস্তারিত API-র পুরো উত্তর (কোন কোন ফিল্ড আছে দেখতে/লিংক খুঁজতে)।
Future<Map<String, dynamic>> fetchTeletalkDetailRaw(int primaryId) async {
  final body = await httpGet('$_site/api/v1/govt-jobs/public-details?id=$primaryId', json: true);
  return Map<String, dynamic>.from(jsonDecode(body) as Map);
}

/// Teletalk সার্কুলারের লিংক (…/jobs/government/১?jobId=৯৯) থেকে jobId; অন্য লিংক হলে null।
int? teletalkJobIdFromUrl(String url) {
  final u = Uri.tryParse(url);
  if (u == null || !u.host.contains('teletalk.com.bd')) return null;
  return int.tryParse(u.queryParameters['jobId'] ?? '');
}

/// বিজ্ঞপ্তির PDF-এর আসল লিংক খুঁজে বের করে (পাথ থেকে সম্ভাব্য ঠিকানা পরীক্ষা করে; পাওয়া না গেলে null)।
Future<String?> resolveAdvertisementUrl(String path) async {
  if (path.isEmpty) return null;
  final p = path.replaceFirst(RegExp(r'^/+'), '');
  final candidates = <String>{'$_site/$p', '$_site/${p.replaceFirst(RegExp(r'^public/'), '')}'};
  for (final u in candidates) {
    try {
      final r = await http.head(Uri.parse(u)).timeout(const Duration(seconds: 8));
      final ct = (r.headers['content-type'] ?? '').toLowerCase();
      // সাইট অজানা পাথে 200 + HTML ফেরত দিতে পারে, তাই কনটেন্ট-টাইপ দেখি
      if (r.statusCode == 200 && (ct.contains('pdf') || ct.contains('octet-stream'))) return u;
    } catch (_) {}
  }
  return null;
}
