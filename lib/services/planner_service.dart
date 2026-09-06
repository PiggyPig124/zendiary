import '../models/diary_entry.dart';
import '../models/todo_task.dart';

class PlannerConflict {
  final DiaryEntry first;
  final DiaryEntry second;

  const PlannerConflict({required this.first, required this.second});
}

/// A lightweight, non-persistent suggestion for when an unscheduled todo
/// could be worked on. The suggestion never changes the todo by itself; the
/// caller must explicitly apply it.
class TodoPlanningSuggestion {
  final DateTime scheduledAt;
  final String reason;

  const TodoPlanningSuggestion({
    required this.scheduledAt,
    required this.reason,
  });
}

/// Keeps several todo titles extracted from one timed capture from silently
/// sharing the exact same execution block. The first task keeps the user's
/// explicit time; following tasks get a small editable offset. This is only a
/// capture-time default—the student can still move each task independently.
DateTime? staggerCapturedTodoSchedule(DateTime? anchor, int index, {
  int spacingMinutes = 30,
}) {
  if (anchor == null || index <= 0) return anchor;
  final spacing = spacingMinutes.clamp(5, 480);
  return anchor.add(Duration(minutes: index * spacing));
}

enum DayLoadLevel { light, balanced, full, overloaded }

/// Returns the amount of focused work a todo should occupy when it is placed
/// on the plan. Older tasks have no estimate and intentionally retain the
/// original 30-minute fallback.
int todoPlanningMinutes(TodoTask todo, {int fallback = 30}) {
  final value = todo.estimatedMinutes ?? fallback;
  return value.clamp(5, 480).toInt();
}

/// Returns a short, user-facing warning when a planned execution block cannot
/// finish by the todo's deadline. This is deliberately derived rather than
/// persisted: changing the estimate, plan time, or deadline immediately
/// updates the warning without creating another piece of state to reconcile.
String? todoScheduleDeadlineWarning(TodoTask todo) {
  final scheduledAt = todo.scheduledAt;
  final deadline = todo.deadline;
  if (todo.isCompleted || todo.isArchived || scheduledAt == null || deadline == null) {
    return null;
  }
  final plannedEnd = scheduledAt.add(
    Duration(minutes: todoPlanningMinutes(todo)),
  );
  if (!plannedEnd.isAfter(deadline)) return null;
  return scheduledAt.isAfter(deadline) ? '计划晚于截止' : '预计完成会晚于截止';
}

/// A compact workload summary for the execution page. Only time that has
/// actually been placed on the day counts here: a floating backlog item does
/// not make Today look busy until the student chooses to schedule it.
class DayLoad {
  final int eventMinutes;
  final int todoMinutes;

  const DayLoad({required this.eventMinutes, required this.todoMinutes});

  int get totalMinutes => eventMinutes + todoMinutes;

  DayLoadLevel get level {
    if (totalMinutes <= 180) return DayLoadLevel.light;
    if (totalMinutes <= 360) return DayLoadLevel.balanced;
    if (totalMinutes <= 480) return DayLoadLevel.full;
    return DayLoadLevel.overloaded;
  }

  String get label {
    if (totalMinutes < 60) return '$totalMinutes 分钟';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return minutes == 0 ? '$hours 小时' : '$hours 小时 $minutes 分';
  }

  String get levelLabel => switch (level) {
    DayLoadLevel.light => '轻松',
    DayLoadLevel.balanced => '适中',
    DayLoadLevel.full => '偏满',
    DayLoadLevel.overloaded => '很满',
  };
}

DayLoad buildDayLoad({
  required DateTime day,
  required Iterable<DiaryEntry> events,
  required Iterable<TodoTask> todos,
  int defaultTodoMinutes = 30,
  Set<String> excludedTodoIds = const <String>{},
}) {
  final dayStart = DateTime(day.year, day.month, day.day);
  final dayEnd = dayStart.add(const Duration(days: 1));
  var eventMinutes = 0;
  final seenEvents = <String>{};
  for (final event in events) {
    if (event.category != 'event' || event.isArchived) continue;
    final start = event.eventTime;
    final end = event.endTime;
    if (start == null || end == null) continue;
    final key =
        '${event.id}|${start.toIso8601String()}|${end.toIso8601String()}';
    if (!seenEvents.add(key)) continue;
    final overlapStart = start.isAfter(dayStart) ? start : dayStart;
    final overlapEnd = end.isBefore(dayEnd) ? end : dayEnd;
    if (overlapEnd.isAfter(overlapStart)) {
      eventMinutes += overlapEnd.difference(overlapStart).inMinutes;
    }
  }

  final todoMinutes = todos
      .where(
        (todo) =>
            !todo.isCompleted &&
            !todo.isArchived &&
            !excludedTodoIds.contains(todo.id) &&
            todo.scheduledAt != null &&
            _isSameDay(todo.scheduledAt!, day),
      )
      .fold<int>(
        0,
        (total, todo) =>
            total + todoPlanningMinutes(todo, fallback: defaultTodoMinutes),
      );
  return DayLoad(eventMinutes: eventMinutes, todoMinutes: todoMinutes);
}

