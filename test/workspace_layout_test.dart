import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:zendiary/core/theme/zen_theme.dart';
import 'package:zendiary/core/database/db_service.dart';
import 'package:zendiary/models/diary_entry.dart';
import 'package:zendiary/models/notebook_entry.dart';
import 'package:zendiary/models/reminder_rule.dart';
import 'package:zendiary/models/todo_task.dart';
import 'package:zendiary/providers/app_providers.dart';
import 'package:zendiary/providers/notebook_provider.dart';
import 'package:zendiary/providers/reminder_rule_provider.dart';
import 'package:zendiary/views/timeline/timeline_shared.dart';
import 'package:zendiary/views/timeline/timeline_data.dart';
import 'package:zendiary/views/timeline/week_view.dart';
import 'package:zendiary/views/common/search_overlay.dart';
import 'package:zendiary/views/workspace/workspace_views.dart';

class _LayoutTodoNotifier extends TodoListNotifier {
  _LayoutTodoNotifier(this.initialTodos);

  final List<TodoTask> initialTodos;

  @override
  List<TodoTask> build() => initialTodos;
}

class _LayoutDiaryNotifier extends DiaryNotifier {
  _LayoutDiaryNotifier(this.initialEntries);

  final List<DiaryEntry> initialEntries;

  @override
  List<DiaryEntry> build() => initialEntries;
}

class _LayoutNotebookNotifier extends NotebookListNotifier {
  @override
  List<NotebookEntry> build() => const [];
}

class _SeededLayoutNotebookNotifier extends NotebookListNotifier {
  _SeededLayoutNotebookNotifier(this.initialNotes);

  final List<NotebookEntry> initialNotes;

  @override
  List<NotebookEntry> build() => initialNotes;
}

class _LayoutReminderRuleNotifier extends ReminderRuleNotifier {
  @override
  List<ReminderRule> build() {
    return const [];
  }
}

class _SeededLayoutReminderRuleNotifier extends ReminderRuleNotifier {
  _SeededLayoutReminderRuleNotifier(this.initialRules);

  final List<ReminderRule> initialRules;

  @override
  List<ReminderRule> build() => initialRules;
}

class _LayoutDensityNotifier extends UiDensityNotifier {
  @override
  UiDensity build() => UiDensity.standard;
}

