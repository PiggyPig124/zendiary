import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../services/isolated_shared_preferences_store.dart';

class DBService {
  // v2 content boxes intentionally start empty. Legacy boxes are not opened
  // or deleted, so a future import tool can still recover them.
  static const String diaryBoxName = 'diary_box_v2';
  static const String todoBoxName = 'todo_box_v2';
  static const String settingsBoxName = 'settings_box';
  static const String noteBoxName = 'note_box_v2';
  static const String reminderRuleBoxName = 'reminder_rule_box_v2';
  static const String dataDirectoryPreferenceKey = 'zendiary_data_directory';

  static String? _dataDirectoryPath;
  static Directory? _dataDirectoryOverride;
  static SharedPreferencesStorePlatform? _storeBeforeOverride;

  static String? get dataDirectoryPath => _dataDirectoryPath;

  /// Sets the data directory selected by a process-level launch option.
  ///
  /// This must be called before [init]. It deliberately takes precedence over
  /// the persisted setting so a trial process can never open the user's
  /// existing Hive boxes by accident.
  static void configureDataDirectoryOverride(String path) {
    final trimmedPath = path.trim();
    if (trimmedPath.isEmpty) {
      throw const FormatException('数据目录不能为空');
    }
    _dataDirectoryOverride = Directory(trimmedPath).absolute;
    _storeBeforeOverride ??= SharedPreferencesStorePlatform.instance;
    SharedPreferencesStorePlatform.instance = IsolatedSharedPreferencesStore(
      _dataDirectoryOverride!.path,
    );
  }

  @visibleForTesting
  static void debugClearDataDirectoryOverride() {
    _dataDirectoryOverride = null;
    _dataDirectoryPath = null;
    final originalStore = _storeBeforeOverride;
    if (originalStore != null) {
      SharedPreferencesStorePlatform.instance = originalStore;
      _storeBeforeOverride = null;
    }
  }

  static Future<void> init() async {
    final dataDirectory = await resolveDataDirectory();
    await dataDirectory.create(recursive: true);
    _dataDirectoryPath = dataDirectory.path;
    Hive.init(dataDirectory.path);

    await Hive.openBox(settingsBoxName);
    await Hive.openBox(diaryBoxName);
    await Hive.openBox(todoBoxName);
    await Hive.openBox(noteBoxName);
    await Hive.openBox(reminderRuleBoxName);
  }

  static Future<Directory> resolveDataDirectory() async {
    final override = _dataDirectoryOverride;
    if (override != null) return override;
    final prefs = await SharedPreferences.getInstance();
    final configuredPath = prefs.getString(dataDirectoryPreferenceKey)?.trim();
    if (configuredPath != null && configuredPath.isNotEmpty) {
      return Directory(configuredPath);
    }
    return getApplicationDocumentsDirectory();
  }

  static Future<void> saveDataDirectoryPath(String path) async {
    final trimmedPath = path.trim();
    if (trimmedPath.isEmpty) {
      throw const FormatException('数据目录不能为空');
    }
    final directory = Directory(trimmedPath);
    await directory.create(recursive: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(dataDirectoryPreferenceKey, directory.path);
  }

  static Future<void> resetDataDirectoryPath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(dataDirectoryPreferenceKey);
  }
}