bool _isSameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

/// The planning moment shown on the Today page. This is deliberately based
/// on the local clock rather than a persisted flag: the student can open the
/// app for the first time at any point in the day and still get an honest
/// next step.
enum TodayPlanningMoment { startOfDay, betweenPlans, evening }

TodayPlanningMoment todayPlanningMoment(DateTime now) {
  final minutes = now.hour * 60 + now.minute;
  if (minutes < 11 * 60) return TodayPlanningMoment.startOfDay;
  if (minutes < 20 * 60) return TodayPlanningMoment.betweenPlans;
  return TodayPlanningMoment.evening;
}

String todayPlanningMessage(DateTime now, {required int candidateCount}) {
  if (candidateCount == 0) return '没有必须今天的待办；需要时再手动安排一项。';
  return switch (todayPlanningMoment(now)) {
    TodayPlanningMoment.startOfDay => '打开今天先安排下一项；做完后再安排下一项，其余待办先留在收件箱。',
    TodayPlanningMoment.betweenPlans => '白天按节奏推进：完成当前事项后，再安排下一项，不一次塞满今天。',
    TodayPlanningMoment.evening => '今天已经比较晚了：只安排必须今天推进的事项，其余留到明天。',
  };
}

String todayPlanningActionLabel(DateTime now) {
  return switch (todayPlanningMoment(now)) {
    TodayPlanningMoment.startOfDay => '安排下一项',
    TodayPlanningMoment.betweenPlans => '安排下一空档',
    TodayPlanningMoment.evening => '安排必须项',
  };
}

/// How many unscheduled recommendations the one-tap action may place at this
/// planning moment. The picker remains available for intentional exceptions;
/// this limit keeps the default action from turning Today into a backlog.
int todayPlanningBatchLimit(DateTime now) {
  return switch (todayPlanningMoment(now)) {
    // The low-friction action is intentionally one task at a time. The
    // picker still supports up to three when the student explicitly wants a
    // larger morning plan.
    TodayPlanningMoment.startOfDay => 1,
    TodayPlanningMoment.betweenPlans => 1,
    TodayPlanningMoment.evening => 1,
  };
}

/// Decides whether an unscheduled task deserves a slot on the Today page.
///
/// A plain, medium-priority task has no evidence that it must happen today;
/// showing every such task would turn the execution page back into a backlog.
/// We surface tasks with a near deadline, an opening time today, or explicit
/// top priority. The suggestion itself is still opt-in and never persists a
/// schedule automatically.
bool shouldRecommendTodoToday(TodoTask todo, DateTime now) {
  if (todo.isCompleted || todo.isArchived) return false;

  final today = DateTime(now.year, now.month, now.day);
  final opensAt = todo.opensAt;
  if (opensAt != null) {
    final opensDay = DateTime(opensAt.year, opensAt.month, opensAt.day);
    if (opensDay.isAfter(today)) return false;
    if (opensDay == today) return true;
  }

  final deadline = todo.deadline;
  if (deadline != null) {
    final planningDay = DateTime(
      deadline.year,
      deadline.month,
      deadline.day,
    ).subtract(const Duration(days: 2));
    if (!planningDay.isAfter(today)) return true;
  }

  return todo.priority == 'A';
}

/// Returns whether an unscheduled task has a concrete reason to be placed on
/// the current day even when the student opens ZenDiary late in the evening.
///
/// A high-priority label by itself is not enough at night: without a deadline
/// or opening date it is still backlog, and promoting it into Today would
/// recreate the overloaded execution page this planner is meant to avoid.
bool isMustPlanToday(TodoTask todo, DateTime now) {
  if (todo.isCompleted || todo.isArchived) return false;
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));
  final endOfTomorrow = DateTime(
    tomorrow.year,
    tomorrow.month,
    tomorrow.day,
    23,
    59,
    59,
    999,
  );
  final opensAt = todo.opensAt;
  if (opensAt != null && _sameDay(opensAt, today)) return true;
  final deadline = todo.deadline;
  return deadline != null && !deadline.isAfter(endOfTomorrow);
}

