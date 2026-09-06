import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zendiary/core/theme/zen_theme.dart';
import 'package:zendiary/models/diary_entry.dart';
import 'package:zendiary/models/reminder_rule.dart';
import 'package:zendiary/models/todo_task.dart';
import 'package:zendiary/models/unified_item.dart';
import 'package:zendiary/providers/app_providers.dart';
import 'package:zendiary/providers/reminder_rule_provider.dart';
import 'package:zendiary/services/system_notification_service.dart';
import 'package:zendiary/services/unified_item_service.dart';
import 'package:zendiary/views/workspace/workspace_views.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'timeline notification detail offers snooze for a portable fallback event',
    (tester) async {
      final eventTime = DateTime.now().add(const Duration(hours: 1));
      final event = DiaryEntry(
        id: 'portable-timeline-detail-event',
        content: '高等数学课',
        timestamp: eventTime,
        category: 'event',
        eventTime: eventTime,
        durationMinutes: 90,
      );
      final payload =
          'timeline:${event.id}|${eventTime.toIso8601String()}|10|occurrence=${eventTime.toIso8601String()}';

      // A portable build can offer the temporary tray-backed snooze even
      // though it cannot register a long-lived Windows scheduled toast.
      SystemNotificationService.debugSetPortableWindows(true);
      addTearDown(
        () => SystemNotificationService.debugSetPortableWindows(false),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allEntriesProvider.overrideWith(
              () => _DetailsDiaryNotifier([event]),
            ),
            todoListProvider.overrideWith(() => _DetailsTodoNotifier(const [])),
            reminderRuleProvider.overrideWith(_DetailsRuleNotifier.new),
          ],
          child: MaterialApp(
            theme: ZenTheme.lightTheme,
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showUnifiedItemDetails(
                      context,
                      ref,
                      unifiedEventItem(event),
                      fromNotification: true,
                      notificationPayload: payload,
                    ),
                    child: const Text('打开时间线提醒详情'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开时间线提醒详情'));
      await tester.pumpAndSettle();
      expect(find.text('稍后 15 分钟'), findsOneWidget);
    },
  );

  testWidgets('standalone notification detail offers snooze', (tester) async {
    final reminderTime = DateTime.now().add(const Duration(hours: 1));
    final reminder = ReminderRule(
      id: 'portable-standalone-detail-reminder',
      title: '提醒我复习',
      anchorTime: reminderTime,
      advanceMinutes: const [0],
    );
    final payload = SystemNotificationService.occurrencePayload(
      reminder.id,
      reminderTime,
    );

    SystemNotificationService.debugSetPortableWindows(true);
    addTearDown(() => SystemNotificationService.debugSetPortableWindows(false));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith(
            () => _DetailsDiaryNotifier(const []),
          ),
          todoListProvider.overrideWith(() => _DetailsTodoNotifier(const [])),
          reminderRuleProvider.overrideWith(
            () => _SingleDetailsRuleNotifier(reminder),
          ),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showUnifiedItemDetails(
                    context,
                    ref,
                    unifiedReminderItem(reminder),
                    fromNotification: true,
                    notificationPayload: payload,
                  ),
                  child: const Text('打开独立提醒通知详情'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开独立提醒通知详情'));
    await tester.pumpAndSettle();
    expect(find.text('稍后 15 分钟'), findsOneWidget);
  });

  testWidgets('event details keep the original capture below the AI title', (
    tester,
  ) async {
    final event = DiaryEntry(
      id: 'summary-detail-event',
      content: '记得明天下午三点到图书馆参加学习小组，别迟到',
      timestamp: DateTime(2026, 9, 3, 8),
      category: 'event',
      eventTime: DateTime(2026, 9, 4, 15),
      aiSummary: '学习小组 · 图书馆',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith(() => _DetailsDiaryNotifier([event])),
          todoListProvider.overrideWith(() => _DetailsTodoNotifier(const [])),
          reminderRuleProvider.overrideWith(_DetailsRuleNotifier.new),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showUnifiedItemDetails(
                    context,
                    ref,
                    unifiedEventItem(event),
                  ),
                  child: const Text('打开摘要事件详情'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开摘要事件详情'));
    await tester.pumpAndSettle();
    expect(find.text('学习小组 · 图书馆'), findsOneWidget);
    expect(find.text('原文'), findsOneWidget);
    expect(find.text(event.content), findsOneWidget);
  });

  testWidgets('standalone reminder details can edit the shared rule', (
    tester,
  ) async {
    final reminder = ReminderRule(
      id: 'standalone-detail-reminder',
      title: '提醒我复习',
      anchorTime: DateTime(2026, 9, 4, 19),
      advanceMinutes: const [15],
    );
    final ruleNotifier = _InteractiveDetailsRuleNotifier(reminder);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith(
            () => _DetailsDiaryNotifier(const []),
          ),
          todoListProvider.overrideWith(() => _DetailsTodoNotifier(const [])),
          reminderRuleProvider.overrideWith(() => ruleNotifier),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showUnifiedItemDetails(
                    context,
                    ref,
                    unifiedReminderItem(reminder),
                  ),
                  child: const Text('打开独立提醒详情'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开独立提醒详情'));
    await tester.pumpAndSettle();
    expect(find.text('编辑提醒'), findsOneWidget);
    expect(find.text('已启用 · 单次 · 提前 15 分钟'), findsOneWidget);

    await tester.tap(find.text('编辑提醒'));
    await tester.pumpAndSettle();
    expect(find.text('提醒内容'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '提醒我复习（已更新）');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(ruleNotifier.state.single.title, '提醒我复习（已更新）');
  });

  testWidgets('recurring standalone reminder details can skip one occurrence', (
    tester,
  ) async {
    final now = DateTime.now();
    final reminder = ReminderRule(
      id: 'recurring-detail-reminder',
      title: '晚间复盘',
      scheduleType: 'daily',
      anchorTime: DateTime(now.year, now.month, now.day, 19),
    );
    final item = buildStandaloneReminderItemsForDay(
      rules: [reminder],
      day: now,
    ).single;
    final ruleNotifier = _OccurrenceReminderNotifier(reminder);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith(
            () => _DetailsDiaryNotifier(const []),
          ),
          todoListProvider.overrideWith(() => _DetailsTodoNotifier(const [])),
          reminderRuleProvider.overrideWith(() => ruleNotifier),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showUnifiedItemDetails(context, ref, item),
                  child: const Text('打开重复提醒详情'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开重复提醒详情'));
    await tester.pumpAndSettle();
    expect(find.text('跳过本次提醒'), findsOneWidget);
    await tester.tap(find.text('跳过本次提醒'));
    await tester.pumpAndSettle();

    expect(ruleNotifier.state.single.skipDates, hasLength(1));
    final skipped = ruleNotifier.state.single.skipDates.single;
    expect(skipped.year, now.year);
    expect(skipped.month, now.month);
    expect(skipped.day, now.day);
  });

  testWidgets('todo details exposes useful lead-time reminder choices', (
    tester,
  ) async {
    final todo = TodoTask(
      id: 'reminder-detail-todo',
      title: '复习离散数学',
      createdAt: DateTime(2026, 9, 3, 8),
      scheduledAt: DateTime(2026, 9, 3, 19),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith(
            () => _DetailsDiaryNotifier(const []),
          ),
          todoListProvider.overrideWith(() => _DetailsTodoNotifier([todo])),
          reminderRuleProvider.overrideWith(_DetailsRuleNotifier.new),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showUnifiedItemDetails(
                    context,
                    ref,
                    unifiedTodoItem(todo, DateTime(2026, 9, 3, 10)),
                  ),
                  child: const Text('打开待办详情'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开待办详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置提醒'));
    await tester.pumpAndSettle();

    expect(find.text('提前提醒'), findsOneWidget);
    expect(find.text('到点'), findsOneWidget);
    expect(find.text('5 分钟'), findsOneWidget);
    expect(find.text('15 分钟'), findsOneWidget);
    expect(find.text('1 小时'), findsOneWidget);
  });

  testWidgets('today todo details offer a one-tap defer to tomorrow', (
    tester,
  ) async {
    final clock = DateTime.now();
    final todayAtNine = DateTime(clock.year, clock.month, clock.day, 9);
    final todo = TodoTask(
      id: 'defer-detail-todo',
      title: '整理课堂笔记',
      createdAt: todayAtNine.subtract(const Duration(days: 1)),
      scheduledAt: todayAtNine,
      deadline: todayAtNine.add(const Duration(days: 3)),
    );
    late _InteractiveDetailsTodoNotifier todoNotifier;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith(
            () => _DetailsDiaryNotifier(const []),
          ),
          todoListProvider.overrideWith(
            () => todoNotifier = _InteractiveDetailsTodoNotifier(todo),
          ),
          reminderRuleProvider.overrideWith(_DetailsRuleNotifier.new),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showUnifiedItemDetails(
                    context,
                    ref,
                    unifiedTodoItem(todo, clock),
                  ),
                  child: const Text('打开延期详情'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开延期详情'));
    await tester.pumpAndSettle();
    expect(find.text('移到明天同一时间'), findsOneWidget);
    await tester.tap(find.text('移到明天同一时间'));
    await tester.pumpAndSettle();
    expect(
      todoNotifier.state.single.scheduledAt,
      DateTime(clock.year, clock.month, clock.day + 1, 9),
    );
  });

  testWidgets('todo details exposes deadline reminder choices', (tester) async {
    final todo = TodoTask(
      id: 'deadline-reminder-detail-todo',
      title: '准备期末考试',
      createdAt: DateTime(2026, 9, 3, 8),
      deadline: DateTime(2026, 9, 10, 23, 59),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith(
            () => _DetailsDiaryNotifier(const []),
          ),
          todoListProvider.overrideWith(() => _DetailsTodoNotifier([todo])),
          reminderRuleProvider.overrideWith(_DetailsRuleNotifier.new),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showUnifiedItemDetails(
                    context,
                    ref,
                    unifiedTodoItem(todo, DateTime(2026, 9, 3, 10)),
                  ),
                  child: const Text('打开截止提醒详情'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开截止提醒详情'));
    await tester.pumpAndSettle();
    expect(find.text('设置截止提醒'), findsOneWidget);
    await tester.tap(find.text('设置截止提醒'));
    await tester.pumpAndSettle();
    expect(find.text('截止提醒'), findsOneWidget);
    expect(find.text('1 天'), findsOneWidget);
    expect(find.text('3 小时'), findsOneWidget);
    expect(find.text('15 分钟'), findsOneWidget);
  });

  testWidgets('todo details exposes the priority used by Today suggestions', (
    tester,
  ) async {
    final todo = TodoTask(
      id: 'priority-detail-todo',
      title: '准备考试',
      createdAt: DateTime(2026, 9, 3, 8),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith(
            () => _DetailsDiaryNotifier(const []),
          ),
          todoListProvider.overrideWith(() => _DetailsTodoNotifier([todo])),
          reminderRuleProvider.overrideWith(_DetailsRuleNotifier.new),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showUnifiedItemDetails(
                    context,
                    ref,
                    unifiedTodoItem(todo, DateTime(2026, 9, 3, 10)),
                  ),
                  child: const Text('打开优先级详情'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开优先级详情'));
    await tester.pumpAndSettle();
    expect(find.text('优先级 · 普通'), findsOneWidget);
    await tester.tap(find.text('优先级 · 普通'));
    await tester.pumpAndSettle();
    expect(find.text('重要 · 今天优先'), findsOneWidget);
    expect(find.text('普通 · 按截止时间'), findsOneWidget);
    expect(find.text('次要 · 有空再做'), findsOneWidget);
  });

  testWidgets('todo details can edit the title and notes', (tester) async {
    final todo = TodoTask(
      id: 'content-detail-todo',
      title: '复习高数',
      createdAt: DateTime(2026, 9, 3, 8),
      subNotes: const ['先看第三章'],
    );
    late _InteractiveContentDetailsTodoNotifier todoNotifier;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith(
            () => _DetailsDiaryNotifier(const []),
          ),
          todoListProvider.overrideWith(
            () => todoNotifier = _InteractiveContentDetailsTodoNotifier(todo),
          ),
          reminderRuleProvider.overrideWith(_DetailsRuleNotifier.new),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showUnifiedItemDetails(
                    context,
                    ref,
                    unifiedTodoItem(todo, DateTime(2026, 9, 3, 10)),
                  ),
                  child: const Text('打开内容详情'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开内容详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑内容'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), '复习高数第三章');
    await tester.enterText(fields.at(1), '完成例题 1–5\n整理错题');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(todoNotifier.state.single.title, '复习高数第三章');
    expect(todoNotifier.state.single.subNotes, ['完成例题 1–5', '整理错题']);
  });

  testWidgets('routine todo details can skip only today', (tester) async {
    final now = DateTime.now();
    final todo = TodoTask(
      id: 'routine-detail-todo',
      title: '背单词',
      createdAt: now.subtract(const Duration(days: 1)),
    );
    final rule = ReminderRule(
      id: 'routine-detail-rule',
      title: todo.title,
      targetType: 'todo',
      targetId: todo.id,
      scheduleType: 'daily',
      anchorTime: now.subtract(const Duration(days: 1)),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith(
            () => _DetailsDiaryNotifier(const []),
          ),
          todoListProvider.overrideWith(() => _DetailsTodoNotifier([todo])),
          reminderRuleProvider.overrideWith(
            () => _RoutineDetailsRuleNotifier(rule),
          ),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showUnifiedItemDetails(
                    context,
                    ref,
                    unifiedTodoItem(todo, now),
                  ),
                  child: const Text('打开例行详情'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开例行详情'));
    await tester.pumpAndSettle();
    expect(find.text('跳过今天'), findsOneWidget);
    await tester.tap(find.text('跳过今天'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已跳过今天的例行事项'), findsOneWidget);
  });

  testWidgets('todo details exposes safe type conversion choices', (
    tester,
  ) async {
    final todo = TodoTask(
      id: 'conversion-detail-todo',
      title: '整理课堂笔记',
      createdAt: DateTime(2026, 9, 3, 8),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith(
            () => _DetailsDiaryNotifier(const []),
          ),
          todoListProvider.overrideWith(() => _DetailsTodoNotifier([todo])),
          reminderRuleProvider.overrideWith(_DetailsRuleNotifier.new),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showUnifiedItemDetails(
                    context,
                    ref,
                    unifiedTodoItem(todo, DateTime(2026, 9, 3, 10)),
                  ),
                  child: const Text('打开转换详情'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开转换详情'));
    await tester.pumpAndSettle();
    expect(find.text('转换类型'), findsOneWidget);
    await tester.ensureVisible(find.text('转换类型'));
    await tester.tap(find.text('转换类型'));
    await tester.pumpAndSettle();
    expect(find.text('转为笔记'), findsOneWidget);
    expect(find.text('转为事件'), findsOneWidget);
    expect(find.text('原事项会先归档；新事项创建成功后可随时撤销。'), findsOneWidget);
  });
}

class _DetailsDiaryNotifier extends DiaryNotifier {
  _DetailsDiaryNotifier(this._entries);

  final List<DiaryEntry> _entries;

  @override
  List<DiaryEntry> build() => _entries;
}

class _DetailsTodoNotifier extends TodoListNotifier {
  _DetailsTodoNotifier(this._todos);

  final List<TodoTask> _todos;

  @override
  List<TodoTask> build() => _todos;
}

class _InteractiveDetailsTodoNotifier extends _DetailsTodoNotifier {
  _InteractiveDetailsTodoNotifier(TodoTask todo) : super([todo]);

  @override
  void rescheduleTodo(String id, DateTime? scheduledAt) {
    state = [
      for (final todo in state)
        todo.id == id ? todo.copyWith(scheduledAt: scheduledAt) : todo,
    ];
  }
}

class _InteractiveContentDetailsTodoNotifier extends _DetailsTodoNotifier {
  _InteractiveContentDetailsTodoNotifier(TodoTask todo) : super([todo]);

  @override
  void updateTodo(TodoTask updated) {
    state = [updated];
  }
}

class _DetailsRuleNotifier extends ReminderRuleNotifier {
  @override
  List<ReminderRule> build() => const [];
}

class _SingleDetailsRuleNotifier extends ReminderRuleNotifier {
  _SingleDetailsRuleNotifier(this._rule);

  final ReminderRule _rule;

  @override
  List<ReminderRule> build() => [_rule];
}

class _InteractiveDetailsRuleNotifier extends ReminderRuleNotifier {
  _InteractiveDetailsRuleNotifier(this._rule);

  final ReminderRule _rule;

  @override
  List<ReminderRule> build() => [_rule];

  @override
  void updateRule(ReminderRule rule) {
    state = [rule];
  }
}

class _OccurrenceReminderNotifier extends _InteractiveDetailsRuleNotifier {
  _OccurrenceReminderNotifier(super.rule);

  @override
  void addSkipDate(String ruleId, DateTime date) {
    if (ruleId != _rule.id) return;
    state = [
      _rule.copyWith(skipDates: [DateTime(date.year, date.month, date.day)]),
    ];
  }

  @override
  void removeSkipDate(String ruleId, DateTime date) {
    if (ruleId != _rule.id) return;
    state = [_rule.copyWith(skipDates: const [])];
  }
}

class _RoutineDetailsRuleNotifier extends ReminderRuleNotifier {
  _RoutineDetailsRuleNotifier(this._rule);

  final ReminderRule _rule;

  @override
  List<ReminderRule> build() => [_rule];

  @override
  void addSkipDate(String ruleId, DateTime date) {
    if (ruleId != _rule.id) return;
    state = [
      _rule.copyWith(skipDates: [DateTime(date.year, date.month, date.day)]),
    ];
  }

  @override
  void removeSkipDate(String ruleId, DateTime date) {
    if (ruleId != _rule.id) return;
    state = [_rule.copyWith(skipDates: const [])];
  }
}
