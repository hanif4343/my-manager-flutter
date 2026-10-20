import '../../reminder/models/reminder.dart' show Reminder, dateOnly;

/// Job Radar-এর ফলাফলের মডেল (ইঞ্জিন → ক্যাশ → UI)।
class RadarCheck {
  final String key;
  final String s; // ok | warn | fail
  final String msg;
  const RadarCheck({required this.key, required this.s, required this.msg});

  factory RadarCheck.fromMap(Map<String, dynamic> m) => RadarCheck(
        key: (m['key'] as String?) ?? '',
        s: (m['s'] as String?) ?? 'warn',
        msg: (m['msg'] as String?) ?? '',
      );

  Map<String, dynamic> toMap() => {'key': key, 's': s, 'msg': msg};

  String get icon => s == 'ok' ? '✅' : (s == 'fail' ? '❌' : '⚠️');
}

class RadarPost {
  final String title;
  final int? count;
  final String verdict; // ok | warn | fail
  final List<RadarCheck> checks;
  const RadarPost({required this.title, this.count, required this.verdict, required this.checks});

  factory RadarPost.fromMap(Map<String, dynamic> m) => RadarPost(
        title: (m['title'] as String?) ?? '',
        count: (m['count'] as num?)?.toInt(),
        verdict: (m['verdict'] as String?) ?? 'warn',
        checks: ((m['checks'] as List?) ?? const [])
            .map((e) => RadarCheck.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'count': count,
        'verdict': verdict,
        'checks': checks.map((c) => c.toMap()).toList(),
      };
}

class RadarItem {
  final String url;
  final String title;
  final String verdict; // ok | warn
  final String org;
  final DateTime? deadline; // স্থানীয় মধ্যরাত
  final String method;
  final String fee;
  final List<RadarPost> posts;

  const RadarItem({
    required this.url,
    required this.title,
    required this.verdict,
    this.org = '',
    this.deadline,
    this.method = '',
    this.fee = '',
    this.posts = const [],
  });

  factory RadarItem.fromMap(Map<String, dynamic> m) {
    final d = m['deadline'] as String?;
    return RadarItem(
      url: (m['url'] as String?) ?? '',
      title: (m['title'] as String?) ?? '',
      verdict: (m['verdict'] as String?) ?? 'warn',
      org: (m['org'] as String?) ?? '',
      deadline: (d == null || d.length < 10) ? null : Reminder.parseYmd(d.substring(0, 10)),
      method: (m['method'] as String?) ?? '',
      fee: (m['fee'] as String?) ?? '',
      posts: ((m['posts'] as List?) ?? const [])
          .map((e) => RadarPost.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'url': url,
        'title': title,
        'verdict': verdict,
        'org': org,
        'deadline': deadline == null ? null : Reminder.ymd(deadline!),
        'method': method,
        'fee': fee,
        'posts': posts.map((p) => p.toMap()).toList(),
      };

  /// আজকের হিসাবে বাকি দিন (সংরক্ষিত সংখ্যা পুরনো হয়ে যায়, তাই প্রতিবার নিজে হিসাব)।
  int? get daysLeft =>
      deadline == null ? null : dateOnly(deadline!).difference(dateOnly(DateTime.now())).inDays;
}

class RadarFeed {
  final DateTime? generatedAt;
  final List<RadarItem> items;
  /// শেষ রিপোর্টের পর যেগুলো প্রথমবার পাওয়া গেছে।
  final List<String> newUrls;
  const RadarFeed({this.generatedAt, required this.items, this.newUrls = const []});

  factory RadarFeed.fromMap(Map<String, dynamic> m) {
    final g = m['generatedAt'] as String?;
    return RadarFeed(
      generatedAt: g == null ? null : DateTime.tryParse(g)?.toLocal(),
      items: ((m['items'] as List?) ?? const [])
          .map((e) => RadarItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      newUrls: ((m['newUrls'] as List?) ?? const []).map((e) => e.toString()).toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'generatedAt': generatedAt?.toUtc().toIso8601String(),
        'items': items.map((i) => i.toMap()).toList(),
        'newUrls': newUrls,
      };
}