bool isTodoOpenAt(TodoTask todo, DateTime now) {
  final opensAt = todo.opensAt;
  return opensAt == null || !now.isBefore(opensAt);
}

/// A scheduled execution that was missed should remain visible on the
/// current execution day until the student explicitly moves it again. Tasks
/// whose deadline is already visible today are handled by the deadline lane,
/// so this helper keeps the two lanes disjoint.
bool shouldSurfaceMissedScheduledTodo(TodoTask todo, DateTime now) {
  if (todo.isCompleted || todo.isArchived || todo.scheduledAt == null) {
    return false;
  }
  if (!isTodoOpenAt(todo, now)) return false;
  // A plan that has already passed today is just as missed as one carried
  // over from yesterday. Comparing against the current clock keeps Today
  // honest after a student returns from class in the afternoon.
  if (!todo.scheduledAt!.isBefore(now)) return false;
  final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
  final deadline = todo.deadline;
  // A deadline due today or earlier belongs to the deadline/overdue lane.
  if (deadline != null && !deadline.isAfter(endOfToday)) return false;
  return true;
}

TodoPlanningSuggestion? suggestTodoSchedule(TodoTask todo, DateTime now) {
  if (todo.isCompleted) return null;

  final today = DateTime(now.year, now.month, now.day);
  final opensDay = todo.opensAt == null
      ? null
      : DateTime(todo.opensAt!.year, todo.opensAt!.month, todo.opensAt!.day);
  final deadlineDay = todo.deadline == null
      ? null
      : DateTime(todo.deadline!.year, todo.deadline!.month, todo.deadline!.day);

  late DateTime suggestedDay;
  late String reason;
  if (opensDay != null && opensDay.isAfter(today)) {
    suggestedDay = opensDay;
    reason = '开放后开始';
  } else if (deadlineDay != null) {
    final twoDaysBefore = deadlineDay.subtract(const Duration(days: 2));
    suggestedDay = twoDaysBefore.isBefore(today) ? today : twoDaysBefore;
    reason = suggestedDay == today ? '截止临近' : '截止前 2 天';
    if (opensDay != null && suggestedDay.isBefore(opensDay)) {
      suggestedDay = opensDay;
      reason = '开放日';
    }
  } else {
    suggestedDay = today;
    reason = '今天开始';
  }

  final suggestedTime = suggestedDay == today
      ? suggestedTodoScheduleTime(now, notBefore: todo.opensAt)
      : null;
  return TodoPlanningSuggestion(
    scheduledAt: DateTime(
      suggestedDay.year,
      suggestedDay.month,
      suggestedDay.day,
      suggestedTime?.hour ?? 9,
      suggestedTime?.minute ?? 0,
    ),
    reason: reason,
  );
}

/// Returns a future, low-friction time when a student chooses “安排今天”.
///
/// Before 09:00 we keep the plan at the start of the study day. Afterwards
/// we use the next quarter-hour instead of putting the task in the past. The
/// final slot remains on the current day even when the user acts late at
/// night.
DateTime suggestedTodoScheduleTime(DateTime now, {DateTime? notBefore}) {
  final todayAtNine = DateTime(now.year, now.month, now.day, 9);
  var candidate = now.isBefore(todayAtNine)
      ? todayAtNine
      : snapToQuarterHour(now.add(const Duration(minutes: 15)));

  if (notBefore != null &&
      notBefore.year == now.year &&
      notBefore.month == now.month &&
      notBefore.day == now.day &&
      notBefore.isAfter(candidate)) {
    candidate = notBefore;
  }

  final latestToday = DateTime(
    now.year,
    now.month,
    now.day,
    23,
    59,
    59,
    999,
    999,
  );
  return candidate.isAfter(latestToday) ? latestToday : candidate;
}

/// Uses the current-day suggestion only when the target day is today; future
/// days keep a predictable 09:00 default for drag-and-drop planning.
DateTime suggestedTodoScheduleForDay(DateTime day, DateTime now) {
  final target = DateTime(day.year, day.month, day.day);
  final today = DateTime(now.year, now.month, now.day);
  if (target == today) return suggestedTodoScheduleTime(now);
  return DateTime(target.year, target.month, target.day, 9);
}

