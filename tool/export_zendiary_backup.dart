import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';

const boxNames = [
  'diary_box_v2',
  'todo_box_v2',
  'note_box_v2',
  'settings_box',
  'reminder_rule_box_v2',
];

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    stderr.writeln(
      '用法: dart run tool/export_zendiary_backup.dart <数据目录> <输出文件>',
    );
    exitCode = 64;
    return;
  }

  final dataDirectory = Directory(arguments[0]);
  final output = File(arguments[1]);
  if (!await dataDirectory.exists()) {
    throw FileSystemException('数据目录不存在', dataDirectory.path);
  }

  Hive.init(dataDirectory.path);
  final boxes = <String, dynamic>{};
  try {
    for (final name in boxNames) {
      final box = await Hive.openBox(name);
      boxes[name] = _backupBox(name, box.toMap());
      await box.close();
    }
  } finally {
    await Hive.close();
  }

  final payload = <String, dynamic>{
    'app': 'ZenDiary',
    'exportedAt': DateTime.now().toIso8601String(),
    'boxes': boxes,
  };
  await output.parent.create(recursive: true);
  await output.writeAsString(
    const JsonEncoder.withIndent('  ').convert(payload),
    encoding: utf8,
  );
  stdout.writeln(output.absolute.path);
  for (final name in boxNames) {
    stdout.writeln('$name: ${(boxes[name] as Map).length} 条');
  }
}

Map<String, dynamic> _backupBox(
  String name,
  Map<dynamic, dynamic> values,
) {
  final safe = <String, dynamic>{};
  for (final entry in values.entries) {
    final key = entry.key.toString();
    if (name == 'settings_box' && key == 'ai_settings' && entry.value is Map) {
      safe[key] = _sanitizeAiSettings(entry.value as Map);
    } else {
      safe[key] = _jsonSafeValue(entry.value);
    }
  }
  return safe;
}

Map<String, dynamic> _sanitizeAiSettings(Map<dynamic, dynamic> values) {
  final safe = values.map(
    (key, value) => MapEntry(key.toString(), _jsonSafeValue(value)),
  );
  final apiKeyConfigured = (safe['apiKey']?.toString() ?? '').isNotEmpty;
  safe.remove('apiKey');
  safe['apiKeyConfigured'] = apiKeyConfigured;
  final rawBaseUrl = safe['baseUrl']?.toString();
  if (rawBaseUrl != null) {
    final uri = Uri.tryParse(rawBaseUrl.trim());
    safe['baseUrl'] = uri == null || !uri.hasScheme || uri.host.isEmpty
        ? ''
        : uri.replace(userInfo: '', query: '', fragment: '').toString()
            .replaceFirst(RegExp(r'[?#]+$'), '');
  }
  return safe;
}

dynamic _jsonSafeValue(dynamic value) {
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
  if (value is Iterable) return value.map(_jsonSafeValue).toList();
  return value.toString();
}
