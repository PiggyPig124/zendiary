import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/database/db_service.dart';
import '../models/recurrence_override.dart';
import '../models/reminder_rule.dart';
import '../services/recurrence_service.dart';
import 'app_providers.dart';

final reminderRuleProvider =
    NotifierProvider<ReminderRuleNotifier, List<ReminderRule>>(
      ReminderRuleNotifier.new,
    );

/// 判断一个待办是否关联了活跃的重复提醒规则。
///
/// [ReminderRule] 是例行状态的唯一真相来源，替代了已废弃的 TodoTask.isRoutine。
bool isRoutineTodo(String todoId, List<ReminderRule> rules) {
  return routineRuleForTodo(todoId, rules) != null;
}

/// Returns the active recurring rule that drives a routine todo, if any.
/// Keeping this lookup in one place prevents the Today page, Todo page and
/// notification actions from disagreeing about which rule is the routine.
ReminderRule? routineRuleForTodo(String todoId, List<ReminderRule> rules) {
  for (final rule in rules) {
    if (rule.targetType == 'todo' &&
        rule.targetId == todoId &&
        rule.isActive &&
        _isRecurringSchedule(rule.scheduleType)) {
      return rule;
    }
  }
  return null;
}

/// Whether a routine todo has an occurrence on [day] that is not skipped.
/// A skipped occurrence is a one-day decision; the underlying rule remains
/// unchanged for the next occurrence.
bool isRoutineDueOnDate(String todoId, DateTime day, List<ReminderRule> rules) {
  final rule = routineRuleForTodo(todoId, rules);
  if (rule == null) return false;
  final date = DateTime(day.year, day.month, day.day);
  if (rule.skipDates.any(
    (value) => RecurrenceService.isSameDate(value, date),
  )) {
    return false;
  }
  return RecurrenceService.occurrenceOn(rule, date) != null;
}

bool isRoutineSkippedOnDate(
  String todoId,
  DateTime day,
  List<ReminderRule> rules,
) {
  final rule = routineRuleForTodo(todoId, rules);
  if (rule == null) return false;
  final date = DateTime(day.year, day.month, day.day);
  return rule.skipDates.any(
    (value) => RecurrenceService.isSameDate(value, date),
  );
}

bool _isRecurringSchedule(String scheduleType) =>
    const ['daily', 'weekly', 'every_n_days', 'monthly'].contains(scheduleType);

String _todoRuleRole(ReminderRule rule) {
  if (rule.note == '事项提醒') return 'execution';
  if (_isRecurringSchedule(rule.scheduleType)) return 'routine';
  return 'deadline';
}

final activeReminderRulesProvider = Provider<List<ReminderRule>>((ref) {
  return ref.watch(reminderRuleProvider).where((rule) => rule.isActive).toList()
    ..sort((a, b) {
      final left = a.anchorTime ?? a.createdAt;
      final right = b.anchorTime ?? b.createdAt;
      return left.compareTo(right);
    });
});

/// 包含 active + disabled + paused 的提醒规则（排除 archived），
/// 用于提醒管理界面，关闭 toggle 后规则不会从列表中消失。
final allNonArchivedRulesProvider = Provider<List<ReminderRule>>((ref) {
  return ref
      .watch(reminderRuleProvider)
      .where((rule) => rule.status != 'archived')
      .toList()
    ..sort((a, b) {
      final left = a.anchorTime ?? a.createdAt;
      final right = b.anchorTime ?? b.createdAt;
      return left.compareTo(right);
    });
});

class ReminderRuleNotifier extends Notifier<List<ReminderRule>> {
  @override
  List<ReminderRule> build() {
    final box = Hive.box(DBService.reminderRuleBoxName);
    final rules = <ReminderRule>[];
    for (final value in box.values) {
      if (value is Map) {
        final rule = ReminderRule.fromJson(value);
        if (rule.title.trim().isNotEmpty) rules.add(rule);
      }
    }
    return rules;
  }

