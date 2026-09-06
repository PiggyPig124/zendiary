import '../models/diary_entry.dart';
import '../models/reminder_rule.dart';
import '../models/todo_task.dart';
import '../models/unified_item.dart';
import 'recurrence_service.dart';
import 'system_notification_service.dart';

/// Resolves a notification payload to the source item that the detail drawer
/// should open. Keeping this separate from window and Riverpod state makes the
/// click contract testable without pretending a fake toast is an OS test.
class NotificationTargetResolver {
  const NotificationTargetResolver._();

  static UnifiedItem? resolve({
    required String? payload,
    required List<ReminderRule> rules,
    required List<TodoTask> todos,
    required List<DiaryEntry> events,
    required DateTime now,
    DateTime? occurrenceTime,
  }) {
    if (payload == null || payload.isEmpty) return null;
    final rule = rules.cast<ReminderRule?>().firstWhere(
      (value) =>
          value != null &&
          (payload.startsWith('${value.id}|') ||
              payload.startsWith('${value.id}:')),
      orElse: () => null,
    );
    if (rule != null) {
      if (rule.targetType == 'todo') {
        final todo = todos.cast<TodoTask?>().firstWhere(
          (value) => value?.id == rule.targetId,
          orElse: () => null,
        );
        if (todo == null) return null;
        final recurring = const [
          'daily',
          'weekly',
          'every_n_days',
          'monthly',
        ].contains(rule.scheduleType);
        return unifiedTodoItem(
          todo,
          now,
          scheduledAtOverride: recurring ? occurrenceTime : null,
        );
      }
      if (rule.targetType == 'event') {
        final entry = events.cast<DiaryEntry?>().firstWhere(
          (value) => value?.id == rule.targetId,
          orElse: () => null,
        );
        if (entry == null) return null;
        return _eventItem(entry, rule, occurrenceTime);
      }
      return unifiedReminderItem(rule);
    }

    // Portable runtime fallback uses synthetic timeline:{entryId} rules.
    final entry = events.cast<DiaryEntry?>().firstWhere(
      (value) =>
          value != null &&
          SystemNotificationService.isTimelineFallbackPayload(
            payload,
            value.id,
          ),
      orElse: () => null,
    );
    return entry == null ? null : unifiedEventItem(entry);
  }

  static UnifiedItem _eventItem(
    DiaryEntry entry,
    ReminderRule rule,
    DateTime? occurrenceTime,
  ) {
    if (occurrenceTime == null || rule.scheduleType == 'once') {
      return unifiedEventItem(entry);
    }
    final dayStart = DateTime(
      occurrenceTime.year,
      occurrenceTime.month,
      occurrenceTime.day,
    );
    final occurrence =
        RecurrenceService.occurrencesBetween(
          rule,
          dayStart,
          dayStart
              .add(const Duration(days: 1))
              .subtract(const Duration(microseconds: 1)),
        ).cast<RecurrenceOccurrence?>().firstWhere(
          (value) =>
              value != null &&
              value.scheduledTime.isAtSameMomentAs(occurrenceTime),
          orElse: () => null,
        );
    if (occurrence == null) return unifiedEventItem(entry);
    final override = occurrence.override;
    final duration = override?.newDurationMinutes ?? entry.durationMinutes;
    return UnifiedItem(
      id: entry.id,
      source: UnifiedItemSource.event,
      sourceId: entry.id,
      title: compactItemTitle(override?.newContent ?? entry.content),
      startAt: occurrence.scheduledTime,
      endAt: duration == null
          ? null
          : occurrence.scheduledTime.add(Duration(minutes: duration)),
      status: override?.isCompleted == true || entry.isCompleted
          ? 'completed'
          : 'active',
      tags: entry.tags,
      location: override?.newLocation ?? entry.location,
    );
  }
}
