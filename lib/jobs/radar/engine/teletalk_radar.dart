import '../radar_models.dart';
import 'bn_util.dart';
import 'match_engine.dart';
import 'teletalk_source.dart';

/// Teletalk-এর তালিকা থেকে তোমার টার্গেট পদগুলো বেছে একই প্রতিষ্ঠানের পদ একসাথে করে RadarItem বানায়।
///
/// তালিকার API-তে শুধু পদের নাম, প্রতিষ্ঠান, পদসংখ্যা, আবেদন শুরু ও শেষ তারিখ আছে — বয়স/শিক্ষা/টাইপিংয়ের
/// শর্ত নেই। তাই ফলাফল সবসময় "যাচাই বাকি" (🟡); শর্ত দেখতে আবেদনের লিংকে যেতে হবে।
List<RadarItem> teletalkItems(List<TeletalkJob> jobs, RadarProfile profile, {DateTime? now}) {
  final today = todayDhaka(now);
  final groups = <String, List<TeletalkJob>>{};
  for (final j in jobs) {
    if (j.deadline != null && daysBetween(today, j.deadline!) < 0) continue; // মেয়াদ শেষ
    final rel = postRelevance('${j.titleBn} ${j.titleEn}', profile);
    if (rel != 'yes') continue; // টার্গেট নয় বা সাঁটলিপি লাগে
    final key = j.applyUrl.isNotEmpty ? j.applyUrl : j.shortName;
    groups.putIfAbsent(key, () => []).add(j);
  }

  final items = <RadarItem>[];
  groups.forEach((key, list) {
    final first = list.first;
    final org = first.orgNameBn.isNotEmpty ? first.orgNameBn : first.orgName;

    final posts = <RadarPost>[];
    for (final j in list) {
      final checks = <RadarCheck>[
        RadarCheck(key: 'post', s: 'ok', msg: 'পদের নাম মিলেছে: ${j.titleEn}'),
      ];
      if (j.published != null && daysBetween(today, j.published!) > 0) {
        checks.add(RadarCheck(key: 'start', s: 'warn', msg: 'আবেদন শুরু: ${fmtDateBn(j.published!)} (এখনো শুরু হয়নি)'));
      }
      checks.add(const RadarCheck(
        key: 'details',
        s: 'warn',
        msg: 'বয়স, শিক্ষা ও টাইপিংয়ের শর্ত Teletalk-এর বিজ্ঞপ্তিতে দেখো — এখনো স্বয়ংক্রিয় যাচাই হয়নি',
      ));
      posts.add(RadarPost(
        title: j.titleBn.isNotEmpty ? j.titleBn : j.titleEn,
        count: j.vacancy,
        verdict: 'warn',
        checks: checks,
      ));
    }

    final deadlines = list.map((j) => j.deadline).whereType<DateTime>().toList()..sort();
    final dl = deadlines.isEmpty ? null : deadlines.first;
    items.add(RadarItem(
      // একই প্রতিষ্ঠানের আবেদন-পোর্টাল একটাই; #teletalk যোগ করে bdgovtjob-এর লিংকের সাথে মিশে যাওয়া ঠেকানো
      url: '${first.applyUrl}#teletalk',
      title: '$org (Teletalk)',
      verdict: 'warn',
      org: org,
      deadline: dl == null ? null : DateTime(dl.year, dl.month, dl.day),
      method: 'অনলাইন — ${first.applyUrl}',
      posts: posts,
    ));
  });
  return items;
}
