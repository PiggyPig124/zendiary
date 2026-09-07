import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zendiary/core/theme/zen_theme.dart';
import 'package:zendiary/models/reminder_rule.dart';
import 'package:zendiary/models/todo_task.dart';
import 'package:zendiary/providers/app_providers.dart';
import 'package:zendiary/providers/reminder_rule_provider.dart';
import 'package:zendiary/views/workspace/today_focus_card.dart';
import 'package:zendiary/views/workspace/today_missed_section.dart';
import 'package:zendiary/views/workspace/workspace_views.dart';

class _MissedClock extends CurrentTimeNotifier {
  _MissedClock(this.initial);

  final DateTime initial;

  @override
  DateTime build() => initial;

  void setTime(DateTime value) => state = value;
}

class _MissedTodos extends TodoListNotifier {
  _MissedTodos(this.initial);

  final List<TodoTask> initial;

  @override
  List<TodoTask> build() => initial;

  @override
  void toggleTodo(String id) {
    state = [
      for (final todo in state)
        todo.id == id ? todo.copyWith(isCompleted: !todo.isCompleted) : todo,
    ];
  }

  @override
  void completeTodos(Iterable<String> ids, {required bool completed}) {
    final idSet = ids.toSet();
    state = [
      for (final todo in state)
        idSet.contains(todo.id) ? todo.copyWith(isCompleted: completed) : todo,
    ];
  }

  @override
  void rescheduleTodo(String id, DateTime? scheduledAt) {
    state = [
      for (final todo in state)
        todo.id == id
            ? todo.copyWith(
                scheduledAt: scheduledAt,
                clearScheduledAt: scheduledAt == null,
              )
            : todo,
    ];
  }
}

class _MissedRules extends ReminderRuleNotifier {
  @override
  List<ReminderRule> build() => const [];
}

class _MissedDay extends DayBoundaryNotifier {
  _MissedDay(this.day);

  final DateTime day;

