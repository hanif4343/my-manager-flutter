import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../reminder/models/reminder.dart' show bn;
import '../../widgets/app_theme.dart';
import '../services/app_launcher.dart';
import 'engine/bdgovtjob_source.dart' show httpGet;
import 'engine/teletalk_source.dart' show resolveAdvertisementUrl;

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

  Future<String?> _findPdfUrl() async {
    if ((widget.directUrl ?? '').isNotEmpty) return widget.directUrl;
    if (widget.adFile.isNotEmpty) {
      final u = await resolveAdvertisementUrl(widget.adFile);
      if (u != null) return u;
    }
    final page = widget.pageUrl;
    if (page != null && page.isNotEmpty && !page.contains('#teletalk')) {
      try {
        final html = await httpGet(page);
        final m = RegExp(r'''https?://[^\s"'<>\\]+?\.pdf''', caseSensitive: false).firstMatch(html);
        if (m != null) return m.group(0);
      } catch (_) {}
    }
    return null;
  }

  String _cacheName(String url) {
    var h = 5381;
    for (final c in url.codeUnits) {
      h = ((h * 33) ^ c) & 0x7fffffff;
    }
    return 'radar_$h.pdf';
  }

  Future<void> _load() async {
    setState(() { _error = null; _path = null; _progress = null; _step = 'বিজ্ঞপ্তি খোঁজা হচ্ছে…'; });
    try {
      final url = await _findPdfUrl();
      if (url == null) {
        throw 'এই সার্কুলারের PDF-এর সরাসরি লিংক পাওয়া যায়নি';
      }
      _url = url;
      final dir = Directory('${(await getTemporaryDirectory()).path}/radar_pdf');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/${_cacheName(url)}');

      // আগে নামানো থাকলে সাথে সাথে খুলি
      if (await file.exists() && await file.length() > 1024) {
        if (mounted) setState(() => _path = file.path);
        return;
      }

      _setStep('PDF নামানো হচ্ছে…', p: 0);
      final client = http.Client();
      try {
        final req = http.Request('GET', Uri.parse(url))
          ..headers['user-agent'] = 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36';
        final res = await client.send(req).timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) throw 'সার্ভার সাড়া দিয়েছে (HTTP ${res.statusCode})';
        final total = res.contentLength ?? 0;
        final bytes = <int>[];
        await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
          bytes.addAll(chunk);
          if (total > 0) _setStep('PDF নামানো হচ্ছে…', p: bytes.length / total);
        }
        if (bytes.length < 100 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
          throw 'ফাইলটা PDF নয় (সাইট অন্য কিছু পাঠিয়েছে)';
        }
        await file.writeAsBytes(bytes, flush: true);
      } finally {
        client.close();
      }
      if (mounted) setState(() => _path = file.path);
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
          ]),
        ),
      );
    }
    if (_path == null) {
      return Center(
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
