import '../../models/diary_entry.dart';
import '../../models/recurrence_override.dart';
import '../../models/reminder_rule.dart';
import '../../models/todo_task.dart';
import '../../models/unified_item.dart';
import '../../providers/reminder_rule_provider.dart';
import '../../services/planner_service.dart';
import '../../services/recurrence_service.dart';

enum TimelineDayItemType { event, deadline, todo }

enum TimelineFloatingTodoPolicy { include, exclude }

class TimelineDayItem {
  final TimelineDayItemType type;
  final String id;
  final String title;
  final DateTime? time;
  final DateTime? endTime;
  final String? meta;
  final bool isCompleted;

  /// 关联的 ReminderRule.id，仅投影事件有值。用于完成操作时找到对应规则。
  final String? ruleId;

  /// 本次投影对应的窗口起始投影日。用于在 overrides 中匹配。
  final DateTime? projectionDate;

  // ── spanning 视觉标记 ──
  final bool isSpanningStart;
  final bool isSpanningEnd;
  final bool isSpanningMiddle;

  /// 同一条 spanning 事件的跨天标识。格式: "{ruleId}:{projectionDate}"。
  final String? spanningGroupId;

  const TimelineDayItem({
    required this.type,
    required this.id,
    required this.title,
    this.time,
    this.endTime,
    this.meta,
    this.isCompleted = false,
    this.ruleId,
    this.projectionDate,
    this.isSpanningStart = false,
    this.isSpanningEnd = false,
    this.isSpanningMiddle = false,
    this.spanningGroupId,
  });
}

class TimelineDaySummary {
  final DateTime day;
  final List<DiaryEntry> events;
  final List<TodoTask> deadlineTodos;
  final List<TodoTask> actionTodos;
  final List<TimelineDayItem> items;

  /// Completed todos that should still be visible for this day.
  final List<TodoTask> completedTodos;

  const TimelineDaySummary({
    required this.day,
    required this.events,
    required this.deadlineTodos,
    required this.actionTodos,
    required this.items,
    this.completedTodos = const [],
  });

  int get eventCount => events.length;
  int get deadlineCount => deadlineTodos.length;
  int get todoCount => actionTodos.length;
  int get completedCount => completedTodos.length;
  int get totalCount => eventCount + deadlineCount + todoCount;
}

class WeekTimelineSummary {
  final DateTime weekStart;
  final List<TimelineDaySummary> days;

  const WeekTimelineSummary({required this.weekStart, required this.days});

  int get eventCount => days.fold(0, (total, day) => total + day.eventCount);
  int get deadlineCount =>
      days.fold(0, (total, day) => total + day.deadlineCount);
  int get todoCount => days.fold(0, (total, day) => total + day.todoCount);
  int get completedCount =>
      days.fold(0, (total, day) => total + day.completedCount);
}

bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

