import '../models/reminder_rule.dart';
import '../models/todo_task.dart';
import 'planner_service.dart';
import 'today_list_service.dart';

/// Derives explicit execution blocks whose expected end has already passed.
///
/// This is a projection over [TodayListService]'s actionable list. Keeping
/// that source of truth means opening dates, attention dates, deadlines,
/// routine skips and archived/completed tasks retain the same Today meaning.
/// A missed block is never persisted and remains discoverable across dates
/// until the student completes it, moves it, or clears its schedule.
class TodayMissedService {
  const TodayMissedService._();

  static List<TodoTask> build({
    required Iterable<TodoTask> todos,
    required DateTime now,
    Iterable<ReminderRule> rules = const [],
  }) {
    final actionable = TodayListService.build(
      todos: todos,
      rules: rules,
      now: now,
    ).actionable;
    return fromActionable(actionable, now: now);
  }

  /// Applies only the end-time boundary to an already projected actionable
  /// list. The helper keeps the boundary easy to test without duplicating
  /// TodayListService's lifecycle rules.
  static List<TodoTask> fromActionable(
    Iterable<TodoTask> actionable, {
    required DateTime now,
  }) {
    final missed = actionable.where((todo) {
      final scheduledAt = todo.scheduledAt;
      if (scheduledAt == null) return false;
      final plannedEnd = scheduledAt.add(
        Duration(minutes: todoPlanningMinutes(todo)),
      );
      return !plannedEnd.isAfter(now);
    }).toList();
    missed.sort(TodayListService.compare);
    return missed;
  }
}
