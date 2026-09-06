import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:zendiary/models/diary_entry.dart';
import 'package:zendiary/models/pending_action_preview.dart';
import 'package:zendiary/models/reminder_rule.dart';
import 'package:zendiary/models/todo_task.dart';
import 'package:zendiary/providers/app_providers.dart';
import 'package:zendiary/providers/reminder_rule_provider.dart';
import 'package:zendiary/views/morning/morning_briefing_view.dart';

class _FakeDiaryNotifier extends DiaryNotifier {
  _FakeDiaryNotifier(this.entries);

  final List<DiaryEntry> entries;

  @override
  List<DiaryEntry> build() => entries;
}

class _FakeTodoNotifier extends TodoListNotifier {
  @override
  List<TodoTask> build() => const [];
}

class _FakeReminderRuleNotifier extends ReminderRuleNotifier {
  @override
  List<ReminderRule> build() => const [];
}

class _FakeLowLoadStatusNotifier extends LowLoadStatusNotifier {
  @override
  LowLoadStatus? build() => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('keeps morning focus event time on one line', (tester) async {
    await initializeDateFormatting('zh_CN', null);
    final now = DateTime.now();
    final eventTime = DateTime(now.year, now.month, now.day, 17, 50);
    final event = DiaryEntry(
      id: 'focus-event',
      content: 'Focus event',
      timestamp: eventTime,
      category: 'event',
      eventTime: eventTime,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith(() => _FakeDiaryNotifier([event])),
          todoListProvider.overrideWith(_FakeTodoNotifier.new),
          reminderRuleProvider.overrideWith(_FakeReminderRuleNotifier.new),
          lowLoadStatusProvider.overrideWith(_FakeLowLoadStatusNotifier.new),
        ],
        child: const MaterialApp(
          home: Scaffold(body: MorningBriefingView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.event_note_outlined));
    await tester.pumpAndSettle();

    final timeLabels = tester.widgetList<Text>(find.text('17:50')).toList();
    expect(timeLabels, isNotEmpty);
    for (final timeLabel in timeLabels) {
      expect(timeLabel.maxLines, 1);
      expect(timeLabel.softWrap, isFalse);
    }
  });
}