TimelineDaySummary buildTimelineDaySummary({
  required DateTime day,
  required List<DiaryEntry> events,
  required List<TodoTask> todos,
  List<String>? completedPriorityFilter,
  List<String>? actionPriorityFilter,
  TimelineFloatingTodoPolicy floatingTodoPolicy =
      TimelineFloatingTodoPolicy.include,
  bool includeOverdueDeadlines = true,
  List<ReminderRule>? rules,
}) {
  final dayEvents =
      events
          .where((entry) => isSameDay(entry.sortTime, day))
          .map((entry) {
            final rule = _resolveEventRule(entry, events, rules ?? []);
            if (rule == null) return entry;
            for (final override in rule.overrides) {
              if (isSameDay(override.originalDate, entry.sortTime)) {
                return _applyOverride(entry, override);
              }
            }
            return entry;
          })
          // An anchor occurrence can be moved to another date. It was selected
          // above by its source date, so filter again after applying the override
          // to keep the old day from retaining a ghost entry.
          .where((entry) => isSameDay(entry.sortTime, day))
          .toList()
        ..sort((a, b) => a.sortTime.compareTo(b.sortTime));

  // 虚拟投影：将重复事件的投影加入当天
  final projectedEvents = projectRecurringEvents(
    day: day,
    events: events,
    rules: rules ?? [],
  );
  final allDayEvents = [...dayEvents, ...projectedEvents]
    ..sort((a, b) => a.sortTime.compareTo(b.sortTime));

  // 防止同一日内出现重复事件条目（如真实事件和投影事件时间、标题相同）
  final dedupedDayEvents = _dedupeDayEvents(allDayEvents);

  final eventSourceIds = events.map((entry) => entry.id).toSet();

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  // 包含已完成待办：勾选后留在原位划线，不消失。
  // 无截止日期的浮动待办完成后只在当天可见。
  final todosForDay = todos.where((todo) {
    if (todo.isArchived) return false;
    final scheduledOnAnotherDay =
        todo.scheduledAt != null &&
        !isSameDay(todo.scheduledAt!, day) &&
        (todo.deadline == null || !isSameDay(todo.deadline!, day));
    if (scheduledOnAnotherDay &&
        !(isSameDay(day, today) &&
            shouldSurfaceMissedScheduledTodo(todo, now))) {
      return false;
    }
    if (todo.isCompleted && todo.deadline == null && !isSameDay(day, today)) {
      return false;
    }
    // 应用 completedPriorityFilter：已完成待办的优先级过滤
    if (todo.isCompleted &&
        completedPriorityFilter != null &&
        !completedPriorityFilter.contains(todo.priority)) {
      return false;
    }
    return true;
  }).toList();

  final deadlineTodos =
      todosForDay
          .where(
            (todo) =>
                todo.deadline != null &&
                _isDeadlineVisibleOnDay(
                  todo.deadline!,
                  day,
                  includeOverdueDeadlines,
                ) &&
                !isRoutineTodo(todo.id, rules ?? []) &&
                !_isSyncedFromTimelineEvent(todo, eventSourceIds) &&
                _matchesPriorityFilter(todo, actionPriorityFilter),
          )
          .toList()
        ..sort(_compareTodosForDay(day));

  final deadlineIds = deadlineTodos.map((todo) => todo.id).toSet();
  final actionTodos =
      todosForDay
          .where(
            (todo) =>
                !deadlineIds.contains(todo.id) &&
                !isRoutineTodo(todo.id, rules ?? []) &&
                !_isSyncedFromTimelineEvent(todo, eventSourceIds) &&
                _isActionTodoVisibleOnDay(todo, day, now) &&
                _matchesFloatingTodoPolicy(todo, floatingTodoPolicy) &&
                _matchesPriorityFilter(todo, actionPriorityFilter),
          )
          .toList()
        ..sort(_compareTodosForDay(day));

  // 已完成计数（用于头部 chip 统计）
  final completedTodos = <TodoTask>[
    ...deadlineTodos.where((t) => t.isCompleted),
    ...actionTodos.where((t) => t.isCompleted),
  ]..sort(_compareTodosForDay(day));

  final items = [
    ...dedupedDayEvents.map((entry) {
      // 尝试找到关联的 rule 和投影信息
      final rule = _resolveEventRule(entry, events, rules ?? []);
      final projDate = rule != null
          ? lastProjectionDay(
              rule,
              DateTime(
                entry.sortTime.year,
                entry.sortTime.month,
                entry.sortTime.day,
              ),
              rule.anchorTime ?? entry.sortTime,
            )
          : null;

      return TimelineDayItem(
        type: TimelineDayItemType.event,
        id: entry.id,
        title: compactItemTitle(
          entry.content.trim().isNotEmpty
              ? entry.content
              : entry.aiSummary ?? '',
        ),
        time: entry.sortTime,
        endTime: entry.endTime,
        meta: entry.location,
        isCompleted: entry.isCompleted,
        ruleId: rule?.id,
        projectionDate: projDate,
      );
    }),
    ...deadlineTodos.map(
      (todo) => TimelineDayItem(
        type: TimelineDayItemType.deadline,
        id: todo.id,
        title: todo.title,
        time: todo.deadline,
        meta: 'deadline',
      ),
    ),
    ...actionTodos.map((todo) {
      final missed =
          isSameDay(day, now) && shouldSurfaceMissedScheduledTodo(todo, now);
      return TimelineDayItem(
        type: TimelineDayItemType.todo,
        id: todo.id,
        title: todo.title,
        // A missed plan is shown as a carryover, not with yesterday's clock
        // time rendered as if it belonged to today.
        time: missed ? null : todo.scheduledAt ?? todo.deadline,
        meta: missed
            ? 'missed'
            : todo.scheduledAt == null
            ? 'today'
            : 'scheduled',
      );
    }),
  ];

  return TimelineDaySummary(
    day: day,
    events: dedupedDayEvents,
    deadlineTodos: deadlineTodos,
    actionTodos: actionTodos,
    items: items,
    completedTodos: completedTodos,
  );
}