/// Finds non-overlapping starting times for a batch of todos on a target day.
///
/// Batch drops used to add a fixed 30-minute offset. That looked tidy for
/// short tasks but placed a 90-minute assignment on top of the next one. This
/// helper uses each todo's estimate, existing events and already scheduled
/// todos, while retaining the non-blocking rule: if the day is full, the
/// first requested slot is returned and the UI can warn the student.
Map<String, DateTime> suggestTodoBatchSlots(
  Iterable<TodoTask> todos,
  DateTime targetDay,
  DateTime now, {
  Iterable<DiaryEntry> events = const [],
  Iterable<TodoTask> scheduledTodos = const [],
}) {
  final target = DateTime(targetDay.year, targetDay.month, targetDay.day);
  final today = DateTime(now.year, now.month, now.day);
  var cursor = target == today
      ? suggestedTodoScheduleTime(now)
      : DateTime(target.year, target.month, target.day, 9);
  final occupied = [...scheduledTodos];
  final result = <String, DateTime>{};

  for (final todo in todos) {
    final requested = respectTodoOpening(todo, cursor);
    var candidate = requested;
    var chosen = requested;
    var found = false;
    final candidateDay = DateTime(
      candidate.year,
      candidate.month,
      candidate.day,
    );
    for (var index = 0; index < 96; index++) {
      if (isTodoScheduleSlotAvailable(
        todo,
        now,
        candidate,
        events: events,
        scheduledTodos: occupied,
      )) {
        chosen = candidate;
        found = true;
        break;
      }
      final next = candidate.add(const Duration(minutes: 15));
      if (!_isSameDay(next, candidateDay)) break;
      candidate = next;
    }
    // A full day remains an explicit, editable conflict rather than silently
    // moving work to another date.
    if (!found) chosen = requested;
    result[todo.id] = chosen;
    occupied.add(todo.copyWith(scheduledAt: chosen));
    cursor = chosen.add(Duration(minutes: todoPlanningMinutes(todo)));
  }
  return result;
}

/// Keeps manual and drag-and-drop planning from placing a task before its
/// explicit opening time. The deadline remains independent and is never
/// changed by this adjustment.
DateTime respectTodoOpening(TodoTask todo, DateTime requested) {
  final opensAt = todo.opensAt;
  if (opensAt != null && requested.isBefore(opensAt)) return opensAt;
  return requested;
}

/// Finds a low-friction execution slot for a todo on the current day.
///
/// The slot is only a suggestion: it never persists anything by itself. We
/// reserve a small default block for a task (or its saved estimate) and skip
/// events that have an explicit duration. Punctual events intentionally do
/// not block a slot, matching the planner's half-open conflict rules.
DateTime suggestTodoScheduleSlot(
  TodoTask todo,
  DateTime now, {
  Iterable<DiaryEntry> events = const [],
  Iterable<TodoTask> scheduledTodos = const [],
  int? durationMinutes,
}) {
  // A future opening date is a hard boundary, not merely a hint. Returning
  // a slot on the current day here would let a caller that only knows about
  // “next free slot” schedule work before the course platform has opened it.
  final opening = todo.opensAt;
  if (opening != null && opening.isAfter(now) && !_sameDay(opening, now)) {
    return opening;
  }
  final baseline = suggestedTodoScheduleTime(now, notBefore: todo.opensAt);
  final duration = (durationMinutes ?? todo.estimatedMinutes ?? 30)
      .clamp(5, 480)
      .toInt();
  final dayEnd = DateTime(
    baseline.year,
    baseline.month,
    baseline.day,
    23,
    59,
    59,
    999,
  );
  final deadline = todo.deadline;
  final hardStop =
      deadline != null &&
          _sameDay(deadline, baseline) &&
          deadline.isAfter(baseline)
      ? deadline
      : dayEnd;

  var candidate = baseline;
  // Keep a late-night baseline on the same day instead of rounding it into
  // tomorrow. During normal hours, quarter-hour snapping makes the action
  // predictable and aligns with the event grid.
  final snapped = snapToQuarterHour(candidate);
  if (_sameDay(snapped, baseline) && !snapped.isBefore(candidate)) {
    candidate = snapped;
  }

  for (var index = 0; index < 96; index++) {
    final end = candidate.add(Duration(minutes: duration));
    if (!end.isAfter(hardStop) &&
        isTodoScheduleSlotAvailable(
          todo,
          now,
          candidate,
          events: events,
          scheduledTodos: scheduledTodos,
          durationMinutes: duration,
        )) {
      return candidate;
    }
    candidate = candidate.add(const Duration(minutes: 15));
    if (!_sameDay(candidate, baseline)) break;
  }

  // If the day is packed or the deadline is already too close, keep the
  // explicit current-day suggestion. The UI will still show it as adjustable
  // instead of silently moving the task to tomorrow.
  return baseline;
}

