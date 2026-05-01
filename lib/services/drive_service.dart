import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../db/db_helper.dart';

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();
  GoogleAuthClient(this._headers);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}

class DriveService {
  static const _folderName = 'MyManager_Backup';
  static DriveService? _instance;
  static DriveService get instance => _instance ??= DriveService._();
  DriveService._();

  final _googleSignIn = GoogleSignIn(scopes: [drive.DriveApi.driveFileScope]);
  drive.DriveApi? _driveApi;
  GoogleSignInAccount? _account;
  String? _backupFolderId;

  bool get isSignedIn => _account != null && _driveApi != null;
  String? get userEmail => _account?.email;

  // ── SIGN IN ────────────────────────────────────────────
  Future<bool> signIn() async {
    try {
      _account = await _googleSignIn.signIn();
      if (_account == null) return false;
      await _initApi();
      return true;
    } catch (e) {
      debugPrint('DriveService signIn error: $e');
      return false;
    }
  }

  Future<bool> signInSilently() async {
    try {
      _account = await _googleSignIn.signInSilently();
      if (_account == null) return false;
      await _initApi();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _account = null;
    _driveApi = null;
    _backupFolderId = null;
  }

  Future<void> _initApi() async {
    if (_account == null) return;
    final auth = await _account!.authentication;
    final headers = {'Authorization': 'Bearer ${auth.accessToken}'};
    _driveApi = drive.DriveApi(GoogleAuthClient(headers));
    _backupFolderId = await _ensureFolder();
  }

  // ── FOLDER ────────────────────────────────────────────
  Future<String?> _ensureFolder() async {
    if (_driveApi == null) return null;
    try {
      final q = "mimeType='application/vnd.google-apps.folder' and name='$_folderName' and trashed=false";
      final list = await _driveApi!.files.list(q: q, $fields: 'files(id,name)');
      if (list.files != null && list.files!.isNotEmpty) {
        return list.files!.first.id;
      }
      final folder = drive.File()
        ..name = _folderName
        ..mimeType = 'application/vnd.google-apps.folder';
      final created = await _driveApi!.files.create(folder, $fields: 'id');
      return created.id;
    } catch (e) {
      debugPrint('DriveService _ensureFolder error: $e');
      return null;
    }
  }

  // ── BACKUP DB ─────────────────────────────────────────
  Future<DriveBackupResult> backupDatabase() async {
    if (!isSignedIn) return DriveBackupResult.notSignedIn;
    try {
      // Refresh auth
      await _initApi();
      _backupFolderId ??= await _ensureFolder();
      if (_backupFolderId == null) return DriveBackupResult.failed;

      final dbPath = p.join(await getDatabasesPath(), 'mymanager.db');
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) return DriveBackupResult.failed;

      // Export all data as JSON
      final jsonData = await _exportAllDataAsJson();
      final jsonBytes = utf8.encode(jsonData);
      final jsonFile = drive.File()
        ..name = 'mymanager_backup.json'
        ..parents = [_backupFolderId!];

      // Check if exists
      final q = "name='mymanager_backup.json' and '${_backupFolderId!}' in parents and trashed=false";
      final existing = await _driveApi!.files.list(q: q, $fields: 'files(id)');

      if (existing.files != null && existing.files!.isNotEmpty) {
        // Update
        await _driveApi!.files.update(
          drive.File(),
          existing.files!.first.id!,
          uploadMedia: drive.Media(Stream.value(jsonBytes), jsonBytes.length),
          $fields: 'id',
        );
      } else {
        // Create
        await _driveApi!.files.create(
          jsonFile,
          uploadMedia: drive.Media(Stream.value(jsonBytes), jsonBytes.length),
          $fields: 'id',
        );
      }
      return DriveBackupResult.success;
    } catch (e) {
      debugPrint('DriveService backup error: $e');
      return DriveBackupResult.failed;
    }
  }

  // ── RESTORE ───────────────────────────────────────────
  Future<DriveBackupResult> restoreFromDrive() async {
    if (!isSignedIn) return DriveBackupResult.notSignedIn;
    try {
      await _initApi();
      _backupFolderId ??= await _ensureFolder();
      if (_backupFolderId == null) return DriveBackupResult.failed;

      final q = "name='mymanager_backup.json' and '${_backupFolderId!}' in parents and trashed=false";
      final list = await _driveApi!.files.list(q: q, $fields: 'files(id,name,modifiedTime)');

      if (list.files == null || list.files!.isEmpty) return DriveBackupResult.noBackup;

      final fileId = list.files!.first.id!;
      final media = await _driveApi!.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;

      final bytes = <int>[];
      await for (final chunk in media.stream) { bytes.addAll(chunk); }
      final jsonData = utf8.decode(bytes);

      await _importFromJson(jsonData);
      return DriveBackupResult.success;
    } catch (e) {
      debugPrint('DriveService restore error: $e');
      return DriveBackupResult.failed;
    }
  }

  // ── EXPORT JSON ───────────────────────────────────────
  Future<String> _exportAllDataAsJson() async {
    final d = await DBHelper.db;
    final projects = await d.query('projects');
    final ideas = await d.query('ideas');
    final files = await d.query('idea_files');
    final versions = await d.query('project_versions');

    return jsonEncode({
      'version': 3,
      'exported_at': DateTime.now().toIso8601String(),
      'projects': projects,
      'ideas': ideas,
      'idea_files': files,
      'project_versions': versions,
    });
  }

  Future<void> _importFromJson(String jsonData) async {
    final data = jsonDecode(jsonData) as Map<String, dynamic>;
    final d = await DBHelper.db;

    await d.transaction((txn) async {
      await txn.delete('idea_files');
      await txn.delete('project_versions');
      await txn.delete('ideas');
      await txn.delete('projects');

      for (final row in (data['projects'] as List)) {
        await txn.insert('projects', Map<String, dynamic>.from(row));
      }
      for (final row in (data['ideas'] as List)) {
        await txn.insert('ideas', Map<String, dynamic>.from(row));
      }
      for (final row in (data['idea_files'] as List)) {
        await txn.insert('idea_files', Map<String, dynamic>.from(row));
      }
      if (data['project_versions'] != null) {
        for (final row in (data['project_versions'] as List)) {
          await txn.insert('project_versions', Map<String, dynamic>.from(row));
        }
      }
    });
  }

  // ── LAST BACKUP TIME ──────────────────────────────────
  Future<DateTime?> getLastBackupTime() async {
    if (!isSignedIn || _backupFolderId == null) return null;
    try {
      await _initApi();
      final q = "name='mymanager_backup.json' and '${_backupFolderId!}' in parents and trashed=false";
      final list = await _driveApi!.files.list(q: q, $fields: 'files(modifiedTime)');
      if (list.files != null && list.files!.isNotEmpty) {
        return list.files!.first.modifiedTime;
      }
    } catch (e) { /**/ }
    return null;
  }
}

enum DriveBackupResult { success, failed, notSignedIn, noBackup }
