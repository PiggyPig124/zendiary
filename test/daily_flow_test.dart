import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zendiary/core/database/db_service.dart';
import 'package:zendiary/models/todo_task.dart';
import 'package:zendiary/providers/app_providers.dart';
import 'package:zendiary/services/data_migration_service.dart';
import 'package:zendiary/services/local_data_service.dart';
import 'package:zendiary/services/today_list_service.dart';
import 'package:zendiary/views/workspace/workspace_views.dart';
import 'package:zendiary/views/todo/todo_create_dialog.dart';
import 'package:zendiary/views/common/task_attention_fields.dart';

class _TestClock extends CurrentTimeNotifier {
  @override
  DateTime build() => DateTime.now();
}

class _MemoryTodos extends TodoListNotifier {
  final List<TodoTask> initial;
  _MemoryTodos(this.initial);
  @override
  List<TodoTask> build() => initial;
  @override
  void toggleTodo(String id) => state = [for (final todo in state)
    todo.id == id ? todo.copyWith(isCompleted: !todo.isCompleted) : todo];
  @override
  void completeTodos(Iterable<String> ids, {required bool completed}) => state = [for (final todo in state)
    ids.contains(todo.id) ? todo.copyWith(isCompleted: completed) : todo];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ProviderContainer container;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zendiary-daily-');
    SharedPreferences.setMockInitialValues({
      DBService.dataDirectoryPreferenceKey: directory.path,
    });
    Hive.init(directory.path);
    for (final name in LocalDataService.boxNames) {
      await Hive.openBox(name);
    }
    container = ProviderContainer(overrides: [currentTimeProvider.overrideWith(_TestClock.new)]);
  });
  tearDown(() async {
    container.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  Future<void> today(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: TodayView())),
      ),
    );
    await tester.pumpAndSettle();
  }

  test(
    'capture survives restart, confirmation, edits and backup roundtrip',
    () async {
      final source = '大作业：课程论文，9月6日开始关注，9月26日截止';
      await container.read(allEntriesProvider.notifier).addEntry(source);
      final captured = container.read(todoListProvider).single;
      expect(captured.taskKind, TaskKind.preparation);
      expect(captured.attentionConfirmed, isFalse);
      expect(captured.validationMessage, isNotNull);
      expect(container.read(allEntriesProvider).single.content, source);
      container.dispose();
      container = ProviderContainer(overrides: [currentTimeProvider.overrideWith(_TestClock.new)]);
      final restored = container.read(todoListProvider).single;
      expect(restored.attentionConfirmed, isFalse);
      container
          .read(todoListProvider.notifier)
          .updateTodo(restored.copyWith(attentionConfirmed: true));
      container
          .read(todoListProvider.notifier)
          .setDeadline(restored.id, DateTime(2027, 9, 26, 23, 59));
      var updated = container.read(todoListProvider).single;
      expect(updated.taskKind, TaskKind.preparation);
      expect(updated.attentionDate, restored.attentionDate);
      final file = await LocalDataService.exportBackup();
      await Hive.box(DBService.todoBoxName).clear();
      await LocalDataService.importBackupFile(file.path);
      final raw = Hive.box(DBService.todoBoxName).get(restored.id) as Map;
      updated = TodoTask.fromJson(raw);
      expect(updated.taskKind, TaskKind.preparation);
      expect(updated.attentionDate, restored.attentionDate);
      expect(updated.attentionConfirmed, isTrue);
    },
  );

  test(
    'legacy migration and re-import are idempotent and preserve manual schedules',
    () async {
      final schedule = DateTime(2026, 9, 8, 15);
      final old =
          TodoTask(
              id: 'old',
              title: 'old',
              createdAt: DateTime(2026, 9, 1),
              scheduledAt: schedule,
            ).toJson()
            ..remove('taskKind')
            ..remove('attentionDate');
      final box = Hive.box(DBService.todoBoxName);
      await box.put('old', old);
      await DataMigrationService.migrateIfNeeded();
      final first = Map.of(box.get('old') as Map);
      await DataMigrationService.migrateIfNeeded();
      expect(box.length, 1);
      expect(box.get('old'), first);
      expect(TodoTask.fromJson(first).attentionDate, calendarDate(schedule));
      await box.put('old', old);
      await DataMigrationService.migrateIfNeeded();
      expect(box.get('old'), first);
      expect(TodoTask.fromJson(first).scheduledAt, schedule);
    },
  );

  testWidgets(
    'ordinary tasks are visible without estimates or planning and complete with undo',
    (tester) async {
      container.dispose();
      container = ProviderContainer(overrides: [
        currentTimeProvider.overrideWith(_TestClock.new),
        todoListProvider.overrideWith(() => _MemoryTodos([
          TodoTask(id: 'ordinary', title: '整理课堂资料', createdAt: DateTime.now()),
        ])),
      ]);
      await today(tester);
      expect(find.text('整理课堂资料'), findsOneWidget);
      expect(find.text('今天要做 (1)'), findsOneWidget);
      expect(find.text('现在安排'), findsNothing);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('今天没有待处理事项'), findsOneWidget);
      expect(find.text('已完成 (1)'), findsOneWidget);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(find.text('今天要做 (1)'), findsOneWidget);
      expect(container.read(todoListProvider).single.scheduledAt, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());

    },
  );

  testWidgets(
    'pending work remains discoverable alongside the empty-state message',
    (tester) async {
      await tester.runAsync(() => container.read(allEntriesProvider.notifier).addEntry('大作业：课程论文'));
      await today(tester);
      expect(find.text('今天没有待处理事项'), findsOneWidget);
      expect(find.text('待补充 (1)'), findsOneWidget);
      await tester.tap(find.text('待补充 (1)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('请选择开始关注日'), findsOneWidget);
      await tester.tap(find.text('大作业：课程论文').first);
      await tester.pumpAndSettle();
      expect(find.text('任务类型与关注日期'), findsOneWidget);
      await tester.tap(find.text('确认保存'));
      await tester.pumpAndSettle();
      expect(find.text('请选择开始关注日'), findsOneWidget);
      expect(container.read(todoListProvider).single.attentionDate, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual preparation requires picking attention and does not default it',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<TodoCreateResult>(
                  context: context,
                  builder: (_) => const TodoCreateDialog(),
                ),
                child: const Text('新建'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('新建'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '待办内容'), '课程论文');
      await tester.tap(find.byType(DropdownButtonFormField<TaskKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('准备型作业').last);
      await tester.pumpAndSettle();
      expect(find.text('开始关注日：未选择'), findsOneWidget);
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();
      expect(find.text('请选择开始关注日'), findsOneWidget);
      expect(find.byType(TodoCreateDialog), findsOneWidget);
    },
  );

  testWidgets(
    'confirming an AI attention date resolves pending without creating a time block',
    (tester) async {
      final now = DateTime.now();
      final todo = TodoTask(
        id: 'proposal',
        title: '课程论文',
        createdAt: now,
        taskKind: TaskKind.preparation,
        attentionDate: now,
        attentionConfirmed: false,
      );
      TodoTask? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showTaskAttentionDialog(context, todo);
                },
                child: const Text('补充'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('补充'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认保存'));
      await tester.pumpAndSettle();
      expect(result?.attentionConfirmed, isTrue);
      expect(result?.scheduledAt, isNull);
      expect(
        TodayListService.build(todos: [result!], now: now).actionable.length,
        1,
      );
    },
  );
}
