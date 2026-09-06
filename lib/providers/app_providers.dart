import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/database/db_service.dart';
import '../models/ai_parsed_intent.dart';
import '../models/diary_entry.dart';
import '../models/notebook_entry.dart';
import '../models/pending_action_preview.dart';
import '../models/reminder_rule.dart';
import '../models/todo_task.dart';
import '../models/unified_item.dart';
import 'notebook_provider.dart';
import '../services/action_preview_service.dart';
import '../providers/reminder_rule_provider.dart';
import '../services/ai_service.dart';
import '../services/planner_service.dart';
import '../services/runtime_reminder_service.dart';
import '../services/unified_item_service.dart';
import '../services/pending_confirmation_service.dart';
import '../services/pending_action_service.dart';

final allEntriesProvider = NotifierProvider<DiaryNotifier, List<DiaryEntry>>(
  DiaryNotifier.new,
);

final draftEntriesProvider = Provider<List<DiaryEntry>>((ref) {
  return ref
      .watch(allEntriesProvider)
      .where((e) => e.category == 'draft' && !e.isArchived)
      .toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
});

final timelineEntriesProvider = Provider<List<DiaryEntry>>((ref) {
  return ref
      .watch(allEntriesProvider)
      .where((e) => e.isTimelineVisible)
      .toList()
    ..sort((a, b) => a.sortTime.compareTo(b.sortTime));
});

final todoListProvider = NotifierProvider<TodoListNotifier, List<TodoTask>>(
  TodoListNotifier.new,
);

final unifiedItemsProvider = Provider<List<UnifiedItem>>((ref) {
  return buildUnifiedItems(
    entries: ref.watch(allEntriesProvider),
    todos: ref.watch(todoListProvider),
    rules: ref.watch(reminderRuleProvider),
    notes: ref.watch(notebookListProvider),
  );
});

enum DiaryAddOutcome {
  savedOnly,
  aiDisabled,
  aiNotConfigured,
  aiFailed,
  localUpdated,
  localTodoCreated,
  aiUpdated,
  todoCreated,
  noteCreated,
  reminderNeedsConfirmation,
  localReminderNeedsConfirmation,
  pendingActionNeedsConfirmation,
}

class AiReminderConfirmation {
  final DiaryEntry entry;
  final AiParsedIntent intent;

  const AiReminderConfirmation({required this.entry, required this.intent});
}

class DiaryAddResult {
  final DiaryAddOutcome outcome;
  final AiReminderConfirmation? reminderConfirmation;
  final PendingActionPreview? pendingActionPreview;
  final String? entryId;
  final String? noteId;

  /// The source capture that was promoted out of the diary box. Keeping it in
  /// the result lets the Inbox undo action restore the exact original text,
  /// tags and AI metadata instead of deleting the promoted note irreversibly.
  final DiaryEntry? sourceEntry;

  const DiaryAddResult(
    this.outcome, {
    this.reminderConfirmation,
    this.pendingActionPreview,
    this.entryId,
    this.noteId,
    this.sourceEntry,
  });
}

final lowLoadStatusProvider =
    NotifierProvider<LowLoadStatusNotifier, LowLoadStatus?>(
      LowLoadStatusNotifier.new,
    );

enum UiDensity { comfortable, standard, compact }

final uiDensityProvider = NotifierProvider<UiDensityNotifier, UiDensity>(
  UiDensityNotifier.new,
);

/// A lightweight calendar-day signal used by date-sensitive views.
///
/// Most data providers only notify when an item changes. Without a separate
/// signal, a window left open overnight would keep rendering yesterday's
/// Today page until the next user action. The app refreshes this notifier at
/// startup, midnight and lifecycle resume.
final dayBoundaryProvider = NotifierProvider<DayBoundaryNotifier, DateTime>(
  DayBoundaryNotifier.new,
);

/// A minute-level clock signal for views whose meaning changes as time passes
/// (for example, a planned todo becoming missed at 10:00). It intentionally
/// carries no persisted data; the system clock remains the source of truth.
final currentTimeProvider = NotifierProvider<CurrentTimeNotifier, DateTime>(
  CurrentTimeNotifier.new,
);

class DayBoundaryNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void refresh(DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    if (state != day) state = day;
  }
}

class CurrentTimeNotifier extends Notifier<DateTime> {
  Timer? _timer;

  @override
  DateTime build() {
    ref.onDispose(() => _timer?.cancel());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      state = DateTime.now();
    });
    return DateTime.now();
  }

  void refresh() {
    state = DateTime.now();
  }
}

class UiDensityNotifier extends Notifier<UiDensity> {
  static const _key = 'ui_density';

  @override
  UiDensity build() {
    final value = Hive.box(DBService.settingsBoxName).get(_key)?.toString();
    return UiDensity.values.firstWhere(
      (item) => item.name == value,
      orElse: () => UiDensity.standard,
    );
  }

  void setDensity(UiDensity density) {
    state = density;
    Hive.box(DBService.settingsBoxName).put(_key, density.name);
  }
}

class LowLoadStatusNotifier extends Notifier<LowLoadStatus?> {
  static const _settingsKey = 'low_load_status';

