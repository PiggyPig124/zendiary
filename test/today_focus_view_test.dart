import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zendiary/core/theme/zen_theme.dart';
import 'package:zendiary/models/reminder_rule.dart';
import 'package:zendiary/models/todo_task.dart';
import 'package:zendiary/providers/app_providers.dart';
import 'package:zendiary/providers/reminder_rule_provider.dart';
import 'package:zendiary/views/workspace/today_focus_card.dart';
import 'package:zendiary/views/workspace/workspace_views.dart';

class _FixedClock extends CurrentTimeNotifier {
  _FixedClock(this.initial);

  final DateTime initial;

  @override
  DateTime build() => initial;

  void setTime(DateTime value) => state = value;
}

class _MemoryTodos extends TodoListNotifier {
  _MemoryTodos(this.initial);

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
}

class _EmptyRules extends ReminderRuleNotifier {
  @override
  List<ReminderRule> build() => const [];
}

class _FixedDay extends DayBoundaryNotifier {
  _FixedDay(this.day);

  final DateTime day;

  @override
  DateTime build() => day;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final start = DateTime(2026, 9, 5, 10, 30);
  final end = start.add(const Duration(minutes: 30));

  Future<void> pumpToday(
    WidgetTester tester, {
    required _FixedClock clock,
    required _MemoryTodos todos,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentTimeProvider.overrideWith(() => clock),
          dayBoundaryProvider.overrideWith(
            () => _FixedDay(DateTime(2026, 9, 5)),
          ),
          timelineEntriesProvider.overrideWith((ref) => const []),
          todoListProvider.overrideWith(() => todos),
          reminderRuleProvider.overrideWith(_EmptyRules.new),
        ],
        child: MaterialApp(
          theme: ZenTheme.lightTheme,
          home: const Scaffold(body: TodayView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder focusTitle(WidgetTester tester, String title) => find.descendant(
    of: find.byType(TodayFocusCard),
    matching: find.text(title),
  );

  testWidgets('Today focus follows next/current time and completion changes', (
    tester,
  ) async {
    final todo = TodoTask(
      id: 'focus-todo',
      title: '阅读论文',
      createdAt: start,
      scheduledAt: start,
      estimatedMinutes: 30,
    );
    final clock = _FixedClock(DateTime(2026, 9, 5, 10));
    final todos = _MemoryTodos([todo]);
    await pumpToday(tester, clock: clock, todos: todos);

    expect(focusTitle(tester, todo.title), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TodayFocusCard),
        matching: find.text('接下来'),
      ),
      findsOneWidget,
    );

    clock.setTime(start);
    await tester.pumpAndSettle();
    expect(focusTitle(tester, todo.title), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TodayFocusCard),
        matching: find.text('接下来'),
      ),
      findsNothing,
    );

    await tester.tap(focusTitle(tester, todo.title));
    await tester.pumpAndSettle();
    expect(find.text('完成待办'), findsOneWidget);
    Navigator.of(tester.element(find.text('完成待办'))).pop();
    await tester.pumpAndSettle();

    todos.toggleTodo(todo.id);
    await tester.pumpAndSettle();
    expect(focusTitle(tester, todo.title), findsNothing);
    expect(todos.state.single.isCompleted, isTrue);
    expect(
      find.descendant(
        of: find.byType(TodayFocusCard),
        matching: find.text('现在没有安排，按自己的节奏选择下一件事。'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('ending a focus interval does not complete its todo', (
    tester,
  ) async {
    final todo = TodoTask(
      id: 'focus-end-todo',
      title: '整理笔记',
      createdAt: start,
      scheduledAt: start,
      estimatedMinutes: 30,
    );
    final clock = _FixedClock(DateTime(2026, 9, 5, 10));
    final todos = _MemoryTodos([todo]);
    await pumpToday(tester, clock: clock, todos: todos);

    clock.setTime(start);
    await tester.pumpAndSettle();
    expect(focusTitle(tester, todo.title), findsOneWidget);

    clock.setTime(end);
    await tester.pumpAndSettle();
    expect(focusTitle(tester, todo.title), findsNothing);
    expect(todos.state.single.isCompleted, isFalse);
  });
}
