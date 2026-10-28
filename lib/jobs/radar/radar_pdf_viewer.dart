import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../reminder/models/reminder.dart' show bn;
import '../../widgets/app_theme.dart';
import '../../services/settings_service.dart';
import '../services/app_launcher.dart';
import 'engine/bdgovtjob_source.dart' show httpGet;
import 'engine/teletalk_source.dart' show fetchTeletalkDetailRaw, teletalkAdvertisementCandidates, teletalkJobIdFromUrl;

/// এক ট্যাপে সার্কুলারের বিজ্ঞপ্তি PDF অ্যাপের ভেতরেই খোলে — ব্রাউজারে লম্বা পেজ স্ক্রল করে
/// "Open" খোঁজা আর আলাদা ডাউনলোডের ঝামেলা নেই। একবার নামানো PDF ফোনে জমা থাকে, পরেরবার সাথে সাথে খোলে।
///
/// PDF-এর ঠিকানা এই ক্রমে খোঁজা হয়:
///  ১. [directUrl] (জানা থাকলে)
///  ২. [adFile] — Teletalk-এর বিজ্ঞপ্তি-ফাইলের পাথ
///  ৩. [pageUrl] পেজের HTML-এ থাকা প্রথম .pdf লিংক (bdgovtjob-এর মতো সাইটের জন্য)
/// কিছুই না পেলে পরিষ্কার বার্তা + "পেজ খোলো" বাটন।
Future<void> openRadarPdf(
  BuildContext context, {
  required String title,
  String? directUrl,
  String adFile = '',
  String? pageUrl,
}) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => RadarPdfScreen(title: title, directUrl: directUrl, adFile: adFile, pageUrl: pageUrl),
    ),
  );
}

class RadarPdfScreen extends StatefulWidget {
  final String title;
  final String? directUrl;
  final String adFile;
  final String? pageUrl;
  const RadarPdfScreen({super.key, required this.title, this.directUrl, this.adFile = '', this.pageUrl});

  @override
  State<RadarPdfScreen> createState() => _RadarPdfScreenState();
}

class _RadarPdfScreenState extends State<RadarPdfScreen> {
  String? _path;
  String? _url;
  String? _error;
  String _step = 'বিজ্ঞপ্তি খোঁজা হচ্ছে…';
  double? _progress; // 0..1, মোট সাইজ জানা না থাকলে null
  int _pages = 0;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _setStep(String s, {double? p}) {
    if (mounted) setState(() { _step = s; _progress = p; });
  }

  final List<String> _dbg = []; // কোন ঠিকানায় কী হলো — ব্যর্থ হলে পর্দায় দেখাই (সমস্যা ধরতে)
  static const _kBase = 'radar_pdf_base'; // সাইট থেকে শেখা ফাইল-ঠিকানার সাধারণ অংশ (সব সার্কুলারে কাজে লাগে)
  WebViewController? _wv; // লুকানো পেজ-লোডার (ব্যবহারকারীর চোখে পড়ে না)
  Timer? _wvTimer;
  String _expectedName = ''; // advertisement-….pdf

  @override
  void dispose() {
    _wvTimer?.cancel();
    super.dispose();
  }

