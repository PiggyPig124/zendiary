import 'dart:convert';
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../core/database/db_service.dart';
import '../models/ai_settings.dart';
import 'pending_action_service.dart';
import 'pending_confirmation_service.dart';

class LocalBackupPreview {
  final String filePath;
  final String fileName;
  final String? app;
  final DateTime? exportedAt;
  final Map<String, int> boxCounts;

  const LocalBackupPreview({
    required this.filePath,
    required this.fileName,
    required this.app,
    required this.exportedAt,
    required this.boxCounts,
  });

  int get totalItems => boxCounts.values.fold(0, (sum, count) => sum + count);

  bool get isZenDiaryBackup => app == 'ZenDiary';
}

class LocalBackupImportResult {
  final int importedItems;
  final Map<String, int> boxCounts;

  const LocalBackupImportResult({
    required this.importedItems,
    required this.boxCounts,
  });
}

class LocalDataService {
  static const List<String> boxNames = [
    DBService.diaryBoxName,
    DBService.todoBoxName,
    DBService.noteBoxName,
    DBService.settingsBoxName,
    DBService.reminderRuleBoxName,
  ];

  /// Content boxes used by ZenDiary 2.0. Settings and the configured data
  /// directory intentionally stay untouched when a new workspace is started.
  static const List<String> v2ContentBoxNames = [
    DBService.diaryBoxName,
    DBService.todoBoxName,
    DBService.noteBoxName,
    DBService.reminderRuleBoxName,
  ];

  static Future<Directory> documentsDirectory() {
    return DBService.resolveDataDirectory();
  }

  static Future<void> saveDataDirectoryPath(String path) {
    return DBService.saveDataDirectoryPath(path);
  }

  static Future<Directory> defaultDocumentsDirectory() {
    return getApplicationDocumentsDirectory();
  }

  static Map<String, String?> boxPaths() {
    return {for (final name in boxNames) name: Hive.box(name).path};
  }