  @override
  DateTime build() => day;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 5, 10);

  Future<void> pumpToday(
    WidgetTester tester, {
    required _MissedClock clock,
    required _MissedTodos todos,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentTimeProvider.overrideWith(() => clock),
          dayBoundaryProvider.overrideWith(() => _MissedDay(calendarDate(now))),
          timelineEntriesProvider.overrideWith((ref) => const []),
          todoListProvider.overrideWith(() => todos),
          reminderRuleProvider.overrideWith(_MissedRules.new),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: const Scaffold(body: TodayView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  TodoTask missedTodo({
    String id = 'missed-view-todo',
    String title = '补完实验报告',
    DateTime? scheduledAt,
  }) => TodoTask(
    id: id,
    title: title,
    createdAt: now.subtract(const Duration(days: 1)),
    scheduledAt: scheduledAt ?? now.subtract(const Duration(hours: 1)),
    deadline: now.add(const Duration(days: 2)),
  );

  testWidgets(
    'missed section shows original block and opens details at 390px',
    (tester) async {
      final todo = missedTodo();
      final clock = _MissedClock(now);
      final todos = _MissedTodos([todo]);
      await pumpToday(tester, clock: clock, todos: todos);

      expect(find.byType(TodayMissedSection), findsOneWidget);
      expect(find.text('安排已过，尚未完成 (1)'), findsOneWidget);
      expect(find.text('没做完也没关系，重新安排或先保留为待办。'), findsOneWidget);
      expect(find.textContaining('原定 9月5日 09:00–9月5日 09:30'), findsOneWidget);
      expect(find.text('待办 (0)'), findsOneWidget);
      expect(find.text('今天没有待处理事项'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text(todo.title));
      await tester.tap(find.text(todo.title));
      await tester.pumpAndSettle();
      expect(find.text('完成待办'), findsOneWidget);
      Navigator.of(tester.element(find.text('完成待办'))).pop();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('clock moving past the end transfers current work to missed', (
    tester,
  ) async {
    final scheduled = now.subtract(const Duration(minutes: 20));
    final todo = missedTodo(scheduledAt: scheduled);
    final clock = _MissedClock(now);
    final todos = _MissedTodos([todo]);
    await pumpToday(tester, clock: clock, todos: todos);

    expect(
      find.descendant(
        of: find.byType(TodayFocusCard),
        matching: find.text(todo.title),
      ),
      findsOneWidget,
    );
    clock.setTime(now.add(const Duration(minutes: 11)));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(TodayFocusCard),
        matching: find.text(todo.title),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(TodayMissedSection),
        matching: find.text(todo.title),
      ),
      findsOneWidget,
    );
  });

  testWidgets('completion and undo keep the same missed todo', (tester) async {
    final todo = missedTodo();
    final clock = _MissedClock(now);
    final todos = _MissedTodos([todo]);
    await pumpToday(tester, clock: clock, todos: todos);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(todos.state.single.isCompleted, isTrue);
    expect(find.byType(TodayMissedSection), findsNothing);
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(todos.state.single.isCompleted, isFalse);
    expect(find.byType(TodayMissedSection), findsOneWidget);
  });

  testWidgets('clearing the schedule returns to Today and undo restores it', (
    tester,
  ) async {
    final todo = missedTodo();
    final clock = _MissedClock(now);
    final todos = _MissedTodos([todo]);
    await pumpToday(tester, clock: clock, todos: todos);

    await tester.tap(find.text('暂不安排'));
    await tester.pumpAndSettle();
    expect(todos.state.single.scheduledAt, isNull);
    expect(find.byType(TodayMissedSection), findsNothing);
    expect(find.text('待办 (1)'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(todos.state.single.scheduledAt, todo.scheduledAt);
    expect(find.byType(TodayMissedSection), findsOneWidget);
  });

  testWidgets('canceling the date picker does not write a new schedule', (
    tester,
  ) async {
    final todo = missedTodo();
    final clock = _MissedClock(now);
    final todos = _MissedTodos([todo]);
    await pumpToday(tester, clock: clock, todos: todos);
    final previous = todo.scheduledAt;

    await tester.tap(find.text('调整时间'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    // The localized label is supplied by MaterialLocalizations, so use the
    // first action in the date dialog rather than depending on its language.
    final dateDialogActions = find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.byType(TextButton),
    );
    expect(dateDialogActions, findsAtLeastNWidgets(1));
    await tester.tap(dateDialogActions.first);
    await tester.pumpAndSettle();
    expect(todos.state.single.scheduledAt, previous);
    expect(find.byType(TodayMissedSection), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canceling the time picker does not write a new schedule', (
    tester,
  ) async {
    final todo = missedTodo();
    final clock = _MissedClock(now);
    final todos = _MissedTodos([todo]);
    await pumpToday(tester, clock: clock, todos: todos);
    final previous = todo.scheduledAt;

    await tester.tap(find.text('调整时间'));
    await tester.pumpAndSettle();
    final dateDialog = find.byType(DatePickerDialog);
    final dateActions = find.descendant(
      of: dateDialog,
      matching: find.byType(TextButton),
    );
    await tester.tap(dateActions.last);
    await tester.pumpAndSettle();
    final timeDialog = find.byType(TimePickerDialog);
    expect(timeDialog, findsOneWidget);
    final timeActions = find.descendant(
      of: timeDialog,
      matching: find.byType(TextButton),
    );
    await tester.tap(timeActions.first);
    await tester.pumpAndSettle();

    expect(todos.state.single.scheduledAt, previous);
    expect(find.byType(TodayMissedSection), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'detail reschedule closes and its undo restores the source task',
    (tester) async {
      final todo = missedTodo();
      final clock = _MissedClock(now);
      final todos = _MissedTodos([todo]);
      await pumpToday(tester, clock: clock, todos: todos);
      final previous = todo.scheduledAt;

      final missedTitle = find.descendant(
        of: find.byType(TodayMissedSection),
        matching: find.text(todo.title),
      );
      await tester.ensureVisible(missedTitle);
      await tester.tap(missedTitle);
      await tester.pumpAndSettle();
      await tester.tap(find.text('调整排期'));
      await tester.pumpAndSettle();

      final dateDialog = find.byType(DatePickerDialog);
      expect(dateDialog, findsOneWidget);
      final futureDay = find.descendant(
        of: dateDialog,
        matching: find.text('6'),
      );
      expect(futureDay, findsOneWidget);
      await tester.tap(futureDay);
      final dateActions = find.descendant(
        of: dateDialog,
        matching: find.byType(TextButton),
      );
      await tester.tap(dateActions.last);
      await tester.pumpAndSettle();

      final timeDialog = find.byType(TimePickerDialog);
      expect(timeDialog, findsOneWidget);
      final timeActions = find.descendant(
        of: timeDialog,
        matching: find.byType(TextButton),
      );
      await tester.tap(timeActions.last);
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsNothing);
      expect(find.text('调整排期'), findsNothing);
      expect(todos.state.single.scheduledAt, isNot(previous));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(todos.state.single.scheduledAt, previous);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rescheduling a missed task keeps its id and returns it to focus',
    (tester) async {
      final todo = missedTodo();
      final clock = _MissedClock(now);
      final todos = _MissedTodos([todo]);
      await pumpToday(tester, clock: clock, todos: todos);

      await tester.tap(find.text('调整时间'));
      await tester.pumpAndSettle();
      final dateDialog = find.byType(DatePickerDialog);
      final dateActions = find.descendant(
        of: dateDialog,
        matching: find.byType(TextButton),
      );
      // Keep today's date and change only the time to a future slot.
      await tester.tap(dateActions.last);
      await tester.pumpAndSettle();
      final timeDialog = find.byType(TimePickerDialog);
      final hourFields = find.descendant(
        of: timeDialog,
        matching: find.byType(TextField),
      );
      expect(hourFields, findsAtLeastNWidgets(1));
      await tester.tap(hourFields.first);
      await tester.enterText(hourFields.first, '11');
      final timeActions = find.descendant(
        of: timeDialog,
        matching: find.byType(TextButton),
      );
      await tester.tap(timeActions.last);
      await tester.pumpAndSettle();

      expect(todos.state.map((item) => item.id), [todo.id]);
      expect(todos.state.single.scheduledAt, DateTime(2026, 9, 5, 11));
      expect(find.byType(TodayMissedSection), findsNothing);
      expect(
        find.descendant(
          of: find.byType(TodayFocusCard),
          matching: find.text(todo.title),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(TodayFocusCard),
          matching: find.text('接下来'),
        ),
        findsOneWidget,
      );
    },
  );
}
