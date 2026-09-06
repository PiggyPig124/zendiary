import 'package:hive_flutter/hive_flutter.dart';

import '../core/database/db_service.dart';
import '../models/diary_entry.dart';
import '../models/reminder_rule.dart';
import '../models/todo_task.dart';

class DataMigrationService {
  static const _legacyCleanupKey =
      'data_migration_v2_removed_todo_remindAt_timeWindow';
  static const _todoReminderRestoreKey =
      'data_migration_v3_restored_todo_deadline_reminders';
  static const _eventDurationRestoreKey =
      'data_migration_v4_restored_event_durations';
  static const _todoDeadlineIndependenceKey =
      'data_migration_v5_independent_todo_deadline_reminders';

  static Future<void> migrateIfNeeded() async {
    // Per-record marker also covers legacy backups imported after upgrade.
    final todos = Hive.box(DBService.todoBoxName);
    for (final key in todos.keys.toList()) {
      final raw = todos.get(key);
      if (raw is Map && !raw.containsKey('taskKind')) {
        await todos.put(key, TodoTask.fromJson(raw).toJson());
      }
    }
    final settings = Hive.box(DBService.settingsBoxName);
    if (settings.get(_legacyCleanupKey) != true) {
      await _migrateTodoBox();
      await settings.put(_legacyCleanupKey, true);
    }
    if (settings.get(_todoReminderRestoreKey) != true) {
      await _restoreTodoDeadlineRules();
      await settings.put(_todoReminderRestoreKey, true);
    }
    if (settings.get(_eventDurationRestoreKey) != true) {
      await _restoreEventDurations();
      await settings.put(_eventDurationRestoreKey, true);
    }
    // v3 treated any todo reminder as a deadline reminder. Repair that
    // ambiguity once so tasks that already had an execution reminder also
    // receive their independent deadline reminder.
    if (settings.get(_todoDeadlineIndependenceKey) != true) {
      await _restoreTodoDeadlineRules();
      await settings.put(_todoDeadlineIndependenceKey, true);
    }
  }

  /// Restores durations for imported events whose source text contains an
  /// explicit time range such as “周一 12:00–15:00”. Older v2 import files
  /// predate the duration field, so treating those events as punctual would
  /// make conflict detection and auto-planning silently optimistic. Events
  /// without a clear range remain punctual; no duration is guessed.
  static Future<void> _restoreEventDurations() async {
    final box = Hive.box(DBService.diaryBoxName);
    for (final key in box.keys) {
      final value = box.get(key);
      if (value is! Map) continue;
      final entry = DiaryEntry.fromJson(value);
      if (entry.category != 'event' ||
          entry.eventTime == null ||
          entry.durationMinutes != null) {
        continue;
      }
      final duration = inferDurationMinutes(
        entry.aiSummary?.trim().isNotEmpty == true
            ? entry.aiSummary!
            : entry.content,
      );
      if (duration == null) continue;
      await box.put(
        entry.id,
        entry.copyWith(durationMinutes: duration).toJson(),
      );
    }
  }

  /// Extracts one unambiguous clock range from text and returns its length.
  /// The range may use a hyphen, en/em dash, tilde or the Chinese “至”.
  /// Invalid, zero-length or over-day ranges are rejected.
  static int? inferDurationMinutes(String text) {
    final match = RegExp(
      r'(?<!\d)([01]?\d|2[0-3])[:：]([0-5]\d)\s*[-–—~至]\s*([01]?\d|2[0-3])[:：]([0-5]\d)(?!\d)',
    ).firstMatch(text);
    if (match == null) return null;
    final start = int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
    final end = int.parse(match.group(3)!) * 60 + int.parse(match.group(4)!);
    final duration = end - start;
    return duration > 0 && duration <= 1440 ? duration : null;
  }

  static Future<void> _migrateTodoBox() async {
    final todoBox = Hive.box(DBService.todoBoxName);
    for (final key in todoBox.keys) {
      final value = todoBox.get(key);
      if (value is! Map) continue;
      value.remove('remindAt');
      value.remove('timeWindow');
      await todoBox.put(key, value);
    }
  }

  static Future<void> _restoreTodoDeadlineRules() async {
    final todoBox = Hive.box(DBService.todoBoxName);
    final ruleBox = Hive.box(DBService.reminderRuleBoxName);
    final existingDeadlineTargets = <String>{};
    for (final value in ruleBox.values) {
      if (value is! Map || value['targetType'] != 'todo') continue;
      final targetId = value['targetId']?.toString();
      if (targetId == null) continue;
      final note = value['note']?.toString() ?? '';
      final todoValue = todoBox.get(targetId);
      final todo = todoValue is Map ? TodoTask.fromJson(todoValue) : null;
      if (!_looksLikeDeadlineRule(value, todo)) continue;
      existingDeadlineTargets.add(targetId);
      if (value['status'] == 'disabled' && note.contains('[migrated:')) {
        if (todo?.deadline == null) continue;
        final restored = ReminderRule.fromJson(value).copyWith(
          title: todo!.title,
          status: 'active',
          scheduleType: 'once',
          anchorTime: todo.deadline,
          advanceMinutes: const [60],
          note: '作业截止前一小时提醒',
        );
        await ruleBox.put(restored.id, restored.toJson());
      }
    }

    for (final value in todoBox.values) {
      if (value is! Map) continue;
      final todo = TodoTask.fromJson(value);
      if (todo.deadline == null || existingDeadlineTargets.contains(todo.id)) {
        continue;
      }
      final baseId = 'todo-deadline-${todo.id}';
      final ruleId = ruleBox.containsKey(baseId) ? '$baseId-due' : baseId;
      final rule = ReminderRule(
        id: ruleId,
        title: todo.title,
        targetType: 'todo',
        targetId: todo.id,
        category: todo.category,
        scheduleType: 'once',
        anchorTime: todo.deadline,
        advanceMinutes: const [60],
        note: '作业截止前一小时提醒',
      );
      await ruleBox.put(rule.id, rule.toJson());
    }
  }

  static bool _looksLikeDeadlineRule(
    Map<dynamic, dynamic> value,
    TodoTask? todo,
  ) {
    final note = value['note']?.toString() ?? '';
    // Execution and recurring routine reminders must not satisfy the
    // deadline check simply because they target the same todo.
    if (note == '事项提醒' || note == 'AI 例行提醒') return false;
    if (note.contains('截止') || note.contains('deadline')) return true;
    if (value['id']?.toString().startsWith('todo-deadline-') == true) {
      return true;
    }
    final anchor = DateTime.tryParse(value['anchorTime']?.toString() ?? '');
    return todo?.deadline != null && anchor == todo!.deadline;
  }
}