  void addRule(ReminderRule rule) {
    state = [rule, ...state];
    Hive.box(DBService.reminderRuleBoxName).put(rule.id, rule.toJson());
  }

  void updateRule(ReminderRule rule) {
    final index = state.indexWhere((item) => item.id == rule.id);
    if (index == -1) return;
    state = [...state.sublist(0, index), rule, ...state.sublist(index + 1)];
    Hive.box(DBService.reminderRuleBoxName).put(rule.id, rule.toJson());
  }

  ReminderRule? ruleForTarget(String targetType, String targetId) {
    for (final rule in state) {
      if (rule.targetType == targetType && rule.targetId == targetId) {
        return rule;
      }
    }
    return null;
  }

  /// User-created reminder for the time the student plans to work on a todo.
  /// Deadline reminders use a separate rule for the same target.
  ReminderRule? ruleForTodoExecution(String todoId) {
    return state.cast<ReminderRule?>().firstWhere(
      (rule) =>
          rule?.targetType == 'todo' &&
          rule?.targetId == todoId &&
          rule?.note == '事项提醒',
      orElse: () => null,
    );
  }

  /// Automatic/manual deadline reminder for a todo, excluding its execution
  /// reminder so the two schedules can coexist.
  ReminderRule? ruleForTodoDeadline(String todoId) {
    return state.cast<ReminderRule?>().firstWhere(
      (rule) =>
          rule?.targetType == 'todo' &&
          rule?.targetId == todoId &&
          rule != null &&
          _todoRuleRole(rule) == 'deadline',
      orElse: () => null,
    );
  }

  void upsertRuleForTarget(ReminderRule rule) {
    final index = state.indexWhere((item) {
      if (item.targetType != rule.targetType ||
          item.targetId != rule.targetId) {
        return false;
      }
      // Todos may own both an execution reminder and a deadline reminder.
      // They may also own a recurring routine rule. Keep all three roles
      // separate; event targets still have one rule.
      if (rule.targetType == 'todo') {
        return _todoRuleRole(item) == _todoRuleRole(rule);
      }
      return true;
    });
    if (index == -1) {
      addRule(rule);
      return;
    }

    final existing = state[index];
    updateRule(
      existing.copyWith(
        title: rule.title,
        category: rule.category,
        importance: rule.importance,
        disturbanceLevel: rule.disturbanceLevel,
        scheduleType: rule.scheduleType,
        scheduleInterval: rule.scheduleInterval,
        scheduleDay: rule.scheduleDay,
        clearScheduleDay: rule.scheduleDay == null,
        anchorTime: rule.anchorTime,
        advanceMinutes: rule.advanceMinutes,
        status: rule.status,
        generatedByAi: rule.generatedByAi,
        requiresConfirmation: rule.requiresConfirmation,
        note: rule.note,
        clearNote: rule.note == null,
        displayMode: rule.displayMode,
        customSpanDays: rule.customSpanDays,
        clearCustomSpanDays: rule.customSpanDays == null,
        startDate: rule.startDate,
        clearStartDate: rule.startDate == null,
        endDate: rule.endDate,
        clearEndDate: rule.endDate == null,
        endCount: rule.endCount,
        clearEndCount: rule.endCount == null,
        byDay: rule.byDay,
        clearByDay: rule.byDay == null,
        byMonthDay: rule.byMonthDay,
        clearByMonthDay: rule.byMonthDay == null,
        // skipDates 和 overrides 通过专用方法管理（addSkipDate 等），
        // 不在 upsertRuleForTarget 中覆盖
      ),
    );
  }

  void addSkipDate(String ruleId, DateTime date) {
    final index = state.indexWhere((item) => item.id == ruleId);
    if (index == -1) return;
    final rule = state[index];
    final skipDate = DateTime(date.year, date.month, date.day);
    if (rule.skipDates.any((d) => _sameDay(d, skipDate))) return;
    final updated = rule.copyWith(skipDates: [...rule.skipDates, skipDate]);
    updateRule(updated);
  }

