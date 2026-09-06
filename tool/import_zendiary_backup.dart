import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';

const legacyBoxNames = [
  'diary_box',
  'todo_box',
  'note_box',
  'settings_box',
  'reminder_rule_box',
];

const v2BoxNames = [
  'diary_box_v2',
  'todo_box_v2',
  'note_box_v2',
  'settings_box',
  'reminder_rule_box_v2',
];

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    stderr.writeln(
      '用法: dart run tool/import_zendiary_backup.dart <数据目录> <备份文件> [--dry-run]',
    );
    exitCode = 64;
    return;
  }
  final dataDirectory = Directory(arguments[0]);
  final source = File(arguments[1]);
  final dryRun = arguments.contains('--dry-run');
  final useV2 = arguments.contains('--v2');
  final decoded = jsonDecode(await source.readAsString());
  if (decoded is! Map || decoded['app'] != 'ZenDiary') {
    throw const FormatException('不是 ZenDiary 备份文件');
  }
  final boxes = decoded['boxes'];
  if (boxes is! Map) throw const FormatException('备份缺少 boxes');
  await dataDirectory.create(recursive: true);
  Hive.init(dataDirectory.path);

  final mappings = useV2
      ? <String, String>{
          for (var i = 0; i < legacyBoxNames.length; i++)
            legacyBoxNames[i]: v2BoxNames[i],
        }
      : <String, String>{for (final name in legacyBoxNames) name: name};

  var total = 0;
  for (final entry in mappings.entries) {
    final sourceBoxName = entry.key;
    final targetBoxName = entry.value;
    final values = boxes[sourceBoxName] ?? boxes[targetBoxName];
    if (values is! Map) continue;
    stdout.writeln('$sourceBoxName -> $targetBoxName: ${values.length} 条');
    total += values.length;
    if (dryRun) continue;
    final box = await Hive.openBox(targetBoxName);
    for (final entry in values.entries) {
      await box.put(entry.key.toString(), entry.value);
    }
    await box.close();
  }
  stdout.writeln(dryRun ? '预览完成：$total 条' : '导入完成：$total 条');
}
