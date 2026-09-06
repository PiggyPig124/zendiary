import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:zendiary/models/diary_entry.dart';
import 'package:zendiary/models/reminder_rule.dart';
import 'package:zendiary/models/todo_task.dart';

const _todoBoxName = 'todo_box_v2';
const _diaryBoxName = 'diary_box_v2';
const _reminderRuleBoxName = 'reminder_rule_box_v2';

Future<void> main(List<String> args) async {
  final options = _parseOptions(args);
  final dataDirectory = Directory(options.dataDirectory).absolute;
  await dataDirectory.create(recursive: true);
  Hive.init(dataDirectory.path);
  final todoBox = await Hive.openBox(_todoBoxName);
  final diaryBox = await Hive.openBox(_diaryBoxName);
  final ruleBox = await Hive.openBox(_reminderRuleBoxName);

  final seededAt = DateTime.now();
  final todoTime = seededAt.add(Duration(minutes: options.todoMinutes));
  final todo = TodoTask(
    id: 'windows-trial-todo',
    title: '试用：改期后执行提醒',
    createdAt: seededAt,
    scheduledAt: todoTime,
    estimatedMinutes: 30,
  );
  final todoRule = ReminderRule(
    id: 'windows-trial-todo-rule',
    title: todo.title,
    targetType: 'todo',
    targetId: todo.id,
    anchorTime: todoTime,
    advanceMinutes: const [0],
    note: '事项提醒',
    createdAt: seededAt,
    updatedAt: seededAt,
  );
  await todoBox.put(todo.id, todo.toJson());
  await ruleBox.put(todoRule.id, todoRule.toJson());

  final eventTime = seededAt.add(Duration(minutes: options.eventMinutes));
  final event = DiaryEntry(
    id: 'windows-trial-event',
    content: '试用：托盘通知点击目标',
    timestamp: seededAt,
    category: 'event',
    eventTime: eventTime,
    durationMinutes: 30,
  );
  final eventRule = ReminderRule(
    id: 'windows-trial-event-rule',
    title: event.content,
    targetType: 'event',
    targetId: event.id,
    anchorTime: eventTime,
    advanceMinutes: const [0],
    createdAt: seededAt,
    updatedAt: seededAt,
  );
  await diaryBox.put(event.id, event.toJson());
  await ruleBox.put(eventRule.id, eventRule.toJson());

  final manifest = <String, Object>{
    'seededAt': seededAt.toIso8601String(),
    'todoId': todo.id,
    'todoRuleId': todoRule.id,
    'todoTime': todoTime.toIso8601String(),
    'eventId': event.id,
    'eventRuleId': eventRule.id,
    'eventTime': eventTime.toIso8601String(),
  };
  await File(
    '${dataDirectory.path}${Platform.pathSeparator}trial_manifest.json',
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));

  stdout.writeln('试用数据已写入隔离目录：${dataDirectory.path}');
  stdout.writeln('试用待办：${todoTime.toIso8601String()} (${todo.id})');
  stdout.writeln('托盘点击事项：${eventTime.toIso8601String()} (${event.id})');
  await Hive.close();
}

_SeedOptions _parseOptions(List<String> args) {
  String? dataDirectory;
  var todoMinutes = 20;
  var eventMinutes = 8;
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (argument == '--data-dir' && index + 1 < args.length) {
      dataDirectory = args[++index];
    } else if (argument.startsWith('--data-dir=')) {
      dataDirectory = argument.substring('--data-dir='.length);
    } else if (argument == '--todo-minutes' && index + 1 < args.length) {
      todoMinutes = int.tryParse(args[++index]) ?? -1;
    } else if (argument.startsWith('--todo-minutes=')) {
      todoMinutes =
          int.tryParse(argument.substring('--todo-minutes='.length)) ?? -1;
    } else if (argument == '--event-minutes' && index + 1 < args.length) {
      eventMinutes = int.tryParse(args[++index]) ?? -1;
    } else if (argument.startsWith('--event-minutes=')) {
      eventMinutes =
          int.tryParse(argument.substring('--event-minutes='.length)) ?? -1;
    } else {
      throw FormatException('未知或不完整的参数：$argument');
    }
  }
  if (dataDirectory == null || dataDirectory.trim().isEmpty) {
    throw const FormatException('必须提供 --data-dir <目录>');
  }
  if (todoMinutes < 1 || todoMinutes > 1440) {
    throw const FormatException('--todo-minutes 必须在 1 到 1440 之间');
  }
  if (eventMinutes < 1 || eventMinutes > 1440) {
    throw const FormatException('--event-minutes 必须在 1 到 1440 之间');
  }
  return _SeedOptions(
    dataDirectory: dataDirectory,
    todoMinutes: todoMinutes,
    eventMinutes: eventMinutes,
  );
}

class _SeedOptions {
  final String dataDirectory;
  final int todoMinutes;
  final int eventMinutes;

  const _SeedOptions({
    required this.dataDirectory,
    required this.todoMinutes,
    required this.eventMinutes,
  });
}
