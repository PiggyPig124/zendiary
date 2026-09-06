import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zendiary/core/theme/zen_theme.dart';
import 'package:zendiary/models/diary_entry.dart';
import 'package:zendiary/models/ai_parsed_intent.dart';
import 'package:zendiary/models/pending_action_preview.dart';
import 'package:zendiary/models/recurrence_override.dart';
import 'package:zendiary/models/reminder_rule.dart';
import 'package:zendiary/models/todo_task.dart';
import 'package:zendiary/services/action_preview_service.dart';
import 'package:zendiary/services/recurrence_service.dart';
import 'package:zendiary/services/runtime_reminder_service.dart';
import 'package:zendiary/services/system_notification_service.dart';
import 'package:zendiary/views/timeline/day_view.dart';
import 'package:zendiary/views/timeline/timeline_data.dart';
import 'package:zendiary/views/todo/todo_create_dialog.dart';
import 'package:zendiary/views/todo/todo_view.dart';

class _FakeNotificationAdapter implements NotificationSchedulingAdapter {
  final List<int> cancelled = [];
  final List<int> shown = [];
  final List<int> scheduled = [];
  final List<String> shownBodies = [];
  final List<String?> shownPayloads = [];
  final List<DateTime> scheduledTimes = [];
  final List<String> scheduledBodies = [];
  final List<String?> scheduledPayloads = [];

