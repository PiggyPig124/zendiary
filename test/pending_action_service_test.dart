import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:zendiary/core/database/db_service.dart';
import 'package:zendiary/models/diary_entry.dart';
import 'package:zendiary/models/pending_action_preview.dart';
import 'package:zendiary/models/reminder_rule.dart';
import 'package:zendiary/models/todo_task.dart';
import 'package:zendiary/services/pending_action_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zendiary-action-');
    Hive.init(directory.path);
    await Hive.openBox(DBService.settingsBoxName);
  });

  tearDown(() async {
    await Hive.close();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test(
    'high-impact action survives reload and can be cleared independently',
    () async {
      final createdAt = DateTime(2026, 9, 2, 10, 30);
      final preview = PendingActionPreview(
        type: PendingActionType.lowLoad,
        title: '开启低负荷安排',
        reason: '这几天课程较密集',
        createdAt: createdAt,
        rangeStart: DateTime(2026, 9, 2),
        rangeEnd: DateTime(2026, 9, 4),
        todos: [
          TodoTask(
            id: 'todo-1',
            title: '复习离散数学',
            createdAt: createdAt,
            deadline: DateTime(2026, 9, 3, 23),
          ),
        ],
        events: [
          DiaryEntry(
            id: 'event-1',
            content: 'CS2310 Lecture',
            timestamp: createdAt,
            category: 'event',
            eventTime: DateTime(2026, 9, 3, 12),
            durationMinutes: 90,
          ),
        ],
        rules: [
          ReminderRule(
            id: 'rule-1',
            title: '考试提醒',
            targetType: 'event',
            targetId: 'event-1',
            anchorTime: DateTime(2026, 9, 3, 12),
            advanceMinutes: [30],
          ),
        ],
        protectedItems: const ['重要考试'],
      );

      await PendingActionService.save(preview);
      final restored = PendingActionService.loadAll().single;

      expect(restored.type, PendingActionType.lowLoad);
      expect(restored.createdAt, createdAt);
      expect(restored.rangeEnd, DateTime(2026, 9, 4));
      expect(restored.todos.single.id, 'todo-1');
      expect(restored.todos.single.deadline, DateTime(2026, 9, 3, 23));
      expect(restored.events.single.durationMinutes, 90);
      expect(restored.rules.single.advanceMinutes, [30]);
      expect(restored.protectedItems, ['重要考试']);

      PendingActionService.clear(preview);
      expect(PendingActionService.loadAll(), isEmpty);
    },
  );

  test('multiple pending actions do not overwrite one another', () async {
    final first = PendingActionPreview(
      type: PendingActionType.lowLoad,
      title: '低负荷',
      reason: '课程较密集',
      createdAt: DateTime(2026, 9, 2, 8),
      todos: [
        TodoTask(
          id: 'todo-1',
          title: '任务一',
          createdAt: DateTime(2026, 9, 2, 8),
        ),
      ],
    );
    final second = PendingActionPreview(
      type: PendingActionType.disableFuture,
      title: '停用未来提醒',
      reason: '提醒太频繁',
      createdAt: DateTime(2026, 9, 2, 9),
      rules: [ReminderRule(id: 'rule-2', title: '喝水提醒')],
    );

    await PendingActionService.save(first);
    await PendingActionService.save(second);

    expect(PendingActionService.loadAll().map((item) => item.title), [
      '低负荷',
      '停用未来提醒',
    ]);
    PendingActionService.clear(first);
    expect(PendingActionService.loadAll().map((item) => item.title), [
      '停用未来提醒',
    ]);
  });
}
