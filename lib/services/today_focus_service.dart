import '../models/diary_entry.dart';
import '../models/reminder_rule.dart';
import '../models/todo_task.dart';
import '../models/unified_item.dart';
import 'planner_service.dart';
import 'recurrence_service.dart';

/// A presentation item for the small execution cue at the top of Today.
///
/// The item is derived from the source models every time Today rebuilds. It
/// deliberately carries the source [UnifiedItem] so the view can open the
/// same details sheet as the rest of the workspace without persisting another
/// planning state.
class TodayFocusItem {
  final UnifiedItem item;
  final DateTime startAt;
  final DateTime? endAt;
  final String? warning;

  const TodayFocusItem({
    required this.item,
    required this.startAt,
    this.endAt,
    this.warning,
  });

  bool get isEvent => item.source == UnifiedItemSource.event;
  bool get isTodo => item.source == UnifiedItemSource.todo;
}

/// The current and next execution cues shown on Today.
class TodayFocus {
  final List<TodayFocusItem> current;
  final List<TodayFocusItem> next;

  const TodayFocus({required this.current, required this.next});

  bool get isEmpty => current.isEmpty && next.isEmpty;
}

/// Derives a small, honest execution cue from explicit schedule data.
///
/// This service does not schedule floating todos. It only considers todos
/// with an explicit [TodoTask.scheduledAt], and it uses the existing planner
/// duration helper for their end time. Events are expanded from their active
/// recurrence rules over the current day and the preceding day so an event
/// that started before midnight can remain visible while it is in progress.
class TodayFocusService {
  const TodayFocusService._();

  static const _recurringScheduleTypes = [
    'daily',
    'weekly',
    'every_n_days',
    'monthly',
  ];

  static TodayFocus build({
    required DateTime now,
    required Iterable<DiaryEntry> events,
    required Iterable<TodoTask> todos,
    Iterable<ReminderRule> rules = const [],
  }) {
    final current = <TodayFocusItem>[];
    final nextCandidates = <TodayFocusItem>[];
    final todayStart = calendarDate(now);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final allRules = rules.toList();

    for (final event in _scheduledEvents(
      events: events,
      rules: allRules,
      from: todayStart.subtract(const Duration(days: 1)),
      to: todayEnd,
    )) {
      _classify(
        TodayFocusItem(
          item: unifiedEventItem(event),
          startAt: event.eventTime!,
          endAt: event.endTime,
        ),
        now: now,
        todayStart: todayStart,
        todayEnd: todayEnd,
        current: current,
        nextCandidates: nextCandidates,
      );
    }

    for (final todo in todos) {
      if (!_isEligibleTodo(todo, now: now, rules: allRules)) continue;
      final start = todo.scheduledAt!;
      final end = start.add(Duration(minutes: todoPlanningMinutes(todo)));
      _classify(
        TodayFocusItem(
          item: unifiedTodoItem(todo, now),
          startAt: start,
          endAt: end,
          warning: todoScheduleDeadlineWarning(todo),
        ),
        now: now,
        todayStart: todayStart,
        todayEnd: todayEnd,
        current: current,
        nextCandidates: nextCandidates,
      );
    }

    current.sort(_compare);
    nextCandidates.sort(_compare);
    final next = nextCandidates.isEmpty
        ? const <TodayFocusItem>[]
        : nextCandidates
              .where(
                (item) =>
                    item.startAt.isAtSameMomentAs(nextCandidates.first.startAt),
              )
              .toList();
    return TodayFocus(current: current, next: next);
  }

  static bool _isEligibleTodo(
    TodoTask todo, {
    required DateTime now,
    required Iterable<ReminderRule> rules,
  }) {
    final scheduledAt = todo.scheduledAt;
    if (scheduledAt == null ||
        todo.isCompleted ||
        todo.isArchived ||
        todo.validationMessage != null) {
      return false;
    }
    if (todo.opensAt != null && now.isBefore(todo.opensAt!)) return false;
    // Keep Today and the focus cue aligned with the daily list: a preparation
    // task is not actionable before its explicitly confirmed attention day,
    // even if stale schedule data happens to point at today.
    if (todo.taskKind != TaskKind.timed &&
        todo.attentionDate != null &&
        calendarDate(now).isBefore(todo.attentionDate!)) {
      return false;
    }
    if (todo.deadline != null && !now.isBefore(todo.deadline!)) return false;

    final routine = _routineRuleFor(todo.id, rules);
    if (routine != null &&
        (routine.skipDates.any(
              (date) => RecurrenceService.isSameDate(date, now),
            ) ||
            RecurrenceService.occurrenceOn(routine, calendarDate(now)) ==
                null)) {
      return false;
    }
    return true;
  }