  void removeSkipDate(String ruleId, DateTime date) {
    final index = state.indexWhere((item) => item.id == ruleId);
    if (index == -1) return;
    final rule = state[index];
    final skipDate = DateTime(date.year, date.month, date.day);
    final newSkips = rule.skipDates
        .where((d) => !_sameDay(d, skipDate))
        .toList();
    updateRule(rule.copyWith(skipDates: newSkips));
  }

  void upsertOverride(String ruleId, RecurrenceOverride override) {
    final index = state.indexWhere((item) => item.id == ruleId);
    if (index == -1) return;
    final rule = state[index];
    final existingIdx = rule.overrides.indexWhere(
      (ov) => _sameDay(ov.originalDate, override.originalDate),
    );
    final newOverrides = List<RecurrenceOverride>.from(rule.overrides);
    if (existingIdx == -1) {
      newOverrides.add(override);
    } else {
      newOverrides[existingIdx] = override;
    }
    updateRule(rule.copyWith(overrides: newOverrides));
  }

  void updateOccurrence(
    String ruleId,
    DateTime originalDate, {
    DateTime? newTime,
    bool clearNewTime = false,
    int? newDurationMinutes,
    bool clearNewDurationMinutes = false,
    String? newContent,
    bool clearNewContent = false,
    String? newLocation,
    bool clearNewLocation = false,
  }) {
    final index = state.indexWhere((item) => item.id == ruleId);
    if (index == -1) return;
    final rule = state[index];
    RecurrenceOverride? existing;
    for (final item in rule.overrides) {
      if (_sameDay(item.originalDate, originalDate)) {
        existing = item;
        break;
      }
    }
    final override =
        existing?.copyWith(
          newTime: newTime,
          clearNewTime: clearNewTime,
          newDurationMinutes: newDurationMinutes,
          clearNewDurationMinutes: clearNewDurationMinutes,
          clearDurationMinutes: clearNewDurationMinutes,
          newContent: newContent,
          clearNewContent: clearNewContent,
          newLocation: newLocation,
          clearNewLocation: clearNewLocation,
          clearLocation: clearNewLocation,
        ) ??
        RecurrenceOverride(
          originalDate: DateTime(
            originalDate.year,
            originalDate.month,
            originalDate.day,
          ),
          newTime: newTime,
          newDurationMinutes: newDurationMinutes,
          clearDurationMinutes: clearNewDurationMinutes,
          newContent: newContent,
          newLocation: newLocation,
          clearLocation: clearNewLocation,
        );
    upsertOverride(ruleId, override);
  }

  void removeOverride(String ruleId, DateTime originalDate) {
    final index = state.indexWhere((item) => item.id == ruleId);
    if (index == -1) return;
    final rule = state[index];
    final newOverrides = rule.overrides
        .where((ov) => !_sameDay(ov.originalDate, originalDate))
        .toList();
    updateRule(rule.copyWith(overrides: newOverrides));
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void archiveRulesForTarget(String targetType, String targetId) {
    final matched = state.where(
      (item) => item.targetType == targetType && item.targetId == targetId,
    );
    for (final rule in matched) {
      updateRule(rule.copyWith(status: 'archived'));
    }
  }

  /// Temporarily archives only active reminders because their source item was
  /// completed. A separate marker makes the completion toggle reversible
  /// without restoring reminders that were already paused or disabled.
  void archiveActiveRulesForCompletion(String targetType, String targetId) {
    final matched = state.where(
      (item) =>
          item.targetType == targetType &&
          item.targetId == targetId &&
          item.isActive,
    );
    for (final rule in matched) {
      updateRule(
        rule.copyWith(status: 'archived', archivedByCompletion: true),
      );
    }
  }

  /// Temporarily archives only one-off reminders when a todo is completed.
  /// Recurring routines must stay active so their next occurrence can still
  /// reset the task and produce a future cue.
  void archiveActiveOneOffRulesForCompletion(
    String targetType,
    String targetId,
  ) {
    final matched = state.where(
      (item) =>
          item.targetType == targetType &&
          item.targetId == targetId &&
          item.isActive &&
          !_isRecurringSchedule(item.scheduleType),
    );
    for (final rule in matched) {
      updateRule(
        rule.copyWith(status: 'archived', archivedByCompletion: true),
      );
    }
  }

  /// Restores reminders that were archived as a side effect of completing
  /// their source event. This keeps an event's completion toggle reversible
  /// without changing rules that are still disabled or paused.
  void restoreArchivedRulesForTarget(String targetType, String targetId) {
    final matched = state.where(
      (item) =>
          item.targetType == targetType &&
          item.targetId == targetId &&
          item.status == 'archived',
    );
    for (final rule in matched) {
      updateRule(rule.copyWith(status: 'active'));
    }
  }

  /// Restores only rules archived by [archiveActiveRulesForCompletion].
  void restoreCompletedRulesForTarget(String targetType, String targetId) {
    final matched = state.where(
      (item) =>
          item.targetType == targetType &&
          item.targetId == targetId &&
          item.status == 'archived' &&
          item.archivedByCompletion,
    );
    for (final rule in matched) {
      updateRule(
        rule.copyWith(status: 'active', archivedByCompletion: false),
      );
    }
  }

  void pauseRules(Iterable<String> ids) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    for (final rule in state.where((item) => idSet.contains(item.id))) {
      updateRule(rule.copyWith(status: 'paused'));
    }
  }

