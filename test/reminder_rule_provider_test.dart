import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:zendiary/core/database/db_service.dart';
import 'package:zendiary/models/ai_parsed_intent.dart';
import 'package:zendiary/models/diary_entry.dart';
import 'package:zendiary/models/reminder_rule.dart';
import 'package:zendiary/models/recurrence_override.dart';
import 'package:zendiary/providers/app_providers.dart';
import 'package:zendiary/providers/reminder_rule_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zendiary-rules-');
    Hive.init(directory.path);
    await Hive.openBox(DBService.settingsBoxName);
    await Hive.openBox(DBService.reminderRuleBoxName);
    await Hive.openBox(DBService.todoBoxName);
  });

  tearDown(() async {
    await Hive.close();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test('todo execution and deadline reminders coexist', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(reminderRuleProvider.notifier);

    notifier.upsertRuleForTarget(
      ReminderRule(
        id: 'deadline-rule',
        title: '交报告',
        targetType: 'todo',
        targetId: 'report',
        anchorTime: DateTime(2026, 9, 10, 23, 59),
        advanceMinutes: const [60],
        note: '作业截止前一小时提醒',
      ),
    );
    notifier.upsertRuleForTarget(
      ReminderRule(
        id: 'execution-rule',
        title: '交报告',
        targetType: 'todo',
        targetId: 'report',
        anchorTime: DateTime(2026, 9, 8, 19),
        advanceMinutes: const [0],
        note: '事项提醒',
      ),
    );

    expect(container.read(reminderRuleProvider), hasLength(2));
    expect(notifier.ruleForTodoDeadline('report')?.id, 'deadline-rule');
    expect(notifier.ruleForTodoExecution('report')?.id, 'execution-rule');

    // Updating one role must not overwrite the other role.
    notifier.upsertRuleForTarget(
      ReminderRule(
        title: '交报告',
        targetType: 'todo',
        targetId: 'report',
        anchorTime: DateTime(2026, 9, 8, 20),
        advanceMinutes: const [15],
        note: '事项提醒',
      ),
    );
    expect(container.read(reminderRuleProvider), hasLength(2));
    expect(
      notifier.ruleForTodoExecution('report')?.anchorTime,
      DateTime(2026, 9, 8, 20),
    );
    expect(
      notifier.ruleForTodoDeadline('report')?.anchorTime,
      DateTime(2026, 9, 10, 23, 59),
    );
  });

  test('unanchored AI todo reminder stays pending instead of disappearing', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final todoNotifier = container.read(todoListProvider.notifier);
    final entry = DiaryEntry(
      id: 'capture-without-time',
      content: '提醒我复习',
      timestamp: DateTime(2026, 9, 4, 8),
      category: 'todo',
    );
    final todo = todoNotifier.addTodo(
      '复习',
      sourceEntryId: entry.id,
    );
    final confirmation = AiReminderConfirmation(
      entry: entry,
      intent: const AiParsedIntent(
        category: 'todo',
        reminder: AiReminderCandidate(enabled: true),
      ),
    );

    final confirmed = container
        .read(allEntriesProvider.notifier)
        .confirmAiReminder(confirmation);

    expect(confirmed, isFalse);
    expect(
      container.read(reminderRuleProvider),
      isEmpty,
    );

    todoNotifier.rescheduleTodo(todo.id, DateTime(2026, 9, 4, 19));
    expect(
      container
          .read(allEntriesProvider.notifier)
          .confirmAiReminder(confirmation),
      isTrue,
    );
    expect(
      container.read(reminderRuleProvider.notifier).ruleForTodoExecution(todo.id),
      isNotNull,
    );
  });

  test('todo detail edits keep the execution reminder in sync', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final todoNotifier = container.read(todoListProvider.notifier);
    final ruleNotifier = container.read(reminderRuleProvider.notifier);
    final initialTime = DateTime(2026, 9, 4, 19);
    final todo = todoNotifier.addTodo('复习旧标题', scheduledAt: initialTime);
    ruleNotifier.upsertRuleForTarget(
      ReminderRule(
        id: 'execution-detail-sync',
        title: todo.title,
        targetType: 'todo',
        targetId: todo.id,
        anchorTime: initialTime,
        note: '事项提醒',
      ),
    );

    final nextTime = DateTime(2026, 9, 5, 20);
    todoNotifier.updateTodo(
      todo.copyWith(title: '复习新标题', scheduledAt: nextTime),
    );

    final updated = ruleNotifier.ruleForTodoExecution(todo.id);
    expect(updated?.title, '复习新标题');
    expect(updated?.anchorTime, nextTime);
  });

  test(
    'routine date helpers honor a one-day skip without changing the rule',
    () {
      final rule = ReminderRule(
        id: 'vocab-routine',
        title: '背单词',
        targetType: 'todo',
        targetId: 'vocab',
        scheduleType: 'daily',
        anchorTime: DateTime(2026, 9, 1, 20),
      );
      final rules = [rule];
      final day = DateTime(2026, 9, 3);

      expect(routineRuleForTodo('vocab', rules), same(rule));
      expect(isRoutineDueOnDate('vocab', day, rules), isTrue);
      expect(isRoutineSkippedOnDate('vocab', day, rules), isFalse);

      final skipped = rule.copyWith(skipDates: [day]);
      expect(isRoutineDueOnDate('vocab', day, [skipped]), isFalse);
      expect(isRoutineSkippedOnDate('vocab', day, [skipped]), isTrue);
      expect(
        isRoutineDueOnDate('vocab', day.add(const Duration(days: 1)), [
          skipped,
        ]),
        isTrue,
      );
    },
  );

  test(
    'single occurrence edits can clear old duration and location overrides',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(reminderRuleProvider.notifier);
      final originalDate = DateTime(2026, 9, 7);
      final rule = ReminderRule(
        id: 'class-rule',
        title: '高等数学',
        targetType: 'event',
        targetId: 'math',
        scheduleType: 'weekly',
        byDay: const [1],
        anchorTime: DateTime(2026, 9, 1, 10),
        overrides: [
          RecurrenceOverride(
            originalDate: originalDate,
            newTime: DateTime(2026, 9, 7, 11),
            newDurationMinutes: 90,
            newLocation: 'B203',
          ),
        ],
      );
      notifier.addRule(rule);

      notifier.updateOccurrence(
        rule.id,
        originalDate,
        newTime: DateTime(2026, 9, 7, 11),
        clearNewDurationMinutes: true,
        newContent: '高等数学（调课）',
        clearNewLocation: true,
      );

      final updated = notifier.ruleForTarget('event', 'math');
      final override = updated!.overrides.single;
      expect(override.newTime, DateTime(2026, 9, 7, 11));
      expect(override.newDurationMinutes, isNull);
      expect(override.clearDurationMinutes, isTrue);
      expect(override.newLocation, isNull);
      expect(override.clearLocation, isTrue);
      expect(override.newContent, '高等数学（调课）');
    },
  );

  test('switching a recurring todo to one-off keeps rule ids unique', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(reminderRuleProvider.notifier);

    notifier.addRule(
      ReminderRule(
        id: 'routine-rule',
        title: '每日复习',
        targetType: 'todo',
        targetId: 'study',
        scheduleType: 'daily',
        anchorTime: DateTime(2026, 9, 2, 19),
      ),
    );
    notifier.archiveRule('routine-rule');

    // The deadline rule must not reuse the archived recurring-rule id.
    notifier.upsertRuleForTarget(
      ReminderRule(
        title: '每日复习',
        targetType: 'todo',
        targetId: 'study',
        scheduleType: 'once',
        anchorTime: DateTime(2026, 9, 4, 23, 59),
        note: '作业截止前一小时提醒',
      ),
    );

    final rules = container.read(reminderRuleProvider);
    expect(rules, hasLength(2));
    expect(rules.map((rule) => rule.id).toSet(), hasLength(2));
    expect(notifier.ruleForTodoDeadline('study')?.id, isNot('routine-rule'));
  });

  test('upserting a recurring todo refreshes interval and weekday fields', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(reminderRuleProvider.notifier);

    notifier.upsertRuleForTarget(
      ReminderRule(
        id: 'routine-fields',
        title: '复习',
        targetType: 'todo',
        targetId: 'study',
        scheduleType: 'weekly',
        scheduleInterval: 1,
        byDay: const [1],
        anchorTime: DateTime(2026, 9, 7, 19),
      ),
    );
    notifier.upsertRuleForTarget(
      ReminderRule(
        title: '复习',
        targetType: 'todo',
        targetId: 'study',
        scheduleType: 'every_n_days',
        scheduleInterval: 3,
        anchorTime: DateTime(2026, 9, 7, 20),
      ),
    );

    final updated = notifier.ruleForTarget('todo', 'study');
    expect(updated?.scheduleType, 'every_n_days');
    expect(updated?.scheduleInterval, 3);
    expect(updated?.byDay, isNull);
  });

  test('unscheduling a todo preserves its execution reminder preference', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final todoNotifier = container.read(todoListProvider.notifier);
    final ruleNotifier = container.read(reminderRuleProvider.notifier);
    final initialTime = DateTime(2026, 9, 3, 19);
    final todo = todoNotifier.addTodo('复习离散数学', scheduledAt: initialTime);
    ruleNotifier.upsertRuleForTarget(
      ReminderRule(
        id: 'execution-preserved',
        title: todo.title,
        targetType: 'todo',
        targetId: todo.id,
        anchorTime: initialTime,
        advanceMinutes: const [0],
        note: '事项提醒',
      ),
    );

    todoNotifier.rescheduleTodo(todo.id, null);
    final unscheduledRule = ruleNotifier.ruleForTodoExecution(todo.id);
    expect(unscheduledRule?.isActive, isTrue);
    expect(unscheduledRule?.anchorTime, isNull);

    final nextTime = DateTime(2026, 9, 4, 20);
    todoNotifier.rescheduleTodo(todo.id, nextTime);
    final rescheduledRule = ruleNotifier.ruleForTodoExecution(todo.id);
    expect(rescheduledRule?.isActive, isTrue);
    expect(rescheduledRule?.anchorTime, nextTime);
  });

  test(
    'schedule changes persist once and keep deadline reminders separate',
    () async {
      final container = ProviderContainer();
      var containerDisposed = false;
      addTearDown(() {
        if (!containerDisposed) container.dispose();
      });
      final initialTime = DateTime(2026, 9, 3, 19);
      final deadline = DateTime(2026, 9, 10, 23, 59);
      final todo = container
          .read(todoListProvider.notifier)
          .addTodo('跨日补做实验', scheduledAt: initialTime, deadline: deadline);
      container
          .read(reminderRuleProvider.notifier)
          .upsertRuleForTarget(
            ReminderRule(
              id: 'hive-execution-${todo.id}',
              title: todo.title,
              targetType: 'todo',
              targetId: todo.id,
              anchorTime: initialTime,
              note: '事项提醒',
            ),
          );

      final nextTime = DateTime(2026, 9, 12, 20);
      container
          .read(todoListProvider.notifier)
          .rescheduleTodo(todo.id, nextTime);
      container.read(todoListProvider.notifier).rescheduleTodo(todo.id, null);

      final todoBox = Hive.box(DBService.todoBoxName);
      expect(todoBox.keys.where((key) => key == todo.id), hasLength(1));
      expect(
        container
            .read(reminderRuleProvider.notifier)
            .ruleForTodoExecution(todo.id)
            ?.anchorTime,
        isNull,
      );
      expect(
        container
            .read(reminderRuleProvider.notifier)
            .ruleForTodoDeadline(todo.id)
            ?.anchorTime,
        deadline,
      );

      container.dispose();
      containerDisposed = true;
      await Hive.close();
      await Hive.openBox(DBService.settingsBoxName);
      await Hive.openBox(DBService.reminderRuleBoxName);
      await Hive.openBox(DBService.todoBoxName);
      final restored = ProviderContainer();
      addTearDown(restored.dispose);
      expect(restored.read(todoListProvider), hasLength(1));
      expect(restored.read(todoListProvider).single.id, todo.id);
      expect(restored.read(todoListProvider).single.scheduledAt, isNull);
      expect(
        restored
            .read(reminderRuleProvider.notifier)
            .ruleForTodoExecution(todo.id)
            ?.anchorTime,
        isNull,
      );
      expect(
        restored
            .read(reminderRuleProvider.notifier)
            .ruleForTodoDeadline(todo.id)
            ?.anchorTime,
        deadline,
      );
    },
  );

  test(
    'undo removal deletes a generated todo without cascading to its reminder',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final todoNotifier = container.read(todoListProvider.notifier);
      final ruleNotifier = container.read(reminderRuleProvider.notifier);
      final todo = todoNotifier.addTodo('批量整理的待办');
      ruleNotifier.addRule(
        ReminderRule(
          id: 'generated-execution-rule',
          title: todo.title,
          targetType: 'todo',
          targetId: todo.id,
          anchorTime: DateTime(2026, 9, 4, 19),
          note: '事项提醒',
        ),
      );

      todoNotifier.removeTodoWithoutCascade(todo.id);

      expect(container.read(todoListProvider), isEmpty);
      expect(
        container
            .read(reminderRuleProvider)
            .any(
              (rule) => rule.targetType == 'todo' && rule.targetId == todo.id,
            ),
        isFalse,
      );
    },
  );

  test('restoring a completed event reactivates its archived reminder', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(reminderRuleProvider.notifier);
    notifier.addRule(
      ReminderRule(
        id: 'completed-event-reminder',
        title: '实验课',
        targetType: 'event',
        targetId: 'lab',
        status: 'archived',
      ),
    );

    notifier.restoreArchivedRulesForTarget('event', 'lab');

    expect(notifier.ruleForTarget('event', 'lab')?.status, 'active');
  });

  test('completing a one-off todo archives its reminders and undo restores them', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final todoNotifier = container.read(todoListProvider.notifier);
    final todo = todoNotifier.addTodo(
      '交报告',
      scheduledAt: DateTime(2026, 9, 8, 19),
      deadline: DateTime(2026, 9, 10, 23, 59),
    );
    final ruleNotifier = container.read(reminderRuleProvider.notifier);
    ruleNotifier.addRule(
      ReminderRule(
        id: 'todo-execution-completion',
        title: todo.title,
        targetType: 'todo',
        targetId: todo.id,
        note: '事项提醒',
        anchorTime: todo.scheduledAt,
      ),
    );

    todoNotifier.toggleTodo(todo.id);

    final archived = container
        .read(reminderRuleProvider)
        .firstWhere((rule) => rule.id == 'todo-execution-completion');
    expect(archived.status, 'archived');
    expect(archived.archivedByCompletion, isTrue);

    todoNotifier.toggleTodo(todo.id);

    final restored = container
        .read(reminderRuleProvider)
        .firstWhere((rule) => rule.id == 'todo-execution-completion');
    expect(restored.status, 'active');
    expect(restored.archivedByCompletion, isFalse);
  });

  test('completing a recurring todo keeps its routine reminder active', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final todoNotifier = container.read(todoListProvider.notifier);
    final todo = todoNotifier.addTodo('每日背单词');
    final ruleNotifier = container.read(reminderRuleProvider.notifier);
    ruleNotifier.addRule(
      ReminderRule(
        id: 'todo-recurring-completion',
        title: todo.title,
        targetType: 'todo',
        targetId: todo.id,
        scheduleType: 'daily',
        anchorTime: DateTime(2026, 9, 8, 20),
      ),
    );

    todoNotifier.toggleTodo(todo.id);

    final rule = container
        .read(reminderRuleProvider)
        .firstWhere((item) => item.id == 'todo-recurring-completion');
    expect(rule.status, 'active');
    expect(rule.archivedByCompletion, isFalse);
  });

  test('completion undo does not revive a reminder disabled beforehand', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(reminderRuleProvider.notifier);
    notifier.addRule(
      ReminderRule(
        id: 'paused-before-completion',
        title: '实验课',
        targetType: 'event',
        targetId: 'lab',
        status: 'paused',
      ),
    );
    notifier.addRule(
      ReminderRule(
        id: 'active-before-completion',
        title: '实验课',
        targetType: 'event',
        targetId: 'lab',
      ),
    );

    notifier.archiveActiveRulesForCompletion('event', 'lab');
    final paused = container
        .read(reminderRuleProvider)
        .firstWhere((rule) => rule.id == 'paused-before-completion');
    final archived = container
        .read(reminderRuleProvider)
        .firstWhere((rule) => rule.id == 'active-before-completion');
    expect(paused.status, 'paused');
    expect(paused.archivedByCompletion, isFalse);
    expect(archived.status, 'archived');
    expect(archived.archivedByCompletion, isTrue);
    expect(
      ReminderRule.fromJson(archived.toJson()).archivedByCompletion,
      isTrue,
    );

    notifier.restoreCompletedRulesForTarget('event', 'lab');
    final restored = container.read(reminderRuleProvider);
    expect(
      restored.firstWhere((rule) => rule.id == 'active-before-completion').status,
      'active',
    );
    expect(
      restored.firstWhere((rule) => rule.id == 'paused-before-completion').status,
      'paused',
    );
  });
}