  @override
  LowLoadStatus? build() {
    final raw = Hive.box(DBService.settingsBoxName).get(_settingsKey);
    if (raw is! Map) return null;
    final status = LowLoadStatus.fromJson(raw);
    if (!status.active) return null;
    final until = status.until;
    if (until != null && until.isBefore(DateTime.now())) return null;
    return status;
  }

  void activate(LowLoadStatus status) {
    state = status;
    Hive.box(DBService.settingsBoxName).put(_settingsKey, status.toJson());
  }

  void clear() {
    state = null;
    Hive.box(DBService.settingsBoxName).delete(_settingsKey);
  }
}

class DiaryNotifier extends Notifier<List<DiaryEntry>> {
  @override
  List<DiaryEntry> build() {
    final box = Hive.box(DBService.diaryBoxName);
    final entries = <DiaryEntry>[];
    for (final value in box.values) {
      if (value is Map) {
        entries.add(DiaryEntry.fromJson(value));
      }
    }
    return entries;
  }

  Future<DiaryAddResult> addEntry(String content) async {
    final now = DateTime.now();
    final entry = DiaryEntry(
      id: const Uuid().v4(),
      content: content,
      timestamp: now,
      category: 'draft',
    );

    state = [entry, ...state];
    _save(entry);

    final settings = AIService.loadSettings();
    debugPrint(
      '[addEntry] AI 设置: enabled=${settings.enabled}, configured=${settings.isConfigured}',
    );
    AiParsedIntent? parsedIntent;
    var usedLocalParser = false;
    if (!settings.enabled || !settings.isConfigured) {
      final fallback = AIService.parseLocalIntent(content, now);
      if (fallback != null) {
        parsedIntent = fallback;
        usedLocalParser = true;
        debugPrint('[addEntry] → 使用本地规则整理捕捉');
      } else if (!settings.enabled) {
        debugPrint('[addEntry] ❌ AI 未启用，返回 aiDisabled');
        return DiaryAddResult(DiaryAddOutcome.aiDisabled, entryId: entry.id);
      } else {
        debugPrint('[addEntry] ❌ AI 配置不完整，返回 aiNotConfigured');
        return DiaryAddResult(
          DiaryAddOutcome.aiNotConfigured,
          entryId: entry.id,
        );
      }
    } else {
      debugPrint('[addEntry] → 调用 AI 分类');
      parsedIntent = await AIService.parseDiaryIntent(content, now);
      if (parsedIntent == null) {
        final fallback = AIService.parseLocalIntent(content, now);
        if (fallback != null) {
          parsedIntent = fallback;
          usedLocalParser = true;
          debugPrint('[addEntry] → AI 无结果，改用本地规则整理');
        }
      }
      if (parsedIntent == null) {
        debugPrint('[addEntry] ❌ AI 与本地规则均无结果，返回 aiFailed');
        return DiaryAddResult(DiaryAddOutcome.aiFailed, entryId: entry.id);
      }
    }
    final intent = parsedIntent;
    debugPrint('[addEntry] AI 分类完成: category=${intent.category}');

    // 注意：不能 ref.read(timelineEntriesProvider)，因为它依赖 allEntriesProvider
    // 在 DiaryNotifier 内部读取会造成循环依赖。直接用 state 过滤。
    final timelineEvents = state.where((e) => e.isTimelineVisible).toList()
      ..sort((a, b) => a.sortTime.compareTo(b.sortTime));

    final preview = ActionPreviewService.buildPreview(
      intent: intent,
      sourceText: content,
      now: now,
      todos: ref.read(todoListProvider),
      events: timelineEvents,
      rules: ref.read(reminderRuleProvider),
    );
    if (preview != null) {
      debugPrint('[addEntry] → 返回 pendingActionNeedsConfirmation');
      await PendingActionService.save(preview);
      return DiaryAddResult(
        DiaryAddOutcome.pendingActionNeedsConfirmation,
        pendingActionPreview: preview,
        entryId: entry.id,
      );
    }

    final updated = AIService.normalizeCapturedEntry(
      AIService.applyAIIntent(entry, intent),
    );
    _replaceEntry(updated);
    debugPrint(
      '[addEntry] 条目已更新: category=${updated.category}, eventTime=${updated.eventTime}',
    );

    if (updated.category == 'note') {
      final title =
          (updated.aiSummary?.trim().isNotEmpty == true
                  ? updated.aiSummary!
                  : updated.content.trim().split('\n').first)
              .trim();
      final note = NotebookEntry(
        title: title.isEmpty ? '无标题' : title,
        content: updated.content,
        tags: updated.tags,
      );
      ref.read(notebookListProvider.notifier).addNote(note);
      state = state.where((item) => item.id != updated.id).toList();
      Hive.box(DBService.diaryBoxName).delete(updated.id);
      return DiaryAddResult(
        DiaryAddOutcome.noteCreated,
        noteId: note.id,
        sourceEntry: updated,
      );
    }

    if (updated.category == 'event' && updated.eventTime != null) {
      // 事件→提醒规则：为 AI 分类的事件自动创建提醒规则
      // 注意：不再自动创建关联 TodoTask（用户输入一句话不应变出三个实体）
      if (intent.requiresReminderConfirmation) {
        final outcome = usedLocalParser
            ? DiaryAddOutcome.localReminderNeedsConfirmation
            : DiaryAddOutcome.reminderNeedsConfirmation;
        debugPrint('[addEntry] → 返回 $outcome');
        await PendingConfirmationService.save(entry: updated, intent: intent);
        return DiaryAddResult(
          outcome,
          reminderConfirmation: AiReminderConfirmation(
            entry: updated,
            intent: intent,
          ),
          entryId: entry.id,
        );
      }
      _syncAiEventReminderRule(updated, intent: intent);
      debugPrint('[addEntry] 提醒规则已同步');
    }

    var createdTodo = false;
    final createdTodos = <TodoTask>[];
    final todoTitles = AIService.todoTitlesForIntent(intent, content);
    if (updated.category == 'todo' && todoTitles.isNotEmpty) {
      final todoNotifier = ref.read(todoListProvider.notifier);
      for (var index = 0; index < todoTitles.length; index++) {
        final title = todoTitles[index];
        if (title.isNotEmpty) {
          final todo = todoNotifier.addTodo(
            title,
            sourceEntryId: entry.id,
            category: intent.tags.isEmpty ? 'general' : intent.tags.first,
            priority: _priorityForImportance(intent.importance),
            scheduledAt: staggerCapturedTodoSchedule(intent.scheduledAt, index),
            taskKind: intent.taskKind,
            attentionDate: intent.attentionDate,
            opensAt: intent.todoOpensAt,
            attentionConfirmed: intent.taskKind != TaskKind.preparation,
            deadline: intent.todoDeadline,
            tags: intent.tags,
          );
          createdTodos.add(todo);
          createdTodo = true;
        }
      }
    }

    // AI 识别出的待办也可能带有重复/执行提醒。让高干扰、重复或多次
    // 提醒先进入收件箱确认；低干扰的一次性执行提醒可以直接同步。
    // 截止提醒由 addTodo() 的 deadline 规则独立负责，避免生成两个相同提醒。
    if (createdTodos.isNotEmpty && intent.reminder.enabled) {
      if (intent.requiresReminderConfirmation) {
        await PendingConfirmationService.save(entry: updated, intent: intent);
        return DiaryAddResult(
          usedLocalParser
              ? DiaryAddOutcome.localReminderNeedsConfirmation
              : DiaryAddOutcome.todoCreated,
          reminderConfirmation: AiReminderConfirmation(
            entry: updated,
            intent: intent,
          ),
          entryId: entry.id,
        );
      }
      for (final todo in createdTodos) {
        _syncAiTodoReminderRule(todo, intent: intent, now: now);
      }
    }

    final outcome = createdTodo
        ? (usedLocalParser
              ? DiaryAddOutcome.localTodoCreated
              : DiaryAddOutcome.todoCreated)
        : (usedLocalParser
              ? DiaryAddOutcome.localUpdated
              : DiaryAddOutcome.aiUpdated);
    debugPrint('[addEntry] → 返回 $outcome');
    return DiaryAddResult(outcome, entryId: entry.id);
  }