  /// সম্ভাব্য PDF ঠিকানার তালিকা। Teletalk হলে আগে বিস্তারিত API থেকে ফাইলের পাথ আনে (পুরনো ক্যাশে
  /// পাথ না থাকলেও চলে), তারপর একাধিক সম্ভাব্য ঠিকানা বানায়। অন্য সাইটের পেজে থাকা .pdf লিংকও যোগ হয়।
  Future<List<String>> _candidates() async {
    final out = <String>[];
    void add(String u) {
      if (u.isNotEmpty && !out.contains(u)) out.add(u);
    }

    if ((widget.directUrl ?? '').isNotEmpty) add(widget.directUrl!);
    final page = widget.pageUrl ?? '';
    var ad = widget.adFile;
    final jobId = teletalkJobIdFromUrl(page);
    if (jobId != null) {
      try {
        final raw = await fetchTeletalkDetailRaw(jobId);
        final details = Map<String, dynamic>.from((raw['details'] as Map?) ?? {});
        if (ad.isEmpty) ad = (details['advertisement_file'] ?? '').toString().trim();
        // API-র যেকোনো ফিল্ডে সম্পূর্ণ PDF লিংক থাকলে সেটাই সবচেয়ে ভালো
        void walk(Object? v) {
          if (v is Map) {
            v.values.forEach(walk);
          } else if (v is List) {
            v.forEach(walk);
          } else if (v is String && v.startsWith('http') && v.toLowerCase().contains('.pdf')) {
            add(v);
          }
        }
        walk(raw);
        _dbg.add('API ফিল্ড: ${raw.keys.join(', ')} | details: ${details.keys.join(', ')}');
      } catch (e) {
        _dbg.add('বিস্তারিত API ব্যর্থ: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
    if (ad.isNotEmpty) {
      _expectedName = ad.split('/').last;
      _dbg.add('ফাইলের পাথ: $ad');
      // আগে সাইট থেকে শেখা ঠিকানার ছাঁচ থাকলে সেটাই প্রথমে
      final base = SettingsService.getString(_kBase);
      if (base.isNotEmpty) add('$base$_expectedName');
    }
    for (final u in teletalkAdvertisementCandidates(ad)) {
      add(u);
    }
    if (page.isNotEmpty && teletalkJobIdFromUrl(page) == null && !page.contains('#teletalk')) {
      try {
        final html = await httpGet(page);
        final re = RegExp(r'''https?://[^\s"'<>\\]+?\.pdf''', caseSensitive: false);
        for (final m in re.allMatches(html).take(3)) {
          add(m.group(0)!);
        }
        if (re.allMatches(html).isEmpty) _dbg.add('পেজে কোনো .pdf লিংক নেই');
      } catch (e) {
        _dbg.add('পেজ পড়া যায়নি: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
    return out;
  }

  String _cacheName(String url) {
    var h = 5381;
    for (final c in url.codeUnits) {
      h = ((h * 33) ^ c) & 0x7fffffff;
    }
    return 'radar_$h.pdf';
  }

  /// একটা ঠিকানা থেকে নামায়; আসল PDF (%PDF- দিয়ে শুরু) হলে ফাইলে লিখে পথ ফেরত দেয়, নইলে null।
  Future<String?> _download(String url, File file) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..headers['user-agent'] = 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36'
        ..headers['accept'] = 'application/pdf,*/*;q=0.8';
      if (url.contains('teletalk.com.bd')) req.headers['referer'] = 'https://alljobs.teletalk.com.bd/';
      final res = await client.send(req).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) {
        _dbg.add('HTTP ${res.statusCode} ← $url');
        return null;
      }
      final total = res.contentLength ?? 0;
      final bytes = <int>[];
      await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
        bytes.addAll(chunk);
        if (total > 0) _setStep('PDF নামানো হচ্ছে…', p: bytes.length / total);
        if (bytes.length >= 5 && String.fromCharCodes(bytes.take(5)) != '%PDF-') {
          _dbg.add('PDF নয় (অন্য কিছু ফেরত) ← $url');
          return null; // বড় HTML পেজ পুরোটা নামানোর দরকার নেই
        }
      }
      if (bytes.length < 100 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
        _dbg.add('PDF নয় ← $url');
        return null;
      }
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      _dbg.add('ত্রুটি (${e.toString().split('\n').first}) ← $url');
      return null;
    } finally {
      client.close();
    }
  }

  static const _extractJs = r"""(function(){
  try{window.scrollTo(0,document.body.scrollHeight);}catch(e){}
  var r=[];
  try{var q=document.querySelectorAll('iframe,embed,object,a,source,link');
    for(var i=0;i<q.length;i++){var e=q[i];var u=e.src||e.data||e.href||'';if(u)r.push(String(u));}}catch(e){}
  try{performance.getEntriesByType('resource').forEach(function(x){r.push(x.name);});}catch(e){}
  return JSON.stringify(r);
})()""";

  /// Teletalk-এর পেজ লুকানো WebView-তে খুলে (স্ক্রল করে) PDF-এর আসল ঠিকানা বের করে — পেজের iframe/লিংক
  /// অথবা পেজ যে নেটওয়ার্ক রিকোয়েস্ট করেছে সেখান থেকে। পাওয়া না গেলে null।
  Future<String?> _discoverViaWebView(String pageUrl) async {
    final done = Completer<String?>();
    final seen = <String>{};
    bool isPdf(String u) => u.startsWith('http') && RegExp(r'\.pdf(\?|#|$)', caseSensitive: false).hasMatch(u);
    String unwrap(String u) {
      // docs.google.com/viewer?url=<pdf> ধরনের মোড়ক খুলি
      try {
        final q = Uri.parse(u).queryParameters;
        for (final k in ['url', 'file', 'src']) {
          final v = q[k];
          if (v != null && isPdf(v)) return v;
        }
      } catch (_) {}
      return u;
    }

    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          if (isPdf(r.url)) {
            if (!done.isCompleted) done.complete(unwrap(r.url));
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ));
    if (mounted) setState(() => _wv = c);
    try {
      await c.loadRequest(Uri.parse(pageUrl));
    } catch (e) {
      _dbg.add('পেজ লোড হয়নি: $e');
    }

    var tries = 0;
    _wvTimer?.cancel();
    _wvTimer = Timer.periodic(const Duration(milliseconds: 900), (t) async {
      if (done.isCompleted) {
        t.cancel();
        return;
      }
      if (++tries > 28) {
        t.cancel();
        if (!done.isCompleted) done.complete(null);
        return;
      }
      try {
        final r = await c.runJavaScriptReturningResult(_extractJs);
        var s = r.toString();
        if (s.startsWith('"')) {
          try {
            s = jsonDecode(s) as String;
          } catch (_) {}
        }
        final list = (jsonDecode(s) as List).map((e) => unwrap(e.toString())).toList();
        seen.addAll(list.where((u) => u.toLowerCase().contains('advertis') || isPdf(u)));
        final pdfs = list.where(isPdf).toList();
        if (pdfs.isNotEmpty) {
          // প্রত্যাশিত ফাইলের নামে মিললে সেটা, নইলে প্রথমটা
          final best = pdfs.firstWhere((u) => _expectedName.isNotEmpty && u.contains(_expectedName), orElse: () => pdfs.first);
          if (!done.isCompleted) done.complete(best);
          t.cancel();
        }
      } catch (_) {}
    });

    final res = await done.future.timeout(const Duration(seconds: 30), onTimeout: () => null);
    _wvTimer?.cancel();
    if (res == null) {
      _dbg.add(seen.isEmpty
          ? 'সাইটের পেজে PDF-সংক্রান্ত কোনো লিংক/রিকোয়েস্ট পাওয়া যায়নি'
          : 'সাইটের পেজে পাওয়া (PDF নয়): ${seen.take(4).join(' | ')}');
    }
    if (mounted) setState(() => _wv = null);
    return res;
  }

  Future<void> _load() async {
    _dbg.clear();
    setState(() { _error = null; _path = null; _progress = null; _step = 'বিজ্ঞপ্তি খোঁজা হচ্ছে…'; });
    try {
      final cands = await _candidates();
      if (cands.isEmpty) {
        throw 'এই সার্কুলারের PDF-এর ঠিকানা পাওয়া যায়নি';
      }
      final dir = Directory('${(await getTemporaryDirectory()).path}/radar_pdf');
      if (!await dir.exists()) await dir.create(recursive: true);

      // আগে নামানো থাকলে সাথে সাথে খুলি
      for (final u in cands) {
        final f = File('${dir.path}/${_cacheName(u)}');
        if (await f.exists() && await f.length() > 1024) {
          _url = u;
          if (mounted) setState(() => _path = f.path);
          return;
        }
      }

      _setStep('PDF নামানো হচ্ছে…', p: 0);
      for (final u in cands) {
        final saved = await _download(u, File('${dir.path}/${_cacheName(u)}'));
        if (saved != null) {
          _url = u;
          if (mounted) setState(() => _path = saved);
          return;
        }
        _setStep('অন্য ঠিকানায় চেষ্টা হচ্ছে…', p: 0);
      }

      // সব আন্দাজি ঠিকানা ব্যর্থ — এবার Teletalk-এর পেজটাই (লুকিয়ে) খুলে দেখি PDF-এর আসল ঠিকানা কী
      final page = widget.pageUrl ?? '';
      final jobId = teletalkJobIdFromUrl(page);
      if (jobId != null) {
        _setStep('সাইট থেকে আসল ঠিকানা জানা হচ্ছে…', p: null);
        final found = await _discoverViaWebView(page.replaceFirst(RegExp(r'#.*$'), ''));
        if (found != null) {
          _dbg.add('সাইট থেকে পাওয়া: $found');
          final saved = await _download(found, File('${dir.path}/${_cacheName(found)}'));
          if (saved != null) {
            // ঠিকানার সাধারণ অংশ মনে রাখি — পরের সব সার্কুলারে সরাসরি কাজে লাগবে
            final name = found.split('?').first.split('/').last;
            final cut = found.indexOf(name);
            if (cut > 0 && name.toLowerCase().endsWith('.pdf')) {
              await SettingsService.setString(_kBase, found.substring(0, cut));
            }
            _url = found;
            if (mounted) setState(() => _path = saved);
            return;
          }
        }
      }
      throw 'PDF নামানো যায়নি — সাইট থেকে ফাইল পাওয়া গেল না';
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _openInBrowser() async {
    final u = _url ?? widget.pageUrl;
    if (u == null || u.isEmpty) return;
    await AppLauncher.openUrl(u.replaceFirst('#teletalk', ''));
  }

  Future<void> _share() async {
    final p = _path;
    if (p == null) return;
    await Share.shareXFiles([XFile(p, mimeType: 'application/pdf')], text: widget.title);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg2,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w700)),
          if (_pages > 0)
            Text('পৃষ্ঠা ${bn(_page + 1)} / ${bn(_pages)}',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
        ]),
        actions: [
          IconButton(
            tooltip: 'শেয়ার / সেভ',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _path == null ? null : _share,
          ),
          IconButton(
            tooltip: 'ব্রাউজারে খোলো',
            icon: const Icon(Icons.open_in_browser_rounded),
            onPressed: _openInBrowser,
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.picture_as_pdf_outlined, size: 54, color: AppTheme.textMuted),
            const SizedBox(height: 14),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.45)),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('আবার চেষ্টা করো'),
            ),
            TextButton(onPressed: _openInBrowser, child: const Text('🔗 পেজটা ব্রাউজারে খোলো')),
            if (_dbg.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.bg2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: SelectableText(
                  'কী কী চেষ্টা হলো:\n${_dbg.join('\n')}',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5, height: 1.4),
                ),
              ),
            ],
          ]),
        ),
      );
    }
    if (_path == null) {
      final loading = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 54,
              height: 54,
              child: CircularProgressIndicator(value: _progress, color: AppTheme.accent, strokeWidth: 4),
            ),
            const SizedBox(height: 16),
            Text(
              _progress == null ? _step : '$_step ${bn((_progress! * 100).round())}%',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ]),
        ),
      );
      if (_wv == null) return loading;
      // লুকানো পেজ-লোডার: পুরো আকারে চলে (যাতে সাইট স্বাভাবিক লোড হয়), ওপরে লোডিং পর্দা ঢেকে রাখে
      return Stack(children: [
        Positioned.fill(child: WebViewWidget(controller: _wv!)),
        Positioned.fill(child: ColoredBox(color: AppTheme.bg, child: loading)),
      ]);
    }
    return PDFView(
      filePath: _path!,
      enableSwipe: true,
      swipeHorizontal: false,
      autoSpacing: true,
      pageFling: false,
      onRender: (n) {
        if (mounted) setState(() => _pages = n ?? 0);
      },
      onPageChanged: (p, n) {
        if (mounted) setState(() { _page = p ?? 0; _pages = n ?? _pages; });
      },
      onError: (e) {
        if (mounted) setState(() => _error = 'PDF দেখানো যায়নি: $e');
      },
    );
  }
}
