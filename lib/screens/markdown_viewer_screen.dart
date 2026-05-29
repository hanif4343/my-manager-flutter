import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/idea_file.dart';
import '../widgets/app_theme.dart';

class MarkdownViewerScreen extends StatefulWidget {
  final IdeaFile file;
  const MarkdownViewerScreen({super.key, required this.file});

  @override
  State<MarkdownViewerScreen> createState() => _MarkdownViewerScreenState();
}

class _MarkdownViewerScreenState extends State<MarkdownViewerScreen> {
  bool _rawMode = false;

  @override
  Widget build(BuildContext context) {
    final content = widget.file.content ?? '';

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg2,
        title: Row(children: [
          const Icon(Icons.description_outlined, color: AppTheme.accent, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.file.name,
              style: const TextStyle(color: AppTheme.textPrimary,
                  fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          // Toggle raw / rendered
          GestureDetector(
            onTap: () => setState(() => _rawMode = !_rawMode),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _rawMode ? AppTheme.bg3 : AppTheme.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _rawMode ? AppTheme.border : AppTheme.accent),
              ),
              child: Text(
                _rawMode ? '< Raw' : '✨ Rendered',
                style: TextStyle(
                    color: _rawMode ? AppTheme.textSecondary : AppTheme.accent,
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: _rawMode
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                content,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 13,
                    fontFamily: 'monospace', height: 1.6),
              ),
            )
          : Markdown(
              data: content,
              selectable: true,
              padding: const EdgeInsets.all(16),
              styleSheet: MarkdownStyleSheet(
                h1: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 24,
                    fontWeight: FontWeight.w800, height: 1.4),
                h2: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 20,
                    fontWeight: FontWeight.w700, height: 1.4),
                h3: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 17,
                    fontWeight: FontWeight.w600, height: 1.4),
                h4: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 15,
                    fontWeight: FontWeight.w600),
                p: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 14, height: 1.6),
                strong: const TextStyle(
                    color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
                em: const TextStyle(
                    color: AppTheme.textPrimary, fontStyle: FontStyle.italic),
                code: const TextStyle(
                    color: AppTheme.accent, fontSize: 13,
                    fontFamily: 'monospace', backgroundColor: Color(0xFF1E293B)),
                codeblockDecoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border)),
                blockquoteDecoration: BoxDecoration(
                    color: AppTheme.bg3,
                    borderRadius: BorderRadius.circular(4),
                    border: const Border(
                        left: BorderSide(color: AppTheme.accent, width: 3))),
                blockquote: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 14,
                    fontStyle: FontStyle.italic),
                listBullet: const TextStyle(color: AppTheme.accent, fontSize: 14),
                tableHead: const TextStyle(
                    color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
                tableBody: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                tableBorder: TableBorder.all(color: AppTheme.border, width: 1),
                horizontalRuleDecoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppTheme.border))),
                a: const TextStyle(color: AppTheme.accent,
                    decoration: TextDecoration.underline),
              ),
            ),
    );
  }
}
