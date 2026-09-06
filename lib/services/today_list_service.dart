import '../models/todo_task.dart';
import '../models/reminder_rule.dart';
import 'recurrence_service.dart';

class TodayList {
  final List<TodoTask> actionable = [];
  final List<TodoTask> expired = [];
  final List<TodoTask> later = [];
  final List<TodoTask> pending = [];
  final List<TodoTask> completed = [];
  int get outstandingCount => actionable.length + expired.length;
}

/// The daily list is a projection, never a schedule or a copy of yesterday.
class TodayListService {
  static TodayList build({
    required Iterable<TodoTask> todos,
    required DateTime now,
    Iterable<ReminderRule> rules = const [],
  }) {
    final result = TodayList();
    final recurring = <String, ReminderRule>{};
    for (final rule in rules) {
      if (rule.isActive &&
          rule.targetType == 'todo' &&
          rule.targetId != null &&
          const [
            'daily',
            'weekly',
            'every_n_days',
            'monthly',
          ].contains(rule.scheduleType)) {
        recurring.putIfAbsent(rule.targetId!, () => rule);
      }
    }
    final seen = <String>{};
    for (final todo in todos) {
      if (!seen.add(todo.id) || todo.isArchived) continue;
      final routine = recurring[todo.id];
      if (routine != null &&
          (routine.skipDates.any(
                (date) => calendarDate(date) == calendarDate(now),
              ) ||
              RecurrenceService.occurrenceOn(routine, calendarDate(now)) ==
                  null)) {
        result.later.add(todo);
        continue;
      }
      if (todo.isCompleted) {
        result.completed.add(todo);
      } else if (todo.validationMessage != null) {
        result.pending.add(todo);
      } else if (todo.opensAt != null && now.isBefore(todo.opensAt!)) {
        result.later.add(todo);
      } else if (todo.deadline != null && !now.isBefore(todo.deadline!)) {
        result.expired.add(todo);
      } else if (todo.taskKind != TaskKind.timed &&
          todo.attentionDate != null &&
          calendarDate(now).isBefore(todo.attentionDate!)) {
        result.later.add(todo);
      } else {
        result.actionable.add(todo);
      }
    }
    for (final list in [
      result.actionable,
      result.expired,
      result.later,
      result.pending,
      result.completed,
    ]) {
      list.sort(compare);
    }
    return result;
  }

  static int compare(TodoTask a, TodoTask b) {
    if (a.deadline != null && b.deadline == null) return -1;
    if (a.deadline == null && b.deadline != null) return 1;
    if (a.deadline != null && b.deadline != null) {
      final due = a.deadline!.compareTo(b.deadline!);
      if (due != 0) return due;
    }
    final priority = a.priority.compareTo(b.priority);
    if (priority != 0) return priority;
    if (a.deadline == null && b.deadline == null) {
      final attention = (a.attentionDate ?? calendarDate(a.createdAt))
          .compareTo(b.attentionDate ?? calendarDate(b.createdAt));
      if (attention != 0) return attention;
    }
    final created = a.createdAt.compareTo(b.createdAt);
    return created != 0 ? created : a.id.compareTo(b.id);
  }

  static String reason(TodoTask todo, DateTime now) {
    if (todo.validationMessage != null) {
      return '待补充 · ${todo.validationMessage}';
    }
    final parts = <String>[];
    if (todo.opensAt != null) {
      parts.add(now.isBefore(todo.opensAt!) ? '尚未开放' : '已开放');
    } else if (todo.attentionDate != null) {
      final date = todo.attentionDate!;
      parts.add(
        calendarDate(now).isBefore(date)
            ? '${date.month}/${date.day} 开始关注'
            : '开始关注',
      );
    } else {
      parts.add('持续待办');
    }
    if (todo.deadline != null) {
      if (!now.isBefore(todo.deadline!)) {
        parts.add('已截止，待处理');
      } else {
        final due = calendarDate(todo.deadline!);
        final today = calendarDate(now);
        final days = DateTime.utc(
          due.year,
          due.month,
          due.day,
        ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
        parts.add(
          days == 0
              ? '今天截止'
              : days == 1
              ? '明天截止'
              : '剩余 $days 天',
        );
      }
    }
    return parts.join(' · ');
  }
}