  DiaryEntry? addEvent(
    String content,
    DateTime eventTime, {
    String? location,
    int? durationMinutes,
  }) {
    final trimmedContent = content.trim();
    if (trimmedContent.isEmpty) return null;
    final trimmedLocation = location?.trim();
    final entry = DiaryEntry(
      id: const Uuid().v4(),
      content: trimmedContent,
      timestamp: DateTime.now(),
      category: 'event',
      eventTime: eventTime,
      durationMinutes: durationMinutes,
      location: trimmedLocation == null || trimmedLocation.isEmpty
          ? null
          : trimmedLocation,
    );
    state = [entry, ...state];
    _save(entry);
    return entry;
  }

  void deleteEntry(String id) {
    state = state.where((e) => e.id != id).toList();
    Hive.box(DBService.diaryBoxName).delete(id);

    // 向下级联：删除以该条目为源的待办
    final todos = ref.read(todoListProvider);
    for (final todo in todos.where((t) => t.sourceEntryId == id)) {
      ref.read(todoListProvider.notifier).deleteTodo(todo.id);
    }

    // 向下级联：删除关联该条目的提醒规则
    final rules = ref.read(reminderRuleProvider);
    for (final rule in rules.where((r) => r.targetId == id)) {
      ref.read(reminderRuleProvider.notifier).deleteRule(rule.id);
    }
  }

  void deleteEntries(Iterable<String> ids) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    state = state.where((e) => !idSet.contains(e.id)).toList();
    final box = Hive.box(DBService.diaryBoxName);
    for (final id in idSet) {
      box.delete(id);
    }

    // 向下级联：批量删除关联的待办和提醒规则
    final todoNotifier = ref.read(todoListProvider.notifier);
    final todos = ref.read(todoListProvider);
    for (final todo in todos.where(
      (t) => t.sourceEntryId != null && idSet.contains(t.sourceEntryId!),
    )) {
      todoNotifier.deleteTodo(todo.id);
    }