WeekTimelineSummary buildWeekTimelineSummary({
  required DateTime weekStart,
  required List<DiaryEntry> events,
  required List<TodoTask> todos,
  List<String>? completedPriorityFilter,
  List<String>? actionPriorityFilter = const ['A', 'B'],
  TimelineFloatingTodoPolicy floatingTodoPolicy =
      TimelineFloatingTodoPolicy.exclude,
  List<ReminderRule>? rules,
}) {
  // Build individual day summaries first
  final rawDays = List.generate(
    7,
    (index) => buildTimelineDaySummary(
      day: weekStart.add(Duration(days: index)),
      events: events,
      todos: todos,
      completedPriorityFilter: completedPriorityFilter,
      actionPriorityFilter: actionPriorityFilter,
      floatingTodoPolicy: floatingTodoPolicy,
      includeOverdueDeadlines: false,
      rules: rules,
    ),
  );

  // Collect all items across all days for spanning boundary marking
  final allItems = <TimelineDayItem>[];
  final dayItemCounts = <int>[];
  for (final day in rawDays) {
    dayItemCounts.add(day.items.length);
    allItems.addAll(day.items);
  }

  // Mark spanning boundaries on the flat list
  _markSpanningBoundaries(allItems, rules ?? []);

  // Redistribute items back to each day and rebuild summaries
  final days = <TimelineDaySummary>[];
  var offset = 0;
  for (var i = 0; i < 7; i++) {
    final count = dayItemCounts[i];
    final dayItems = allItems.sublist(offset, offset + count);
    offset += count;
    days.add(
      TimelineDaySummary(
        day: rawDays[i].day,
        events: rawDays[i].events,
        deadlineTodos: rawDays[i].deadlineTodos,
        actionTodos: rawDays[i].actionTodos,
        items: dayItems,
        completedTodos: rawDays[i].completedTodos,
      ),
    );
  }

  return WeekTimelineSummary(weekStart: weekStart, days: days);
}

int Function(TodoTask a, TodoTask b) _compareTodosForDay(DateTime day) {
  return (a, b) {
    // 已完成排在未完成之后
    if (a.isCompleted != b.isCompleted) {
      return a.isCompleted ? 1 : -1;
    }

    final deadlineCompare = _deadlineRank(
      a,
      day,
    ).compareTo(_deadlineRank(b, day));
    if (deadlineCompare != 0) return deadlineCompare;

    final priorityCompare = _priorityRank(
      a.priority,
    ).compareTo(_priorityRank(b.priority));
    if (priorityCompare != 0) return priorityCompare;

    return a.createdAt.compareTo(b.createdAt);
  };
}

int _deadlineRank(TodoTask todo, DateTime day) {
  final deadline = todo.deadline;
  if (deadline == null) return 2;
  if (deadline.isBefore(DateTime(day.year, day.month, day.day))) return 0;
  return isSameDay(deadline, day) ? 1 : 2;
}

int _priorityRank(String priority) {
  return switch (priority) {
    'A' => 0,
    'B' => 1,
    _ => 2,
  };
}

DateTime _endOfDay(DateTime day) {
  return DateTime(day.year, day.month, day.day, 23, 59, 59, 999);
}

bool _isDeadlineVisibleOnDay(
  DateTime deadline,
  DateTime day,
  bool includeOverdueDeadlines,
) {
  if (includeOverdueDeadlines) return !deadline.isAfter(_endOfDay(day));
  return isSameDay(deadline, day);
}

bool _matchesPriorityFilter(TodoTask todo, List<String>? priorityFilter) {
  return priorityFilter == null || priorityFilter.contains(todo.priority);
}