  static Future<File> exportBackup() async {
    final docs = await documentsDirectory();
    final backupDir = Directory(
      '${docs.path}${Platform.pathSeparator}zendiary_backups',
    );
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final now = DateTime.now();
    final stamp = now
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final file = File(
      '${backupDir.path}${Platform.pathSeparator}zendiary_backup_$stamp.json',
    );

    final payload = <String, dynamic>{
      'app': 'ZenDiary',
      'exportedAt': now.toIso8601String(),
      'boxes': {
        for (final name in boxNames)
          name: _backupBox(name, Hive.box(name).toMap()),
      },
    };

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      encoding: utf8,
    );
    return file;
  }

  static Future<LocalBackupPreview> previewBackupFile(String path) async {
    final file = File(path.trim());
    if (!await file.exists()) {
      throw const FormatException('文件不存在');
    }

    final payload = await _readBackupPayload(file);
    final boxes = _readBoxes(payload);
    return LocalBackupPreview(
      filePath: file.path,
      fileName: file.uri.pathSegments.isEmpty
          ? file.path
          : Uri.decodeComponent(file.uri.pathSegments.last),
      app: payload['app']?.toString(),
      exportedAt: DateTime.tryParse(payload['exportedAt']?.toString() ?? ''),
      boxCounts: {
        for (final name in boxNames) name: _boxValues(boxes, name).length,
      },
    );
  }

  /// 清空所有本地数据（所有 Hive box + 数据目录配置），
  /// 将软件恢复到刚安装的初始状态。
  static Future<void> clearAllData() async {
    for (final name in boxNames) {
      await Hive.box(name).clear();
    }
    await DBService.resetDataDirectoryPath();
  }

  /// Starts a clean v2 workspace without deleting legacy boxes, settings, or
  /// the selected storage directory. This is the safe reset exposed in the
  /// redesigned settings screen.
  static Future<void> clearV2Workspace() async {
    for (final name in v2ContentBoxNames) {
      await Hive.box(name).clear();
    }
    // Confirmation cards are transient workspace state, not user settings.
    // Do not let an old action reappear after the user starts fresh.
    await PendingActionService.clearAll();
    await PendingConfirmationService.clearAll();
    // Low-load mode is also workspace state; carrying it into an empty
    // workspace would make the new Today page look muted with no reason.
    await Hive.box(DBService.settingsBoxName).delete('low_load_status');
  }

  static Future<LocalBackupImportResult> importBackupFile(String path) async {
    final file = File(path.trim());
    if (!await file.exists()) {
      throw const FormatException('文件不存在');
    }

    final payload = await _readBackupPayload(file);
    final app = payload['app']?.toString();
    if (app != 'ZenDiary') {
      throw const FormatException('不是 ZenDiary 备份文件');
    }

    final boxes = _readBoxes(payload);
    final counts = <String, int>{};
    var imported = 0;

    for (final name in boxNames) {
      final values = _boxValues(boxes, name);
      counts[name] = values.length;
      final box = Hive.box(name);
      for (final entry in values.entries) {
        final value =
            name == DBService.settingsBoxName &&
                entry.key == 'ai_settings' &&
                entry.value is Map
            ? mergeImportedAiSettings(
                entry.value as Map,
                existingSettings: _existingAiSettings(box.get(entry.key)),
              )
            : entry.value;
        await box.put(entry.key, value);
        imported += 1;
      }
    }

    return LocalBackupImportResult(importedItems: imported, boxCounts: counts);
  }

  static Future<Map<String, dynamic>> _readBackupPayload(File file) async {
    final raw = await file.readAsString(encoding: utf8);
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const FormatException('备份文件格式不正确');
  }

  static Map<String, dynamic> _readBoxes(Map<String, dynamic> payload) {
    final rawBoxes = payload['boxes'];
    if (rawBoxes is Map<String, dynamic>) return rawBoxes;
    if (rawBoxes is Map) return Map<String, dynamic>.from(rawBoxes);
    throw const FormatException('备份文件缺少 boxes 数据');
  }

  static Map<String, dynamic> _boxValues(
    Map<String, dynamic> boxes,
    String boxName,
  ) {
    final legacyName = switch (boxName) {
      'diary_box_v2' => 'diary_box',
      'todo_box_v2' => 'todo_box',
      'note_box_v2' => 'note_box',
      'reminder_rule_box_v2' => 'reminder_rule_box',
      _ => null,
    };
    // Manual imports may point at a pre-2.0 backup. We only read that alias
    // when the v2 key is absent; startup never opens or migrates legacy boxes.
    final raw =
        boxes[boxName] ?? (legacyName == null ? null : boxes[legacyName]);
    if (raw == null) return const {};
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    throw FormatException('$boxName 数据格式不正确');
  }

  /// Removes secrets from an AI settings record before it is written to a
  /// portable JSON backup. The configured state is useful for diagnostics,
  /// while the key itself must never be copied to another file or device.
  static Map<String, dynamic> sanitizeAiSettingsForBackup(
    Map<dynamic, dynamic> values,
  ) {
    final safe = values.map(
      (key, value) => MapEntry(key.toString(), _jsonSafeValue(value)),
    );
    final apiKey = safe['apiKey']?.toString() ?? '';
    safe.remove('apiKey');
    if (safe.containsKey('baseUrl')) {
      safe['baseUrl'] = _safeBaseUrl(safe['baseUrl']?.toString());
    }
    safe['apiKeyConfigured'] = apiKey.isNotEmpty;
    return safe;
  }

  /// Merges imported AI settings without allowing a backup to change the
  /// active local AI configuration. This matters because an imported endpoint
  /// could otherwise receive the key already stored on this device.
  ///
  /// On a fresh device, imported credentials are discarded and AI stays
  /// disabled until the user configures it locally.
  static Map<String, dynamic> mergeImportedAiSettings(
    Map<dynamic, dynamic> values, {
    AISettings? existingSettings,
  }) {
    final imported = values.map(
      (key, value) => MapEntry(key.toString(), _jsonSafeValue(value)),
    );
    imported.remove('apiKey');
    imported.remove('apiKeyConfigured');
    if (imported.containsKey('baseUrl')) {
      imported['baseUrl'] = _safeBaseUrl(imported['baseUrl']?.toString());
    }
    if (existingSettings != null) {
      return existingSettings.toJson();
    }
    imported.remove('apiKey');
    imported['enabled'] = false;
    return imported;
  }

  static String _safeBaseUrl(String? value) {
    final uri = Uri.tryParse(value?.trim() ?? '');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '';
    // Credentials and query strings are common places for users to put a
    // token. Strip both before a backup or import can carry them forward.
    var sanitized = uri
        .replace(userInfo: '', query: '', fragment: '')
        .toString();
    // Uri.replace keeps an explicitly empty query/fragment marker. Remove
    // those markers as well so the imported value cannot carry URL metadata.
    sanitized = sanitized.replaceFirst(RegExp(r'[?#]+$'), '');
    return sanitized;
  }

  static AISettings? _existingAiSettings(dynamic value) {
    if (value is! Map) return null;
    return AISettings.fromJson(value);
  }

  static Map<String, dynamic> _backupBox(
    String name,
    Map<dynamic, dynamic> values,
  ) {
    if (name == DBService.settingsBoxName) {
      final safe = <String, dynamic>{};
      for (final entry in values.entries) {
        final key = entry.key.toString();
        safe[key] = key == 'ai_settings' && entry.value is Map
            ? sanitizeAiSettingsForBackup(entry.value as Map)
            : _jsonSafeValue(entry.value);
      }
      return safe;
    }
    return _jsonSafeBox(values);
  }

  static Map<String, dynamic> _jsonSafeBox(Map<dynamic, dynamic> values) {
    return values.map(
      (key, value) => MapEntry(key.toString(), _jsonSafeValue(value)),
    );
  }

  static dynamic _jsonSafeValue(dynamic value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) {
      return value.map(
        (key, nestedValue) =>
            MapEntry(key.toString(), _jsonSafeValue(nestedValue)),
      );
    }
    if (value is Iterable) {
      return value.map(_jsonSafeValue).toList();
    }
    return value.toString();
  }
}
