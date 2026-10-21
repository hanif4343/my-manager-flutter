import 'dart:convert';
import 'package:http/http.dart' as http;
import 'html_text.dart';

const _base = 'https://bdgovtjob.net';
const _ua = 'JobRadar/1.0 (personal app; once a day)';
const _blockSlugs = {
  'category', 'tag', 'author', 'page', 'wp-content', 'wp-json', 'wp-admin', 'feed', 'about', 'contact',
  'privacy-policy', 'disclaimer', 'terms-conditions', 'editorial-policy', 'smart-search', 'saved-jobs',
  'age-calculator', 'notice', 'sitemap', 'comments', 'search',
};

class ListedPost {
  final String url;
  final String title;
  final String? modified;
  const ListedPost(this.url, this.title, this.modified);
}

class FetchedDetail {
  final String title;
  final String text;
  const FetchedDetail(this.title, this.text);
}

Future<String> httpGet(String url, {bool json = false}) async {
  Object? last;
  for (var i = 0; i < 2; i++) {
    try {
      final res = await http.get(Uri.parse(url), headers: {
        'user-agent': _ua,
        'accept': json ? 'application/json' : 'text/html,*/*',
        'accept-language': 'bn,en;q=0.8',
      }).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      return utf8.decode(res.bodyBytes);
    } catch (e) {
      last = e;
      await Future<void>.delayed(Duration(seconds: 2 * (i + 1)));
    }
  }
  throw Exception('$last');
}

/// সর্বশেষ আপডেট হওয়া পোস্টের তালিকা। আগে WordPress REST, না হলে HTML থেকে লিংক।
Future<List<ListedPost>> listLatest({int limit = 40}) async {
  try {
    final body = await httpGet(
      '$_base/wp-json/wp/v2/posts?per_page=${limit > 50 ? 50 : limit}&orderby=modified&order=desc&_fields=link,title,modified',
      json: true,
    );
    final arr = jsonDecode(body);
    if (arr is List && arr.isNotEmpty) {
      return arr.map<ListedPost>((p) {
        final m = Map<String, dynamic>.from(p as Map);
        final t = decodeEntities(((m['title'] as Map?)?['rendered'] ?? '').toString())
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .trim();
        return ListedPost((m['link'] ?? '').toString(), t, m['modified']?.toString());
      }).where((p) => p.url.isNotEmpty).toList();
    }
  } catch (_) {
    // REST কাজ না করলে নিচের HTML তালিকায় যাব
  }
  final seen = <String, ListedPost>{};
  for (final u in ['$_base/', '$_base/category/government-jobs-circular/', '$_base/category/teletalk-application/']) {
    try {
      final html = await httpGet(u);
      final re = RegExp(r'<a[^>]+href="(https://bdgovtjob\.net/([^"/?#]+)/)"[^>]*>([\s\S]*?)</a>', caseSensitive: false);
      for (final m in re.allMatches(html)) {
        final url = m[1]!, slug = m[2]!;
        if (_blockSlugs.contains(slug) || slug.length < 6) continue;
        final title = decodeEntities(m[3]!.replaceAll(RegExp(r'<[^>]+>'), '')).replaceAll(RegExp(r'\s+'), ' ').trim();
        final old = seen[url];
        if (old == null || title.length > old.title.length) seen[url] = ListedPost(url, title, null);
      }
    } catch (_) {}
  }
  return seen.values.take(limit).toList();
}

/// একটি সার্কুলার পেজ → শিরোনাম ও টেক্সট।
Future<FetchedDetail> fetchDetail(String url) async {
  final html = await httpGet(url);
  var body = html;
  final a = html.indexOf(RegExp(r'<article[\s>]', caseSensitive: false));
  final b = html.indexOf(RegExp(r'</article>', caseSensitive: false));
  if (a >= 0 && b > a) body = html.substring(a, b);
  var text = htmlToText(body);
  // নিচের "আরও চলমান নিয়োগ / FAQ" অংশ বাদ — ভুল মিল এড়াতে
  final cut = text.indexOf(RegExp(r'^##\s*(সরকারি চাকরি: আরও|সাধারণ জিজ্ঞাসা|⏳|🆕|📂)', multiLine: true));
  if (cut > 0) text = text.substring(0, cut);
  return FetchedDetail(titleOf(html), text);
}
