import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:zendiary/core/database/db_service.dart';
import 'package:zendiary/models/reminder_rule.dart';
import 'package:zendiary/models/todo_task.dart';
import 'package:zendiary/services/data_migration_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zendiary-migration-');
    Hive.init(directory.path);
    await Hive.openBox(DBService.settingsBoxName);
    await Hive.openBox(DBService.todoBoxName);
    await Hive.openBox(DBService.diaryBoxName);
    await Hive.openBox(DBService.noteBoxName);
    await Hive.openBox(DBService.reminderRuleBoxName);
  });

  tearDown(() async {
    await Hive.close();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test(
    'deadline repair keeps execution reminders and adds a separate rule',
    () async {
      final todo = TodoTask(
        id: 'migration-deadline-todo',
        title: '交实验报告',
        createdAt: DateTime(2026, 9, 1),
        deadline: DateTime(2026, 9, 10, 23, 59),
      );
      final executionRule = ReminderRule(
        id: 'migration-execution-rule',
        title: todo.title,
        targetType: 'todo',
        targetId: todo.id,
        scheduleType: 'once',
        anchorTime: DateTime(2026, 9, 8, 19),
        advanceMinutes: const [0],
        note: '事项提醒',
      );
      await Hive.box(DBService.todoBoxName).put(todo.id, todo.toJson());
      await Hive.box(
        DBService.reminderRuleBoxName,
      ).put(executionRule.id, executionRule.toJson());

      await DataMigrationService.migrateIfNeeded();

      final rules = Hive.box(DBService.reminderRuleBoxName).values
          .whereType<Map>()
          .map(ReminderRule.fromJson)
          .where((rule) => rule.targetId == todo.id)
          .toList();
      expect(rules, hasLength(2));
      expect(rules.any((rule) => rule.note == '事项提醒'), isTrue);
      final deadline = rules.singleWhere((rule) => rule.note!.contains('截止'));
      expect(deadline.anchorTime, todo.deadline);
      expect(deadline.id, isNot(executionRule.id));
    },
  );

  test('deadline repair is idempotent on a second startup', () async {
    final todo = TodoTask(
      id: 'migration-idempotent-todo',
      title: '准备测验',
      createdAt: DateTime(2026, 9, 1),
      deadline: DateTime(2026, 9, 12, 18),
    );
    await Hive.box(DBService.todoBoxName).put(todo.id, todo.toJson());

    await DataMigrationService.migrateIfNeeded();
    final first = Hive.box(DBService.reminderRuleBoxName).values.length;
    await DataMigrationService.migrateIfNeeded();
    final second = Hive.box(DBService.reminderRuleBoxName).values.length;

    expect(first, 1);
    expect(second, first);
  });
}