/// A future-deadline todo is not today's action until it is explicitly
/// scheduled for today. Floating todos without a deadline remain eligible for
/// the caller's "later" or backlog treatment.
bool _isActionTodoVisibleOnDay(TodoTask todo, DateTime day, DateTime now) {
  final scheduledAt = todo.scheduledAt;
  if (scheduledAt != null) {
    if (isSameDay(scheduledAt, day)) return true;
    // Keep a missed execution on today's plan until it is rescheduled. A
    // deadline shown in the separate deadline lane wins over this carryover
    // path, preventing duplicate rows.
    return isSameDay(day, now) && shouldSurfaceMissedScheduledTodo(todo, now);
  }
  return todo.deadline == null;
}

bool _matchesFloatingTodoPolicy(
  TodoTask todo,
  TimelineFloatingTodoPolicy policy,
) {
  return switch (policy) {
    TimelineFloatingTodoPolicy.include => true,
    // A task explicitly placed on a day is no longer floating and should be
    // visible in the weekly board. Unscheduled tasks remain in the strip.
    TimelineFloatingTodoPolicy.exclude => todo.scheduledAt != null,
  };
}

bool _isSyncedFromTimelineEvent(TodoTask todo, Set<String> eventSourceIds) {
  final sourceEntryId = todo.sourceEntryId;
  return sourceEntryId != null && eventSourceIds.contains(sourceEntryId);
}

/// 去重同一来源的重复投影，但不要吞掉不同来源的同名事件。
///
/// 一个真实事件和它的投影副本会共享来源 ID 与时间；两门同名、同刻
/// 的课程仍然拥有不同 ID，必须都保留，才能让学生看见真实冲突。
List<DiaryEntry> _dedupeDayEvents(List<DiaryEntry> events) {
  final seen = <String>{};
  return events.where((entry) {
    final key = '${entry.id}|${entry.sortTime.toIso8601String()}';
    return seen.add(key);
  }).toList();
}

/// 为事件条目查找关联的活跃 ReminderRule。
/// 返回 null 表示该事件没有活跃的重复规则（即不是投影事件）。
ReminderRule? _resolveEventRule(
  DiaryEntry entry,
  List<DiaryEntry> allEvents,
  List<ReminderRule> rules,
) {
  if (entry.category != 'event') return null;
  for (final rule in rules) {
    if (rule.isActive &&
        rule.targetType == 'event' &&
        rule.targetId == entry.id &&
        rule.scheduleType != 'once' &&
        rule.scheduleType != 'custom') {
      return rule;
    }
  }
  return null;
}

// ── 重复事件虚拟投影 ──

