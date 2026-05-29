import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/idea_file.dart';
import '../widgets/app_theme.dart';

class PdfViewerScreen extends StatefulWidget {
  final IdeaFile file;
  const PdfViewerScreen({super.key, required this.file});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  String? _pdfPath;
  int _totalPages = 0;
  int _currentPage = 0;
  bool _loading = true;
  String? _error;
  PDFViewController? _controller;

  @override
  void initState() {
    super.initState();
    _preparePdf();
  }

  Future<void> _preparePdf() async {
    try {
      if (widget.file.content == null) {
        setState(() { _error = 'ফাইলে কোনো content নেই'; _loading = false; });
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${widget.file.name}';
      final f = File(path);
      final bytes = base64Decode(widget.file.content!);
      await f.writeAsBytes(bytes);
      setState(() { _pdfPath = path; _loading = false; });
    } catch (e) {
      setState(() { _error = 'PDF লোড করা যায়নি: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg2,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.file.name,
              style: const TextStyle(color: AppTheme.textPrimary,
                  fontSize: 14, fontWeight: FontWeight.w700,
                  fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis),
          if (_totalPages > 0)
            Text('পৃষ্ঠা ${_currentPage + 1} / $_totalPages',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ]),
        actions: [
          if (_controller != null && _totalPages > 1) ...[
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up, color: AppTheme.textSecondary),
              onPressed: _currentPage > 0
                  ? () => _controller!.setPage(_currentPage - 1)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.textSecondary),
              onPressed: _currentPage < _totalPages - 1
                  ? () => _controller!.setPage(_currentPage + 1)
                  : null,
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppTheme.accent),
                SizedBox(height: 16),
                Text('PDF লোড হচ্ছে...', style: TextStyle(color: AppTheme.textSecondary)),
              ],
            ))
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.picture_as_pdf_outlined,
                        color: AppTheme.red, size: 56),
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(
                        color: AppTheme.textSecondary), textAlign: TextAlign.center),
                  ]),
                ))
              : PDFView(
                  filePath: _pdfPath!,
                  enableSwipe: true,
                  swipeHorizontal: false,
                  autoSpacing: true,
                  pageFling: true,
                  pageSnap: true,
                  fitPolicy: FitPolicy.BOTH,
                  backgroundColor: AppTheme.bg,
                  onRender: (pages) => setState(() => _totalPages = pages ?? 0),
                  onPageChanged: (page, _) => setState(() => _currentPage = page ?? 0),
                  onViewCreated: (ctrl) => setState(() => _controller = ctrl),
                  onError: (e) => setState(() => _error = e.toString()),
                ),
    );
  }
}
