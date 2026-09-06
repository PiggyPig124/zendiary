import 'package:flutter_test/flutter_test.dart';
import 'package:zendiary/models/diary_entry.dart';
import 'package:zendiary/models/reminder_rule.dart';
import 'package:zendiary/models/todo_task.dart';
import 'package:zendiary/models/unified_item.dart';
import 'package:zendiary/services/notification_target_resolver.dart';
import 'package:zendiary/services/system_notification_service.dart';

void main() {
  final now = DateTime(2026, 9, 6, 8);

  test('one-off todo payload resolves to the same todo item', () {
    final todo = TodoTask(
      id: 'trial-todo',
      title: '试用改期事项',
      createdAt: DateTime(2026, 9, 1),
      scheduledAt: DateTime(2026, 9, 6, 9),
    );
    final rule = ReminderRule(
      id: 'trial-rule',
      title: todo.title,
      targetType: 'todo',
      targetId: todo.id,
      anchorTime: todo.scheduledAt,
      advanceMinutes: const [0],
      note: '事项提醒',
    );
    final payload = SystemNotificationService.occurrencePayload(
      rule.id,
      todo.scheduledAt!,
    );

    final item = NotificationTargetResolver.resolve(
      payload: payload,
      rules: [rule],
      todos: [todo],
      events: const [],
      occurrenceTime: todo.scheduledAt,
      now: now,
    );

    expect(item?.source, UnifiedItemSource.todo);
    expect(item?.id, todo.id);
    expect(item?.title, todo.title);
    expect(item?.scheduledAt, todo.scheduledAt);
  });

  test('event payload uses the current event source and occurrence date', () {
    final eventTime = DateTime(2026, 9, 6, 10);
    final event = DiaryEntry(
      id: 'trial-event',
      content: '试用课程',
      timestamp: DateTime(2026, 9, 1),
      category: 'event',
      eventTime: eventTime,
      durationMinutes: 90,
    );
    final rule = ReminderRule(
      id: 'trial-event-rule',
      title: event.content,
      targetType: 'event',
      targetId: event.id,
      anchorTime: eventTime,
      advanceMinutes: const [0],
    );
    final payload = SystemNotificationService.occurrencePayload(
      rule.id,
      eventTime,
    );

    final item = NotificationTargetResolver.resolve(
      payload: payload,
      rules: [rule],
      todos: const [],
      events: [event],
      occurrenceTime: eventTime,
      now: now,
    );

    expect(item?.source, UnifiedItemSource.event);
    expect(item?.id, event.id);
    expect(item?.startAt, eventTime);
    expect(item?.endAt, DateTime(2026, 9, 6, 11, 30));
  });

  test(
    'portable timeline fallback payload resolves without a persisted rule',
    () {
      final event = DiaryEntry(
        id: 'trial-timeline',
        content: '试用时间线事项',
        timestamp: DateTime(2026, 9, 1),
        category: 'event',
        eventTime: DateTime(2026, 9, 6, 11),
      );

      final item = NotificationTargetResolver.resolve(
        payload: 'timeline:${event.id}|2026-09-06T11:00:00.000|10',
        rules: const [],
        todos: const [],
        events: [event],
        now: now,
      );

      expect(item?.source, UnifiedItemSource.event);
      expect(item?.id, event.id);
    },
  );
}