/// 为当天生成重复事件的虚拟投影条目。
///
/// 对于 [events] 中 category='event' 且关联了活跃 ReminderRule 的条目，
/// 当规则的 scheduleType 匹配 [day] 时，生成一个 eventTime 锚定到当天的
/// 投影副本。已在当天有真实 eventTime 的条目不投影（去重）。
List<DiaryEntry> projectRecurringEvents({
  required DateTime day,
  required List<DiaryEntry> events,
  required List<ReminderRule> rules,
}) {
  // 构建 targetId → rule 的快速查找表（仅活跃的 event 类型规则）
  final ruleByTargetId = <String, ReminderRule>{};
  for (final rule in rules) {
    if (rule.isActive &&
        rule.targetType == 'event' &&
        rule.targetId != null &&
        rule.scheduleType != 'once' &&
        rule.scheduleType != 'custom') {
      ruleByTargetId[rule.targetId!] = rule;
    }
  }
  if (ruleByTargetId.isEmpty) return const [];

  final projected = <DiaryEntry>[];
  for (final entry in events) {
    if (entry.category != 'event') continue;
    final rule = ruleByTargetId[entry.id];
    if (rule == null) continue;

    // 去重：如果原始 entry 的 sortTime 就在当天，不投影
    if (isSameDay(entry.sortTime, day)) continue;

    // 检查规则是否应该投影到今天
    final anchorTime = rule.anchorTime ?? entry.sortTime;
    if (rule.displayMode == 'punctual') {
      final dayStart = DateTime(day.year, day.month, day.day);
      final dayEnd = dayStart
          .add(const Duration(days: 1))
          .subtract(const Duration(microseconds: 1));
      // A moved instance may share its destination day with a native
      // recurrence. Keep every occurrence instead of taking only the first
      // one, otherwise the moved class silently disappears from the planner.
      final occurrences = RecurrenceService.occurrencesBetween(
        rule,
        dayStart,
        dayEnd,
      );
      for (final occurrence in occurrences) {
        var projectedEntry = _projectEntry(entry, occurrence.scheduledTime);
        final recurrenceOverride = occurrence.override;
        if (recurrenceOverride != null) {
          projectedEntry = _applyOverride(projectedEntry, recurrenceOverride);
          projectedEntry = projectedEntry.copyWith(
            eventTime: occurrence.scheduledTime,
          );
        }
        projected.add(projectedEntry);
      }
      continue;
    }
    if (!_isInActiveWindow(rule, day, anchorTime)) continue;

    // 找到本次投影的「投影日」（用于 skip/override 匹配）
    final lastProj = lastProjectionDay(rule, day, anchorTime);
    if (lastProj == null) continue;

    // ── 例外系统 ──

    // 检查 skipDates：如果本次投影日被跳过，整个窗口不显示
    final projDate = DateTime(lastProj.year, lastProj.month, lastProj.day);
    if (rule.skipDates.any((skip) => isSameDay(skip, projDate))) continue;

    // 生成默认投影
    var projectedEntry = _projectEntry(entry, day);

    // 检查 overrides：找到匹配本次投影日的覆盖
    RecurrenceOverride? matchedOverride;
    for (final ov in rule.overrides) {
      if (isSameDay(ov.originalDate, projDate)) {
        matchedOverride = ov;
        break;
      }
    }
    if (matchedOverride != null) {
      // 完成的重复实例不再显示；下一次 occurrence 会重新投影为未完成。
      // 这保持“完成后收起”语义，避免周视图被历史课次重新撑高。
      if (matchedOverride.isCompleted) {
        continue;
      }
      projectedEntry = _applyOverride(projectedEntry, matchedOverride);
    }

    projected.add(projectedEntry);
  }

  return projected;
}

/// 判断 [day] 是否落在 [rule] 的某个活跃投影窗口内。
bool _isInActiveWindow(ReminderRule rule, DateTime day, DateTime anchor) {
  // 1. 起始日检查
  final start = rule.startDate ?? anchor;
  final today = DateTime(day.year, day.month, day.day);
  final startDay = DateTime(start.year, start.month, start.day);
  if (today.isBefore(startDay)) return false;

  // 2. 截止日检查
  if (rule.endDate != null) {
    final endDay = DateTime(
      rule.endDate!.year,
      rule.endDate!.month,
      rule.endDate!.day,
    );
    if (today.isAfter(endDay)) return false;
  }

  // 3. 截止次数检查
  if (rule.endCount != null) {
    // 找到最近一次投影日并计算其序号
    // 如果当前窗口的序号 > endCount，不显示
    final projDay = lastProjectionDay(rule, today, anchor);
    if (projDay == null) return false;
    final occurrenceIndex = _occurrenceIndex(rule, projDay, anchor);
    if (occurrenceIndex >= rule.endCount!) return false;
  }

  // 4. 找到最近一次投影日
  final lastProj = lastProjectionDay(rule, today, anchor);
  if (lastProj == null) return false;

  // 5. 点事件：必须在投影日当天
  if (rule.displayMode == 'punctual') {
    return isSameDay(today, lastProj);
  }

  // 6. 自定义窗口：投影日 + customSpanDays
  if (rule.displayMode == 'customSpan') {
    final spanDays = rule.customSpanDays ?? 1;
    final windowEnd = lastProj.add(Duration(days: spanDays));
    return !today.isBefore(lastProj) && today.isBefore(windowEnd);
  }

  // 7. 跨期任务
  if (rule.displayMode == 'spanning') {
    final nextProj = _nextProjectionDay(rule, lastProj, anchor);
    return !today.isBefore(lastProj) && today.isBefore(nextProj);
  }

  return false;
}

