import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:zendiary/core/theme/zen_theme.dart';
import 'package:zendiary/models/diary_entry.dart';
import 'package:zendiary/models/reminder_rule.dart';
import 'package:zendiary/models/todo_task.dart';
import 'package:zendiary/providers/app_providers.dart';
import 'package:zendiary/providers/reminder_rule_provider.dart';
import 'package:zendiary/views/timeline/timeline_view.dart';
import 'package:zendiary/views/timeline/timeline_shared.dart';
import 'package:zendiary/views/timeline/month_view.dart';
import 'package:zendiary/views/timeline/day_view.dart';

class _TimelineRuleNotifier extends ReminderRuleNotifier {
  @override
  List<ReminderRule> build() => const [];
}

class _TimelineRuleDataNotifier extends ReminderRuleNotifier {
  final List<ReminderRule> data;

  _TimelineRuleDataNotifier(this.data);

  @override
  List<ReminderRule> build() => data;
}

class _TimelineTodoNotifier extends TodoListNotifier {
  @override
  List<TodoTask> build() => const [];
}

class _TimelineTodoDataNotifier extends TodoListNotifier {
  final List<TodoTask> data;

  _TimelineTodoDataNotifier(this.data);

  @override
  List<TodoTask> build() => data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('timeline multi-select exposes batch reschedule', (tester) async {
    final now = DateTime.now();
    final events = [
      DiaryEntry(
        id: 'timeline-batch-a',
        content: '离散数学',
        timestamp: now,
        category: 'event',
        eventTime: DateTime(now.year, now.month, now.day, 9),
        durationMinutes: 90,
      ),
      DiaryEntry(
        id: 'timeline-batch-b',
        content: '程序设计',
        timestamp: now,
        category: 'event',
        eventTime: DateTime(now.year, now.month, now.day, 14),
        durationMinutes: 60,
      ),
    ];

    await tester.binding.setSurfaceSize(const Size(1000, 760));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timelineEntriesProvider.overrideWith((ref) => events),
          reminderRuleProvider.overrideWith(_TimelineRuleNotifier.new),
          todoListProvider.overrideWith(_TimelineTodoNotifier.new),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: const Scaffold(body: TimelineView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('多选'));
    await tester.pumpAndSettle();

    expect(find.text('批量改期'), findsOneWidget);
    expect(find.text('离散数学'), findsOneWidget);
    expect(find.text('程序设计'), findsOneWidget);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('day view mirrors todays active unscheduled todos', (
    tester,
  ) async {
    await initializeDateFormatting('zh_CN', null);
    final now = DateTime.now();
    final todo = TodoTask(
      id: 'today-attention-todo',
      title: '今天已经开始关注的作业',
      createdAt: now.subtract(const Duration(days: 2)),
      attentionDate: DateTime(now.year, now.month, now.day),
      deadline: now.add(const Duration(days: 10)),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timelineEntriesProvider.overrideWith((ref) => const []),
          todoListProvider.overrideWith(
            () => _TimelineTodoDataNotifier([todo]),
          ),
          reminderRuleProvider.overrideWith(_TimelineRuleNotifier.new),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: Scaffold(body: DayView(day: now)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今天已经开始关注的作业'), findsOneWidget);
    expect(find.text('截止与待办'), findsOneWidget);
  });

  testWidgets('recurring occurrence dialog explains shared reminder rules', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ZenTheme.lightTheme,
        home: TimelineEventDialog(
          initialContent: '线性代数课',
          initialTime: DateTime(2026, 9, 7, 9),
          initialReminder: ReminderFormData.defaults(),
          reminderEditable: false,
          isEdit: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('提醒规则（整条重复安排）'), findsOneWidget);
    expect(find.textContaining('提醒设置沿用整条重复安排'), findsOneWidget);
    expect(find.text('提前提醒'), findsNothing);
  });

  testWidgets('event reminder editor exposes interval and monthly day rules', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: ZenTheme.lightTheme,
        home: TimelineEventDialog(
          initialContent: '缴费提醒',
          initialTime: DateTime(2026, 9, 5, 9),
          initialReminder: ReminderFormData.defaults(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('每N天'), findsOneWidget);
    expect(find.text('每月'), findsOneWidget);
    await tester.ensureVisible(find.text('每月'));
    await tester.tap(find.text('每月'));
    await tester.pumpAndSettle();
    expect(find.text('几号'), findsOneWidget);
    expect(find.textContaining('31 号在短月按月底'), findsOneWidget);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('month view keeps archived items out of the month map', (
    tester,
  ) async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final archivedEvent = DiaryEntry(
      id: 'archived-month-event',
      content: '已归档课程',
      timestamp: monthStart,
      category: 'event',
      eventTime: DateTime(monthStart.year, monthStart.month, 3, 9),
      isArchived: true,
    );
    final archivedTodo = TodoTask(
      id: 'archived-month-todo',
      title: '已归档作业',
      createdAt: monthStart,
      deadline: DateTime(monthStart.year, monthStart.month, 4, 18),
      isArchived: true,
      monthVisibility: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timelineEntriesProvider.overrideWith((ref) => [archivedEvent]),
          todoListProvider.overrideWith(
            () => _TimelineTodoDataNotifier([archivedTodo]),
          ),
          reminderRuleProvider.overrideWith(_TimelineRuleNotifier.new),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: Scaffold(
            body: MonthView(monthStart: monthStart, onItemTap: null),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已归档课程'), findsNothing);
    expect(find.text('已归档作业'), findsNothing);
  });

  testWidgets('month view surfaces important standalone reminders', (
    tester,
  ) async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final reminder = ReminderRule(
      id: 'important-month-reminder',
      title: '缴交奖学金材料',
      importance: 'important',
      anchorTime: DateTime(monthStart.year, monthStart.month, 12, 10),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timelineEntriesProvider.overrideWith((ref) => const []),
          todoListProvider.overrideWith(_TimelineTodoNotifier.new),
          reminderRuleProvider.overrideWith(
            () => _TimelineRuleDataNotifier([reminder]),
          ),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: Scaffold(
            body: MonthView(monthStart: monthStart, onItemTap: null),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('缴交奖学金材料'), findsOneWidget);
  });
}
