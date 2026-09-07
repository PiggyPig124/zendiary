import 'diary_entry.dart';
import 'notebook_entry.dart';
import 'reminder_rule.dart';
import 'todo_task.dart';

enum UnifiedItemSource { event, todo, reminder, draft, note }

/// A presentation-only item shared by Today, Plan, Inbox and search.
/// Business data remains in the source models and is never persisted here.
class UnifiedItem {
  final String id;
  final UnifiedItemSource source;
  final String title;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime? scheduledAt;
  final DateTime? deadline;
  final String status;
  final String priority;
  final List<String> tags;
  final String? location;
  final String? sourceId;

  const UnifiedItem({
    required this.id,
    required this.source,
    required this.title,
    this.startAt,
    this.endAt,
    this.scheduledAt,
    this.deadline,
    this.status = 'active',
    this.priority = 'B',
    this.tags = const [],
    this.location,
    this.sourceId,
  });

  bool get isCompleted => status == 'completed';
  bool get isOverdue => status == 'overdue';
  bool get isArchived => status == 'archived';
  bool get hasSchedule => startAt != null || scheduledAt != null;
}

String compactItemTitle(String title) {
  final trimmed = title.trim();
  if (trimmed.isEmpty) return '未命名事项';
  // AI summaries imported from course schedules often repeat the day/time
  // already visible in the planner. Keep the useful title only.
  final withoutSchedule = trimmed.replaceFirst(
    RegExp(r'\s*[（(]\s*周[一二三四五六日].*?[）)]\s*$'),
    '',
  );
  return withoutSchedule.trim().isEmpty ? trimmed : withoutSchedule.trim();
}

UnifiedItem unifiedEventItem(DiaryEntry event) {
  final summary = event.aiSummary?.trim();
  final isImportedTimetableEvent = event.tags.contains('AIMS');
  return UnifiedItem(
    id: event.id,
    sourceId: event.id,
    source: UnifiedItemSource.event,
    title: compactItemTitle(
      isImportedTimetableEvent || summary?.isNotEmpty != true
          ? event.content
          : summary!,
    ),
    startAt: event.eventTime,
    endAt: event.endTime,
    status: event.isArchived
        ? 'archived'
        : event.isCompleted
        ? 'completed'
        : 'active',
    tags: event.tags,
    location: event.location,
  );
}

UnifiedItem unifiedTodoItem(
  TodoTask todo,
  DateTime now, {
  DateTime? scheduledAtOverride,
}) {
  final lifecycle = todo.lifecycleAt(now);
  return UnifiedItem(
    id: todo.id,
    sourceId: todo.id,
    source: UnifiedItemSource.todo,
    title: todo.title,
    scheduledAt: scheduledAtOverride ?? todo.scheduledAt,
    deadline: todo.deadline,
    status: todo.isArchived
        ? 'archived'
        : switch (lifecycle) {
            TodoLifecycle.completed => 'completed',
            TodoLifecycle.overdue => 'overdue',
            TodoLifecycle.upcoming => 'upcoming',
            TodoLifecycle.active => 'active',
          },
    priority: todo.priority,
    tags: todo.tags,
  );
}

UnifiedItem unifiedReminderItem(ReminderRule rule) {
  return UnifiedItem(
    id: rule.id,
    // For standalone and recurring projections the rule is the source. The
    // target ID is only linkage metadata for event/todo rules, which are not
    // emitted as independent unified items.
    sourceId: rule.id,
    source: UnifiedItemSource.reminder,
    title: rule.title,
    startAt: rule.anchorTime,
    status: rule.status,
    priority: rule.importance == 'important' ? 'A' : 'B',
    location: rule.note,
  );
}

UnifiedItem unifiedDraftItem(DiaryEntry draft) {
  return UnifiedItem(
    id: draft.id,
    sourceId: draft.id,
    source: UnifiedItemSource.draft,
    title: draft.content,
    status: draft.isArchived ? 'archived' : 'inbox',
    tags: draft.tags,
  );
}

UnifiedItem unifiedDiaryNoteItem(DiaryEntry note) {
  return UnifiedItem(
    id: note.id,
    sourceId: note.id,
    source: UnifiedItemSource.note,
    title: note.aiSummary?.trim().isNotEmpty == true
        ? note.aiSummary!.trim()
        : compactItemTitle(note.content),
    status: note.isArchived ? 'archived' : 'active',
    tags: note.tags,
  );
}

UnifiedItem unifiedNoteItem(NotebookEntry note) {
  return UnifiedItem(
    id: note.id,
    sourceId: note.id,
    source: UnifiedItemSource.note,
    title: note.title.trim().isEmpty ? '无标题' : note.title,
    status: note.isArchived ? 'archived' : 'active',
    tags: note.tags,
  );
}