    final ruleNotifier = ref.read(reminderRuleProvider.notifier);
    final rules = ref.read(reminderRuleProvider);
    for (final rule in rules.where(
      (r) => r.targetId != null && idSet.contains(r.targetId!),
    )) {
      ruleNotifier.deleteRule(rule.id);
    }
  }

  void editEntry(String id, String newContent) {
    final index = state.indexWhere((e) => e.id == id);
    if (index == -1) return;
    _replaceEntry(state[index].copyWith(content: newContent));
  }

  void archiveEntry(String id, {bool archived = true}) {
    final index = state.indexWhere((entry) => entry.id == id);
    if (index == -1) return;
    _replaceEntry(state[index].copyWith(isArchived: archived));
  }

  /// Re-inserts a promoted capture when the Inbox undo action is pressed.
  /// This is intentionally idempotent so a delayed snackbar callback cannot
  /// create duplicate source rows.
  void restoreEntry(DiaryEntry entry) {
    final existingIndex = state.indexWhere((item) => item.id == entry.id);
    if (existingIndex == -1) {
      state = [entry, ...state];
      _save(entry);
    } else {
      _replaceEntry(entry);
    }
  }

  void convertToEvent(
    String id,
    DateTime eventTime, {
    String? location,
    int? durationMinutes,
  }) {
    final index = state.indexWhere((e) => e.id == id);
    if (index == -1) return;
    final trimmedLocation = location?.trim();
    _replaceEntry(
      state[index].copyWith(
        category: 'event',
        eventTime: eventTime,
        durationMinutes: durationMinutes,
        clearDurationMinutes: durationMinutes == null,
        location: trimmedLocation,
        clearLocation: trimmedLocation == null || trimmedLocation.isEmpty,
      ),
    );
  }

  void rescheduleEvent(String id, DateTime startAt, {int? durationMinutes}) {
    final index = state.indexWhere((entry) => entry.id == id);
    if (index == -1) return;
    final current = state[index];
    _replaceEntry(
      current.copyWith(eventTime: startAt, durationMinutes: durationMinutes),
    );
    final ruleNotifier = ref.read(reminderRuleProvider.notifier);
    final rule = ruleNotifier.ruleForTarget('event', id);
    if (rule != null && rule.scheduleType == 'once') {
      ruleNotifier.updateRule(rule.copyWith(anchorTime: startAt));
    }
  }

  void editEntryFull(DiaryEntry updated) {
    _replaceEntry(updated);
  }

  void _replaceEntry(DiaryEntry updated) {
    final index = state.indexWhere((e) => e.id == updated.id);
    if (index == -1) return;
    state = [...state.sublist(0, index), updated, ...state.sublist(index + 1)];
    _save(updated);
  }

  /// Confirms a reminder candidate when it has enough information to create a
  /// real trigger. A one-off todo without a scheduled time or deadline is
  /// deliberately left pending: confirming it used to clear the card while
  /// creating no reminder at all.
  bool confirmAiReminder(AiReminderConfirmation confirmation) {
    if (confirmation.entry.category == 'event' &&
        confirmation.entry.eventTime != null) {
      _syncAiEventReminderRule(
        confirmation.entry,
        intent: confirmation.intent,
        requiresConfirmation: false,
      );
    } else {
      final todos = ref
          .read(todoListProvider)
          .where((todo) => todo.sourceEntryId == confirmation.entry.id)
          .toList();
      final recurring = const [
        'daily',
        'weekly',
        'every_n_days',
        'monthly',
      ].contains(confirmation.intent.reminder.scheduleType);
      final allHaveAnchors =
          recurring ||
          (todos.isNotEmpty &&
              todos.every(
                (todo) => todo.scheduledAt != null || todo.deadline != null,
              ));
      if (!allHaveAnchors) return false;
      for (final todo in todos) {
        _syncAiTodoReminderRule(
          todo,
          intent: confirmation.intent,
          now: DateTime.now(),
          requiresConfirmation: false,
        );
      }
    }
    PendingConfirmationService.clear(confirmation.entry.id);
    return true;
  }

  void _syncAiEventReminderRule(
    DiaryEntry entry, {
    AiParsedIntent? intent,
    bool requiresConfirmation = false,
  }) {
    final reminderNotifier = ref.read(reminderRuleProvider.notifier);
    final existing = reminderNotifier.ruleForTarget('event', entry.id);
    if (existing != null) return; // Don't overwrite user-configured rules

    final scheduleType = intent?.reminder.scheduleType ?? 'once';
    final summary = (entry.aiSummary?.trim().isNotEmpty == true)
        ? entry.aiSummary!
        : entry.content;
    reminderNotifier.addRule(
      ReminderRule(
        title: summary,
        targetType: 'event',
        targetId: entry.id,
        category: entry.tags.isEmpty ? 'timeline' : entry.tags.first,
        importance: intent?.importance ?? 'important',
        disturbanceLevel: intent?.disturbanceLevel ?? 'strong',
        scheduleType: scheduleType,
        scheduleInterval: intent?.reminder.scheduleInterval ?? 1,
        scheduleDay: intent?.reminder.scheduleDay,
        anchorTime: entry.eventTime,
        advanceMinutes: intent?.reminder.advanceMinutes.isEmpty == false
            ? intent!.reminder.advanceMinutes
            : const [0],
        generatedByAi: true,
        requiresConfirmation: requiresConfirmation,
        note: entry.location,
        createdAt: entry.timestamp,
        byDay: intent?.reminder.byDay,
        byMonthDay:
            scheduleType == 'monthly' && intent?.reminder.scheduleDay != null
            ? [intent!.reminder.scheduleDay!]
            : null,
      ),
    );

    // 注意：不再需要 _syncTodoRoutineFlag — isRoutine 字段已移除，
    // 例行状态由 ReminderRule 作为唯一真相来源。
  }

  /// Creates the reminder attached to an AI-created todo. Deadline reminders
  /// are kept separate and are already synchronized by [TodoListNotifier];
  /// this method only handles a requested execution cue or a recurring habit.
  void _syncAiTodoReminderRule(
    TodoTask todo, {
    required AiParsedIntent intent,
    required DateTime now,
    bool requiresConfirmation = false,
  }) {
    final candidate = intent.reminder;
    final recurring = const [
      'daily',
      'weekly',
      'every_n_days',
      'monthly',
    ].contains(candidate.scheduleType);
    final advances = candidate.advanceMinutes.isEmpty
        ? const [0]
        : candidate.advanceMinutes;
    final notifier = ref.read(reminderRuleProvider.notifier);

    // A once reminder without a planned execution time is already covered by
    // the independent deadline rule. Preserve the student's requested lead
    // time there instead of silently dropping it or creating a duplicate.
    if (!recurring && todo.scheduledAt == null) {
      final deadlineReminder = notifier.ruleForTodoDeadline(todo.id);
      if (deadlineReminder != null && candidate.advanceMinutes.isNotEmpty) {
        notifier.updateRule(
          deadlineReminder.copyWith(
            title: todo.title,
            category: todo.category,
            advanceMinutes: advances,
            disturbanceLevel: intent.disturbanceLevel,
            importance: intent.importance,
          ),
        );
      }
      return;
    }

    final anchor = todo.scheduledAt ?? _defaultRoutineAnchor(now);
    final rule = ReminderRule(
      id: null,
      title: todo.title,
      targetType: 'todo',
      targetId: todo.id,
      category: todo.category,
      importance: candidate.enabled ? intent.importance : 'normal',
      disturbanceLevel: intent.disturbanceLevel,
      scheduleType: recurring ? candidate.scheduleType : 'once',
      scheduleInterval: candidate.scheduleInterval,
      scheduleDay: candidate.scheduleDay,
      byDay: candidate.byDay,
      byMonthDay:
          candidate.scheduleType == 'monthly' && candidate.scheduleDay != null
          ? [candidate.scheduleDay!]
          : null,
      anchorTime: anchor,
      advanceMinutes: advances,
      status: 'active',
      generatedByAi: true,
      requiresConfirmation: requiresConfirmation,
      // This marker distinguishes an execution reminder from the separate
      // deadline rule. Recurring rules intentionally remain routine rules.
      note: recurring ? 'AI 例行提醒' : '事项提醒',
      createdAt: todo.createdAt,
    );
    notifier.upsertRuleForTarget(rule);
  }

  static DateTime _defaultRoutineAnchor(DateTime now) {
    var anchor = DateTime(now.year, now.month, now.day, 9);
    if (!anchor.isAfter(now)) {
      anchor = anchor.add(const Duration(days: 1));
    }
    return anchor;
  }

  void _save(DiaryEntry entry) {
    Hive.box(DBService.diaryBoxName).put(entry.id, entry.toJson());
  }

  static String _priorityForImportance(String importance) {
    return switch (importance) {
      'important' => 'A',
      'minor' => 'C',
      _ => 'B',
    };
  }
}