  void disableRules(Iterable<String> ids) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    for (final rule in state.where((item) => idSet.contains(item.id))) {
      updateRule(rule.copyWith(status: 'disabled'));
    }
  }

  void disableRule(String id) {
    final index = state.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final updated = state[index].copyWith(status: 'disabled');
    updateRule(updated);
  }

  void archiveRule(String id) {
    final index = state.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final updated = state[index].copyWith(status: 'archived');
    updateRule(updated);
  }

  /// 真正删除一条提醒规则（非归档）。
  ///
  /// 如果规则关联了事件类型的目标 DiaryEntry，会向上级联删除该条目。
  void deleteRule(String id) {
    final rule = state.cast<ReminderRule?>().firstWhere(
      (r) => r?.id == id,
      orElse: () => null,
    );
    if (rule == null) return;

    state = state.where((item) => item.id != id).toList();
    Hive.box(DBService.reminderRuleBoxName).delete(id);

    // 向上级联：如果规则关联了 event 类型的 DiaryEntry，删除源条目
    _cascadeDeleteTargetEntry(rule);
  }

  void deleteRules(Iterable<String> ids) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;

    final toDelete = state.where((item) => idSet.contains(item.id)).toList();

    state = state.where((item) => !idSet.contains(item.id)).toList();
    final box = Hive.box(DBService.reminderRuleBoxName);
    for (final id in idSet) {
      box.delete(id);
    }

    for (final rule in toDelete) {
      _cascadeDeleteTargetEntry(rule);
    }
  }

  /// Removes a rule without touching its target item.
  ///
  /// Normal user deletion intentionally cascades to an event's source entry
  /// through [deleteRule]. Undo paths need the inverse operation instead: a
  /// reminder created by an edit should disappear while the event remains.
  void removeRuleWithoutCascade(String id) {
    if (!state.any((item) => item.id == id)) return;
    state = state.where((item) => item.id != id).toList();
    Hive.box(DBService.reminderRuleBoxName).delete(id);
  }

  /// 如果 [rule] 有 event 类型的 targetId，且目标条目仍存在，则级联删除它。
  void _cascadeDeleteTargetEntry(ReminderRule rule) {
    if (rule.targetType != 'event' || rule.targetId == null) return;

    // 检查目标条目是否还存在（可能已被前序级联操作删除）
    final entries = ref.read(allEntriesProvider);
    final targetExists = entries.any((e) => e.id == rule.targetId);
    if (!targetExists) return;

    ref.read(allEntriesProvider.notifier).deleteEntry(rule.targetId!);
  }
}
