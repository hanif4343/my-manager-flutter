import 'dart:convert';
import '../../reminder/models/reminder.dart' show Reminder;
import '../../services/notification_service.dart';
import '../../services/settings_service.dart';
import 'engine/bdgovtjob_source.dart';
import 'engine/bn_util.dart';
import 'engine/match_engine.dart';
import 'radar_models.dart';
import 'radar_service.dart';

class RadarRunSummary {
  final int total; // তালিকায় মোট চলমান উপযুক্ত
  final int ok;
  final int warn;
  final int fresh; // নতুন
  final String? error;
  const RadarRunSummary({this.total = 0, this.ok = 0, this.warn = 0, this.fresh = 0, this.error});
}

/// রাডার চালায়: সাইট থেকে পড়া → যাচাই → ক্যাশ → (রাতে) একটাই নোটিফিকেশন।
/// অ্যাপ খোলা অবস্থায় ও ব্যাকগ্রাউন্ড টাস্ক — দুই জায়গা থেকেই চলে।
class RadarRunner {
  static const _kState = 'radar_runner_state';
  static const _kRunning = 'radar_running_at';
  static const _maxFetch = 25;

  static String _today() => Reminder.ymd(DateTime.now());

  static Map<String, dynamic> _loadState() {
    final raw = SettingsService.getString(_kState);
    if (raw.isEmpty) return {'items': <String, dynamic>{}, 'lastReport': '', 'reported': <dynamic>[]};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {'items': <String, dynamic>{}, 'lastReport': '', 'reported': <dynamic>[]};
    }
  }

  /// আজকের রিপোর্ট বাকি আছে এবং রিপোর্টের সময় পেরিয়েছে কি না।
  static bool isDue([DateTime? now]) {
    if (!RadarService.dailyOn) return false;
    final n = now ?? DateTime.now();
    final at = DateTime(n.year, n.month, n.day, RadarService.reportHour, RadarService.reportMinute);
    if (n.isBefore(at)) return false;
    return _loadState()['lastReport'] != _today();
  }

  /// প্রোফাইল বদলালে: সব সংরক্ষিত ফলাফল "পুরনো" চিহ্নিত — পরের রানে নতুন প্রোফাইলে আবার যাচাই হবে।
  static Future<void> markStale() async {
    final s = _loadState();
    final items = Map<String, dynamic>.from((s['items'] as Map?) ?? {});
    for (final k in items.keys.toList()) {
      final v = Map<String, dynamic>.from(items[k] as Map);
      v['modified'] = null;
      v['checkedAt'] = 0;
      items[k] = v;
    }
    s['items'] = items;
    await SettingsService.setString(_kState, jsonEncode(s));
  }

  /// সময় হলে চালিয়ে নোটিফিকেশন দেয়। ব্যাকগ্রাউন্ড টাস্ক ও অ্যাপ চালু — দুই জায়গা থেকেই ডাকা হয়।
  static Future<RadarRunSummary?> runIfDue() async {
    await RadarService.reload();
    if (!isDue()) return null;
    return run(report: true);
  }

  /// এখনই চালায়। [report] সত্য হলে রাতের নোটিফিকেশন দেয় ও "আজকের রিপোর্ট হয়ে গেছে" চিহ্নিত করে।
  static Future<RadarRunSummary> run({bool report = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final running = SettingsService.getInt(_kRunning);
    if (running != 0 && now - running < 10 * 60 * 1000) {
      return const RadarRunSummary(error: 'আরেকটা রান চলছে — একটু পরে দেখো');
    }
    await SettingsService.setInt(_kRunning, now);
    try {
      return await _run(report);
    } finally {
      await SettingsService.setInt(_kRunning, 0);
    }
  }

  static Future<RadarRunSummary> _run(bool report) async {
    final profile = RadarService.profile();
    final state = _loadState();
    final items = Map<String, dynamic>.from((state['items'] as Map?) ?? {});
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    List<ListedPost> list;
    try {
      list = await listLatest(limit: 40);
    } catch (e) {
      list = [];
    }
    if (list.isEmpty) {
      // সাইট পাওয়া যায়নি — আগের ক্যাশই থাকুক, রিপোর্ট চিহ্নিত করব না (পরের টাস্কে আবার চেষ্টা)।
      return const RadarRunSummary(error: 'সাইট থেকে তালিকা পাওয়া যায়নি — ইন্টারনেট/সাইট দেখো');
    }

    var fetched = 0;
    for (final it in list) {
      final prev = items[it.url] as Map?;
      if (prev != null) {
        if (it.modified != null && prev['modified'] == it.modified) continue;
        if (it.modified == null && nowMs - ((prev['checkedAt'] as num?)?.toInt() ?? 0) < 6 * 3600 * 1000) continue;
      }
      if (fetched >= _maxFetch) break;
      fetched++;
      await Future<void>.delayed(const Duration(milliseconds: 800));
      FetchedDetail d;
      try {
        d = await fetchDetail(it.url);
      } catch (_) {
        continue;
      }
      final title = it.title.isNotEmpty ? it.title : d.title;
      final r = evaluate(d.text, profile, title: title);
      final good = (r.verdict == 'ok' || r.verdict == 'warn') && !r.expired;
      items[it.url] = {
        'modified': it.modified,
        'checkedAt': nowMs,
        'item': good
            ? RadarItem(
                url: it.url,
                title: title,
                verdict: r.verdict,
                org: r.org,
                deadline: r.nearest == null ? null : DateTime(r.nearest!.year, r.nearest!.month, r.nearest!.day),
                method: r.method,
                fee: r.fee,
                posts: r.posts.where((p) => p.verdict != 'fail').toList(),
              ).toMap()
            : null,
      };
    }

    // ১২০ দিনের পুরনো এন্ট্রি ছাঁটাই
    items.removeWhere((_, v) => nowMs - (((v as Map)['checkedAt'] as num?)?.toInt() ?? 0) > 120 * 86400000);

    // ফিড: চলমান, উপযুক্ত — শেষ তারিখ অনুযায়ী
    final feedItems = <RadarItem>[];
    for (final v in items.values) {
      final m = (v as Map)['item'];
      if (m == null) continue;
      final ri = RadarItem.fromMap(Map<String, dynamic>.from(m as Map));
      if (ri.daysLeft != null && ri.daysLeft! < 0) continue;
      feedItems.add(ri);
    }
    feedItems.sort((a, b) => (a.daysLeft ?? 999).compareTo(b.daysLeft ?? 999));

    final reported = ((state['reported'] as List?) ?? const []).map((e) => e.toString()).toSet();
    final fresh = feedItems.where((i) => !reported.contains(i.url)).map((i) => i.url).toList();

    final feed = RadarFeed(generatedAt: DateTime.now(), items: feedItems, newUrls: fresh);
    await RadarService.saveFeed(feed);

    state['items'] = items;
    if (report) {
      await _notify(feed);
      state['lastReport'] = _today();
      state['reported'] = feedItems.map((i) => i.url).toList(); // এখনকার সবই "জানানো" হলো
    }
    await SettingsService.setString(_kState, jsonEncode(state));

    final ok = feedItems.where((i) => i.verdict == 'ok').length;
    return RadarRunSummary(total: feedItems.length, ok: ok, warn: feedItems.length - ok, fresh: fresh.length);
  }

  // ── রাতের নোটিফিকেশন: একটাই, পুরো তালিকাসহ ──
  static Future<void> _notify(RadarFeed feed) async {
    final its = feed.items;
    if (its.isEmpty) {
      await NotificationService.showRadarReport(
        '📡 আজকের রাডার',
        'আজ তোমার যোগ্যতার সাথে মেলে এমন চলমান সার্কুলার নেই।',
        'আজ তোমার যোগ্যতার সাথে মেলে এমন চলমান সার্কুলার নেই। কাল আবার দেখব।',
      );
      return;
    }
    final ok = its.where((i) => i.verdict == 'ok').length;
    final warn = its.length - ok;
    final fresh = feed.newUrls.toSet();
    final head = '📡 আজকের রাডার: ${toBnStr(its.length)}টি সার্কুলার'
        '${fresh.isNotEmpty ? ' (🆕 ${toBnStr(fresh.length)}টি নতুন)' : ''}';
    final short = '🟢 ${toBnStr(ok)}টি সম্ভাব্য যোগ্য · 🟡 ${toBnStr(warn)}টি যাচাই বাকি';
    final lines = <String>[];
    for (final i in its.take(10)) {
      final dl = i.daysLeft;
      final when = dl == null ? '' : (dl == 0 ? ' — আজই শেষ' : ' — আর ${toBnStr(dl)} দিন');
      lines.add('${fresh.contains(i.url) ? '🆕' : (i.verdict == 'ok' ? '🟢' : '🟡')} ${i.title}$when');
    }
    if (its.length > 10) lines.add('… আরও ${toBnStr(its.length - 10)}টি — অ্যাপে দেখো');
    await NotificationService.showRadarReport(head, short, '$short\n\n${lines.join('\n')}');
  }
}
