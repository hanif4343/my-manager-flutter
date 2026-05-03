import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../db/db_helper.dart';
import '../models/project.dart';
import '../models/idea.dart';
import '../models/idea_file.dart';

class ExportService {

  // ── EXPORT PROJECT as folder structure ZIP ─────────────
  // Structure:
  // ProjectName_v1/
  //   _project_meta.json
  //   IdeaTitle_1/
  //     _idea_meta.json
  //     filename.js
  //     icon.png
  //   IdeaTitle_2/
  //     ...
  static Future<String?> exportProject(Project project) async {
    try {
      final ideas = await DBHelper.getIdeas(project.id!);
      final archive = Archive();

      // Project meta
      final projectMeta = jsonEncode({
        'id': project.id,
        'name': project.name,
        'description': project.description,
        'tags': project.tags,
        'color': project.colorValue,
        'version': project.version,
        'exported_at': DateTime.now().toIso8601String(),
        'idea_count': ideas.length,
      });
      final metaBytes = utf8.encode(projectMeta);
      archive.addFile(ArchiveFile(
          '_project_meta.json', metaBytes.length, metaBytes));

      // Each idea as subfolder
      for (int i = 0; i < ideas.length; i++) {
        final idea = ideas[i];
        final safeTitle = _safeName(idea.title);
        final folder = '${i + 1}_$safeTitle';

        // Idea meta
        final ideaMeta = jsonEncode({
          'id': idea.id,
          'title': idea.title,
          'description': idea.description,
          'status': idea.status,
          'priority': idea.priority,
          'created_at': idea.createdAt,
        });
        final ideaMetaBytes = utf8.encode(ideaMeta);
        archive.addFile(ArchiveFile(
            '$folder/_idea_meta.json', ideaMetaBytes.length, ideaMetaBytes));

        // Files
        final files = await DBHelper.getFiles(idea.id!);
        for (final f in files) {
          if (f.content == null) continue;
          List<int> fileBytes;
          if (f.isText) {
            fileBytes = utf8.encode(f.content!);
          } else {
            try { fileBytes = base64Decode(f.content!); }
            catch (_) { fileBytes = utf8.encode(f.content!); }
          }
          archive.addFile(ArchiveFile(
              '$folder/${f.name}', fileBytes.length, fileBytes));
        }
      }

      // Write ZIP
      final dir = await getTemporaryDirectory();
      final safeProjectName = _safeName(project.name);
      final zipName = '${safeProjectName}_v${project.version}.zip';
      final zipFile = File('${dir.path}/$zipName');
      final encoder = ZipEncoder();
      final encoded = encoder.encode(archive);
      if (encoded == null) return null;
      await zipFile.writeAsBytes(encoded);

      await Share.shareXFiles(
        [XFile(zipFile.path)],
        text: '📦 ${project.name} — My Manager Export',
      );
      return zipFile.path;
    } catch (e) {
      return null;
    }
  }

  // ── IMPORT PROJECT from folder structure ZIP ───────────
  static Future<ImportResult> importProject(String zipPath) async {
    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Find project meta
      final metaFile = archive.files
          .where((f) => f.name == '_project_meta.json' && f.isFile)
          .firstOrNull;
      if (metaFile == null) return ImportResult.noMeta;

      final metaJson = jsonDecode(utf8.decode(metaFile.content as List<int>));
      final n = DateTime.now().millisecondsSinceEpoch;

      // Create project
      final projectId = await DBHelper.insertProject(Project(
        name: '${metaJson['name']} (Imported)',
        description: metaJson['description'],
        colorValue: metaJson['color'] ?? 0xFF6366F1,
        tags: (metaJson['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
        version: metaJson['version'] ?? 1,
        createdAt: n, updatedAt: n,
      ));

      // Find idea folders
      final ideaFolders = <String>{};
      for (final f in archive.files) {
        final parts = f.name.split('/');
        if (parts.length >= 2 && parts[0] != '_project_meta.json') {
          ideaFolders.add(parts[0]);
        }
      }

      int ideaCount = 0;
      int fileCount = 0;

      for (final folder in ideaFolders.toList()..sort()) {
        // Read idea meta
        final ideaMetaFile = archive.files
            .where((f) => f.name == '$folder/_idea_meta.json' && f.isFile)
            .firstOrNull;

        String ideaTitle = folder.replaceFirst(RegExp(r'^\d+_'), '');
        String? ideaDesc;
        String ideaStatus = 'todo';
        String ideaPriority = 'medium';

        if (ideaMetaFile != null) {
          try {
            final m = jsonDecode(utf8.decode(ideaMetaFile.content as List<int>));
            ideaTitle = m['title'] ?? ideaTitle;
            ideaDesc = m['description'];
            ideaStatus = m['status'] ?? 'todo';
            ideaPriority = m['priority'] ?? 'medium';
          } catch (_) {}
        }

        final ideaId = await DBHelper.insertIdea(Idea(
          projectId: projectId,
          title: ideaTitle,
          description: ideaDesc,
          status: ideaStatus,
          priority: ideaPriority,
          createdAt: n, updatedAt: n,
        ));
        ideaCount++;

        // Import files in this folder
        final ideaFiles = archive.files.where((f) =>
            f.name.startsWith('$folder/') &&
            f.isFile &&
            !f.name.endsWith('_idea_meta.json'));

        for (final af in ideaFiles) {
          final fileName = af.name.split('/').last;
          final ext = fileName.contains('.')
              ? fileName.split('.').last.toLowerCase() : '';
          final isText = IdeaFile(
            ideaId: ideaId, projectId: projectId,
            name: fileName, type: 'text',
            createdAt: n, updatedAt: n,
          ).isText;

          String content;
          if (isText) {
            content = utf8.decode(af.content as List<int>,
                allowMalformed: true);
          } else {
            content = base64Encode(af.content as List<int>);
          }

          await DBHelper.insertFile(IdeaFile(
            ideaId: ideaId, projectId: projectId,
            name: fileName,
            type: isText ? 'text' : 'binary',
            content: content,
            createdAt: n, updatedAt: n,
          ));
          fileCount++;
        }
      }

      return ImportResult.success(ideaCount, fileCount);
    } catch (e) {
      return ImportResult.failed(e.toString());
    }
  }

  static String _safeName(String name) =>
      name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
          .replaceAll(RegExp(r'\s+'), '_')
          .substring(0, name.length.clamp(0, 50));
}

class ImportResult {
  final bool success;
  final String? error;
  final int ideaCount;
  final int fileCount;

  const ImportResult._({
    required this.success, this.error,
    this.ideaCount = 0, this.fileCount = 0,
  });

  static const noMeta = ImportResult._(success: false,
      error: 'ZIP-এ _project_meta.json নেই। My Manager-এর ZIP দাও।');

  static ImportResult success(int ideas, int files) =>
      ImportResult._(success: true, ideaCount: ideas, fileCount: files);

  static ImportResult failed(String e) =>
      ImportResult._(success: false, error: e);
}
