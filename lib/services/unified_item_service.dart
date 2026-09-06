import '../models/diary_entry.dart';
import '../models/notebook_entry.dart';
import '../models/reminder_rule.dart';
import '../models/todo_task.dart';
import '../models/unified_item.dart';
import 'recurrence_service.dart';

/// Projects standalone reminder rules into the selected day without turning
/// the reminder rule itself into another persisted item. Event/todo reminders
/// stay attached to their source item; only reminders with no source need a
/// lightweight row in Today/Plan so a student can actually discover them.
List<UnifiedItem> buildStandaloneReminderItemsForDay({
  required List<ReminderRule> rules,
  required DateTime day,
}) {
  final start = DateTime(day.year, day.month, day.day);
  final end = start
      .add(const Duration(days: 1))
      .subtract(const Duration(microseconds: 1));
  final result = <UnifiedItem>[];
  for (final rule in rules) {
    if (!rule.isActive ||
        (rule.targetType != 'standalone' && rule.targetType != 'rule') ||
        rule.anchorTime == null) {
      continue;
    }
    final occurrences = RecurrenceService.occurrencesBetween(rule, start, end);
    for (final occurrence in occurrences) {
      final once = rule.scheduleType == 'once';
      result.add(
        UnifiedItem(
          id: once
              ? rule.id
              : '${rule.id}@${occurrence.originalTime.toIso8601String()}',
          sourceId: rule.id,
          source: UnifiedItemSource.reminder,
          title: compactItemTitle(rule.title),
          startAt: occurrence.scheduledTime,
          status: rule.status,
          priority: rule.importance == 'important' ? 'A' : 'B',
          location: rule.note,
        ),
      );
    }
  }
  result.sort((a, b) {
    final left = a.startAt;
    final right = b.startAt;
    if (left == null && right == null) return a.title.compareTo(b.title);
    if (left == null) return 1;
    if (right == null) return -1;
    final time = left.compareTo(right);
    return time == 0 ? a.title.compareTo(b.title) : time;
  });
  return result;
}

List<UnifiedItem> buildUnifiedItems({
  required List<DiaryEntry> entries,
  required List<TodoTask> todos,
  required List<ReminderRule> rules,
  List<NotebookEntry> notes = const [],
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final items = <UnifiedItem>[
    // Archived events remain discoverable from global search so they can be
    // restored; active events still require a real time to enter the planner.
    ...entries
        .where(
          (e) => e.category == 'event' && (e.isTimelineVisible || e.isArchived),
        )
        .map(unifiedEventItem),
    ...entries.where((e) => e.category == 'draft').map(unifiedDraftItem),
    ...entries.where((e) => e.category == 'note').map(unifiedDiaryNoteItem),
    ...todos.map((todo) => unifiedTodoItem(todo, current)),
    // Associated rules are shown on the source item's detail. Standalone
    // rules remain first-class planner items.
    ...rules
        .where(
          (rule) =>
              rule.targetType == 'standalone' || rule.targetType == 'rule',
        )
        .map(unifiedReminderItem),
    ...notes.map(unifiedNoteItem),
  ];
  // Imports can temporarily contain both a diary-backed note and its
  // notebook counterpart (or duplicate rows with the same source ID). Keep
  // one presentation item so Today/search never turns storage overlap into a
  // second piece of work. Use the underlying source ID when available rather
  // than prefixing it with the presentation type: a note copied from the
  // legacy diary box and its notebook counterpart are still one item to the
  // student. Standalone reminders are different, however: their targetId is
  // optional metadata and may be shared, so those must remain keyed by their
  // own rule ID. The first item wins, preserving the existing ordering while
  // remaining deterministic.
  final seen = <String>{};
  items.removeWhere((item) {
    final identity = item.source == UnifiedItemSource.reminder
        ? '${item.source.name}:${item.id}'
        : item.sourceId ?? item.id;
    return !seen.add(identity);
  });
  items.sort((a, b) {
    final left = a.startAt ?? a.scheduledAt ?? a.deadline;
    final right = b.startAt ?? b.scheduledAt ?? b.deadline;
    if (left == null && right == null) return a.title.compareTo(b.title);
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  });
  return items;
}

/// Builds the Inbox's recent-capture list without exposing the hidden diary
/// source record as a second, non-actionable todo. AI-created todo entries
/// point at one or more real [TodoTask] objects through [sourceEntryId].
List<UnifiedItem> buildRecentCaptureItems({
  required List<DiaryEntry> entries,
  required List<TodoTask> todos,
  List<NotebookEntry> notes = const [],
  DateTime? now,
  int limit = 12,
}) {
  final current = now ?? DateTime.now();
  final todosBySource = <String, List<TodoTask>>{};
  for (final todo in todos) {
    if (todo.isArchived) continue;
    final sourceId = todo.sourceEntryId;
    if (sourceId == null) continue;
    (todosBySource[sourceId] ??= []).add(todo);
  }

  // Keep the timestamp alongside the presentation item. Hive does not
  // guarantee that UUID-keyed values are returned in capture order, and
  // notebook captures live in a different box from diary-backed captures.
  // Sorting before applying the limit keeps “最近捕捉” honest after restart.
  final datedItems = <({UnifiedItem item, DateTime capturedAt})>[];
  for (final entry in entries) {
    if (entry.isArchived) continue;
    if (entry.category == 'todo') {
      final linked = todosBySource[entry.id];
      if (linked != null && linked.isNotEmpty) {
        datedItems.addAll(
          linked.map(
            (todo) => (
              item: unifiedTodoItem(todo, current),
              capturedAt: todo.createdAt,
            ),
          ),
        );
      } else {
        // A legacy or malformed source is still recoverable from the Inbox.
        datedItems.add((
          item: unifiedDraftItem(entry),
          capturedAt: entry.timestamp,
        ));
      }
      continue;
    }
    datedItems.add((
      item: entry.isTimelineVisible
          ? unifiedEventItem(entry)
          : entry.category == 'draft'
          ? unifiedDraftItem(entry)
          : entry.category == 'note'
          ? unifiedDiaryNoteItem(entry)
          : unifiedDraftItem(entry),
      capturedAt: entry.timestamp,
    ));
  }
  // AI-created notes are removed from the diary box once they are promoted,
  // so include the notebook side explicitly instead of losing that capture
  // from the Inbox's recent section.
  for (final note in notes) {
    if (note.isArchived) continue;
    datedItems.add((item: unifiedNoteItem(note), capturedAt: note.updatedAt));
  }
  datedItems.sort((a, b) {
    final time = b.capturedAt.compareTo(a.capturedAt);
    if (time != 0) return time;
    return a.item.id.compareTo(b.item.id);
  });
  return datedItems.take(limit).map((entry) => entry.item).toList();
}