/// Whether a suggested execution block is actually usable.
///
/// Suggestions remain non-blocking: a student may still explicitly save a
/// conflicting plan. This helper exists so the UI can distinguish a clean
/// recommendation from a fallback that runs into another plan or the task's
/// deadline, instead of presenting both as equally safe.
bool isTodoScheduleSlotAvailable(
  TodoTask todo,
  DateTime now,
  DateTime slot, {
  Iterable<DiaryEntry> events = const [],
  Iterable<TodoTask> scheduledTodos = const [],
  int? durationMinutes,
}) {
  if (slot.isBefore(now) && _sameDay(slot, now)) return false;
  if (!isTodoOpenAt(todo, slot)) return false;

  final duration = (durationMinutes ?? todo.estimatedMinutes ?? 30)
      .clamp(5, 480)
      .toInt();
  final end = slot.add(Duration(minutes: duration));
  final deadline = todo.deadline;
  if (deadline != null && end.isAfter(deadline)) return false;

  for (final event in events) {
    final eventStart = event.eventTime;
    final eventEnd = event.endTime;
    if (!event.isTimelineVisible || eventStart == null || eventEnd == null) {
      continue;
    }
    if (slot.isBefore(eventEnd) && eventStart.isBefore(end)) return false;
  }

  for (final other in scheduledTodos) {
    final otherStart = other.scheduledAt;
    if (other.id == todo.id ||
        other.isCompleted ||
        other.isArchived ||
        otherStart == null ||
        !_sameDay(otherStart, slot)) {
      continue;
    }
    // Todos do not have a duration field yet. Reserve the same default
    // execution block used for the task being placed so auto-arranging a
    // second task does not stack it on top of an existing plan.
    final otherEnd = otherStart.add(
      Duration(
        minutes: (other.estimatedMinutes ?? 30)
            .clamp(5, 480)
            .toInt(),
      ),
    );
    if (slot.isBefore(otherEnd) && otherStart.isBefore(end)) return false;
  }
  return true;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Returns timed events whose occupied interval intersects [periodStart,
/// periodEnd). Punctual markers are intentionally excluded because they have
/// no occupied interval and therefore cannot create a duration conflict.
///
/// Keeping this range test separate from [findEventConflicts] prevents a
/// cross-midnight class from disappearing from the conflict banner on the
/// following day or week merely because its start date is outside the view.
List<DiaryEntry> eventsOverlappingPeriod(
  Iterable<DiaryEntry> events,
  DateTime periodStart,
  DateTime periodEnd,
) {
  return events.where((event) {
    final start = event.eventTime;
    final end = event.endTime;
    if (event.category != 'event' ||
        event.isArchived ||
        start == null ||
        end == null) {
      return false;
    }
    return start.isBefore(periodEnd) && end.isAfter(periodStart);
  }).toList();
}

DateTime snapToQuarterHour(DateTime value) {
  final minutes = (value.minute / 15).round() * 15;
  final snapped = DateTime(
    value.year,
    value.month,
    value.day,
    value.hour,
  ).add(Duration(minutes: minutes));
  return snapped;
}

List<PlannerConflict> findEventConflicts(Iterable<DiaryEntry> events) {
  final scheduled =
      events
          .where(
            (event) =>
                event.category == 'event' &&
                !event.isArchived &&
                event.eventTime != null &&
                event.endTime != null,
          )
          .toList()
        ..sort((a, b) => a.eventTime!.compareTo(b.eventTime!));
  final conflicts = <PlannerConflict>[];
  for (var i = 0; i < scheduled.length; i++) {
    final first = scheduled[i];
    final firstEnd = first.endTime!;
    for (var j = i + 1; j < scheduled.length; j++) {
      final second = scheduled[j];
      if (!second.eventTime!.isBefore(firstEnd)) break;
      if (second.endTime!.isAfter(first.eventTime!)) {
        conflicts.add(PlannerConflict(first: first, second: second));
      }
    }
  }
  return conflicts;
}