  static ReminderRule? _routineRuleFor(
    String todoId,
    Iterable<ReminderRule> rules,
  ) {
    for (final rule in rules) {
      if (rule.isActive &&
          rule.targetType == 'todo' &&
          rule.targetId == todoId &&
          _recurringScheduleTypes.contains(rule.scheduleType)) {
        return rule;
      }
    }
    return null;
  }

  static void _classify(
    TodayFocusItem candidate, {
    required DateTime now,
    required DateTime todayStart,
    required DateTime todayEnd,
    required List<TodayFocusItem> current,
    required List<TodayFocusItem> nextCandidates,
  }) {
    final start = candidate.startAt;
    final end = candidate.endAt;
    if (end != null && !start.isAfter(now) && now.isBefore(end)) {
      _addUnique(current, candidate);
      return;
    }

    // The next cue is intentionally limited to today's calendar. A plan for
    // tomorrow belongs to Plan and should not make Today look pre-filled.
    if (start.isAfter(now) &&
        !start.isBefore(todayStart) &&
        start.isBefore(todayEnd) &&
        (end == null || end.isAfter(now))) {
      _addUnique(nextCandidates, candidate);
    }
  }

  static void _addUnique(List<TodayFocusItem> target, TodayFocusItem value) {
    final duplicate = target.any(
      (existing) =>
          existing.item.source == value.item.source &&
          existing.item.id == value.item.id &&
          existing.startAt.isAtSameMomentAs(value.startAt) &&
          _sameMomentOrNull(existing.endAt, value.endAt),
    );
    if (!duplicate) target.add(value);
  }

  static bool _sameMomentOrNull(DateTime? left, DateTime? right) {
    if (left == null || right == null) return left == null && right == null;
    return left.isAtSameMomentAs(right);
  }

  static int _compare(TodayFocusItem left, TodayFocusItem right) {
    final time = left.startAt.compareTo(right.startAt);
    if (time != 0) return time;
    final title = left.item.title.compareTo(right.item.title);
    if (title != 0) return title;
    return left.item.id.compareTo(right.item.id);
  }

  /// Returns raw events plus recurrence occurrences over the only window the
  /// focus card needs: yesterday through the end of today. The one-day look
  /// back is enough because DiaryEntry durations are capped at 24 hours.
  static List<DiaryEntry> _scheduledEvents({
    required Iterable<DiaryEntry> events,
    required Iterable<ReminderRule> rules,
    required DateTime from,
    required DateTime to,
  }) {
    final sourceEvents = events
        .where(
          (event) =>
              event.category == 'event' &&
              event.eventTime != null &&
              !event.isArchived,
        )
        .toList();
    final eventById = <String, DiaryEntry>{
      for (final event in sourceEvents) event.id: event,
    };
    final recurringTargetIds = rules
        .where(
          (rule) =>
              rule.isActive &&
              rule.targetType == 'event' &&
              rule.targetId != null &&
              _recurringScheduleTypes.contains(rule.scheduleType),
        )
        .map((rule) => rule.targetId!)
        .toSet();
    final result = <DiaryEntry>[];

    // Generate the occurrence first. When an event has a same-day override,
    // this gives it precedence over the unchanged source row below.
    for (final rule in rules) {
      if (!rule.isActive ||
          rule.targetType != 'event' ||
          rule.targetId == null ||
          !_recurringScheduleTypes.contains(rule.scheduleType)) {
        continue;
      }
      final source = eventById[rule.targetId!];
      if (source == null) continue;
      final occurrences = RecurrenceService.occurrencesBetween(
        rule,
        from,
        to.subtract(const Duration(microseconds: 1)),
      );
      for (final occurrence in occurrences) {
        result.add(_eventForOccurrence(source, occurrence));
      }
    }

    // Include explicit one-off events and source events with no supported
    // recurrence rule. A source with an active recurrence is intentionally
    // not added here: doing so would resurrect an old timestamp when today's
    // occurrence was skipped, completed or moved by an override.
    for (final event in sourceEvents) {
      if (event.isCompleted || recurringTargetIds.contains(event.id)) continue;
      final key = _eventKey(event);
      if (!result.any((value) => _eventKey(value) == key)) {
        result.add(event);
      }
    }
    return result;
  }

  static DiaryEntry _eventForOccurrence(
    DiaryEntry source,
    RecurrenceOccurrence occurrence,
  ) {
    final override = occurrence.override;
    return source.copyWith(
      content: override?.newContent ?? source.content,
      eventTime: occurrence.scheduledTime,
      durationMinutes: override?.newDurationMinutes,
      clearDurationMinutes: override?.clearDurationMinutes == true,
      location: override?.newLocation,
      clearLocation: override?.clearLocation == true,
      isCompleted: false,
    );
  }

  static String _eventKey(DiaryEntry event) {
    return '${event.id}|${event.eventTime?.toIso8601String()}|${event.endTime?.toIso8601String()}';
  }
}