class TodoListNotifier extends Notifier<List<TodoTask>> {
  DateTime? _lastRecurringRefreshDay;

  @override
  List<TodoTask> build() {
    final box = Hive.box(DBService.todoBoxName);
    final todos = <TodoTask>[];
    for (final value in box.values) {
      if (value is Map) {
        final todo = TodoTask.fromJson(value);
        if (todo.title.trim().isNotEmpty) todos.add(todo);
      }
    }
    return todos..sort((a, b) => a.priority.compareTo(b.priority));
  }

  TodoTask addTodo(
    String title, {
    String? sourceEntryId,
    String category = 'general',
    String priority = 'B',
    DateTime? opensAt,
    DateTime? scheduledAt,
    int? estimatedMinutes,
    TaskKind taskKind = TaskKind.ordinary,
    DateTime? attentionDate,
    bool attentionConfirmed = true,
    DateTime? deadline,
    List<String> tags = const [],
    bool monthVisibility = true,
  }) {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) throw ArgumentError('title must not be empty');

    // 去重：同一 (sourceEntryId, title) 组合不重复创建
    if (sourceEntryId != null) {
      final existing = state.cast<TodoTask?>().firstWhere(
        (t) => t?.sourceEntryId == sourceEntryId && t?.title == trimmedTitle,
        orElse: () => null,
      );
      if (existing != null) return existing;
    }

