import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zendiary/core/theme/zen_theme.dart';
import 'package:zendiary/models/notebook_entry.dart';
import 'package:zendiary/providers/app_providers.dart';
import 'package:zendiary/providers/notebook_provider.dart';
import 'package:zendiary/providers/reminder_rule_provider.dart';
import 'package:zendiary/models/diary_entry.dart';
import 'package:zendiary/models/reminder_rule.dart';
import 'package:zendiary/models/todo_task.dart';
import 'package:zendiary/models/unified_item.dart';
import 'package:zendiary/views/workspace/workspace_views.dart';
import 'package:zendiary/views/notebook/notebook_view.dart';

void main() {
  group('NotebookView', () {
    testWidgets('shows the notes header and one create action when empty', (
      tester,
    ) async {
      await tester.pumpWidget(_buildNotebook(const []));

      expect(find.text('\u7b14\u8bb0'), findsOneWidget);
      expect(find.text('\u65b0\u5efa\u7b14\u8bb0'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('shows selected note content in preview mode', (tester) async {
      const noteTitle = '\u5468\u672b\u6563\u6b65\u7684\u60f3\u6cd5';
      const noteBody = '\u8bb0\u5f55\u5199\u4f5c\u5185\u5bb9';
      final note = NotebookEntry(title: noteTitle, content: noteBody);

      await tester.pumpWidget(_buildNotebook([note]));

      await tester.tap(find.text(noteTitle));
      await tester.pump();
      await tester.tap(find.text('\u9884\u89c8'));
      await tester.pumpAndSettle();

      expect(find.text(noteBody), findsWidgets);
    });

    testWidgets('switches to a single-column editor on a phone width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final note = NotebookEntry(title: '手机笔记', content: '正文');

      await tester.pumpWidget(_buildNotebook([note]));
      await tester.tap(find.text('手机笔记'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('全部笔记'), findsOneWidget);
    });

    testWidgets('unified note details shows the body and an open-note action', (
      tester,
    ) async {
      final note = NotebookEntry(
        id: 'detail-note',
        title: '离散数学复习',
        content: '先整理定义，再做三道例题。',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notebookListProvider.overrideWith(
              () => _TestNotebookListNotifier([note]),
            ),
            allEntriesProvider.overrideWith(() => _TestDiaryNotifier(const [])),
            todoListProvider.overrideWith(() => _TestTodoNotifier(const [])),
            reminderRuleProvider.overrideWith(_TestReminderRuleNotifier.new),
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
                      unifiedNoteItem(note),
                    ),
                    child: const Text('打开详情'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开详情'));
      await tester.pumpAndSettle();

      expect(find.text('正文'), findsOneWidget);
      expect(find.text(note.content), findsOneWidget);
      expect(find.text('打开笔记'), findsOneWidget);
    });
  });
}

Widget _buildNotebook(List<NotebookEntry> notes) {
  return ProviderScope(
    overrides: [
      notebookListProvider.overrideWith(() => _TestNotebookListNotifier(notes)),
    ],
    child: MaterialApp(
      theme: ZenTheme.lightTheme,
      home: const Scaffold(body: NotebookView()),
    ),
  );
}

class _TestNotebookListNotifier extends NotebookListNotifier {
  _TestNotebookListNotifier(this._initialNotes);

  final List<NotebookEntry> _initialNotes;

  @override
  List<NotebookEntry> build() => _initialNotes;

  @override
  void addNote(NotebookEntry entry) {
    state = [entry, ...state];
  }

  @override
  void updateNote(NotebookEntry entry) {
    final index = state.indexWhere((note) => note.id == entry.id);
    if (index == -1) return;
    state = [...state]..[index] = entry;
  }

  @override
  void deleteNote(String id) {
    state = state.where((note) => note.id != id).toList();
  }
}

class _TestDiaryNotifier extends DiaryNotifier {
  _TestDiaryNotifier(this._initialEntries);

  final List<DiaryEntry> _initialEntries;

  @override
  List<DiaryEntry> build() => _initialEntries;
}

class _TestTodoNotifier extends TodoListNotifier {
  _TestTodoNotifier(this._initialTodos);

  final List<TodoTask> _initialTodos;

  @override
  List<TodoTask> build() => _initialTodos;
}

class _TestReminderRuleNotifier extends ReminderRuleNotifier {
  @override
  List<ReminderRule> build() => const [];
}