class _LayoutDayBoundaryNotifier extends DayBoundaryNotifier {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('zendiary-layout-');
    Hive.init(hiveDirectory.path);
    await Hive.openBox(DBService.settingsBoxName);
    await Hive.openBox(DBService.reminderRuleBoxName);
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDirectory.existsSync()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  testWidgets('Today stays readable at phone, tablet and desktop widths', (
    tester,
  ) async {
    await initializeDateFormatting('zh_CN', null);
    final now = DateTime.now();
    final eventTime = now.add(const Duration(hours: 1));
    final event = DiaryEntry(
      id: 'layout-event',
      content: '下一节课',
      timestamp: eventTime,
      category: 'event',
      eventTime: eventTime,
      durationMinutes: 90,
    );
    final todos = List.generate(
      8,
      (index) => TodoTask(
        id: 'layout-todo-$index',
        title: '今日行动 $index',
        createdAt: now,
        scheduledAt: now.add(Duration(hours: index + 2)),
      ),
    );

    for (final size in const [
      Size(390, 844),
      Size(768, 1024),
      Size(1440, 900),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timelineEntriesProvider.overrideWith((ref) => [event]),
            todoListProvider.overrideWith(() => _LayoutTodoNotifier(todos)),
            reminderRuleProvider.overrideWith(_LayoutReminderRuleNotifier.new),
            uiDensityProvider.overrideWith(_LayoutDensityNotifier.new),
            dayBoundaryProvider.overrideWith(_LayoutDayBoundaryNotifier.new),
          ],
          child: MaterialApp(
            theme: ZenTheme.lightTheme,
            home: const Scaffold(body: TodayView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'layout $size');
      expect(find.text('待办 (8)'), findsOneWidget);
      expect(find.text('现在安排'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('固定时间'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('固定时间'), findsOneWidget);
      expect(find.text('下一节课'), findsAtLeastNWidgets(1));
    }

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Today retains overnight events alongside todays classes', (
    tester,
  ) async {
    await initializeDateFormatting('zh_CN', null);
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final overnight = DiaryEntry(
      id: 'layout-overnight',
      content: '夜间实验室',
      timestamp: dayStart.subtract(const Duration(minutes: 30)),
      category: 'event',
      eventTime: dayStart.subtract(const Duration(minutes: 30)),
      durationMinutes: 120,
    );
    final early = DiaryEntry(
      id: 'layout-early',
      content: '清晨测验',
      timestamp: dayStart,
      category: 'event',
      eventTime: dayStart.add(const Duration(minutes: 45)),
      durationMinutes: 30,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timelineEntriesProvider.overrideWith((ref) => [overnight, early]),
          todoListProvider.overrideWith(() => _LayoutTodoNotifier(const [])),
          reminderRuleProvider.overrideWith(_LayoutReminderRuleNotifier.new),
          uiDensityProvider.overrideWith(_LayoutDensityNotifier.new),
          dayBoundaryProvider.overrideWith(_LayoutDayBoundaryNotifier.new),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: const Scaffold(body: TodayView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('夜间实验室'), findsOneWidget);
    expect(find.text('清晨测验'), findsOneWidget);
    expect(find.text('固定时间'), findsOneWidget);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Plan exposes batch reschedule for events in the active range', (
    tester,
  ) async {
    await initializeDateFormatting('zh_CN', null);
    final now = DateTime.now();
    final event = DiaryEntry(
      id: 'plan-batch-event',
      content: '实验课',
      timestamp: now,
      category: 'event',
      eventTime: DateTime(now.year, now.month, now.day, 10),
      durationMinutes: 90,
    );

    await tester.binding.setSurfaceSize(const Size(1000, 760));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timelineEntriesProvider.overrideWith((ref) => [event]),
          todoListProvider.overrideWith(() => _LayoutTodoNotifier(const [])),
          reminderRuleProvider.overrideWith(_LayoutReminderRuleNotifier.new),
          uiDensityProvider.overrideWith(_LayoutDensityNotifier.new),
          dayBoundaryProvider.overrideWith(_LayoutDayBoundaryNotifier.new),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: const Scaffold(body: PlanView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('批量改期'), findsOneWidget);
    await tester.tap(find.byTooltip('批量改期'));
    await tester.pumpAndSettle();
    expect(find.text('批量改期'), findsOneWidget);
    expect(find.text('实验课'), findsNWidgets(2));

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Plan stays single-column and usable on a phone width', (
    tester,
  ) async {
    await initializeDateFormatting('zh_CN', null);
    final now = DateTime.now();
    final event = DiaryEntry(
      id: 'plan-phone-event',
      content: '手机端课程',
      timestamp: now,
      category: 'event',
      eventTime: DateTime(now.year, now.month, now.day, 10),
      durationMinutes: 90,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timelineEntriesProvider.overrideWith((ref) => [event]),
          todoListProvider.overrideWith(() => _LayoutTodoNotifier(const [])),
          reminderRuleProvider.overrideWith(_LayoutReminderRuleNotifier.new),
          uiDensityProvider.overrideWith(_LayoutDensityNotifier.new),
          dayBoundaryProvider.overrideWith(_LayoutDayBoundaryNotifier.new),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: const Scaffold(body: PlanView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('计划'), findsOneWidget);
    expect(find.text('手机端课程'), findsOneWidget);
    expect(find.byTooltip('批量改期'), findsOneWidget);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets(
    'Plan can reveal unscheduled tasks beyond the compact first page',
    (tester) async {
      final now = DateTime.now();
      final todos = List.generate(
        9,
        (index) => TodoTask(
          id: 'plan-overflow-$index',
          title: '待安排任务 $index',
          createdAt: now,
        ),
      );

      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timelineEntriesProvider.overrideWith((ref) => const []),
            todoListProvider.overrideWith(() => _LayoutTodoNotifier(todos)),
            reminderRuleProvider.overrideWith(_LayoutReminderRuleNotifier.new),
            uiDensityProvider.overrideWith(_LayoutDensityNotifier.new),
            dayBoundaryProvider.overrideWith(_LayoutDayBoundaryNotifier.new),
          ],
          child: MaterialApp(
            theme: ZenTheme.lightTheme,
            home: const Scaffold(body: PlanView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('显示其余 1 项'), findsOneWidget);
      expect(find.text('待安排任务 8'), findsNothing);
      await tester.tap(find.text('显示其余 1 项'));
      await tester.pumpAndSettle();
      expect(find.text('待安排任务 8'), findsOneWidget);
      expect(tester.takeException(), isNull);
      addTearDown(() => tester.binding.setSurfaceSize(null));
    },
  );

  testWidgets(
    'Plan batch reschedule includes each visible occurrence of a recurring event',
    (tester) async {
      await initializeDateFormatting('zh_CN', null);
      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      final monday = dayStart.subtract(Duration(days: dayStart.weekday - 1));
      final event = DiaryEntry(
        id: 'plan-batch-recurring-event',
        content: '每周研讨课',
        timestamp: monday,
        category: 'event',
        eventTime: monday.add(const Duration(hours: 10)),
        durationMinutes: 90,
      );
      final rule = ReminderRule(
        id: 'plan-batch-recurring-rule',
        title: event.content,
        targetType: 'event',
        targetId: event.id,
        scheduleType: 'weekly',
        byDay: const [1, 3],
        anchorTime: event.eventTime,
      );

      await tester.binding.setSurfaceSize(const Size(1000, 760));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timelineEntriesProvider.overrideWith((ref) => [event]),
            todoListProvider.overrideWith(() => _LayoutTodoNotifier(const [])),
            reminderRuleProvider.overrideWith(
              () => _SeededLayoutReminderRuleNotifier([rule]),
            ),
            uiDensityProvider.overrideWith(_LayoutDensityNotifier.new),
            dayBoundaryProvider.overrideWith(_LayoutDayBoundaryNotifier.new),
          ],
          child: MaterialApp(
            theme: ZenTheme.lightTheme,
            home: const Scaffold(body: PlanView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('批量改期'));
      await tester.pumpAndSettle();

      expect(find.text('批量改期'), findsOneWidget);
      // The selected week contains the Monday anchor and Wednesday
      // projection. Both must be independently selectable.
      expect(find.text('每周研讨课'), findsAtLeastNWidgets(2));

      addTearDown(() => tester.binding.setSurfaceSize(null));
    },
  );

  testWidgets('Week summary separates planned work from unscheduled backlog', (
    tester,
  ) async {
    await initializeDateFormatting('zh_CN', null);
    final now = DateTime.now();
    final planned = TodoTask(
      id: 'week-planned-todo',
      title: '已排进本周',
      createdAt: now,
      // Keep the fixture on the selected calendar day even when the current
      // day is Sunday (the next day would otherwise fall outside this week).
      scheduledAt: DateTime(now.year, now.month, now.day, 23, 59),
    );
    final backlog = TodoTask(
      id: 'week-backlog-todo',
      title: '以后再做',
      createdAt: now,
      priority: 'A',
    );

    await tester.binding.setSurfaceSize(const Size(1200, 760));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timelineEntriesProvider.overrideWith((ref) => const []),
          todoListProvider.overrideWith(
            () => _LayoutTodoNotifier([planned, backlog]),
          ),
          reminderRuleProvider.overrideWith(_LayoutReminderRuleNotifier.new),
          uiDensityProvider.overrideWith(_LayoutDensityNotifier.new),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: Scaffold(
            body: WeekView(weekStart: startOfWeek(now), focusDay: now),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final weekSummary = buildWeekTimelineSummary(
      weekStart: startOfWeek(now),
      events: const [],
      todos: [planned, backlog],
      rules: const [],
      floatingTodoPolicy: TimelineFloatingTodoPolicy.exclude,
    );
    // Keep the widget assertion close to the source summary so a future
    // change cannot silently turn scheduled work into backlog again.
    expect(weekSummary.todoCount, 1);
    expect(find.text('已排期 1'), findsOneWidget);
    expect(find.text('待办 1'), findsOneWidget);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Inbox recent captures keep the original capture visible', (
    tester,
  ) async {
    final now = DateTime(2026, 9, 4, 14);
    final source = DiaryEntry(
      id: 'inbox-capture-source',
      content: '明天复习高数，先看第三章',
      timestamp: now,
      category: 'todo',
    );
    final todo = TodoTask(
      id: 'inbox-capture-todo',
      title: '复习高数第三章',
      createdAt: now,
      sourceEntryId: source.id,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith(() => _LayoutDiaryNotifier([source])),
          todoListProvider.overrideWith(() => _LayoutTodoNotifier([todo])),
          notebookListProvider.overrideWith(_LayoutNotebookNotifier.new),
          reminderRuleProvider.overrideWith(_LayoutReminderRuleNotifier.new),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: const Scaffold(body: InboxView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('复习高数第三章'), findsOneWidget);
    expect(find.text('原文：明天复习高数，先看第三章'), findsOneWidget);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Global search uses one result for a duplicated note source', (
    tester,
  ) async {
    final capturedAt = DateTime(2026, 9, 4, 14);
    final diaryNote = DiaryEntry(
      id: 'search-shared-note',
      content: '离散数学复习提纲',
      timestamp: capturedAt,
      category: 'note',
    );
    final notebookCopy = NotebookEntry(
      id: diaryNote.id,
      title: '离散数学复习提纲',
      content: diaryNote.content,
      createdAt: capturedAt,
      updatedAt: capturedAt,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith(
            () => _LayoutDiaryNotifier([diaryNote]),
          ),
          todoListProvider.overrideWith(() => _LayoutTodoNotifier(const [])),
          notebookListProvider.overrideWith(
            () => _SeededLayoutNotebookNotifier([notebookCopy]),
          ),
          reminderRuleProvider.overrideWith(_LayoutReminderRuleNotifier.new),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: const Scaffold(body: SearchOverlay()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '离散数学');
    await tester.pumpAndSettle();
    // A matching result uses RichText so the query can be highlighted. One
    // title RichText here proves the diary/notebook copies collapsed to one
    // search result rather than rendering twice.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText() == '离散数学复习提纲',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Global search date filter keeps a task due today when scheduled later',
    (tester) async {
      final now = DateTime.now();
      final todo = TodoTask(
        id: 'search-split-dates',
        title: '今天必须交但明天安排',
        createdAt: now,
        scheduledAt: now.add(const Duration(days: 1)),
        deadline: now.add(const Duration(hours: 2)),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allEntriesProvider.overrideWith(
              () => _LayoutDiaryNotifier(const []),
            ),
            todoListProvider.overrideWith(() => _LayoutTodoNotifier([todo])),
            notebookListProvider.overrideWith(_LayoutNotebookNotifier.new),
            reminderRuleProvider.overrideWith(_LayoutReminderRuleNotifier.new),
          ],
          child: MaterialApp(
            theme: ZenTheme.lightTheme,
            home: const Scaffold(body: SearchOverlay()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('日期'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('今天'));
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText() == '今天必须交但明天安排',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