  @override
  Future<void> cancel(int id) async => cancelled.add(id);

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime triggerAt,
    String? payload,
  }) async {
    scheduled.add(id);
    scheduledTimes.add(triggerAt);
    scheduledBodies.add(body);
    scheduledPayloads.add(payload);
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    shown.add(id);
    shownBodies.add(body);
    shownPayloads.add(payload);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('DiaryEntry reads legacy thought category as draft', () {
    final entry = DiaryEntry.fromJson({
      'id': '1',
      'content': 'hello',
      'timestamp': '2026-06-28T12:03:50.874199',
      'category': 'thought',
    });

    expect(entry.category, 'draft');
    expect(entry.content, 'hello');
  });

  test('DiaryEntry treats event without eventTime as not timeline-visible', () {
    final entry = DiaryEntry(
      id: 'floating-event',
      content: 'draft promoted by bad legacy data',
      timestamp: DateTime(2026, 7, 4, 23, 50),
      category: 'event',
    );

    expect(entry.isTimelineVisible, isFalse);
  });

  test('DiaryEntry preserves timeline completion state', () {
    final entry = DiaryEntry.fromJson({
      'id': 'done-event',
      'content': 'take medicine',
      'timestamp': '2026-07-04T08:00:00',
      'category': 'event',
      'eventTime': '2026-07-04T09:00:00',
      'isCompleted': true,
    });

    expect(entry.isCompleted, isTrue);
    expect(entry.toJson()['isCompleted'], isTrue);
    expect(entry.copyWith(isCompleted: false).isCompleted, isFalse);
  });

  test('ZenTheme applies a single app font family to Material text', () {
    final theme = ZenTheme.lightTheme;

    expect(theme.textTheme.bodyLarge?.fontFamily, ZenTheme.appFontFamily);
    expect(
      theme.elevatedButtonTheme.style?.textStyle?.resolve({})?.fontFamily,
      ZenTheme.appFontFamily,
    );
  });

  testWidgets('TodoCreateDialog keeps recurrence controls reachable on phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ZenTheme.lightTheme,
        home: const Scaffold(body: TodoCreateDialog()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('每N天'), findsOneWidget);
    expect(find.text('每月'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('每月'));
    await tester.tap(find.text('每月'));
    await tester.pumpAndSettle();
    expect(find.text('几号'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('TodoTask reads legacy todo payload safely', () {
    final todo = TodoTask.fromJson({'todo': 'buy milk', 'priority': 'X'});

    expect(todo.title, 'buy milk');
    expect(todo.priority, 'B');
    expect(todo.category, 'general');
    expect(todo.sourceEntryId, isNull);
  });

  test('TodoTask ignores legacy remindAt and timeWindow fields', () {
    final todo = TodoTask.fromJson({
      'title': 'old todo',
      'remindAt': '2026-07-04T14:00:00',
      'timeWindow': 'tonight',
    });

    expect(todo.title, 'old todo');
    // remindAt / timeWindow are silently ignored during deserialization
  });

  test('todo deadline quick date uses end of day when no time exists', () {
    final picked = DateTime(2026, 9, 10);

    expect(
      todoDeadlineForPickedDate(picked, null),
      DateTime(2026, 9, 10, 23, 59),
    );
    expect(
      todoDeadlineForPickedDate(picked, DateTime(2026, 9, 1, 18, 30)),
      DateTime(2026, 9, 10, 18, 30),
    );
  });

  test(
    'monthly routine anchor honors requested day and clamps short months',
    () {
      final now = DateTime(2026, 9, 5, 8);
      expect(
        monthlyAnchorAfter(
          now,
          15,
          preferredTime: DateTime(2026, 9, 15, 18, 30),
        ),
        DateTime(2026, 9, 15, 18, 30),
      );
      expect(
        monthlyAnchorAfter(DateTime(2026, 9, 20, 8), 31),
        DateTime(2026, 9, 30, 9),
      );
      expect(
        monthlyAnchorAfter(DateTime(2026, 9, 30, 20), 31),
        DateTime(2026, 10, 31, 9),
      );
      expect(
        monthlyAnchorAfter(DateTime(2026, 2, 1, 8), 31),
        DateTime(2026, 2, 28, 9),
      );
      expect(
        monthlyAnchorAfter(
          DateTime(2026, 9, 5, 8),
          15,
          preferredTime: DateTime(2024, 1, 15, 18, 30),
        ),
        DateTime(2026, 9, 15, 18, 30),
      );
    },
  );

  test('ReminderRule reads invalid payload safely', () {
    final rule = ReminderRule.fromJson({
      'title': 'exam',
      'targetType': 'unknown',
      'importance': 'urgent',
      'disturbanceLevel': 'loud',
      'scheduleType': 'forever',
      'status': 'missing',
      'advanceMinutes': ['60', 'bad', 15],
    });

    expect(rule.title, 'exam');
    expect(rule.targetType, 'standalone');
    expect(rule.importance, 'normal');
    expect(rule.disturbanceLevel, 'normal');
    expect(rule.scheduleType, 'once');
    expect(rule.status, 'active');
    expect(rule.advanceMinutes, [60, 15]);
  });

  test('ReminderRule supports new scheduleType values', () {
    final daily = ReminderRule.fromJson({
      'title': 'daily task',
      'scheduleType': 'daily',
    });
    expect(daily.scheduleType, 'daily');

    final everyNDays = ReminderRule.fromJson({
      'title': 'every 3 days',
      'scheduleType': 'every_n_days',
      'scheduleInterval': 3,
    });
    expect(everyNDays.scheduleType, 'every_n_days');
    expect(everyNDays.scheduleInterval, 3);

    final monthly = ReminderRule.fromJson({
      'title': 'monthly',
      'scheduleType': 'monthly',
      'scheduleDay': 15,
    });
    expect(monthly.scheduleType, 'monthly');
    expect(monthly.scheduleDay, 15);
  });

  test('AiParsedIntent reads old and new AI payload safely', () {
    final intent = AiParsedIntent.fromJson({
      'category': 'event',
      'event_time': '2026-07-04T09:00:00',
      'ai_summary': '考试',
      'todos': ['复习'],
      'tags': ['学习'],
      'importance': 'important',
      'disturbance_level': 'strong',
      'reminder': {
        'enabled': true,
        'schedule_type': 'once',
        'schedule_interval': 1,
        'advance_minutes': [60, '15', 'bad', 5],
        'requires_confirmation': true,
      },
      'missing_info': ['考场'],
    });

    expect(intent.category, 'event');
    expect(intent.eventTime, DateTime(2026, 7, 4, 9));
    expect(intent.importance, 'important');
    expect(intent.disturbanceLevel, 'strong');
    expect(intent.reminder.advanceMinutes, [60, 15, 5]);
    expect(intent.reminder.scheduleInterval, 1);
    expect(intent.requiresReminderConfirmation, isTrue);
    expect(intent.missingInfo, ['考场']);
  });

  test('AiParsedIntent ignores legacy todo_time_window', () {
    final intent = AiParsedIntent.fromJson({
      'category': 'todo',
      'todos': ['buy milk'],
      'todo_time_window': 'tonight',
    });

    expect(intent.category, 'todo');
    expect(intent.todos, ['buy milk']);
    // todo_time_window is silently ignored
  });

  test('RuntimeReminderService returns due strong advance reminders', () {
    final now = DateTime(2026, 7, 3, 8, 45);
    final rule = ReminderRule(
      id: 'exam-rule',
      title: '考试',
      disturbanceLevel: 'strong',
      anchorTime: DateTime(2026, 7, 3, 9),
      advanceMinutes: [60, 15, 5],
    );

    final hits = RuntimeReminderService.dueReminders([rule], now);

    expect(hits, hasLength(1));
    expect(hits.single.advanceMinutes, 15);
    expect(hits.single.key, 'exam-rule:2026-07-03T09:00:00.000:15');
  });

  test(
    'RuntimeReminderService includes normal reminders but respects dismissed hits',
    () {
      final now = DateTime(2026, 7, 3, 8, 45);
      final normalRule = ReminderRule(
        id: 'normal-rule',
        title: '普通提醒',
        disturbanceLevel: 'normal',
        anchorTime: DateTime(2026, 7, 3, 9),
        advanceMinutes: [15],
      );
      final strongRule = ReminderRule(
        id: 'strong-rule',
        title: '强提醒',
        disturbanceLevel: 'strong',
        anchorTime: DateTime(2026, 7, 3, 9),
        advanceMinutes: [15],
      );

      final hits = RuntimeReminderService.dueReminders(
        [normalRule, strongRule],
        now,
        dismissedKeys: {'strong-rule:2026-07-03T09:00:00.000:15'},
      );

      // 普通提醒应该触发，强提醒被 dismissed 过滤掉
      expect(hits.length, 1);
      expect(hits.first.rule.id, 'normal-rule');
    },
  );

  test('RuntimeReminderService ignores silent reminders', () {
    final now = DateTime(2026, 7, 3, 7, 45);
    final silentRule = ReminderRule(
      id: 'silent-rule',
      title: '静默提醒',
      disturbanceLevel: 'silent',
      anchorTime: DateTime(2026, 7, 3, 8),
      advanceMinutes: [15],
    );

    final hits = RuntimeReminderService.dueReminders([silentRule], now);

    expect(hits, isEmpty);
  });

  test('RuntimeReminderService supports daily strong reminders', () {
    final now = DateTime(2026, 7, 3, 7, 45);
    final rule = ReminderRule(
      title: '上课',
      disturbanceLevel: 'strong',
      scheduleType: 'daily',
      anchorTime: DateTime(2026, 1, 1, 8),
      advanceMinutes: [15],
    );

    final hits = RuntimeReminderService.dueReminders([rule], now);

    expect(hits, hasLength(1));
    expect(hits.single.occurrenceTime, DateTime(2026, 7, 3, 8));
    expect(hits.single.advanceMinutes, 15);
  });

  test('RuntimeReminderService supports every_n_days reminders', () {
    // Anchor was 2 days ago with interval=2, so today should match
    final now = DateTime(2026, 7, 3, 7, 45);
    final rule = ReminderRule(
      title: 'every 2 days',
      disturbanceLevel: 'strong',
      scheduleType: 'every_n_days',
      scheduleInterval: 2,
      anchorTime: DateTime(2026, 7, 1, 8),
      advanceMinutes: [15],
    );

    final hits = RuntimeReminderService.dueReminders([rule], now);

    expect(hits, hasLength(1));
    expect(hits.single.occurrenceTime, DateTime(2026, 7, 3, 8));
  });

  test('RuntimeReminderService supports monthly reminders', () {
    final now = DateTime(2026, 7, 15, 7, 45);
    final rule = ReminderRule(
      title: 'monthly task',
      disturbanceLevel: 'strong',
      scheduleType: 'monthly',
      scheduleDay: 15,
      anchorTime: DateTime(2026, 1, 15, 8),
      advanceMinutes: [15],
    );

    final hits = RuntimeReminderService.dueReminders([rule], now);

    expect(hits, hasLength(1));
    expect(hits.single.occurrenceTime, DateTime(2026, 7, 15, 8));
  });

  test('RuntimeReminderService triggers timeline event fallback reminders', () {
    final now = DateTime(2026, 7, 3, 15, 11, 5);
    final event = DiaryEntry(
      id: 'timeline-event-1',
      content: '1',
      timestamp: DateTime(2026, 7, 3, 15, 10),
      category: 'event',
      eventTime: DateTime(2026, 7, 3, 15, 11),
    );

    final fallbackRules = RuntimeReminderService.timelineFallbackRules([event]);
    final hits = RuntimeReminderService.dueReminders(fallbackRules, now);

    expect(fallbackRules, hasLength(1));
    expect(fallbackRules.single.id, 'timeline:timeline-event-1');
    expect(fallbackRules.single.disturbanceLevel, 'normal');
    expect(fallbackRules.single.advanceMinutes, [10]);
    expect(hits, hasLength(1));
    expect(hits.single.rule.title, '1');
    expect(hits.single.occurrenceTime, DateTime(2026, 7, 3, 15, 11));
  });

  test('RuntimeReminderService skips timeline fallback when rule exists', () {
    final event = DiaryEntry(
      id: 'timeline-event-disabled',
      content: 'muted',
      timestamp: DateTime(2026, 7, 3, 15, 10),
      category: 'event',
      eventTime: DateTime(2026, 7, 3, 15, 11),
    );

    final fallbackRules = RuntimeReminderService.timelineFallbackRules(
      [event],
      ignoredEntryIds: {'timeline-event-disabled'},
    );

    expect(fallbackRules, isEmpty);
  });

  test(
    'RuntimeReminderService skips timeline fallback for completed events',
    () {
      final event = DiaryEntry(
        id: 'timeline-event-completed',
        content: '已完成签到',
        timestamp: DateTime(2026, 7, 3, 15, 10),
        category: 'event',
        eventTime: DateTime(2026, 7, 3, 15, 11),
        isCompleted: true,
      );

      expect(RuntimeReminderService.timelineFallbackRules([event]), isEmpty);
    },
  );

  test(
    'RuntimeReminderService computeRecurringTodoResets resets daily todos',
    () {
      final now = DateTime(2026, 7, 3, 8);
      final todo = TodoTask(
        id: 'daily-todo',
        title: 'game dailies',
        createdAt: now,
        isCompleted: true,
        priority: 'C',
      );
      final rule = ReminderRule(
        targetType: 'todo',
        targetId: 'daily-todo',
        scheduleType: 'daily',
        title: 'game dailies',
      );

      final resets = RuntimeReminderService.computeRecurringTodoResets(
        [todo],
        [rule],
        now,
      );

      expect(resets, hasLength(1));
      expect(resets.first.id, 'daily-todo');
      expect(resets.first.isCompleted, false);
    },
  );

  test(
    'RuntimeReminderService computeRecurringTodoResets ignored for non-completed',
    () {
      final now = DateTime(2026, 7, 3, 8);
      final todo = TodoTask(
        id: 'open-todo',
        title: 'not done yet',
        createdAt: now,
        isCompleted: false,
      );
      final rule = ReminderRule(
        targetType: 'todo',
        targetId: 'open-todo',
        scheduleType: 'daily',
        title: 'not done yet',
      );

      final resets = RuntimeReminderService.computeRecurringTodoResets(
        [todo],
        [rule],
        now,
      );

      expect(resets, isEmpty);
    },
  );

  test('weekly recurring todos reset on every selected weekday', () {
    final todo = TodoTask(
      id: 'weekly-study',
      title: '每周复习',
      createdAt: DateTime(2026, 7, 6),
      isCompleted: true,
    );
    final rule = ReminderRule(
      targetType: 'todo',
      targetId: todo.id,
      scheduleType: 'weekly',
      byDay: [1, 3, 5],
      anchorTime: DateTime(2026, 7, 6, 19),
      title: todo.title,
    );

    expect(
      RuntimeReminderService.computeRecurringTodoResets(
        [todo],
        [rule],
        DateTime(2026, 7, 8, 8),
      ),
      hasLength(1),
    );
  });

  test('recurring todo reset ignores a separate deadline rule', () {
    final todo = TodoTask(
      id: 'mixed-reminders',
      title: '每周交作业',
      createdAt: DateTime(2026, 7, 6),
      isCompleted: true,
    );
    final deadlineRule = ReminderRule(
      id: 'deadline-rule',
      targetType: 'todo',
      targetId: todo.id,
      scheduleType: 'once',
      anchorTime: DateTime(2026, 7, 10, 23, 59),
      title: todo.title,
    );
    final recurringRule = ReminderRule(
      id: 'weekly-rule',
      targetType: 'todo',
      targetId: todo.id,
      scheduleType: 'weekly',
      byDay: [3],
      anchorTime: DateTime(2026, 7, 6, 19),
      title: todo.title,
    );

    final resets = RuntimeReminderService.computeRecurringTodoResets(
      [todo],
      [deadlineRule, recurringRule],
      DateTime(2026, 7, 8, 8),
    );

    expect(resets, hasLength(1));
    expect(resets.single.isCompleted, isFalse);
  });

  test('disabled recurring todo rules do not reopen completed tasks', () {
    final todo = TodoTask(
      id: 'paused-routine',
      title: '暂停的例行任务',
      createdAt: DateTime(2026, 7, 6),
      isCompleted: true,
    );
    final rule = ReminderRule(
      targetType: 'todo',
      targetId: todo.id,
      scheduleType: 'daily',
      status: 'disabled',
      title: todo.title,
    );

    expect(
      RuntimeReminderService.computeRecurringTodoResets(
        [todo],
        [rule],
        DateTime(2026, 7, 8, 8),
      ),
      isEmpty,
    );
  });

  test('monthly recurring todos reset on their actual occurrence day', () {
    final todo = TodoTask(
      id: 'monthly-study',
      title: '每月复盘',
      createdAt: DateTime(2026, 7, 15),
      isCompleted: true,
    );
    final rule = ReminderRule(
      targetType: 'todo',
      targetId: todo.id,
      scheduleType: 'monthly',
      anchorTime: DateTime(2026, 7, 15, 19),
      title: todo.title,
    );

    expect(
      RuntimeReminderService.computeRecurringTodoResets(
        [todo],
        [rule],
        DateTime(2026, 8, 1, 8),
      ),
      isEmpty,
    );
    expect(
      RuntimeReminderService.computeRecurringTodoResets(
        [todo],
        [rule],
        DateTime(2026, 8, 15, 8),
      ),
      hasLength(1),
    );
  });

  test('recurring todo refresh runs once per calendar day', () {
    expect(
      RuntimeReminderService.shouldRefreshRecurringTodos(
        null,
        DateTime(2026, 7, 3, 8),
      ),
      isTrue,
    );
    expect(
      RuntimeReminderService.shouldRefreshRecurringTodos(
        DateTime(2026, 7, 3, 0),
        DateTime(2026, 7, 3, 22),
      ),
      isFalse,
    );
    expect(
      RuntimeReminderService.shouldRefreshRecurringTodos(
        DateTime(2026, 7, 3, 0),
        DateTime(2026, 7, 4, 0),
      ),
      isTrue,
    );
  });

  test('ActionPreviewService low-load preview protects exams', () {
    final now = DateTime(2026, 7, 4, 8);
    final workTodo = TodoTask(
      id: 'todo-work',
      title: '完成工作周报',
      createdAt: now,
      category: '工作',
    );
    final examEvent = DiaryEntry(
      id: 'exam',
      content: '高数考试',
      timestamp: now,
      category: 'event',
      eventTime: DateTime(2026, 7, 4, 10),
    );
    final workRule = ReminderRule(
      id: 'rule-work',
      title: '工作周报',
      targetType: 'todo',
      targetId: 'todo-work',
      disturbanceLevel: 'strong',
      anchorTime: DateTime(2026, 7, 4, 9),
    );

    final preview = ActionPreviewService.buildLowLoadPreview(
      sourceText: '帮我推掉今天的工作和课',
      now: now,
      days: 1,
      targetText: '工作 课程',
      todos: [workTodo],
      events: [examEvent],
      rules: [workRule],
    );

    expect(preview.type, PendingActionType.lowLoad);
    expect(preview.todos.map((todo) => todo.id), ['todo-work']);
    expect(preview.rules.map((rule) => rule.id), ['rule-work']);
    expect(preview.events, isEmpty);
    expect(preview.protectedItems, contains('高数考试'));
  });

  test('low-load preview includes planned study blocks without deadlines', () {
    final now = DateTime(2026, 7, 4, 8);
    final plannedStudy = TodoTask(
      id: 'planned-study',
      title: '复习线性代数',
      createdAt: now.subtract(const Duration(days: 4)),
      scheduledAt: DateTime(2026, 7, 4, 14),
      category: '课程',
    );

    final preview = ActionPreviewService.buildLowLoadPreview(
      sourceText: '今天想降低负荷',
      now: now,
      days: 1,
      targetText: '课程',
      todos: [plannedStudy],
      events: const [],
      rules: const [],
    );

    expect(preview.todos.map((todo) => todo.id), ['planned-study']);
  });

  test('ActionPreviewService disable-future preview keeps history out', () {
    final now = DateTime(2026, 7, 4, 8);
    final futureClass = DiaryEntry(
      id: 'future-class',
      content: '高数课',
      timestamp: now,
      category: 'event',
      eventTime: DateTime(2026, 7, 5, 10),
    );
    final pastClass = DiaryEntry(
      id: 'past-class',
      content: '高数课',
      timestamp: now,
      category: 'event',
      eventTime: DateTime(2026, 7, 3, 10),
    );

    final preview = ActionPreviewService.buildDisableFuturePreview(
      sourceText: '我以后的高数课都不上了',
      now: now,
      targetText: '高数课',
      todos: const [],
      events: [futureClass, pastClass],
      rules: const [],
    );

    expect(preview.type, PendingActionType.disableFuture);
    expect(preview.events.map((entry) => entry.id), ['future-class']);
  });

  test(
    'SystemNotificationService creates stable non-zero notification IDs',
    () {
      final first = SystemNotificationService.stableNotificationId(
        'rule-1|2026-09-01T10:00:00|10',
      );
      final second = SystemNotificationService.stableNotificationId(
        'rule-1|2026-09-01T10:00:00|10',
      );
      expect(first, second);
      expect(first, isNot(0));
    },
  );

  test('notification payload recovers the occurrence date', () {
    expect(
      SystemNotificationService.notificationDateFromPayload(
        'rule-1|2026-09-03T09:00:00.000|30',
      ),
      DateTime(2026, 9, 3, 9),
    );
    expect(
      SystemNotificationService.notificationDateFromPayload(
        'rule-1:2026-09-03T09:00:00.000:30',
      ),
      DateTime(2026, 9, 3, 9),
    );
    expect(
      SystemNotificationService.notificationDateFromPayload(
        'rule-1|2026-09-01T09:00:00.000|10|occurrence=2026-09-02T14:00:00.000',
      ),
      DateTime(2026, 9, 2, 14),
    );
    expect(SystemNotificationService.notificationDateFromPayload(null), isNull);
  });

  test('timeline fallback payload keeps the event actionable', () {
    const payload =
        'timeline:course-101|2026-09-04T10:00:00.000|10|occurrence=2026-09-04T10:00:00.000';
    expect(
      SystemNotificationService.isTimelineFallbackPayload(
        payload,
        'course-101',
      ),
      isTrue,
    );
    expect(
      SystemNotificationService.isTimelineFallbackPayload(
        'timeline:course-101:2026-09-04T10:00:00.000:10',
        'course-101',
      ),
      isTrue,
    );
    expect(
      SystemNotificationService.isTimelineFallbackPayload(payload, 'other'),
      isFalse,
    );
  });

  test(
    'recurring todo reminders keep future occurrences after completion',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakeNotificationAdapter();
      SystemNotificationService.debugUseSchedulingAdapter(fake);
      final todo = TodoTask(
        id: 'daily-review',
        title: '每日复习',
        createdAt: DateTime(2026, 9, 1),
        isCompleted: true,
      );
      final rule = ReminderRule(
        id: 'daily-review-rule',
        title: todo.title,
        targetType: 'todo',
        targetId: todo.id,
        scheduleType: 'daily',
        anchorTime: DateTime(2026, 9, 1, 20),
        endDate: DateTime(2026, 9, 2),
        advanceMinutes: const [30],
      );

      await SystemNotificationService.reconcile(
        rules: [rule],
        todos: [todo],
        now: DateTime(2026, 9, 2, 8),
      );

      expect(fake.scheduledTimes, [DateTime(2026, 9, 2, 19, 30)]);
    },
  );

  test('recurring system reminders use a rolling horizon', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeNotificationAdapter();
    SystemNotificationService.debugUseSchedulingAdapter(fake);
    final rule = ReminderRule(
      id: 'rolling-daily-rule',
      title: '每日复习',
      scheduleType: 'daily',
      anchorTime: DateTime(2026, 9, 1, 20),
      advanceMinutes: const [0],
    );

    await SystemNotificationService.reconcile(
      rules: [rule],
      todos: const [],
      now: DateTime(2026, 9, 5, 8),
    );

    // 30 days from 9/5 08:00 includes the 30 evening occurrences from 9/5
    // through 10/4, rather than expanding a daily rule for a full year.
    expect(fake.scheduledTimes, hasLength(30));
    expect(
      fake.scheduledTimes.last.difference(fake.scheduledTimes.first).inDays,
      29,
    );
  });

  test('runtime reminders suppress completed todo hits', () {
    final rule = ReminderRule(
      id: 'completed-daily-rule',
      title: '已完成日常',
      targetType: 'todo',
      targetId: 'completed-daily',
      scheduleType: 'daily',
      anchorTime: DateTime(2026, 9, 2, 10),
      advanceMinutes: const [0],
    );

    expect(
      RuntimeReminderService.dueReminders(
        [rule],
        DateTime(2026, 9, 2, 10),
        completedTodoIds: {'completed-daily'},
      ),
      isEmpty,
    );
  });

  test(
    'Todo lifecycle moves through upcoming, active, overdue and completed',
    () {
      final todo = TodoTask(
        id: 'assignment',
        title: 'Report',
        createdAt: DateTime(2026, 9, 1),
        opensAt: DateTime(2026, 9, 10, 9),
        deadline: DateTime(2026, 9, 12, 23, 59),
      );
      expect(todo.lifecycleAt(DateTime(2026, 9, 9)), TodoLifecycle.upcoming);
      expect(todo.lifecycleAt(DateTime(2026, 9, 10, 9)), TodoLifecycle.active);
      expect(todo.lifecycleAt(DateTime(2026, 9, 13)), TodoLifecycle.overdue);
      todo.isCompleted = true;
      expect(todo.lifecycleAt(DateTime(2026, 9, 13)), TodoLifecycle.completed);
    },
  );

  test('notification reconcile is idempotent and replaces changes', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeNotificationAdapter();
    SystemNotificationService.debugUseSchedulingAdapter(fake);
    final rule = ReminderRule(
      id: 'class-rule',
      title: 'Tutorial',
      anchorTime: DateTime(2026, 9, 2, 10),
      advanceMinutes: const [10],
    );

    await SystemNotificationService.reconcile(
      rules: [rule],
      todos: const [],
      now: DateTime(2026, 9, 1),
    );
    await SystemNotificationService.reconcile(
      rules: [rule],
      todos: const [],
      now: DateTime(2026, 9, 1),
    );
    expect(fake.scheduled, hasLength(1));
    expect(fake.cancelled, isEmpty);

    await SystemNotificationService.reconcile(
      rules: [rule.copyWith(anchorTime: DateTime(2026, 9, 3, 10))],
      todos: const [],
      now: DateTime(2026, 9, 1),
    );
    expect(fake.scheduled, hasLength(2));
    expect(fake.cancelled, hasLength(1));
  });

  test('silent reminders stay out of operating-system notifications', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeNotificationAdapter();
    SystemNotificationService.debugUseSchedulingAdapter(fake);
    final rule = ReminderRule(
      id: 'silent-study',
      title: '安静复习',
      anchorTime: DateTime(2026, 9, 3, 20),
      advanceMinutes: const [30],
      disturbanceLevel: 'silent',
    );

    await SystemNotificationService.reconcile(
      rules: [rule],
      todos: const [],
      now: DateTime(2026, 9, 3, 8),
    );

    expect(fake.scheduled, isEmpty);
    expect(fake.shown, isEmpty);
  });

  test('reconcile surfaces a recently missed event reminder once', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeNotificationAdapter();
    SystemNotificationService.debugUseSchedulingAdapter(fake);
    final rule = ReminderRule(
      id: 'missed-event',
      title: '上课',
      targetType: 'event',
      anchorTime: DateTime(2026, 9, 2, 10),
      advanceMinutes: const [10],
    );

    await SystemNotificationService.reconcile(
      rules: [rule],
      todos: const [],
      now: DateTime(2026, 9, 2, 10, 5),
    );
    await SystemNotificationService.reconcile(
      rules: [rule],
      todos: const [],
      now: DateTime(2026, 9, 2, 10, 5),
    );

    expect(fake.shown, hasLength(1));
    expect(fake.scheduled, isEmpty);
    expect(fake.shownBodies.single, contains('10 分钟后开始'));
    expect(fake.shownBodies.single, contains('09-02 10:00'));
  });

  test(
    'reconcile surfaces a recently missed one-off todo reminder once',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakeNotificationAdapter();
      SystemNotificationService.debugUseSchedulingAdapter(fake);
      final scheduledAt = DateTime(2026, 9, 2, 10);
      final todo = TodoTask(
        id: 'missed-todo',
        title: '复习离散数学',
        createdAt: DateTime(2026, 9, 1),
        scheduledAt: scheduledAt,
      );
      final rule = ReminderRule(
        id: 'missed-todo-rule',
        title: todo.title,
        targetType: 'todo',
        targetId: todo.id,
        anchorTime: scheduledAt,
        advanceMinutes: const [0],
        note: '事项提醒',
      );

      await SystemNotificationService.reconcile(
        rules: [rule],
        todos: [todo],
        now: DateTime(2026, 9, 2, 10, 5),
      );
      await SystemNotificationService.reconcile(
        rules: [rule],
        todos: [todo],
        now: DateTime(2026, 9, 2, 10, 5),
      );

      expect(fake.shown, hasLength(1));
      expect(fake.scheduled, isEmpty);
      expect(fake.shownBodies.single, '计划现在开始');
    },
  );

  test('reconcile ignores a stale one-off todo reminder', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeNotificationAdapter();
    SystemNotificationService.debugUseSchedulingAdapter(fake);
    final scheduledAt = DateTime(2026, 9, 2, 8);
    final todo = TodoTask(
      id: 'stale-todo',
      title: '早课复习',
      createdAt: DateTime(2026, 9, 1),
      scheduledAt: scheduledAt,
    );
    final rule = ReminderRule(
      id: 'stale-todo-rule',
      title: todo.title,
      targetType: 'todo',
      targetId: todo.id,
      anchorTime: scheduledAt,
      advanceMinutes: const [0],
      note: '事项提醒',
    );

    await SystemNotificationService.reconcile(
      rules: [rule],
      todos: [todo],
      now: DateTime(2026, 9, 2, 10),
    );

    expect(fake.shown, isEmpty);
    expect(fake.scheduled, isEmpty);
  });

  test('reconcile ignores reminders attached to archived items', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeNotificationAdapter();
    SystemNotificationService.debugUseSchedulingAdapter(fake);
    final event = DiaryEntry(
      id: 'archived-class',
      content: '已归档课程',
      timestamp: DateTime(2026, 9, 1),
      category: 'event',
      eventTime: DateTime(2026, 9, 3, 10),
      isArchived: true,
    );
    final todo = TodoTask(
      id: 'archived-task',
      title: '已归档作业',
      createdAt: DateTime(2026, 9, 1),
      scheduledAt: DateTime(2026, 9, 3, 11),
      isArchived: true,
    );
    final rules = [
      ReminderRule(
        id: 'archived-event-rule',
        title: event.content,
        targetType: 'event',
        targetId: event.id,
        anchorTime: event.eventTime,
        advanceMinutes: const [10],
      ),
      ReminderRule(
        id: 'archived-todo-rule',
        title: todo.title,
        targetType: 'todo',
        targetId: todo.id,
        anchorTime: todo.scheduledAt,
        advanceMinutes: const [10],
        note: '事项提醒',
      ),
    ];

    await SystemNotificationService.reconcile(
      rules: rules,
      todos: [todo],
      events: [event],
      now: DateTime(2026, 9, 2),
    );

    expect(fake.scheduled, isEmpty);
    expect(fake.shown, isEmpty);
  });

  test(
    'reconcile ignores reminders attached to completed one-off events',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakeNotificationAdapter();
      SystemNotificationService.debugUseSchedulingAdapter(fake);
      final event = DiaryEntry(
        id: 'completed-class',
        content: '已完成课程',
        timestamp: DateTime(2026, 9, 1),
        category: 'event',
        eventTime: DateTime(2026, 9, 3, 10),
        isCompleted: true,
      );
      final rule = ReminderRule(
        id: 'completed-class-rule',
        title: event.content,
        targetType: 'event',
        targetId: event.id,
        anchorTime: event.eventTime,
        advanceMinutes: const [10],
      );

      await SystemNotificationService.reconcile(
        rules: [rule],
        todos: const [],
        events: [event],
        now: DateTime(2026, 9, 2),
      );

      expect(fake.scheduled, isEmpty);
      expect(fake.shown, isEmpty);
    },
  );

  test('reconcile ignores reminders attached to missing events', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeNotificationAdapter();
    SystemNotificationService.debugUseSchedulingAdapter(fake);
    final rule = ReminderRule(
      id: 'dangling-event-rule',
      title: '已删除的课程',
      targetType: 'event',
      targetId: 'missing-event',
      anchorTime: DateTime(2026, 9, 3, 10),
      advanceMinutes: const [10],
    );

    await SystemNotificationService.reconcile(
      rules: [rule],
      todos: const [],
      events: const [],
      now: DateTime(2026, 9, 3, 8),
    );

    expect(fake.shown, isEmpty);
    expect(fake.scheduled, isEmpty);
  });

  test(
    'switching from portable to packaged mode re-registers reminders',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakeNotificationAdapter();
      SystemNotificationService.debugUseSchedulingAdapter(fake);
      final rule = ReminderRule(
        id: 'mode-switch',
        title: '提交作业',
        targetType: 'event',
        anchorTime: DateTime(2026, 9, 3, 10),
        advanceMinutes: const [30],
      );

      SystemNotificationService.debugSetPortableWindows(true);
      await SystemNotificationService.reconcile(
        rules: [rule],
        todos: const [],
        now: DateTime(2026, 9, 2),
      );
      expect(fake.scheduled, isEmpty);

      SystemNotificationService.debugSetPortableWindows(false);
      await SystemNotificationService.reconcile(
        rules: [rule],
        todos: const [],
        now: DateTime(2026, 9, 2),
      );
      expect(fake.scheduledTimes, [DateTime(2026, 9, 3, 9, 30)]);
    },
  );

  test('execution todo reminders follow scheduledAt, not deadline', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeNotificationAdapter();
    SystemNotificationService.debugUseSchedulingAdapter(fake);
    final scheduledAt = DateTime(2026, 9, 3, 9);
    final todo = TodoTask(
      id: 'planned-study',
      title: '复习离散数学',
      createdAt: DateTime(2026, 9, 1),
      scheduledAt: scheduledAt,
      deadline: DateTime(2026, 9, 10, 23, 59),
    );
    final rule = ReminderRule(
      id: 'planned-study-reminder',
      title: todo.title,
      targetType: 'todo',
      targetId: todo.id,
      anchorTime: scheduledAt,
      advanceMinutes: const [30],
      note: '事项提醒',
    );

    await SystemNotificationService.reconcile(
      rules: [rule],
      todos: [todo],
      now: DateTime(2026, 9, 2),
    );

    expect(fake.scheduledTimes, [DateTime(2026, 9, 3, 8, 30)]);
    expect(fake.scheduledBodies, ['计划将在 30 分钟后开始']);

    todo.scheduledAt = DateTime(2026, 9, 4, 10);
    await SystemNotificationService.reconcile(
      rules: [rule.copyWith(anchorTime: todo.scheduledAt)],
      todos: [todo],
      now: DateTime(2026, 9, 2),
    );
    expect(fake.scheduledTimes, [
      DateTime(2026, 9, 3, 8, 30),
      DateTime(2026, 9, 4, 9, 30),
    ]);
    expect(fake.cancelled, hasLength(1));
  });

  test('one-off todo reminders carry a clickable occurrence payload', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeNotificationAdapter();
    SystemNotificationService.debugUseSchedulingAdapter(fake);
    final scheduledAt = DateTime(2026, 9, 3, 15);
    final todo = TodoTask(
      id: 'clickable-todo',
      title: '参加答疑',
      createdAt: DateTime(2026, 9, 1),
      scheduledAt: scheduledAt,
    );
    final rule = ReminderRule(
      id: 'clickable-todo-rule',
      title: todo.title,
      targetType: 'todo',
      targetId: todo.id,
      anchorTime: scheduledAt,
      advanceMinutes: const [15],
      note: '事项提醒',
    );

    await SystemNotificationService.reconcile(
      rules: [rule],
      todos: [todo],
      now: DateTime(2026, 9, 3, 8),
    );

    expect(fake.scheduledPayloads, hasLength(1));
    final payload = fake.scheduledPayloads.single;
    expect(payload, contains('clickable-todo-rule|'));
    expect(
      SystemNotificationService.notificationDateFromPayload(payload),
      scheduledAt,
    );
  });

  test(
    'snooze schedules a temporary follow-up without changing the rule',
    () async {
      final fake = _FakeNotificationAdapter();
      SystemNotificationService.debugUseSchedulingAdapter(fake);
      final before = DateTime.now();

      final scheduled = await SystemNotificationService.snooze(
        title: '参加答疑',
        payload: SystemNotificationService.occurrencePayload(
          'clickable-todo-rule',
          DateTime(2026, 9, 4, 15),
        ),
        delay: const Duration(minutes: 15),
      );

      expect(scheduled, isTrue);
      expect(fake.scheduled, hasLength(1));
      expect(fake.scheduledBodies.single, contains('15 分钟'));
      final delta = fake.scheduledTimes.single.difference(before);
      expect(delta, greaterThan(const Duration(minutes: 14)));
      expect(delta, lessThan(const Duration(minutes: 16)));
      expect(
        SystemNotificationService.notificationDateFromPayload(
          fake.scheduledPayloads.single,
        ),
        DateTime(2026, 9, 4, 15),
      );
    },
  );

  test(
    'portable builds persist a snooze for the running tray process',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakeNotificationAdapter();
      SystemNotificationService.debugUseSchedulingAdapter(fake);
      SystemNotificationService.debugSetPortableWindows(true);
      try {
        final scheduled = await SystemNotificationService.snooze(
          title: '自习',
          payload: 'rule|occurrence=2026-09-04T19:00:00.000',
        );
        expect(scheduled, isTrue);
        expect(fake.scheduled, isEmpty);
      } finally {
        SystemNotificationService.debugSetPortableWindows(false);
      }
    },
  );

  test('portable tray consumes a snooze only once', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeNotificationAdapter();
    SystemNotificationService.debugUseSchedulingAdapter(fake);
    SystemNotificationService.debugSetPortableWindows(true);
    try {
      final before = DateTime.now();
      final payload = SystemNotificationService.occurrencePayload(
        'portable-snooze-rule',
        DateTime(2026, 9, 4, 19),
      );
      await SystemNotificationService.snooze(
        title: '自习',
        payload: payload,
        delay: const Duration(minutes: 15),
      );

      final first = await SystemNotificationService.runPortableRuntimeFallback(
        rules: const [],
        todos: const [],
        events: const [],
        now: before.add(const Duration(minutes: 16)),
      );
      final second = await SystemNotificationService.runPortableRuntimeFallback(
        rules: const [],
        todos: const [],
        events: const [],
        now: before.add(const Duration(minutes: 17)),
      );

      expect(first, 1);
      expect(second, 0);
      expect(fake.shownBodies, ['15 分钟后再次提醒']);
      expect(fake.shownPayloads.single, payload);
    } finally {
      SystemNotificationService.debugSetPortableWindows(false);
    }
  });

  test(
    'unscheduled execution reminders do not fall back to the deadline',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakeNotificationAdapter();
      SystemNotificationService.debugUseSchedulingAdapter(fake);
      final todo = TodoTask(
        id: 'unscheduled-study',
        title: '复习概率论',
        createdAt: DateTime(2026, 9, 1),
        deadline: DateTime(2026, 9, 10, 23, 59),
      );
      final rule = ReminderRule(
        id: 'unscheduled-study-reminder',
        title: todo.title,
        targetType: 'todo',
        targetId: todo.id,
        anchorTime: DateTime(2026, 9, 3, 9),
        advanceMinutes: const [30],
        note: '事项提醒',
      );

      await SystemNotificationService.reconcile(
        rules: [rule],
        todos: [todo],
        now: DateTime(2026, 9, 2),
      );

      expect(fake.scheduledTimes, isEmpty);
    },
  );

  test('portable runtime fallback shows each due reminder only once', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeNotificationAdapter();
    SystemNotificationService.debugUseSchedulingAdapter(fake);
    SystemNotificationService.debugSetPortableWindows(true);
    final eventTime = DateTime(2026, 9, 2, 10, 15);
    final rule = ReminderRule(
      id: 'portable-event',
      title: '离散数学复习',
      targetType: 'event',
      anchorTime: eventTime,
      advanceMinutes: const [10],
    );

    final first = await SystemNotificationService.runPortableRuntimeFallback(
      rules: [rule],
      todos: const [],
      events: const [],
      now: DateTime(2026, 9, 2, 10, 10),
    );
    final second = await SystemNotificationService.runPortableRuntimeFallback(
      rules: [rule],
      todos: const [],
      events: const [],
      now: DateTime(2026, 9, 2, 10, 10, 30),
    );

    expect(first, 1);
    expect(second, 0);
    expect(fake.shownBodies, ['10 分钟后开始']);
  });

  test('portable fallback distinguishes a todo deadline reminder', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeNotificationAdapter();
    SystemNotificationService.debugUseSchedulingAdapter(fake);
    SystemNotificationService.debugSetPortableWindows(true);
    final deadline = DateTime(2026, 9, 2, 10, 45);
    final todo = TodoTask(
      id: 'portable-deadline-todo',
      title: '提交实验报告',
      createdAt: DateTime(2026, 9, 1),
      deadline: deadline,
    );
    final rule = ReminderRule(
      id: 'portable-deadline-rule',
      title: todo.title,
      targetType: 'todo',
      targetId: todo.id,
      anchorTime: deadline,
      advanceMinutes: const [30],
    );

    final shown = await SystemNotificationService.runPortableRuntimeFallback(
      rules: [rule],
      todos: [todo],
      events: const [],
      now: DateTime(2026, 9, 2, 10, 15),
    );

    expect(shown, 1);
    expect(fake.shownBodies, ['作业将在 30 分钟后截止']);
  });

  test(
    'portable execution reminder follows the todo plan after rescheduling',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakeNotificationAdapter();
      SystemNotificationService.debugUseSchedulingAdapter(fake);
      SystemNotificationService.debugSetPortableWindows(true);
      try {
        final todo = TodoTask(
          id: 'portable-rescheduled-todo',
          title: '复习数据结构',
          createdAt: DateTime(2026, 9, 1),
          scheduledAt: DateTime(2026, 9, 2, 11),
        );
        final staleRule = ReminderRule(
          id: 'portable-rescheduled-rule',
          title: todo.title,
          targetType: 'todo',
          targetId: todo.id,
          anchorTime: DateTime(2026, 9, 2, 10),
          advanceMinutes: const [0],
          note: '事项提醒',
        );

        // The old rule timestamp is already due, but the task was moved to
        // 11:00. The tray must not show the stale 10:00 notification.
        final beforeReschedule =
            await SystemNotificationService.runPortableRuntimeFallback(
              rules: [staleRule],
              todos: [todo],
              events: const [],
              now: DateTime(2026, 9, 2, 10),
            );
        expect(beforeReschedule, 0);

        // Clearing the plan also clears the effective execution trigger,
        // even if an older build left an anchor on the reminder rule.
        todo.scheduledAt = null;
        final unscheduled =
            await SystemNotificationService.runPortableRuntimeFallback(
              rules: [staleRule],
              todos: [todo],
              events: const [],
              now: DateTime(2026, 9, 2, 10, 30),
            );
        expect(unscheduled, 0);

        // Scheduling it again makes the new time the only effective trigger.
        todo.scheduledAt = DateTime(2026, 9, 2, 11);
        final afterReschedule =
            await SystemNotificationService.runPortableRuntimeFallback(
              rules: [staleRule],
              todos: [todo],
              events: const [],
              now: DateTime(2026, 9, 2, 11),
            );
        expect(afterReschedule, 1);
        expect(fake.shownBodies, ['计划现在开始']);
      } finally {
        SystemNotificationService.debugSetPortableWindows(false);
      }
    },
  );

  test(
    'portable event reminder follows the event time after rescheduling',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakeNotificationAdapter();
      SystemNotificationService.debugUseSchedulingAdapter(fake);
      SystemNotificationService.debugSetPortableWindows(true);
      try {
        final event = DiaryEntry(
          id: 'portable-rescheduled-event',
          content: '线性代数课',
          timestamp: DateTime(2026, 9, 1),
          category: 'event',
          eventTime: DateTime(2026, 9, 2, 11),
        );
        final staleRule = ReminderRule(
          id: 'portable-rescheduled-event-rule',
          title: event.content,
          targetType: 'event',
          targetId: event.id,
          anchorTime: DateTime(2026, 9, 2, 10),
          advanceMinutes: const [0],
        );

        final beforeReschedule =
            await SystemNotificationService.runPortableRuntimeFallback(
              rules: [staleRule],
              todos: const [],
              events: [event],
              now: DateTime(2026, 9, 2, 10),
            );
        expect(beforeReschedule, 0);

        final afterReschedule =
            await SystemNotificationService.runPortableRuntimeFallback(
              rules: [staleRule],
              todos: const [],
              events: [event],
              now: DateTime(2026, 9, 2, 11),
            );
        expect(afterReschedule, 1);
        expect(fake.shownBodies, ['现在开始']);
      } finally {
        SystemNotificationService.debugSetPortableWindows(false);
      }
    },
  );

  test(
    'system event notification uses the current event time when a rule is stale',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakeNotificationAdapter();
      SystemNotificationService.debugUseSchedulingAdapter(fake);
      final event = DiaryEntry(
        id: 'system-rescheduled-event',
        content: '概率论课',
        timestamp: DateTime(2026, 9, 1),
        category: 'event',
        eventTime: DateTime(2026, 9, 2, 11),
      );
      final staleRule = ReminderRule(
        id: 'system-rescheduled-event-rule',
        title: event.content,
        targetType: 'event',
        targetId: event.id,
        anchorTime: DateTime(2026, 9, 2, 10),
        advanceMinutes: const [0],
      );

      await SystemNotificationService.reconcile(
        rules: [staleRule],
        todos: const [],
        events: [event],
        now: DateTime(2026, 9, 2, 9),
      );

      expect(fake.scheduledTimes, [DateTime(2026, 9, 2, 11)]);
    },
  );

  test('portable fallback respects a disabled event reminder rule', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeNotificationAdapter();
    SystemNotificationService.debugUseSchedulingAdapter(fake);
    SystemNotificationService.debugSetPortableWindows(true);
    final eventTime = DateTime(2026, 9, 2, 10, 15);
    final event = DiaryEntry(
      id: 'muted-event',
      content: '不提醒的课程',
      timestamp: DateTime(2026, 9, 2),
      category: 'event',
      eventTime: eventTime,
    );
    final disabledRule = ReminderRule(
      id: 'muted-event-rule',
      title: event.content,
      targetType: 'event',
      targetId: event.id,
      anchorTime: eventTime,
      status: 'disabled',
      advanceMinutes: const [10],
    );

    final shown = await SystemNotificationService.runPortableRuntimeFallback(
      rules: const [],
      allRules: [disabledRule],
      todos: const [],
      events: [event],
      now: DateTime(2026, 9, 2, 10, 10),
    );

    expect(shown, 0);
    expect(fake.shownBodies, isEmpty);
  });

  test(
    'Recurrence service applies boundaries, skips, overrides and endCount',
    () {
      final rule = ReminderRule(
        title: 'Tutorial',
        scheduleType: 'weekly',
        anchorTime: DateTime(2026, 9, 7, 10),
        startDate: DateTime(2026, 9, 7),
        endDate: DateTime(2026, 10, 31),
        endCount: 4,
        byDay: const [DateTime.monday],
        skipDates: [DateTime(2026, 9, 14)],
        overrides: [
          RecurrenceOverride(
            originalDate: DateTime(2026, 9, 21),
            newTime: DateTime(2026, 9, 22, 14, 30),
          ),
          RecurrenceOverride(
            originalDate: DateTime(2026, 9, 28),
            isCompleted: true,
          ),
        ],
      );
      final values = RecurrenceService.occurrencesBetween(
        rule,
        DateTime(2026, 9, 1),
        DateTime(2026, 10, 31, 23, 59),
      );
      expect(values.map((item) => item.scheduledTime), [
        DateTime(2026, 9, 7, 10),
        DateTime(2026, 9, 22, 14, 30),
      ]);
    },
  );

  test('Recurrence service never emits before an anchor without startDate', () {
    final rule = ReminderRule(
      title: 'Lecture',
      scheduleType: 'weekly',
      anchorTime: DateTime(2026, 9, 10, 9),
      byDay: const [DateTime.monday, DateTime.thursday],
    );
    final values = RecurrenceService.occurrencesBetween(
      rule,
      DateTime(2026, 9, 1),
      DateTime(2026, 9, 15),
    );
    expect(values.first.scheduledTime, DateTime(2026, 9, 10, 9));
  });

  test(
    'Timeline day summary includes same-day events, deadlines, and open todos',
    () {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final events = [
        DiaryEntry(
          id: 'event-today',
          content: 'Project meeting',
          timestamp: day,
          category: 'event',
          eventTime: DateTime(day.year, day.month, day.day, 9, 30),
        ),
        DiaryEntry(
          id: 'event-other-day',
          content: 'Other day',
          timestamp: day,
          category: 'event',
          eventTime: DateTime(day.year, day.month, day.day + 1, 9),
        ),
      ];
      final todos = [
        TodoTask(
          id: 'deadline-today',
          title: 'Submit form',
          createdAt: day,
          priority: 'B',
          deadline: DateTime(day.year, day.month, day.day, 18),
        ),
        TodoTask(
          id: 'no-time-info',
          title: 'Buy milk',
          createdAt: day,
          priority: 'C',
          sourceEntryId: 'draft-source',
        ),
        TodoTask(
          id: 'event-synced',
          title: 'Synced event todo',
          createdAt: day,
          priority: 'A',
          sourceEntryId: 'event-today',
        ),
        TodoTask(
          id: 'completed',
          title: 'Already done',
          createdAt: day,
          isCompleted: true,
          deadline: DateTime(day.year, day.month, day.day),
        ),
        TodoTask(
          id: 'future-deadline',
          title: 'Future deadline',
          createdAt: day,
          priority: 'A',
          deadline: DateTime(day.year, day.month, day.day + 1, 12),
        ),
      ];

      final summary = buildTimelineDaySummary(
        day: day,
        events: events,
        todos: todos,
      );

      expect(summary.events.map((entry) => entry.id), ['event-today']);
      // 已完成的待办保留在 deadline 列表中（划线但不消失）
      expect(summary.deadlineTodos.map((todo) => todo.id), [
        'deadline-today',
        'completed',
      ]);
      expect(summary.actionTodos.map((todo) => todo.id), ['no-time-info']);
      expect(summary.items.map((item) => item.title), [
        'Project meeting',
        'Submit form',
        'Already done',
        'Buy milk',
      ]);
    },
  );

  test('Timeline summary can exclude floating todos from dated views', () {
    final day = DateTime(2026, 7, 8);
    final todos = [
      TodoTask(
        id: 'floating',
        title: 'Buy milk',
        createdAt: day,
        priority: 'A',
      ),
      TodoTask(
        id: 'deadline',
        title: 'Submit form',
        createdAt: day,
        priority: 'B',
        deadline: DateTime(2026, 7, 8, 18),
      ),
      TodoTask(
        id: 'scheduled',
        title: 'Review notes',
        createdAt: day,
        priority: 'B',
        scheduledAt: DateTime(2026, 7, 8, 10),
      ),
    ];

    final summary = buildTimelineDaySummary(
      day: day,
      events: const [],
      todos: todos,
      floatingTodoPolicy: TimelineFloatingTodoPolicy.exclude,
    );

    expect(summary.deadlineTodos.map((todo) => todo.id), ['deadline']);
    expect(summary.actionTodos.map((todo) => todo.id), ['scheduled']);
    expect(summary.items.map((item) => item.id), ['deadline', 'scheduled']);
  });

  test('Future day summary does not pull historical overdue deadlines', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final todos = [
      TodoTask(
        id: 'old-overdue',
        title: 'Old overdue work',
        createdAt: today,
        deadline: today.subtract(const Duration(days: 1)),
      ),
      TodoTask(
        id: 'tomorrow-deadline',
        title: 'Tomorrow work',
        createdAt: today,
        deadline: tomorrow.add(const Duration(hours: 18)),
      ),
    ];

    final summary = buildTimelineDaySummary(
      day: tomorrow,
      events: const [],
      todos: todos,
      includeOverdueDeadlines: false,
    );

    expect(summary.deadlineTodos.map((todo) => todo.id), ['tomorrow-deadline']);
  });

  test('Week timeline excludes floating todos from every day card', () {
    final weekStart = DateTime(2026, 7, 6);
    final todos = [
      TodoTask(
        id: 'floating',
        title: 'Buy milk',
        createdAt: weekStart,
        priority: 'A',
      ),
      TodoTask(
        id: 'deadline',
        title: 'Submit form',
        createdAt: weekStart,
        priority: 'A',
        deadline: DateTime(2026, 7, 8, 18),
      ),
    ];

    final week = buildWeekTimelineSummary(
      weekStart: weekStart,
      events: const [],
      todos: todos,
    );

    expect(
      week.days.expand((day) => day.actionTodos).map((todo) => todo.id),
      isEmpty,
    );
    expect(
      week.days.expand((day) => day.deadlineTodos).map((todo) => todo.id),
      ['deadline'],
    );
  });

  test(
    'Timeline rail layout scales by events and keeps proportional anchors',
    () {
      final first = DateTime(2026, 7, 8, 9);
      final second = DateTime(2026, 7, 8, 9, 5);
      final third = DateTime(2026, 7, 8, 18);

      final layout = TimelineRailLayout.compute([first, second, third]);

      expect(layout.height, 240);
      expect(layout.anchorTop(first), 90);
      expect(layout.anchorTop(third), 180);
      expect(layout.contentTop(second), greaterThan(layout.contentTop(first)));
      expect(layout.contentTop(second) - layout.contentTop(first), 42);
    },
  );

  test('Timeline day todo ordering favors overdue before today deadline', () {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final todos = [
      TodoTask(
        id: 'today-c',
        title: 'Today deadline',
        createdAt: day,
        priority: 'C',
        deadline: DateTime(day.year, day.month, day.day, 23),
      ),
      TodoTask(
        id: 'today-a',
        title: 'Today A deadline',
        createdAt: day,
        priority: 'A',
        deadline: DateTime(day.year, day.month, day.day, 12),
      ),
      TodoTask(
        id: 'other-day-a',
        title: 'Other day A',
        createdAt: day,
        priority: 'A',
        deadline: DateTime(day.year, day.month, day.day + 1, 12),
      ),
      TodoTask(
        id: 'overdue-b',
        title: 'Overdue B',
        createdAt: day,
        priority: 'B',
        deadline: DateTime(day.year, day.month, day.day - 1, 18),
      ),
      TodoTask(
        id: 'open-a',
        title: 'Open A',
        createdAt: day.subtract(const Duration(minutes: 1)),
        priority: 'A',
      ),
    ];

    final summary = buildTimelineDaySummary(
      day: day,
      events: const [],
      todos: todos,
    );

    expect(summary.deadlineTodos.map((todo) => todo.id), [
      'overdue-b',
      'today-a',
      'today-c',
    ]);
    expect(summary.actionTodos.map((todo) => todo.id), ['open-a']);
  });

  // ── 重复事件虚拟投影测试 ──

  test('Recurring daily event projects to future days', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0);
    final targetDay = DateTime(2026, 7, 4); // 3 天后

    final events = [
      DiaryEntry(
        id: 'daily-standup',
        content: '站会',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-standup',
        title: '站会',
        targetType: 'event',
        targetId: 'daily-standup',
        scheduleType: 'daily',
        anchorTime: anchorDay,
      ),
    ];

    final summary = buildTimelineDaySummary(
      day: targetDay,
      events: events,
      todos: const [],
      rules: rules,
    );

    // 投影事件应出现在目标日
    expect(summary.events.length, 1);
    expect(summary.events.first.id, 'daily-standup');
    // eventTime 应为目标日 + 原始时分
    expect(summary.events.first.sortTime, DateTime(2026, 7, 4, 9, 0));
  });

  test('Recurring weekly event projects to same weekday', () {
    // 锚点是周三 7月1日
    final anchorDay = DateTime(2026, 7, 1, 10, 0); // 周三
    final targetDay = DateTime(2026, 7, 8); // 下周三

    final events = [
      DiaryEntry(
        id: 'weekly-meeting',
        content: '周会',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-weekly',
        title: '周会',
        targetType: 'event',
        targetId: 'weekly-meeting',
        scheduleType: 'weekly',
        anchorTime: anchorDay,
      ),
    ];

    final summary = buildTimelineDaySummary(
      day: targetDay,
      events: events,
      todos: const [],
      rules: rules,
    );

    expect(summary.events.length, 1);
    expect(summary.events.first.sortTime, DateTime(2026, 7, 8, 10, 0));
  });

  test('Weekly event does not project to different weekday', () {
    final anchorDay = DateTime(2026, 7, 1, 10, 0); // 周三
    final targetDay = DateTime(2026, 7, 3); // 周五（不是周三）

    final events = [
      DiaryEntry(
        id: 'weekly-meeting',
        content: '周会',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-weekly',
        title: '周会',
        targetType: 'event',
        targetId: 'weekly-meeting',
        scheduleType: 'weekly',
        anchorTime: anchorDay,
      ),
    ];

    final summary = buildTimelineDaySummary(
      day: targetDay,
      events: events,
      todos: const [],
      rules: rules,
    );

    // 周五不是周三，不应投影
    expect(summary.events, isEmpty);
  });

  test('Dedup: no projection when original event is already on target day', () {
    final anchorDay = DateTime(2026, 7, 4, 9, 0);
    final targetDay = DateTime(2026, 7, 4); // 同一天

    final events = [
      DiaryEntry(
        id: 'daily-task',
        content: '每日任务',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-daily',
        title: '每日任务',
        targetType: 'event',
        targetId: 'daily-task',
        scheduleType: 'daily',
        anchorTime: anchorDay,
      ),
    ];

    final summary = buildTimelineDaySummary(
      day: targetDay,
      events: events,
      todos: const [],
      rules: rules,
    );

    // 真实事件已存在，不产生额外投影
    expect(summary.events.length, 1);
    expect(summary.events.first.id, 'daily-task');
    expect(summary.events.first.sortTime, anchorDay);
  });

  test('Once scheduleType does not project', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0);
    final targetDay = DateTime(2026, 7, 4);

    final events = [
      DiaryEntry(
        id: 'one-time',
        content: '一次性事件',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-once',
        title: '一次性事件',
        targetType: 'event',
        targetId: 'one-time',
        scheduleType: 'once',
        anchorTime: anchorDay,
      ),
    ];

    final summary = buildTimelineDaySummary(
      day: targetDay,
      events: events,
      todos: const [],
      rules: rules,
    );

    // once 不投影
    expect(summary.events, isEmpty);
  });

  test('Recurring every_n_days event projects at correct interval', () {
    final anchorDay = DateTime(2026, 7, 1, 8, 0);
    final matchDay = DateTime(2026, 7, 5); // diff=4 天，interval=2，4%2=0 应匹配

    final events = [
      DiaryEntry(
        id: 'every-2-days',
        content: '隔天任务',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-interval',
        title: '隔天任务',
        targetType: 'event',
        targetId: 'every-2-days',
        scheduleType: 'every_n_days',
        scheduleInterval: 2,
        anchorTime: anchorDay,
      ),
    ];

    final summary = buildTimelineDaySummary(
      day: matchDay,
      events: events,
      todos: const [],
      rules: rules,
    );

    expect(summary.events.length, 1);
    expect(summary.events.first.sortTime, DateTime(2026, 7, 5, 8, 0));
  });

  test('Recurring every_n_days skips non-matching interval day', () {
    final anchorDay = DateTime(2026, 7, 1, 8, 0);

    final events = [
      DiaryEntry(
        id: 'every-2-days',
        content: '隔天任务',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-interval',
        title: '隔天任务',
        targetType: 'event',
        targetId: 'every-2-days',
        scheduleType: 'every_n_days',
        scheduleInterval: 2,
        anchorTime: anchorDay,
      ),
    ];

    // 7/4: diff=3, 3%2=1 → 不匹配
    final summary = buildTimelineDaySummary(
      day: DateTime(2026, 7, 4),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(summary.events, isEmpty);
  });

  test('Recurring monthly event projects to same day of month', () {
    final anchorDay = DateTime(2026, 7, 15, 14, 0);

    final events = [
      DiaryEntry(
        id: 'monthly-bill',
        content: '还信用卡',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-monthly',
        title: '还信用卡',
        targetType: 'event',
        targetId: 'monthly-bill',
        scheduleType: 'monthly',
        anchorTime: anchorDay,
      ),
    ];

    // 8月15日：同月日，应投影
    final matchSummary = buildTimelineDaySummary(
      day: DateTime(2026, 8, 15),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(matchSummary.events.length, 1);
    expect(matchSummary.events.first.sortTime, DateTime(2026, 8, 15, 14, 0));

    // 8月16日：不同月日，不投影
    final skipSummary = buildTimelineDaySummary(
      day: DateTime(2026, 8, 16),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(skipSummary.events, isEmpty);
  });

  test('Inactive or archived rules do not project', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0);
    final targetDay = DateTime(2026, 7, 4);

    final events = [
      DiaryEntry(
        id: 'task',
        content: '任务',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-archived',
        title: '任务',
        targetType: 'event',
        targetId: 'task',
        scheduleType: 'daily',
        anchorTime: anchorDay,
        status: 'archived',
      ),
    ];

    final summary = buildTimelineDaySummary(
      day: targetDay,
      events: events,
      todos: const [],
      rules: rules,
    );

    // 已归档规则不投影
    expect(summary.events, isEmpty);
  });

  test('Non-event category entries are not projected', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0);
    final targetDay = DateTime(2026, 7, 4);

    final events = [
      DiaryEntry(
        id: 'draft-entry',
        content: '草稿',
        timestamp: anchorDay,
        category: 'draft',
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-draft',
        title: '草稿',
        targetType: 'event',
        targetId: 'draft-entry',
        scheduleType: 'daily',
        anchorTime: anchorDay,
      ),
    ];

    final summary = buildTimelineDaySummary(
      day: targetDay,
      events: events,
      todos: const [],
      rules: rules,
    );

    // draft 类型不投影
    expect(summary.events, isEmpty);
  });

  test('Projected events do not duplicate in week view across days', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0); // 周三
    final weekStart = DateTime(2026, 7, 6); // 周一

    final events = [
      DiaryEntry(
        id: 'daily-task',
        content: '每日任务',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
      DiaryEntry(
        id: 'normal-event',
        content: '普通事件',
        timestamp: DateTime(2026, 7, 8),
        category: 'event',
        eventTime: DateTime(2026, 7, 8, 14, 0),
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-daily',
        title: '每日任务',
        targetType: 'event',
        targetId: 'daily-task',
        scheduleType: 'daily',
        anchorTime: anchorDay,
      ),
    ];

    final week = buildWeekTimelineSummary(
      weekStart: weekStart,
      events: events,
      todos: const [],
      rules: rules,
    );

    // 每天（周一到周日）都应有 daily-task 的投影
    for (var i = 0; i < 7; i++) {
      final day = week.days[i];
      expect(
        day.events.any((e) => e.id == 'daily-task'),
        isTrue,
        reason: 'Day $i should have daily-task projection',
      );
    }

    // 7月8日（周三）：既有 daily-task 投影，也有 normal-event 真实事件
    final wedIdx = 2; // 7月8日是周三，周一开始第3天（0-indexed: 2）
    final wedEvents = week.days[wedIdx].events;
    expect(wedEvents.where((e) => e.id == 'daily-task').length, 1);
    expect(wedEvents.where((e) => e.id == 'normal-event').length, 1);
    expect(wedEvents.length, 2);
  });

  // ── 实例形态 + 生命周期测试 ──

  test('Spanning displayMode shows event every day within interval window', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0);
    // every_n_days, interval=30, spanning → Day 1-30 都可见

    final events = [
      DiaryEntry(
        id: 'change-sheets',
        content: '换床单',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-sheets',
        title: '换床单',
        targetType: 'event',
        targetId: 'change-sheets',
        scheduleType: 'every_n_days',
        scheduleInterval: 30,
        displayMode: 'spanning',
        anchorTime: anchorDay,
      ),
    ];

    // Day 1 (锚点日): 不投影（原始事件已在这一天）
    final summaryDay1 = buildTimelineDaySummary(
      day: DateTime(2026, 7, 1),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(summaryDay1.events.length, 1); // 原始事件本身

    // Day 15 (窗口内第15天): 应投影
    final summaryDay15 = buildTimelineDaySummary(
      day: DateTime(2026, 7, 15),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(summaryDay15.events.length, 1);
    expect(summaryDay15.events.first.id, 'change-sheets');

    // Day 30 (窗口最后一天): 应投影
    final summaryDay30 = buildTimelineDaySummary(
      day: DateTime(2026, 7, 30),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(summaryDay30.events.length, 1);

    // Day 31 (下一周期): 应投影（属于新窗口）
    final summaryDay31 = buildTimelineDaySummary(
      day: DateTime(2026, 7, 31),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(summaryDay31.events.length, 1);
  });

  test('Punctual displayMode still shows event only on projection day', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0); // 周三

    final events = [
      DiaryEntry(
        id: 'meet-teacher',
        content: '找老师聊天',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-teacher',
        title: '找老师聊天',
        targetType: 'event',
        targetId: 'meet-teacher',
        scheduleType: 'weekly',
        displayMode: 'punctual',
        anchorTime: anchorDay,
      ),
    ];

    // 下周三：应投影
    final nextWed = buildTimelineDaySummary(
      day: DateTime(2026, 7, 8),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(nextWed.events.length, 1);

    // 周四：不应投影
    final thu = buildTimelineDaySummary(
      day: DateTime(2026, 7, 9),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(thu.events, isEmpty);
  });

  test('EndDate stops projection after specified date', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0);

    final events = [
      DiaryEntry(
        id: 'daily-task',
        content: '每日任务',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-daily-limited',
        title: '每日任务',
        targetType: 'event',
        targetId: 'daily-task',
        scheduleType: 'daily',
        displayMode: 'punctual',
        anchorTime: anchorDay,
        endDate: DateTime(2026, 7, 5), // 7月5日截止
      ),
    ];

    // 7月5日（截止日当天）：应投影
    final onEnd = buildTimelineDaySummary(
      day: DateTime(2026, 7, 5),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(onEnd.events.length, 1);

    // 7月6日（截止日后）：不应投影
    final afterEnd = buildTimelineDaySummary(
      day: DateTime(2026, 7, 6),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(afterEnd.events, isEmpty);
  });

  test('Spanning with endDate stops entire window after end date', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0);

    final events = [
      DiaryEntry(
        id: 'sheets-limited',
        content: '换床单（限时）',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-sheets-limited',
        title: '换床单（限时）',
        targetType: 'event',
        targetId: 'sheets-limited',
        scheduleType: 'every_n_days',
        scheduleInterval: 30,
        displayMode: 'spanning',
        anchorTime: anchorDay,
        endDate: DateTime(2026, 8, 15), // ~1.5个月后截止
      ),
    ];

    // 7月15日（在截止前，第1个窗口内）：应投影
    final beforeEnd = buildTimelineDaySummary(
      day: DateTime(2026, 7, 15),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(beforeEnd.events.length, 1);

    // 8月16日（超过 endDate）：不应投影
    final afterEnd = buildTimelineDaySummary(
      day: DateTime(2026, 8, 16),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(afterEnd.events, isEmpty);
  });

  test('Default displayMode is punctual (backward compatible)', () {
    // 不传 displayMode 时，行为与旧版完全相同
    final anchorDay = DateTime(2026, 7, 1, 9, 0);

    final events = [
      DiaryEntry(
        id: 'daily-default',
        content: '默认行为',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-default',
        title: '默认行为',
        targetType: 'event',
        targetId: 'daily-default',
        scheduleType: 'daily',
        anchorTime: anchorDay,
        // displayMode 未指定 → 默认 'punctual'
      ),
    ];

    // 投影日当天正常投影
    final summary = buildTimelineDaySummary(
      day: DateTime(2026, 7, 4),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(summary.events.length, 1);
  });

  test(
    'customSpan displayMode shows event for specified days after projection',
    () {
      final anchorDay = DateTime(2026, 7, 1, 9, 0);

      final events = [
        DiaryEntry(
          id: 'custom-span-task',
          content: '提前提醒任务',
          timestamp: anchorDay,
          category: 'event',
          eventTime: anchorDay,
        ),
      ];
      final rules = [
        ReminderRule(
          id: 'rule-custom-span',
          title: '提前提醒任务',
          targetType: 'event',
          targetId: 'custom-span-task',
          scheduleType: 'every_n_days',
          scheduleInterval: 30,
          displayMode: 'customSpan',
          customSpanDays: 7,
          anchorTime: anchorDay,
        ),
      ];

      // Day 2 (投影日后第1天): 在 7 天窗口内 → 应投影
      final inWindow = buildTimelineDaySummary(
        day: DateTime(2026, 7, 2),
        events: events,
        todos: const [],
        rules: rules,
      );
      expect(inWindow.events.length, 1);

      // Day 8 (投影日后第7天): 刚好超出 7 天窗口 → 不应投影
      final outWindow = buildTimelineDaySummary(
        day: DateTime(2026, 7, 8),
        events: events,
        todos: const [],
        rules: rules,
      );
      expect(outWindow.events, isEmpty);
    },
  );

  test('StartDate blocks projection before start date', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0);
    final events = [
      DiaryEntry(
        id: 'delayed-task',
        content: '延迟任务',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-delayed',
        title: '延迟任务',
        targetType: 'event',
        targetId: 'delayed-task',
        scheduleType: 'daily',
        anchorTime: anchorDay,
        startDate: DateTime(2026, 7, 10),
      ),
    ];

    // 7月5日（早于 startDate）：不投影
    final before = buildTimelineDaySummary(
      day: DateTime(2026, 7, 5),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(before.events, isEmpty);

    // 7月10日（startDate当天）：应投影
    final onStart = buildTimelineDaySummary(
      day: DateTime(2026, 7, 10),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(onStart.events.length, 1);
  });

  // ── Phase 2: byDay 多日限定测试 ──

  test('weekly with byDay projects to specified weekdays', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0); // 周三
    // byDay: [1, 3, 5] = 周一三五
    // anchor.weekday=3(周三) 已包含在 byDay 中

    final events = [
      DiaryEntry(
        id: 'run',
        content: '跑步',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-run',
        title: '跑步',
        targetType: 'event',
        targetId: 'run',
        scheduleType: 'weekly',
        displayMode: 'punctual',
        byDay: [1, 3, 5],
        anchorTime: anchorDay,
      ),
    ];

    // 7月6日 周一 (weekday=1)：应投影
    final mon = buildTimelineDaySummary(
      day: DateTime(2026, 7, 6), // 周一
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(mon.events.length, 1);

    // 7月7日 周二 (weekday=2)：不应投影
    final tue = buildTimelineDaySummary(
      day: DateTime(2026, 7, 7), // 周二
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(tue.events, isEmpty);

    // 7月8日 周三 (weekday=3)：应投影
    final wed = buildTimelineDaySummary(
      day: DateTime(2026, 7, 8), // 周三
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(wed.events.length, 1);

    // 7月10日 周五 (weekday=5)：应投影
    final fri = buildTimelineDaySummary(
      day: DateTime(2026, 7, 10), // 周五
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(fri.events.length, 1);
  });

  test('weekly with byDay + spanning: each projection gets its own window', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0); // 周三
    // byDay: [3, 5] = 周三、周五 + spanning
    // 周三窗口: 周三~周四, 周五窗口: 周五~下周二

    final events = [
      DiaryEntry(
        id: 'task',
        content: '多日任务',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-task',
        title: '多日任务',
        targetType: 'event',
        targetId: 'task',
        scheduleType: 'weekly',
        displayMode: 'spanning',
        byDay: [3, 5],
        anchorTime: anchorDay,
      ),
    ];

    // 7月8日 周三（投影日）：应投影
    final wed = buildTimelineDaySummary(
      day: DateTime(2026, 7, 8), // 周三
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(wed.events.length, 1);

    // 7月9日 周四（在周三窗口内）：应投影
    final thu = buildTimelineDaySummary(
      day: DateTime(2026, 7, 9), // 周四
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(thu.events.length, 1);

    // 7月10日 周五（新的投影日，也是新窗口起点）：应投影
    final fri = buildTimelineDaySummary(
      day: DateTime(2026, 7, 10), // 周五
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(fri.events.length, 1);

    // 7月11日 周六（在周五窗口内至下周三前）：应投影
    final sat = buildTimelineDaySummary(
      day: DateTime(2026, 7, 11), // 周六
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(sat.events.length, 1);
  });

  test('monthly with byMonthDay projects to specified days', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0);

    final events = [
      DiaryEntry(
        id: 'bill-reminder',
        content: '账单日',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-bill',
        title: '账单日',
        targetType: 'event',
        targetId: 'bill-reminder',
        scheduleType: 'monthly',
        displayMode: 'punctual',
        byMonthDay: [15, 30],
        anchorTime: anchorDay,
      ),
    ];

    // 7月15日：应投影
    final d15 = buildTimelineDaySummary(
      day: DateTime(2026, 7, 15),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(d15.events.length, 1);

    // 7月16日：不应投影
    final d16 = buildTimelineDaySummary(
      day: DateTime(2026, 7, 16),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(d16.events, isEmpty);

    // 7月30日：应投影
    final d30 = buildTimelineDaySummary(
      day: DateTime(2026, 7, 30),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(d30.events.length, 1);

    // 2月只有28天：byMonthDay 的 30 应自动 clamp 到 28
    final feb28 = buildTimelineDaySummary(
      day: DateTime(2027, 2, 28),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(feb28.events.length, 1);
  });

  test('monthly scheduleDay projects when byMonthDay is absent', () {
    final anchor = DateTime(2026, 7, 1, 9);
    final events = [
      DiaryEntry(
        id: 'monthly-schedule-day',
        content: '固定月度事项',
        timestamp: anchor,
        category: 'event',
        eventTime: anchor,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-schedule-day',
        title: '固定月度事项',
        targetType: 'event',
        targetId: 'monthly-schedule-day',
        scheduleType: 'monthly',
        scheduleDay: 15,
        anchorTime: anchor,
      ),
    ];

    expect(
      buildTimelineDaySummary(
        day: DateTime(2026, 7, 15),
        events: events,
        todos: const [],
        rules: rules,
      ).events,
      hasLength(1),
    );
    expect(
      buildTimelineDaySummary(
        day: DateTime(2026, 7, 2),
        events: events,
        todos: const [],
        rules: rules,
      ).events,
      isEmpty,
    );
  });

  test('weekly byDay defaults to anchor weekday when not specified', () {
    // byDay == null → 行为与 Phase 1 完全相同
    final anchorDay = DateTime(2026, 7, 1, 9, 0); // 周三

    final events = [
      DiaryEntry(
        id: 'meeting',
        content: '周会',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-meeting',
        title: '周会',
        targetType: 'event',
        targetId: 'meeting',
        scheduleType: 'weekly',
        // byDay 未设 → 默认 [anchor.weekday] = [3]
        anchorTime: anchorDay,
      ),
    ];

    // 下周三应投影
    final nextWed = buildTimelineDaySummary(
      day: DateTime(2026, 7, 8),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(nextWed.events.length, 1);

    // 下周四不应投影
    final nextThu = buildTimelineDaySummary(
      day: DateTime(2026, 7, 9),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(nextThu.events, isEmpty);
  });

  // ── Phase 3: 例外系统 (skipDates + overrides) 测试 ──

  test('skipDates excludes specific projection days', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0); // 周三

    final events = [
      DiaryEntry(
        id: 'weekly-meeting',
        content: '周会',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-meeting',
        title: '周会',
        targetType: 'event',
        targetId: 'weekly-meeting',
        scheduleType: 'weekly',
        displayMode: 'punctual',
        anchorTime: anchorDay,
        skipDates: [DateTime(2026, 7, 15)], // 跳过7月15日周三
      ),
    ];

    // 7月8日 周三（未跳过）：应投影
    final jul8 = buildTimelineDaySummary(
      day: DateTime(2026, 7, 8),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(jul8.events.length, 1);

    // 7月15日 周三（被跳过）：不应投影
    final jul15 = buildTimelineDaySummary(
      day: DateTime(2026, 7, 15),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(jul15.events, isEmpty);

    // 7月22日 周三（未被跳过）：应投影
    final jul22 = buildTimelineDaySummary(
      day: DateTime(2026, 7, 22),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(jul22.events.length, 1);
  });

  test('skipDates on spanning mode skips the entire window', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0);

    final events = [
      DiaryEntry(
        id: 'sheets',
        content: '换床单',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-sheets',
        title: '换床单',
        targetType: 'event',
        targetId: 'sheets',
        scheduleType: 'every_n_days',
        scheduleInterval: 30,
        displayMode: 'spanning',
        anchorTime: anchorDay,
        skipDates: [DateTime(2026, 7, 31)], // 跳过第二个周期（7/31-8/29）
      ),
    ];

    // Day 15（第1个窗口内，未被跳过）：应投影
    final firstWindow = buildTimelineDaySummary(
      day: DateTime(2026, 7, 15),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(firstWindow.events.length, 1);

    // 7月31日（第2个窗口的投影日，被跳过）：不应投影
    final skippedProjDay = buildTimelineDaySummary(
      day: DateTime(2026, 7, 31),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(skippedProjDay.events, isEmpty);

    // 8月15日（第2个窗口内，跳过影响整个窗口）：不应投影
    final skippedWindowMid = buildTimelineDaySummary(
      day: DateTime(2026, 8, 15),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(skippedWindowMid.events, isEmpty);
  });

  test('Override replaces content and time for a specific projection', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0); // 周三
    final overrideDate = DateTime(2026, 7, 8); // 下周三

    final events = [
      DiaryEntry(
        id: 'standup',
        content: '站会',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-standup',
        title: '站会',
        targetType: 'event',
        targetId: 'standup',
        scheduleType: 'weekly',
        displayMode: 'punctual',
        anchorTime: anchorDay,
        overrides: [
          RecurrenceOverride(
            originalDate: overrideDate,
            newContent: '站会（改到10点）',
            newTime: DateTime(2026, 7, 8, 10, 0),
          ),
        ],
      ),
    ];

    // 7月8日：应显示覆盖后的内容
    final jul8 = buildTimelineDaySummary(
      day: DateTime(2026, 7, 8),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(jul8.events.length, 1);
    expect(
      jul8.events.first.aiSummary ?? jul8.events.first.content,
      '站会（改到10点）',
    );
    expect(jul8.events.first.sortTime, DateTime(2026, 7, 8, 10, 0));

    // 7月15日：应显示原始内容
    final jul15 = buildTimelineDaySummary(
      day: DateTime(2026, 7, 15),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(jul15.events.length, 1);
    expect(jul15.events.first.aiSummary ?? jul15.events.first.content, '站会');
    expect(jul15.events.first.sortTime, DateTime(2026, 7, 15, 9, 0));
  });

  test('Override on the anchor day changes only that recurring occurrence', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0); // 周三
    final events = [
      DiaryEntry(
        id: 'anchor-meeting',
        content: '周会',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-anchor-meeting',
        title: '周会',
        targetType: 'event',
        targetId: 'anchor-meeting',
        scheduleType: 'weekly',
        anchorTime: anchorDay,
        overrides: [
          RecurrenceOverride(
            originalDate: anchorDay,
            newContent: '周会（本周改期）',
            newTime: DateTime(2026, 7, 1, 11),
          ),
        ],
      ),
    ];

    final anchor = buildTimelineDaySummary(
      day: anchorDay,
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(anchor.events.single.sortTime, DateTime(2026, 7, 1, 11));
    expect(anchor.events.single.content, '周会（本周改期）');

    final nextWeek = buildTimelineDaySummary(
      day: DateTime(2026, 7, 8),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(nextWeek.events.single.sortTime, DateTime(2026, 7, 8, 9));
    expect(nextWeek.events.single.content, '周会');
  });

  test('Recurring override moved to another day remains visible', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0); // 周三
    final events = [
      DiaryEntry(
        id: 'moved-meeting',
        content: '复习',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-moved-meeting',
        title: '复习',
        targetType: 'event',
        targetId: 'moved-meeting',
        scheduleType: 'weekly',
        displayMode: 'punctual',
        anchorTime: anchorDay,
        overrides: [
          RecurrenceOverride(
            originalDate: DateTime(2026, 7, 8),
            newTime: DateTime(2026, 7, 9, 14, 0),
          ),
        ],
      ),
    ];

    final movedDay = buildTimelineDaySummary(
      day: DateTime(2026, 7, 9),
      events: events,
      todos: const [],
      rules: rules,
    );

    expect(movedDay.events, hasLength(1));
    expect(movedDay.events.single.sortTime, DateTime(2026, 7, 9, 14));
  });

  test('Moving the anchor occurrence removes it from the original day', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0); // 周三
    final events = [
      DiaryEntry(
        id: 'moved-anchor',
        content: '周会',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-moved-anchor',
        title: '周会',
        targetType: 'event',
        targetId: 'moved-anchor',
        scheduleType: 'weekly',
        displayMode: 'punctual',
        anchorTime: anchorDay,
        overrides: [
          RecurrenceOverride(
            originalDate: anchorDay,
            newTime: DateTime(2026, 7, 2, 14, 0),
          ),
        ],
      ),
    ];

    final originalDay = buildTimelineDaySummary(
      day: anchorDay,
      events: events,
      todos: const [],
      rules: rules,
    );
    final movedDay = buildTimelineDaySummary(
      day: DateTime(2026, 7, 2),
      events: events,
      todos: const [],
      rules: rules,
    );

    expect(originalDay.events, isEmpty);
    expect(movedDay.events.single.sortTime, DateTime(2026, 7, 2, 14));
    expect(
      RecurrenceService.originalDateForOccurrence(
        rules.single,
        DateTime(2026, 7, 2, 14),
      ),
      DateTime(2026, 7, 1),
    );
  });

  test('Override with isCompleted hides remaining days in spanning window', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0);

    final events = [
      DiaryEntry(
        id: 'sheets',
        content: '换床单',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-sheets',
        title: '换床单',
        targetType: 'event',
        targetId: 'sheets',
        scheduleType: 'every_n_days',
        scheduleInterval: 30,
        displayMode: 'spanning',
        anchorTime: anchorDay,
        overrides: [
          RecurrenceOverride(
            originalDate: DateTime(2026, 7, 1),
            isCompleted: true,
            completedAt: DateTime(2026, 7, 10),
          ),
        ],
      ),
    ];

    // Day 2（投影日后第1天，完成前）：由于 isCompleted 且 spanning → 不显示
    // 注意：第一个窗口的 originalDate = 7/1，完成于7/10
    // spanning 模式下次序: 7/1 被标记为已完成 → 整个窗口跳过
    final day2 = buildTimelineDaySummary(
      day: DateTime(2026, 7, 2),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(day2.events, isEmpty);

    // 第2个窗口（7/31 及之后）：未完成，应正常投影
    final aug1 = buildTimelineDaySummary(
      day: DateTime(2026, 7, 31),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(aug1.events.length, 1);
  });

  test('Skip takes priority over override for same date', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0);

    final events = [
      DiaryEntry(
        id: 'standup',
        content: '站会',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-standup',
        title: '站会',
        targetType: 'event',
        targetId: 'standup',
        scheduleType: 'weekly',
        displayMode: 'punctual',
        anchorTime: anchorDay,
        skipDates: [DateTime(2026, 7, 8)],
        overrides: [
          RecurrenceOverride(
            originalDate: DateTime(2026, 7, 8),
            newContent: '改到明天',
          ),
        ],
      ),
    ];

    // 7月8日：既被 skip 又被 override → skip 优先，不显示
    final jul8 = buildTimelineDaySummary(
      day: DateTime(2026, 7, 8),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(jul8.events, isEmpty);
  });

  // ── Phase 4: 独立实例完成状态测试 ──

  test('Projected event does not inherit isCompleted from original entry', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0);

    // 原条目被标记为已完成
    final events = [
      DiaryEntry(
        id: 'daily-task',
        content: '每日任务',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
        isCompleted: true, // 锚点日完成了
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-daily',
        title: '每日任务',
        targetType: 'event',
        targetId: 'daily-task',
        scheduleType: 'daily',
        anchorTime: anchorDay,
      ),
    ];

    // 7月4日投影：不应从原条目继承 isCompleted
    final summary = buildTimelineDaySummary(
      day: DateTime(2026, 7, 4),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(summary.events.length, 1);
    // 关键断言：投影的 isCompleted 应为 false
    expect(summary.events.first.isCompleted, isFalse);
  });

  test('Override with isCompleted hides spanning window after completion', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0);

    final events = [
      DiaryEntry(
        id: 'sheets',
        content: '换床单',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-sheets',
        title: '换床单',
        targetType: 'event',
        targetId: 'sheets',
        scheduleType: 'every_n_days',
        scheduleInterval: 30,
        displayMode: 'spanning',
        anchorTime: anchorDay,
        overrides: [
          RecurrenceOverride(
            originalDate: DateTime(2026, 7, 1), // 第1个窗口的投影日
            isCompleted: true,
            completedAt: DateTime(2026, 7, 10),
          ),
        ],
      ),
    ];

    // 第1个窗口内（7/5）：已完成 → 不显示
    final day5 = buildTimelineDaySummary(
      day: DateTime(2026, 7, 5),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(day5.events, isEmpty);

    // 第2个窗口（7/31开始）：新的未完成实例 → 应显示
    final day31 = buildTimelineDaySummary(
      day: DateTime(2026, 7, 31),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(day31.events.length, 1);
    expect(day31.events.first.isCompleted, isFalse);
  });

  test('Punctual completion only affects the specific projection day', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0); // 周三

    final events = [
      DiaryEntry(
        id: 'weekly-meeting',
        content: '周会',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-meeting',
        title: '周会',
        targetType: 'event',
        targetId: 'weekly-meeting',
        scheduleType: 'weekly',
        displayMode: 'punctual',
        anchorTime: anchorDay,
        overrides: [
          RecurrenceOverride(
            originalDate: DateTime(2026, 7, 8), // 下周三
            isCompleted: true,
          ),
        ],
      ),
    ];

    // 7月8日：已完成，不显示
    final jul8 = buildTimelineDaySummary(
      day: DateTime(2026, 7, 8),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(jul8.events, isEmpty);

    // 7月15日：新的未完成实例，应显示
    final jul15 = buildTimelineDaySummary(
      day: DateTime(2026, 7, 15),
      events: events,
      todos: const [],
      rules: rules,
    );
    expect(jul15.events.length, 1);
    expect(jul15.events.first.isCompleted, isFalse);
  });

  test(
    'New window after completion starts fresh (no isCompleted inherited)',
    () {
      final anchorDay = DateTime(2026, 7, 1, 9, 0);

      final events = [
        DiaryEntry(
          id: 'daily-fresh',
          content: '每日新鲜',
          timestamp: anchorDay,
          category: 'event',
          eventTime: anchorDay,
          isCompleted: true, // 锚点日完成了
        ),
      ];
      final rules = [
        ReminderRule(
          id: 'rule-daily-fresh',
          title: '每日新鲜',
          targetType: 'event',
          targetId: 'daily-fresh',
          scheduleType: 'daily',
          anchorTime: anchorDay,
        ),
      ];

      // 锚点日（7/1）：isCompleted=true，这是原始事件本身
      final anchor = buildTimelineDaySummary(
        day: anchorDay,
        events: events,
        todos: const [],
        rules: rules,
      );
      expect(anchor.events.length, 1);
      expect(anchor.events.first.isCompleted, isTrue);

      // 投影日（7/5）：isCompleted=false 的新实例
      final proj = buildTimelineDaySummary(
        day: DateTime(2026, 7, 5),
        events: events,
        todos: const [],
        rules: rules,
      );
      expect(proj.events.length, 1);
      expect(proj.events.first.isCompleted, isFalse);
    },
  );

  // ── Phase 5: spanning 视觉呈现测试 ──

  test('Spanning boundaries are correctly marked on TimelineDayItems', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0); // 周三
    final weekStart = DateTime(2026, 7, 6); // 周一

    final events = [
      DiaryEntry(
        id: 'span-task',
        content: '跨期任务',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-span',
        title: '跨期任务',
        targetType: 'event',
        targetId: 'span-task',
        scheduleType: 'every_n_days',
        scheduleInterval: 7,
        displayMode: 'spanning',
        anchorTime: anchorDay,
      ),
    ];

    // anchorDay 是周三(7/1)，7天后是7/8周三。spanning 窗口: 7/1-7/7, 7/8-7/14
    // weekStart 7/6周一 → 7/6(Mon) 和 7/7(Tue) 在窗口 7/1-7/7 内
    final week = buildWeekTimelineSummary(
      weekStart: weekStart,
      events: events,
      todos: const [],
      rules: rules,
    );

    // 每天都有这个 spanning 事件（7天内连续）
    for (var i = 0; i < 7; i++) {
      final hasEvent = week.days[i].items.any(
        (item) =>
            item.type == TimelineDayItemType.event && item.id == 'span-task',
      );
      expect(hasEvent, isTrue, reason: 'Day $i should have spanning event');
    }
  });

  test('Spanning bars do not affect punctual event display', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0);

    final events = [
      DiaryEntry(
        id: 'punctual-event',
        content: '点事件',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-punctual',
        title: '点事件',
        targetType: 'event',
        targetId: 'punctual-event',
        scheduleType: 'weekly',
        displayMode: 'punctual', // 不是 spanning
        anchorTime: anchorDay,
      ),
    ];

    final summary = buildTimelineDaySummary(
      day: DateTime(2026, 7, 8), // 下周三
      events: events,
      todos: const [],
      rules: rules,
    );

    // punctual 事件正常显示，spanning 标记均为 false
    final eventItem = summary.items.firstWhere(
      (item) =>
          item.type == TimelineDayItemType.event && item.id == 'punctual-event',
    );
    expect(eventItem.isSpanningStart, isFalse);
    expect(eventItem.isSpanningEnd, isFalse);
    expect(eventItem.isSpanningMiddle, isFalse);
    expect(eventItem.spanningGroupId, isNull);
  });

  test('Spanning boundaries mark start/middle/end correctly within a week', () {
    final anchorDay = DateTime(2026, 7, 1, 9, 0); // 周三
    // every_n_days=7, spanning → 窗口: 7/1-7/7, 7/8-7/14, ...
    final weekStart = DateTime(2026, 7, 6); // 周一

    final events = [
      DiaryEntry(
        id: 'sheets',
        content: '换床单',
        timestamp: anchorDay,
        category: 'event',
        eventTime: anchorDay,
      ),
    ];
    final rules = [
      ReminderRule(
        id: 'rule-sheets',
        title: '换床单',
        targetType: 'event',
        targetId: 'sheets',
        scheduleType: 'every_n_days',
        scheduleInterval: 7,
        displayMode: 'spanning',
        anchorTime: anchorDay,
      ),
    ];

    final week = buildWeekTimelineSummary(
      weekStart: weekStart,
      events: events,
      todos: const [],
      rules: rules,
    );

    // 7/6(周一, day 0) 和 7/7(周二, day 1) 在 7/1-7/7 窗口内
    // 7/8(周三, day 2) ~ 7/12(周日, day 6) 在 7/8-7/14 窗口内
    // 所以两个窗口: [0,1] 和 [2,3,4,5,6]

    // 第一窗口 — 检查边界
    final day0Sheets = week.days[0].items.firstWhere(
      (item) => item.id == 'sheets',
    );
    expect(
      day0Sheets.isSpanningStart,
      isTrue,
      reason: '7/6 should be spanning start of first window',
    );
    expect(day0Sheets.isSpanningMiddle, isFalse);
    expect(day0Sheets.isSpanningEnd, isFalse);

    final day1Sheets = week.days[1].items.firstWhere(
      (item) => item.id == 'sheets',
    );
    expect(
      day1Sheets.isSpanningStart,
      isFalse,
      reason: '7/7 should be spanning end of first window',
    );
    expect(day1Sheets.isSpanningMiddle, isFalse);
    expect(day1Sheets.isSpanningEnd, isTrue);

    // 第二窗口 — 检查边界
    final day2Sheets = week.days[2].items.firstWhere(
      (item) => item.id == 'sheets',
    );
    expect(
      day2Sheets.isSpanningStart,
      isTrue,
      reason: '7/8 should be spanning start of second window',
    );
    expect(day2Sheets.isSpanningEnd, isFalse);

    // 中间天
    final day3Sheets = week.days[3].items.firstWhere(
      (item) => item.id == 'sheets',
    );
    expect(
      day3Sheets.isSpanningMiddle,
      isTrue,
      reason: '7/9 should be spanning middle',
    );

    // 最后一天
    final day6Sheets = week.days[6].items.firstWhere(
      (item) => item.id == 'sheets',
    );
    expect(
      day6Sheets.isSpanningEnd,
      isTrue,
      reason: '7/12 should be spanning end of second window',
    );
  });
}
