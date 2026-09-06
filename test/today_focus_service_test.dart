import 'package:flutter_test/flutter_test.dart';
import 'package:zendiary/models/diary_entry.dart';
import 'package:zendiary/models/recurrence_override.dart';
import 'package:zendiary/models/reminder_rule.dart';
import 'package:zendiary/models/todo_task.dart';
import 'package:zendiary/services/today_focus_service.dart';

void main() {
  final now = DateTime(2026, 9, 5, 10);

  DiaryEntry event(
    String id,
    DateTime start, {
    int? minutes,
    bool completed = false,
    bool archived = false,
  }) => DiaryEntry(
    id: id,
    content: id,
    timestamp: start,
    category: 'event',
    eventTime: start,
    durationMinutes: minutes,
    isCompleted: completed,
    isArchived: archived,
  );

  TodoTask todo(
    String id,
    DateTime? start, {
    int? estimate,
    DateTime? opening,
    DateTime? deadline,
    bool completed = false,
    bool archived = false,
  }) => TodoTask(
    id: id,
    title: id,
    createdAt: now,
    scheduledAt: start,
    estimatedMinutes: estimate,
    opensAt: opening,
    deadline: deadline,
    isCompleted: completed,
    isArchived: archived,
  );

  test(
    'uses half-open intervals and keeps all current and tied next items',
    () {
      final focus = TodayFocusService.build(
        now: now,
        events: [
          event(
            'ends-now',
            now.subtract(const Duration(hours: 1)),
            minutes: 60,
          ),
          event(
            'current-event',
            now.subtract(const Duration(minutes: 1)),
            minutes: 30,
          ),
          event('next-event', now.add(const Duration(hours: 1)), minutes: 30),
        ],
        todos: [
          todo('next-todo', now.add(const Duration(hours: 1)), estimate: 45),
        ],
      );

      expect(focus.current.map((item) => item.item.id), ['current-event']);
      expect(focus.next.map((item) => item.item.id), [
        'next-event',
        'next-todo',
      ]);
    },
  );

  test('does not use past point events or tomorrow plans as a next cue', () {
    final focus = TodayFocusService.build(
      now: now,
      events: [
        event('past-point', now.subtract(const Duration(minutes: 1))),
        event('future-point', now.add(const Duration(minutes: 1))),
      ],
      todos: [
        todo('tomorrow', now.add(const Duration(days: 1))),
        todo('floating', null),
      ],
    );

    expect(focus.current, isEmpty);
    expect(focus.next.map((item) => item.item.id), ['future-point']);
  });

  test('excludes completed, archived, unopened, pending and overdue todos', () {
    final focus = TodayFocusService.build(
      now: now,
      events: const [],
      todos: [
        todo('completed', now, completed: true),
        todo('archived', now, archived: true),
        todo('unopened', now, opening: now.add(const Duration(minutes: 1))),
        todo('overdue', now, deadline: now),
        TodoTask(
          id: 'pending',
          title: 'pending',
          createdAt: now,
          scheduledAt: now,
          taskKind: TaskKind.preparation,
        ),
      ],
    );

    expect(focus.isEmpty, isTrue);
  });

  test(
    'keeps an overnight recurring event current without inventing duration',
    () {
      final sourceStart = DateTime(2026, 9, 4, 23, 30);
      final source = event('overnight-class', sourceStart, minutes: 90);
      final rule = ReminderRule(
        id: 'overnight-rule',
        title: 'overnight-class',
        targetType: 'event',
        targetId: source.id,
        scheduleType: 'daily',
        anchorTime: sourceStart,
        displayMode: 'spanning',
      );

      final focus = TodayFocusService.build(
        now: DateTime(2026, 9, 5, 0, 15),
        events: [source],
        rules: [rule],
        todos: const [],
      );

      expect(focus.current.map((item) => item.item.id), ['overnight-class']);
      expect(focus.current.single.endAt, DateTime(2026, 9, 5, 1));
    },
  );

  test('does not resurrect a skipped, moved or completed occurrence', () {
    final source = event(
      'recurring-class',
      DateTime(2026, 9, 5, 9),
      minutes: 60,
    );
    ReminderRule ruleFor({
      List<DateTime> skipDates = const [],
      List<RecurrenceOverride> overrides = const [],
    }) => ReminderRule(
      id: 'recurring-rule',
      title: source.content,
      targetType: 'event',
      targetId: source.id,
      scheduleType: 'daily',
      anchorTime: source.eventTime,
      skipDates: skipDates,
      overrides: overrides,
    );

    final skipped = TodayFocusService.build(
      now: DateTime(2026, 9, 5, 9, 30),
      events: [source],
      rules: [
        ruleFor(skipDates: [DateTime(2026, 9, 5)]),
      ],
      todos: const [],
    );
    expect(skipped.isEmpty, isTrue);

    final moved = TodayFocusService.build(
      now: DateTime(2026, 9, 5, 9, 30),
      events: [source],
      rules: [
        ruleFor(
          overrides: [
            RecurrenceOverride(
              originalDate: DateTime(2026, 9, 5),
              newTime: DateTime(2026, 9, 5, 12),
            ),
          ],
        ),
      ],
      todos: const [],
    );
    expect(moved.current, isEmpty);
    expect(moved.next.single.startAt, DateTime(2026, 9, 5, 12));

    final completed = TodayFocusService.build(
      now: DateTime(2026, 9, 5, 9, 30),
      events: [source],
      rules: [
        ruleFor(
          overrides: [
            RecurrenceOverride(
              originalDate: DateTime(2026, 9, 5),
              isCompleted: true,
            ),
          ],
        ),
      ],
      todos: const [],
    );
    expect(completed.isEmpty, isTrue);
  });
}
