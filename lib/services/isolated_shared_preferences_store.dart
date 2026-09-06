import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// A small disk-backed legacy SharedPreferences store for an explicitly
/// isolated process.
///
/// Windows' stock implementation resolves RoamingAppData through the Known
/// Folder API, so changing the APPDATA environment variable alone cannot
/// isolate a trial. This store is installed only after `--data-dir` is parsed
/// and keeps the normal no-argument platform store untouched.
class IsolatedSharedPreferencesStore extends SharedPreferencesStorePlatform {
  final File file;
  Map<String, Object>? _values;
  Future<void> _writeChain = Future<void>.value();

  IsolatedSharedPreferencesStore(String directory)
    : file = File(
        '${Directory(directory).absolute.path}${Platform.pathSeparator}'
        'shared_preferences.json',
      );

  Future<Map<String, Object>> _load() async {
    final cached = _values;
    if (cached != null) return cached;
    final loaded = <String, Object>{};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final value = entry.value;
            if (value is bool ||
                value is double ||
                value is int ||
                value is String) {
              loaded[entry.key.toString()] = value;
            } else if (value is List && value.every((item) => item is String)) {
              loaded[entry.key.toString()] = List<String>.from(value);
            }
          }
        }
      } on FormatException {
        // A corrupt isolated preferences file should behave like an empty
        // profile; it must never make the normal profile the fallback.
      } on IOException {
        // Treat an unreadable trial file as empty and let the next write
        // report its own result through the platform contract.
      }
    }
    _values = loaded;
    return loaded;
  }

  Future<bool> _persist(Map<String, Object> values) async {
    final snapshot = Map<String, Object>.from(values);
    final previous = _writeChain;
    _writeChain = previous.then<void>(
      (_) => _writeSnapshot(snapshot),
      // A failed write must not poison every later write in this process.
      onError: (_, _) => _writeSnapshot(snapshot),
    );
    try {
      await _writeChain;
      return true;
    } on IOException {
      return false;
    }
  }

  Future<void> _writeSnapshot(Map<String, Object> snapshot) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(snapshot));
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  @override
  Future<bool> remove(String key) async {
    final values = await _load();
    values.remove(key);
    return _persist(values);
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final supported =
        value is bool ||
        value is double ||
        value is int ||
        value is String ||
        (value is List && value.every((item) => item is String));
    if (!supported) return false;
    final values = await _load();
    values[key] = value is List<String> ? List<String>.from(value) : value;
    return _persist(values);
  }

  @override
  Future<bool> clear() => clearWithParameters(
    ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );

  @override
  Future<bool> clearWithPrefix(String prefix) => clearWithParameters(
    ClearParameters(filter: PreferencesFilter(prefix: prefix)),
  );

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final values = await _load();
    final filter = parameters.filter;
    values.removeWhere(
      (key, _) =>
          key.startsWith(filter.prefix) &&
          (filter.allowList == null || filter.allowList!.contains(key)),
    );
    return _persist(values);
  }

  @override
  Future<Map<String, Object>> getAll() => getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) =>
      getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: prefix)),
      );

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    final values = Map<String, Object>.from(await _load());
    final filter = parameters.filter;
    values.removeWhere(
      (key, _) =>
          !key.startsWith(filter.prefix) ||
          (filter.allowList != null && !filter.allowList!.contains(key)),
    );
    return values;
  }
}
