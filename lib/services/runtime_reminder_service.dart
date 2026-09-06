import '../models/diary_entry.dart';
import '../models/reminder_rule.dart';
import '../models/todo_task.dart';
import 'recurrence_service.dart';

class RuntimeReminderHit {
  final ReminderRule rule;
  final DateTime occurrenceTime;
  final DateTime fireTime;
  final int advanceMinutes;

  const RuntimeReminderHit({
    required this.rule,
    required this.occurrenceTime,
    required this.fireTime,
    required this.advanceMinutes,
  });

  String get key =>
      '${rule.id}:${occurrenceTime.toIso8601String()}:$advanceMinutes';
}

class RuntimeReminderService {
  static const Duration defaultGraceWindow = Duration(minutes: 30);

  /// Returns whether a recurring-todo refresh should run for [now].
  ///
  /// The app invokes refresh on startup, midnight, and every resume. Keeping
  /// this date-only gate in the service prevents a daily task that was just
  /// completed from being reopened by a same-day resume callback.
  static bool shouldRefreshRecurringTodos(
    DateTime? lastRefreshDay,
    DateTime now,
  ) {
    if (lastRefreshDay == null) return true;
    return lastRefreshDay.year != now.year ||
        lastRefreshDay.month != now.month ||
        lastRefreshDay.day != now.day;
  }

  static List<ReminderRule> timelineFallbackRules(
    List<DiaryEntry> entries, {
    Set<String> ignoredEntryIds = const {},
  }) {
    return entries
        .where(
          (entry) =>
              entry.category == 'event' &&
              !entry.isArchived &&
              !entry.isCompleted &&
              entry.eventTime != null &&
              !ignoredEntryIds.contains(entry.id),
        )
        .map(
          (entry) => ReminderRule(
            id: 'timeline:${entry.id}',
            title: entry.content,
            targetType: 'event',
            targetId: entry.id,
            category: entry.tags.isEmpty ? 'timeline' : entry.tags.first,
            importance: 'important',
            disturbanceLevel: 'normal',
            scheduleType: 'once',
            anchorTime: entry.eventTime,
            advanceMinutes: const [10],
            note: entry.location,
            createdAt: entry.timestamp,
            updatedAt: entry.timestamp,
          ),
        )
        .toList();
  }

  /// 返回所有到期的提醒（不过滤 disturbanceLevel）。
  /// 调用方应根据 rule.disturbanceLevel 决定展示方式。
  static List<RuntimeReminderHit> dueReminders(
    List<ReminderRule> rules,
    DateTime now, {
    Duration graceWindow = defaultGraceWindow,
    Set<String> dismissedKeys = const {},
    Set<String> completedTodoIds = const {},
    Map<String, DateTime?> todoScheduledAt = const {},
    Map<String, DateTime?> eventTimes = const {},
  }) {
    final hits = <RuntimeReminderHit>[];
    for (final rule in rules) {
      // An execution reminder belongs to the task's current plan, not to a
      // copied timestamp on the rule. This matters for the portable tray
      // loop, which may run before the next full notification reconciliation.
      // Keep recurring rules on their own recurrence anchor; their schedule is
      // intentionally independent from a one-off task arrangement.
      final isOneOffExecutionReminder =
          rule.targetType == 'todo' &&
          rule.note == '事项提醒' &&
          rule.scheduleType == 'once' &&
          rule.targetId != null &&
          todoScheduledAt.containsKey(rule.targetId);
      final effectiveRule = isOneOffExecutionReminder
          ? (todoScheduledAt[rule.targetId] == null
                ? rule.copyWith(clearAnchorTime: true)
                : rule.copyWith(anchorTime: todoScheduledAt[rule.targetId]))
          : rule.targetType == 'event' &&
                rule.scheduleType == 'once' &&
                rule.targetId != null &&
                eventTimes.containsKey(rule.targetId)
          ? (eventTimes[rule.targetId] == null
                ? rule.copyWith(clearAnchorTime: true)
                : rule.copyWith(anchorTime: eventTimes[rule.targetId]))
          : rule;
      if (!effectiveRule.isActive || effectiveRule.anchorTime == null) {
        continue;
      }

      // A recurring todo is reset at the next calendar occurrence. While it
      // is completed, suppress runtime hits so finishing today's task does
      // not immediately produce another reminder from the same rule.
      if (rule.targetType == 'todo' &&
          rule.targetId != null &&
          completedTodoIds.contains(rule.targetId)) {
        continue;
      }

      // silent 级别不触发运行时通知（仅在早报中可见）
      if (effectiveRule.disturbanceLevel == 'silent') continue;
      final advances = effectiveRule.advanceMinutes.isEmpty
          ? const [10]
          : effectiveRule.advanceMinutes;
      final maxAdvance = advances.reduce((a, b) => a > b ? a : b);
      final occurrences = RecurrenceService.occurrencesBetween(
        effectiveRule,
        now.subtract(graceWindow),
        now.add(Duration(minutes: maxAdvance)),
      );
      for (final value in occurrences) {
        final occurrence = value.scheduledTime;
        for (final advance in advances) {
          final fireTime = occurrence.subtract(Duration(minutes: advance));
          final hit = RuntimeReminderHit(
            rule: rule,
            occurrenceTime: occurrence,
            fireTime: fireTime,
            advanceMinutes: advance,
          );
          if (dismissedKeys.contains(hit.key)) continue;
          if (_isDue(fireTime, now, graceWindow)) hits.add(hit);
        }
      }
    }
    hits.sort((a, b) => a.fireTime.compareTo(b.fireTime));
    return hits;
  }

  static bool _isDue(DateTime fireTime, DateTime now, Duration graceWindow) {
    return !fireTime.isAfter(now) &&
        fireTime.isAfter(now.subtract(graceWindow));
  }

  /// 计算需要重置的周期性待办。
  ///
  /// 重置日直接复用 [RecurrenceService] 的发生日判断，确保 weekly 的
  /// 多个星期、monthly 的 15/31 号以及 skip/end 边界都和提醒一致。
  static List<TodoTask> computeRecurringTodoResets(
    List<TodoTask> todos,
    List<ReminderRule> rules,
    DateTime now,
  ) {
    final updated = <TodoTask>[];
    final recurringRules = rules.where(
      (r) =>
          r.isActive &&
          r.targetType == 'todo' &&
          [
            'daily',
            'weekly',
            'every_n_days',
            'monthly',
          ].contains(r.scheduleType),
    );
    final recurringRuleByTodo = <String, ReminderRule>{};
    for (final rule in recurringRules) {
      final targetId = rule.targetId;
      if (targetId != null) recurringRuleByTodo[targetId] = rule;
    }

    for (final todo in todos) {
      if (!todo.isCompleted) continue;
      if (todo.isArchived) continue;
      final rule = recurringRuleByTodo[todo.id];
      if (rule == null) continue;
      if (_shouldResetForRule(rule, now)) {
        todo.isCompleted = false;
        updated.add(todo);
      }
    }
    return updated;
  }

  static bool _shouldResetForRule(ReminderRule rule, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    // Legacy daily rules may not have persisted an anchor time. Keep those
    // tasks usable while newer rules use the recurrence engine below.
    if (rule.anchorTime == null) {
      return rule.scheduleType == 'daily' ||
          (rule.scheduleType == 'weekly' && now.weekday == DateTime.monday);
    }
    return RecurrenceService.occurrenceOn(rule, today) != null;
  }
}