/// 找到不晚于 [day] 的最近一次投影日。
///
/// 返回 null 表示 [day] 早于锚点日且不应有投影。
DateTime? lastProjectionDay(ReminderRule rule, DateTime day, DateTime anchor) {
  return RecurrenceService.lastProjectionDay(rule, day);
}

/// 找到 [lastProj] 之后的下一次投影日。
DateTime _nextProjectionDay(
  ReminderRule rule,
  DateTime lastProj,
  DateTime anchor,
) {
  return RecurrenceService.nextProjectionDay(rule, lastProj);
}

/// 计算 [projDay] 是从 anchor 开始的第几次投影（0-indexed）。
int _occurrenceIndex(ReminderRule rule, DateTime projDay, DateTime anchor) {
  return RecurrenceService.occurrenceIndex(rule, projDay);
}

/// 将 [original] 投影到 [targetDay]，保留原始时分。
///
/// 投影永远以未完成状态开始；完成状态由 overrides 单独追踪。
DiaryEntry _projectEntry(DiaryEntry original, DateTime targetDay) {
  final time = original.eventTime ?? original.timestamp;
  return original.copyWith(
    eventTime: DateTime(
      targetDay.year,
      targetDay.month,
      targetDay.day,
      time.hour,
      time.minute,
    ),
    isCompleted: false,
  );
}

/// 将 [override] 应用到投影条目 [projected] 上。
DiaryEntry _applyOverride(DiaryEntry projected, RecurrenceOverride override) {
  final changedTime = override.newTime;
  final changedDay =
      changedTime != null && !isSameDay(changedTime, override.originalDate);
  final eventDay = changedDay ? changedTime : projected.sortTime;
  return projected.copyWith(
    content: override.newContent ?? projected.content,
    eventTime: changedTime != null
        ? DateTime(
            eventDay.year,
            eventDay.month,
            eventDay.day,
            changedTime.hour,
            changedTime.minute,
          )
        : projected.eventTime,
    location: override.clearLocation
        ? null
        : override.newLocation ?? projected.location,
    clearLocation: override.clearLocation,
    durationMinutes: override.clearDurationMinutes
        ? null
        : override.newDurationMinutes ?? projected.durationMinutes,
    clearDurationMinutes: override.clearDurationMinutes,
    isCompleted: override.isCompleted,
  );
}

// ── spanning 视觉边界标记 ──

/// 为 event 类型的 spanning 条目标记窗口边界。
///
/// 同一个 event 在一段连续日期内出现时，首日标记 [isSpanningStart]，
/// 末日标记 [isSpanningEnd]，中间日标记 [isSpanningMiddle]。
/// 仅在 [items] 参数来源于同一个周/月视图的连续日期时有效。
void _markSpanningBoundaries(
  List<TimelineDayItem> items,
  List<ReminderRule> rules,
) {
  // 构建 ruleId → rule 的查找表
  final ruleById = <String, ReminderRule>{};
  for (final r in rules) {
    ruleById[r.id] = r;
  }

  // 按 spanning group 分组索引
  final groups = <String, List<int>>{};
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    if (item.type != TimelineDayItemType.event ||
        item.ruleId == null ||
        item.projectionDate == null) {
      continue;
    }

    final rule = ruleById[item.ruleId];
    if (rule == null || rule.displayMode != 'spanning') {
      continue;
    }

    final groupId = '${item.ruleId}:${item.projectionDate!.toIso8601String()}';
    groups.putIfAbsent(groupId, () => []).add(i);
  }

  // 标记每个组的边界
  for (final entry in groups.entries) {
    final indices = entry.value;
    if (indices.isEmpty) continue;

    final firstIdx = indices.first;
    final lastIdx = indices.last;

    for (final idx in indices) {
      items[idx] = TimelineDayItem(
        type: items[idx].type,
        id: items[idx].id,
        title: items[idx].title,
        time: items[idx].time,
        endTime: items[idx].endTime,
        meta: items[idx].meta,
        isCompleted: items[idx].isCompleted,
        ruleId: items[idx].ruleId,
        projectionDate: items[idx].projectionDate,
        isSpanningStart: idx == firstIdx,
        isSpanningEnd: idx == lastIdx,
        isSpanningMiddle: idx != firstIdx && idx != lastIdx,
        spanningGroupId: entry.key,
      );
    }
  }
}