    final todo = TodoTask(
      id: const Uuid().v4(),
      title: trimmedTitle,
      createdAt: DateTime.now(),
      priority: priority,
      category: category,
      sourceEntryId: sourceEntryId,
      opensAt: opensAt,
      scheduledAt: scheduledAt,
      estimatedMinutes: estimatedMinutes,
      taskKind: taskKind,
      attentionDate: attentionDate,
      attentionConfirmed: attentionConfirmed,
      deadline: deadline,
      tags: tags,
      monthVisibility: monthVisibility,
    );
    state = [todo, ...state];
    Hive.box(DBService.todoBoxName).put(todo.id, todo.toJson());
    _syncDeadlineReminder(todo);
    return todo;
  }

  void updateTodo(TodoTask updated) {
    final index = state.indexWhere((t) => t.id == updated.id);
    if (index == -1) return;
    state = [...state.sublist(0, index), updated, ...state.sublist(index + 1)];
    Hive.box(DBService.todoBoxName).put(updated.id, updated.toJson());
    _syncDeadlineReminder(updated);
    // A detail edit can change the schedule (or the title/category shown in
    // the notification) without going through rescheduleTodo. Keep the
    // execution reminder attached to the same source of truth.
    _syncScheduledReminder(updated);
  }

  void archiveTodo(String id, {bool archived = true}) {
    final todo = state.cast<TodoTask?>().firstWhere(
      (item) => item?.id == id,
      orElse: () => null,
    );
    if (todo == null) return;
    updateTodo(todo.copyWith(isArchived: archived));
  }

  void rescheduleTodo(String id, DateTime? scheduledAt) {
    final index = state.indexWhere((todo) => todo.id == id);
    if (index == -1) return;
    final todo = state[index];
    todo.scheduledAt = scheduledAt;
    state = [...state.sublist(0, index), todo, ...state.sublist(index + 1)];
    Hive.box(DBService.todoBoxName).put(todo.id, todo.toJson());
    _syncScheduledReminder(todo);
  }

  void rescheduleTodos(Iterable<String> ids, DateTime? scheduledAt) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    final box = Hive.box(DBService.todoBoxName);
    for (final todo in state) {
      if (!idSet.contains(todo.id)) continue;
      todo.scheduledAt = scheduledAt;
      box.put(todo.id, todo.toJson());
    }
    state = [...state];
    for (final todo in state.where((item) => idSet.contains(item.id))) {
      _syncScheduledReminder(todo);
    }
  }

  void toggleTodo(String id) {
    final index = state.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final todo = state[index];
    todo.isCompleted = !todo.isCompleted;
    state = [...state.sublist(0, index), todo, ...state.sublist(index + 1)];
    Hive.box(DBService.todoBoxName).put(todo.id, todo.toJson());
    _syncCompletionReminderLifecycle(todo.id, todo.isCompleted);
  }

  void deleteTodo(String id) {
    final todo = state.cast<TodoTask?>().firstWhere(
      (t) => t?.id == id,
      orElse: () => null,
    );
    if (todo == null) return;

    state = state.where((t) => t.id != id).toList();
    Hive.box(DBService.todoBoxName).delete(id);
    ref.read(reminderRuleProvider.notifier).archiveRulesForTarget('todo', id);

    // 向上级联：如果该待办来自某个 DiaryEntry 且没有其他待办引用它，删除源条目
    _cascadeDeleteSourceEntry(todo);
  }

  /// Removes a generated todo without cascading into its source capture.
  ///
  /// Batch conversion and other undo paths restore the original capture
  /// separately. Using [deleteTodo] there would see that restored source and
  /// immediately delete it again, so keep this inverse operation explicit.
  void removeTodoWithoutCascade(String id) {
    final todo = state.cast<TodoTask?>().firstWhere(
      (item) => item?.id == id,
      orElse: () => null,
    );
    if (todo == null) return;
    state = state.where((item) => item.id != id).toList();
    Hive.box(DBService.todoBoxName).delete(id);
    final rules = ref.read(reminderRuleProvider);
    for (final rule in rules.where(
      (rule) => rule.targetType == 'todo' && rule.targetId == id,
    )) {
      ref.read(reminderRuleProvider.notifier).removeRuleWithoutCascade(rule.id);
    }
  }

  void deleteTodos(Iterable<String> ids) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;

    // 先收集所有待删除的 todo，用于级联判断
    final toDelete = state.where((t) => idSet.contains(t.id)).toList();

    state = state.where((t) => !idSet.contains(t.id)).toList();
    final box = Hive.box(DBService.todoBoxName);
    for (final id in idSet) {
      box.delete(id);
      ref.read(reminderRuleProvider.notifier).archiveRulesForTarget('todo', id);
    }

    // 批量向上级联
    for (final todo in toDelete) {
      _cascadeDeleteSourceEntry(todo);
    }
  }

  /// 如果 [todo] 有 sourceEntryId，且删除后没有其他待办引用同一源条目，
  /// 则级联删除源 DiaryEntry（该条目会进一步级联清理关联的 ReminderRule）。
  void _cascadeDeleteSourceEntry(TodoTask todo) {
    final sourceId = todo.sourceEntryId;
    if (sourceId == null) return;

    // 检查源条目是否还存在（可能已被前序级联操作删除）
    final entries = ref.read(allEntriesProvider);
    final sourceExists = entries.any((e) => e.id == sourceId);
    if (!sourceExists) return;

    // 检查是否还有其他待办引用同一源条目
    final otherTodos = state.where((t) => t.sourceEntryId == sourceId);
    if (otherTodos.isNotEmpty) return;

    ref.read(allEntriesProvider.notifier).deleteEntry(sourceId);
  }

  void setPriority(String id, String priority) {
    final index = state.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final todo = state[index];
    todo.priority = priority;
    state = [...state.sublist(0, index), todo, ...state.sublist(index + 1)];
    Hive.box(DBService.todoBoxName).put(todo.id, todo.toJson());
  }

  void setPriorityForTodos(Iterable<String> ids, String priority) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    final updated = <TodoTask>[];
    final box = Hive.box(DBService.todoBoxName);
    for (final todo in state) {
      if (idSet.contains(todo.id)) {
        todo.priority = priority;
        box.put(todo.id, todo.toJson());
      }
      updated.add(todo);
    }
    state = updated;
  }

  void setCategory(String id, String category) {
    final index = state.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final todo = state[index];
    todo.category = category.trim().isEmpty ? 'general' : category.trim();
    state = [...state.sublist(0, index), todo, ...state.sublist(index + 1)];
    Hive.box(DBService.todoBoxName).put(todo.id, todo.toJson());
  }

  void setCategoryForTodos(Iterable<String> ids, String category) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    final normalized = category.trim().isEmpty ? 'general' : category.trim();
    final updated = <TodoTask>[];
    final box = Hive.box(DBService.todoBoxName);
    for (final todo in state) {
      if (idSet.contains(todo.id)) {
        todo.category = normalized;
        box.put(todo.id, todo.toJson());
      }
      updated.add(todo);
    }
    state = updated;
  }

  void setTagsForTodos(Iterable<String> ids, List<String> tags) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    final updated = <TodoTask>[];
    final box = Hive.box(DBService.todoBoxName);
    for (final todo in state) {
      if (idSet.contains(todo.id)) {
        todo.tags = List<String>.from(tags);
        box.put(todo.id, todo.toJson());
      }
      updated.add(todo);
    }
    state = updated;
  }

  void completeTodos(Iterable<String> ids, {required bool completed}) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    final updated = <TodoTask>[];
    final box = Hive.box(DBService.todoBoxName);
    for (final todo in state) {
      if (idSet.contains(todo.id)) {
        todo.isCompleted = completed;
        box.put(todo.id, todo.toJson());
        _syncCompletionReminderLifecycle(todo.id, completed);
      }
      updated.add(todo);
    }
    state = updated;
  }

  void _syncCompletionReminderLifecycle(String todoId, bool completed) {
    final reminders = ref.read(reminderRuleProvider.notifier);
    if (completed) {
      reminders.archiveActiveOneOffRulesForCompletion('todo', todoId);
    } else {
      reminders.restoreCompletedRulesForTarget('todo', todoId);
    }
  }

  void editTitle(String id, String newTitle) {
    final index = state.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final todo = state[index];
    final updated = TodoTask(
      id: todo.id,
      title: newTitle,
      createdAt: todo.createdAt,
      isCompleted: todo.isCompleted,
      subNotes: todo.subNotes,
      priority: todo.priority,
      category: todo.category,
      inheritCount: todo.inheritCount,
      sourceEntryId: todo.sourceEntryId,
      opensAt: todo.opensAt,
      scheduledAt: todo.scheduledAt,
      estimatedMinutes: todo.estimatedMinutes,
      taskKind: todo.taskKind,
      attentionDate: todo.attentionDate,
      attentionConfirmed: todo.attentionConfirmed,
      deadline: todo.deadline,
      tags: todo.tags,
      monthVisibility: todo.monthVisibility,
      isArchived: todo.isArchived,
    );
    state = [...state.sublist(0, index), updated, ...state.sublist(index + 1)];
    Hive.box(DBService.todoBoxName).put(updated.id, updated.toJson());
    _syncDeadlineReminder(updated);
    _syncScheduledReminder(updated);
  }

  void setDeadline(String id, DateTime? deadline) {
    final index = state.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final todo = state[index];
    final updated = TodoTask(
      id: todo.id,
      title: todo.title,
      createdAt: todo.createdAt,
      isCompleted: todo.isCompleted,
      subNotes: todo.subNotes,
      priority: todo.priority,
      category: todo.category,
      inheritCount: todo.inheritCount,
      sourceEntryId: todo.sourceEntryId,
      opensAt: todo.opensAt,
      scheduledAt: todo.scheduledAt,
      estimatedMinutes: todo.estimatedMinutes,
      taskKind: todo.taskKind,
      attentionDate: todo.attentionDate,
      attentionConfirmed: todo.attentionConfirmed,
      deadline: deadline,
      tags: todo.tags,
      monthVisibility: todo.monthVisibility,
      isArchived: todo.isArchived,
    );
    state = [...state.sublist(0, index), updated, ...state.sublist(index + 1)];
    Hive.box(DBService.todoBoxName).put(updated.id, updated.toJson());
    _syncDeadlineReminder(updated);
    _syncScheduledReminder(updated);
  }

  void setOpensAt(String id, DateTime? opensAt) {
    final index = state.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final todo = state[index];
    final updated = TodoTask(
      id: todo.id,
      title: todo.title,
      createdAt: todo.createdAt,
      isCompleted: todo.isCompleted,
      subNotes: todo.subNotes,
      priority: todo.priority,
      category: todo.category,
      inheritCount: todo.inheritCount,
      sourceEntryId: todo.sourceEntryId,
      opensAt: opensAt,
      scheduledAt: todo.scheduledAt,
      estimatedMinutes: todo.estimatedMinutes,
      taskKind: todo.taskKind,
      attentionDate: todo.attentionDate,
      attentionConfirmed: todo.attentionConfirmed,
      deadline: todo.deadline,
      tags: todo.tags,
      monthVisibility: todo.monthVisibility,
      isArchived: todo.isArchived,
    );
    updateTodo(updated);
  }

  void _syncDeadlineReminder(TodoTask todo) {
    final notifier = ref.read(reminderRuleProvider.notifier);
    final existing = notifier.ruleForTodoDeadline(todo.id);
    if (todo.deadline == null) {
      if (existing != null) {
        notifier.updateRule(existing.copyWith(status: 'archived'));
      }
      return;
    }
    if (existing != null) {
      // Keep a user's disabled/paused choice; only synchronize the deadline
      // metadata that is derived from the task.
      notifier.updateRule(
        existing.copyWith(
          title: todo.title,
          category: todo.category,
          anchorTime: todo.deadline,
          status: existing.status == 'archived' ? 'active' : existing.status,
        ),
      );
      return;
    }
    final execution = notifier.ruleForTodoExecution(todo.id);
    final defaultDeadlineId = 'todo-deadline-${todo.id}';
    // Older builds could reuse the deterministic deadline id for a user's
    // execution reminder. Avoid overwriting that rule while restoring the
    // now-independent deadline reminder.
    final deadlineId = execution?.id == defaultDeadlineId
        ? '$defaultDeadlineId-due'
        : defaultDeadlineId;
    notifier.upsertRuleForTarget(
      ReminderRule(
        id: deadlineId,
        title: todo.title,
        targetType: 'todo',
        targetId: todo.id,
        category: todo.category,
        scheduleType: 'once',
        anchorTime: todo.deadline,
        advanceMinutes: const [60],
        status: 'active',
        note: '作业截止前一小时提醒',
      ),
    );
  }

  void _syncScheduledReminder(TodoTask todo) {
    final notifier = ref.read(reminderRuleProvider.notifier);
    final reminder = notifier.ruleForTodoExecution(todo.id);
    if (reminder == null || reminder.note != '事项提醒') return;
    final anchor = todo.scheduledAt;
    if (anchor == null) {
      // An unscheduled task has no execution trigger, but this is not the
      // same as the student turning reminders off. Keep the rule and its
      // status intact; the next explicit schedule will fill the anchor back
      // in without silently losing the user's reminder preference.
      if (reminder.anchorTime != null) {
        notifier.updateRule(reminder.copyWith(clearAnchorTime: true));
      }
      return;
    }
    if (reminder.anchorTime != anchor) {
      notifier.updateRule(
        reminder.copyWith(
          title: todo.title,
          category: todo.category,
          anchorTime: anchor,
        ),
      );
    }
  }

  void setTags(String id, List<String> tags) {
    final index = state.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final todo = state[index];
    final updated = TodoTask(
      id: todo.id,
      title: todo.title,
      createdAt: todo.createdAt,
      isCompleted: todo.isCompleted,
      subNotes: todo.subNotes,
      priority: todo.priority,
      category: todo.category,
      inheritCount: todo.inheritCount,
      sourceEntryId: todo.sourceEntryId,
      opensAt: todo.opensAt,
      scheduledAt: todo.scheduledAt,
      estimatedMinutes: todo.estimatedMinutes,
      taskKind: todo.taskKind,
      attentionDate: todo.attentionDate,
      attentionConfirmed: todo.attentionConfirmed,
      deadline: todo.deadline,
      tags: tags,
      monthVisibility: todo.monthVisibility,
      isArchived: todo.isArchived,
    );
    state = [...state.sublist(0, index), updated, ...state.sublist(index + 1)];
    Hive.box(DBService.todoBoxName).put(updated.id, updated.toJson());
    _syncDeadlineReminder(updated);
  }

  void setMonthVisibility(String id, bool monthVisibility) {
    final index = state.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final todo = state[index];
    final updated = TodoTask(
      id: todo.id,
      title: todo.title,
      createdAt: todo.createdAt,
      isCompleted: todo.isCompleted,
      subNotes: todo.subNotes,
      priority: todo.priority,
      category: todo.category,
      inheritCount: todo.inheritCount,
      sourceEntryId: todo.sourceEntryId,
      opensAt: todo.opensAt,
      scheduledAt: todo.scheduledAt,
      estimatedMinutes: todo.estimatedMinutes,
      taskKind: todo.taskKind,
      attentionDate: todo.attentionDate,
      attentionConfirmed: todo.attentionConfirmed,
      deadline: todo.deadline,
      tags: todo.tags,
      monthVisibility: monthVisibility,
      isArchived: todo.isArchived,
    );
    state = [...state.sublist(0, index), updated, ...state.sublist(index + 1)];
    Hive.box(DBService.todoBoxName).put(updated.id, updated.toJson());
    _syncDeadlineReminder(updated);
  }

  void refreshRecurringTodos(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    // Resume callbacks can fire many times in one day. A completed daily
    // task must stay completed until the next occurrence, not be reopened
    // merely because the user switched back to ZenDiary.
    if (!RuntimeReminderService.shouldRefreshRecurringTodos(
      _lastRecurringRefreshDay,
      now,
    )) {
      return;
    }
    _lastRecurringRefreshDay = today;
    final rules = ref.read(reminderRuleProvider);

    final resets = RuntimeReminderService.computeRecurringTodoResets(
      state,
      rules,
      now,
    );
    if (resets.isEmpty) return;
    final box = Hive.box(DBService.todoBoxName);
    for (final todo in resets) {
      box.put(todo.id, todo.toJson());
    }
    state = [...state]; // 触发重建
  }
}
