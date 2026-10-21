import 'dart:convert';
import 'bdgovtjob_source.dart' show httpGet;

const _api = 'https://alljobs.teletalk.com.bd/api/v1/published-jobs/search';

/// Teletalk AllJobs-এর সরকারি চাকরির এন্ট্রি (খোলা JSON API থেকে)।
class TeletalkJob {
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
  Map<String, dynamic> toMap() => {
        'id': jobId, 'en': titleEn, 'bn': titleBn, 'vac': vacancy, 'url': applyUrl,
        'pub': _ymd(published), 'dl': _ymd(deadline), 'org': orgName, 'orgBn': orgNameBn, 'short': shortName,
      };

  factory TeletalkJob.fromCache(Map<String, dynamic> m) => TeletalkJob(
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
