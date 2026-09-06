import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:io';

import '../../core/theme/zen_theme.dart';
import '../../models/diary_entry.dart';
import '../../models/notebook_entry.dart';
import '../../models/pending_action_preview.dart';
import '../../models/recurrence_override.dart';
import '../../models/reminder_rule.dart';
import '../../models/todo_task.dart';
import '../../models/unified_item.dart';
import '../../providers/app_providers.dart';
import '../../providers/notebook_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/reminder_rule_provider.dart';
import '../../services/planner_service.dart';
import '../../services/today_list_service.dart';
import '../../services/today_focus_service.dart';
import '../../services/today_missed_service.dart';
import '../common/task_attention_fields.dart';
import '../todo/todo_create_dialog.dart';
import '../todo/todo_view.dart' show monthlyAnchorAfter;
import '../../services/pending_action_service.dart';
import '../../services/pending_confirmation_service.dart';
import '../../services/recurrence_service.dart';
import '../../services/system_notification_service.dart';
import '../../services/unified_item_service.dart';
import '../draft/draft_view.dart';
import '../reminder/reminder_view.dart';
import '../timeline/day_view.dart';
import '../timeline/month_view.dart';
import '../timeline/timeline_data.dart';
import '../timeline/timeline_shared.dart';
import '../timeline/week_view.dart';
import '../navigation_state.dart';
import 'today_focus_card.dart';
import 'today_missed_section.dart';

class WorkspaceHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const WorkspaceHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ZenTheme.borderSubtle)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: ZenTheme.headingPage),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ZenTheme.labelMedium,
                ),
              ],
            ],
          );
          final actionBlock = Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          );
          // The plan header has several controls; give tablets a second row
          // before the controls become a cramped or overflowing single line.
          if (constraints.maxWidth < 860 && actions.isNotEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleBlock,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: actionBlock),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: titleBlock),
              if (actions.isNotEmpty) actionBlock,
            ],
          );
        },
      ),
    );
  }
}

class TodayView extends ConsumerWidget {
  const TodayView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(currentTimeProvider);
    ref.watch(dayBoundaryProvider);
    final todos = ref.watch(todoListProvider);
    final rules = ref.watch(reminderRuleProvider);
    final entries = ref.watch(timelineEntriesProvider);
    final list = TodayListService.build(todos: todos, rules: rules, now: now);
    final missed = TodayMissedService.fromActionable(
      list.actionable,
      now: now,
    );
    final missedIds = missed.map((todo) => todo.id).toSet();
    final actionable = list.actionable
        .where((todo) => !missedIds.contains(todo.id))
        .toList();
    final focus = TodayFocusService.build(
      now: now,
      events: entries,
      todos: todos,
      rules: rules,
    );
    final summary = buildTimelineDaySummary(
      day: now,
      events: entries,
      todos: todos,
      rules: rules,
      actionPriorityFilter: null,
      floatingTodoPolicy: TimelineFloatingTodoPolicy.exclude,
    );
    final eventsByKey = <String, DiaryEntry>{};
    void addEvent(DiaryEntry event) {
      final key = '${event.id}|${event.sortTime.toIso8601String()}';
      eventsByKey.putIfAbsent(key, () => event);
    }

    for (final event in summary.events) {
      addEvent(event);
    }
    for (final event in entries) {
      if (event.isTimelineVisible &&
          !event.isArchived &&
          event.eventTime != null &&
          event.endTime != null &&
          event.eventTime!.isBefore(calendarDate(now)) &&
          event.endTime!.isAfter(calendarDate(now))) {
        addEvent(event);
      }
    }
    final events = eventsByKey.values.toList()
      ..sort((a, b) => a.sortTime.compareTo(b.sortTime));
    final reminders = buildStandaloneReminderItemsForDay(
      rules: rules,
      day: now,
    );
    final health = Platform.isAndroid
        ? ref.watch(notificationHealthProvider).asData?.value
        : null;
    void settings() =>
        ref.read(navIndexProvider.notifier).setIndex(navIndexSettings);
    Future<void> edit(TodoTask todo) async {
      final updated = await showTaskAttentionDialog(context, todo);
      if (updated != null) {
        ref.read(todoListProvider.notifier).updateTodo(updated);
      }
    }

    Widget tile(TodoTask todo, {bool pending = false}) => _WorkspaceItemTile(
      item: unifiedTodoItem(todo, now),
      hint: TodayListService.reason(todo, now),
      onToggle: pending ? null : () => _toggleTodayTodo(context, ref, todo),
      onTap: () => pending
          ? edit(todo)
          : showUnifiedItemDetails(context, ref, unifiedTodoItem(todo, now)),
      trailing: PopupMenuButton<String>(
        tooltip: '处理事项',
        onSelected: (action) {
          if (action == 'edit') {
            edit(todo);
            return;
          }
          if (action == 'details') {
            showUnifiedItemDetails(context, ref, unifiedTodoItem(todo, now));
            return;
          }
          ref.read(todoListProvider.notifier).archiveTodo(todo.id);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已关闭 · ${todo.title}'),
              action: SnackBarAction(
                label: '撤销',
                onPressed: () => ref
                    .read(todoListProvider.notifier)
                    .archiveTodo(todo.id, archived: false),
              ),
            ),
          );
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('类型与关注日期')),
          if (todo.deadline != null && !now.isBefore(todo.deadline!))
            const PopupMenuItem(value: 'details', child: Text('补做 / 查看详情')),
          const PopupMenuItem(value: 'close', child: Text('关闭事项')),
        ],
      ),
    );
    Widget folded(
      String title,
      List<TodoTask> values, {
      bool pending = false,
    }) => Card(
      child: ExpansionTile(
        title: Text('$title (${values.length})'),
        children: values.map((todo) => tile(todo, pending: pending)).toList(),
      ),
    );
    return Column(
      children: [
        WorkspaceHeader(
          title: '今天',
          subtitle:
              '${DateFormat('M月d日').format(now)} · ${list.outstandingCount} 项未完成',
          actions: [
            TextButton.icon(
              onPressed: () => _createDailyTodo(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('添加待办'),
            ),
            TextButton.icon(
              onPressed: () =>
                  ref.read(navIndexProvider.notifier).setIndex(navIndexInbox),
              icon: const Icon(Icons.inbox_outlined),
              label: const Text('随手记录'),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TodayFocusCard(
                focus: focus,
                onItemTap: (focusItem) =>
                    showUnifiedItemDetails(context, ref, focusItem.item),
              ),
              const SizedBox(height: 12),
              if (missed.isNotEmpty) ...[
                TodayMissedSection(
                  todos: missed,
                  now: now,
                  onTap: (todo) => showUnifiedItemDetails(
                    context,
                    ref,
                    unifiedTodoItem(todo, now),
                  ),
                  onComplete: (todo) =>
                      _toggleTodayTodo(context, ref, todo),
                  onReschedule: (todo) =>
                      _rescheduleMissedTodo(context, ref, todo, now: now),
                  onUnschedule: (todo) =>
                      _unscheduleMissedTodo(context, ref, todo),
                ),
                const SizedBox(height: 12),
              ],
              if (list.pending.isNotEmpty)
                folded('待补充', list.pending, pending: true),
              if (health?.needsAction == true)
                _TodayNotificationHealthBanner(
                  message: health!.actionMessage,
                  onOpenSettings: settings,
                ),
              if (Platform.isWindows &&
                  SystemNotificationService.isPortableWindows &&
                  rules.any(
                    (rule) =>
                        rule.isActive && rule.disturbanceLevel != 'silent',
                  ))
                _TodayPortableReminderBanner(onOpenSettings: settings),
              if (list.expired.isNotEmpty) ...[
                _TodaySection(
                  title: '已截止，待处理',
                  icon: Icons.flag_outlined,
                  emptyText: '',
                  children: list.expired.map(tile).toList(),
                ),
                const SizedBox(height: 12),
              ],
              _TodaySection(
                title: '今天要做',
                icon: Icons.checklist_outlined,
                emptyText: list.expired.isEmpty && missed.isEmpty
                    ? '今天没有待处理事项'
                    : '其余事项已处理',
                children: actionable.map(tile).toList(),
              ),
              const SizedBox(height: 12),
              _TodaySection(
                title: '课程与日程',
                icon: Icons.event_outlined,
                emptyText: '今天没有固定时间安排',
                children: events
                    .map(
                      (event) => _WorkspaceItemTile(
                        item: unifiedEventItem(event),
                        onTap: () => showUnifiedItemDetails(
                          context,
                          ref,
                          unifiedEventItem(event),
                        ),
                      ),
                    )
                    .toList(),
              ),
              if (list.later.isNotEmpty) folded('之后', list.later),
              if (reminders.isNotEmpty)
                _TodayReminderSection(
                  items: reminders,
                  onTap: (item) => showUnifiedItemDetails(context, ref, item),
                ),
              if (list.completed.isNotEmpty) folded('已完成', list.completed),
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> _createDailyTodo(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<TodoCreateResult>(
    context: context,
    builder: (_) => const TodoCreateDialog(),
  );
  if (result == null) return;
  final todo = ref
      .read(todoListProvider.notifier)
      .addTodo(
        result.title,
        taskKind: result.taskKind,
        attentionDate: result.attentionDate,
        opensAt: result.opensAt,
        deadline: result.deadline,
        priority: result.priority,
        tags: result.tags,
      );
  if (result.scheduleType != 'once') {
    final now = DateTime.now();
    ref
        .read(reminderRuleProvider.notifier)
        .upsertRuleForTarget(
          ReminderRule(
            title: todo.title,
            targetType: 'todo',
            targetId: todo.id,
            scheduleType: result.scheduleType,
            scheduleInterval: result.scheduleInterval,
            anchorTime: result.scheduleType == 'monthly'
                ? monthlyAnchorAfter(now, result.scheduleDay ?? now.day)
                : calendarDate(now),
            disturbanceLevel: 'silent',
            advanceMinutes: const [0],
            scheduleDay: result.scheduleDay,
            byDay: result.byDay,
            byMonthDay: result.scheduleDay == null
                ? null
                : [result.scheduleDay!],
            endDate: result.endDate,
          ),
        );
  }
}

class _TodayReminderSection extends StatefulWidget {
  final List<UnifiedItem> items;
  final ValueChanged<UnifiedItem> onTap;
  final String title;

  const _TodayReminderSection({
    required this.items,
    required this.onTap,
    this.title = '今日提醒',
  });

  @override
  State<_TodayReminderSection> createState() => _TodayReminderSectionState();
}

class _TodayReminderSectionState extends State<_TodayReminderSection> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ZenTheme.backgroundMuted,
        borderRadius: BorderRadius.circular(ZenTheme.radiusLg),
      ),
      child: Column(
        children: [
          Material(
            color: ZenTheme.transparent,
            child: ListTile(
              dense: true,
              leading: const Icon(
                Icons.notifications_none_outlined,
                size: 18,
                color: ZenTheme.textMuted,
              ),
              title: Text(widget.title),
              subtitle: Text(
                '${widget.items.length} 项独立提醒',
                style: ZenTheme.labelSmall,
              ),
              trailing: Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: ZenTheme.textMuted,
              ),
              onTap: () => setState(() => expanded = !expanded),
            ),
          ),
          if (expanded)
            ...widget.items.map(
              (item) => _WorkspaceItemTile(
                item: item,
                onTap: () => widget.onTap(item),
              ),
            ),
        ],
      ),
    );
  }
}

class _TodayNotificationHealthBanner extends StatelessWidget {
  final String message;
  final VoidCallback onOpenSettings;

  const _TodayNotificationHealthBanner({
    required this.message,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: ZenTheme.statusOverdueBg,
        borderRadius: BorderRadius.circular(ZenTheme.radiusMd),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_off_outlined,
            size: 18,
            color: ZenTheme.statusOverdue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: ZenTheme.labelSmall.copyWith(color: ZenTheme.textHeading),
            ),
          ),
          TextButton(
            onPressed: onOpenSettings,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }
}

class _TodayPortableReminderBanner extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const _TodayPortableReminderBanner({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: ZenTheme.backgroundMuted,
        borderRadius: BorderRadius.circular(ZenTheme.radiusMd),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.desktop_windows_outlined,
            size: 17,
            color: ZenTheme.textMuted,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '便携版提醒依赖托盘运行 · 关闭窗口会继续提醒，从托盘退出后停止',
              style: ZenTheme.labelSmall,
            ),
          ),
          TextButton(
            onPressed: onOpenSettings,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('查看设置'),
          ),
        ],
      ),
    );
  }
}

class _TodaySection extends StatelessWidget {
  final String title;
  final IconData icon;
  final String emptyText;
  final List<Widget> children;
  const _TodaySection({
    required this.title,
    required this.icon,
    required this.emptyText,
    required this.children,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: ZenTheme.backgroundCard,
      border: Border.all(color: ZenTheme.borderCard),
      borderRadius: BorderRadius.circular(ZenTheme.radiusLg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$title (${children.length})',
                style: ZenTheme.labelMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (children.isEmpty) Text(emptyText, style: ZenTheme.labelMedium),
        ...children,
      ],
    ),
  );
}

class InboxView extends ConsumerStatefulWidget {
  const InboxView({super.key});

  @override
  ConsumerState<InboxView> createState() => _InboxViewState();
}

class _InboxViewState extends ConsumerState<InboxView> {
  final _controller = TextEditingController();
  final Set<String> _selectedDraftIds = <String>{};
  final List<PendingActionPreview> _pendingActions = [];
  final List<AiReminderConfirmation> _pendingReminders = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _pendingActions.addAll(PendingActionService.loadAll());
    final pending = PendingConfirmationService.loadAll();
    final entries = ref.read(allEntriesProvider);
    final rules = ref.read(reminderRuleProvider);
    for (final record in pending) {
      final entryStillExists = entries.any(
        (entry) => entry.id == record.entry.id,
      );
      final sourceTodos = ref
          .read(todoListProvider)
          .where((todo) => todo.sourceEntryId == record.entry.id)
          .toSet();
      final sourceTodoIds = sourceTodos.map((todo) => todo.id).toSet();
      final recurringReminder = const [
        'daily',
        'weekly',
        'every_n_days',
        'monthly',
      ].contains(record.intent.reminder.scheduleType);
      final alreadyConfirmed = rules.any(
        (rule) =>
            rule.isActive &&
            ((rule.targetType == 'event' && rule.targetId == record.entry.id) ||
                (rule.targetType == 'todo' &&
                    record.entry.category == 'todo' &&
                    sourceTodoIds.contains(rule.targetId) &&
                    (recurringReminder
                        ? const [
                            'daily',
                            'weekly',
                            'every_n_days',
                            'monthly',
                          ].contains(rule.scheduleType)
                        : rule.note == '事项提醒'))),
      );
      if (entryStillExists && !alreadyConfirmed) {
        _pendingReminders.add(
          AiReminderConfirmation(entry: record.entry, intent: record.intent),
        );
      } else {
        PendingConfirmationService.clear(record.entry.id);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    _controller.clear();
    final result = await ref.read(allEntriesProvider.notifier).addEntry(text);
    if (!mounted) return;
    final pendingPreview = result.pendingActionPreview;
    setState(() {
      _submitting = false;
      if (pendingPreview != null && !pendingPreview.isEmpty) {
        _pendingActions.removeWhere(_samePendingAction(pendingPreview));
        _pendingActions.add(pendingPreview);
      }
      if (result.reminderConfirmation != null) {
        _pendingReminders.removeWhere(
          (item) => item.entry.id == result.reminderConfirmation!.entry.id,
        );
        _pendingReminders.add(result.reminderConfirmation!);
      }
    });
    final message = switch (result.outcome) {
      DiaryAddOutcome.todoCreated => '已整理到待办',
      DiaryAddOutcome.noteCreated => '已整理到笔记',
      DiaryAddOutcome.aiUpdated => '已自动整理',
      DiaryAddOutcome.reminderNeedsConfirmation => '提醒候选已生成，请确认',
      DiaryAddOutcome.localUpdated => '已用本地规则整理',
      DiaryAddOutcome.localTodoCreated => '已用本地规则整理到待办',
      DiaryAddOutcome.localReminderNeedsConfirmation => '已识别提醒候选，请确认',
      DiaryAddOutcome.pendingActionNeedsConfirmation => '操作预览已生成，请确认',
      DiaryAddOutcome.aiDisabled => '已保存，AI 未启用',
      DiaryAddOutcome.aiNotConfigured => '已保存，AI 配置不完整',
      DiaryAddOutcome.aiFailed => 'AI 暂不可用，已保留在收件箱',
      DiaryAddOutcome.savedOnly => '已保存到收件箱',
    };
    final id = result.entryId;
    final noteId = result.noteId;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: id == null && noteId == null
            ? null
            : SnackBarAction(
                label: '撤销',
                onPressed: () {
                  if (id != null) {
                    ref.read(allEntriesProvider.notifier).deleteEntry(id);
                    PendingConfirmationService.clear(id);
                    if (pendingPreview != null) {
                      PendingActionService.clear(pendingPreview);
                    }
                    if (mounted) {
                      setState(() {
                        _pendingReminders.removeWhere(
                          (item) => item.entry.id == id,
                        );
                        if (pendingPreview != null) {
                          _pendingActions.removeWhere(
                            _samePendingAction(pendingPreview),
                          );
                        }
                      });
                    }
                  } else if (noteId != null) {
                    ref.read(notebookListProvider.notifier).deleteNote(noteId);
                    final sourceEntry = result.sourceEntry;
                    if (sourceEntry != null) {
                      ref
                          .read(allEntriesProvider.notifier)
                          .restoreEntry(sourceEntry);
                    }
                  }
                },
              ),
      ),
    );
  }

  bool _reminderNeedsSchedule(AiReminderConfirmation reminder) {
    if (reminder.entry.category != 'todo') return false;
    if (const [
      'daily',
      'weekly',
      'every_n_days',
      'monthly',
    ].contains(reminder.intent.reminder.scheduleType)) {
      return false;
    }
    if (reminder.intent.scheduledAt != null ||
        reminder.intent.todoDeadline != null) {
      return false;
    }
    final sourceTodos = ref
        .read(todoListProvider)
        .where((todo) => todo.sourceEntryId == reminder.entry.id)
        .toList();
    return sourceTodos.isEmpty ||
        sourceTodos.any(
          (todo) => todo.scheduledAt == null && todo.deadline == null,
        );
  }

  void _confirmReminder(AiReminderConfirmation reminder) {
    final confirmed = ref
        .read(allEntriesProvider.notifier)
        .confirmAiReminder(reminder);
    if (!confirmed) {
      final todo = ref
          .read(todoListProvider)
          .cast<TodoTask?>()
          .firstWhere(
            (value) => value?.sourceEntryId == reminder.entry.id,
            orElse: () => null,
          );
      if (todo != null) {
        showUnifiedItemDetails(
          context,
          ref,
          unifiedTodoItem(todo, DateTime.now()),
        );
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先安排计划时间，再确认这条提醒。')));
      return;
    }
    setState(() {
      _pendingReminders.removeWhere(
        (item) => item.entry.id == reminder.entry.id,
      );
    });
  }

  void _schedulePendingReminderBySuggestion(AiReminderConfirmation reminder) {
    final todo = _todoForPendingReminder(reminder);
    if (todo == null) return;
    final now = DateTime.now();
    final events = _plannerEventsForDay(ref, now);
    final slot = suggestTodoScheduleSlot(
      todo,
      now,
      events: events,
      scheduledTodos: ref.read(todoListProvider),
    );
    final slotIsAvailable = isTodoScheduleSlotAvailable(
      todo,
      now,
      slot,
      events: events,
      scheduledTodos: ref.read(todoListProvider),
    );
    final previous = todo.scheduledAt;
    ref.read(todoListProvider.notifier).rescheduleTodo(todo.id, slot);
    final slotText = isSameDay(slot, now)
        ? '今天 ${DateFormat('HH:mm').format(slot)}'
        : DateFormat('M月d日 HH:mm').format(slot);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          slotIsAvailable
              ? '已按建议安排到 $slotText · 请再确认提醒'
              : '今天没有完整空档，已先安排到 $slotText · 请确认时间后再开启提醒',
        ),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => ref
              .read(todoListProvider.notifier)
              .rescheduleTodo(todo.id, previous),
        ),
      ),
    );
  }

  TodoTask? _todoForPendingReminder(AiReminderConfirmation reminder) {
    return ref
        .read(todoListProvider)
        .cast<TodoTask?>()
        .firstWhere(
          (value) => value?.sourceEntryId == reminder.entry.id,
          orElse: () => null,
        );
  }

  DateTime? _pendingReminderSuggestion(AiReminderConfirmation reminder) {
    final todo = _todoForPendingReminder(reminder);
    if (todo == null) return null;
    final now = DateTime.now();
    return suggestTodoScheduleSlot(
      todo,
      now,
      events: _plannerEventsForDay(ref, now),
      scheduledTodos: ref.read(todoListProvider),
    );
  }

  void _dismissReminder(AiReminderConfirmation reminder) {
    PendingConfirmationService.clear(reminder.entry.id);
    setState(() {
      _pendingReminders.removeWhere(
        (item) => item.entry.id == reminder.entry.id,
      );
    });
  }

  Future<void> _batchConvert(_InboxBatchAction action) async {
    final entries = ref
        .read(allEntriesProvider)
        .where((entry) => _selectedDraftIds.contains(entry.id))
        .toList();
    if (entries.isEmpty) return;

    TimelineEventFormData? eventData;
    if (action == _InboxBatchAction.event) {
      eventData = await showDialog<TimelineEventFormData>(
        context: context,
        builder: (_) => TimelineEventDialog(
          initialContent: entries.first.content,
          initialTime: suggestedTodoScheduleTime(DateTime.now()),
          initialReminder: ReminderFormData.defaults(),
        ),
      );
      if (eventData == null || !mounted) return;
    }

    final todoNotifier = ref.read(todoListProvider.notifier);
    final noteNotifier = ref.read(notebookListProvider.notifier);
    final entryNotifier = ref.read(allEntriesProvider.notifier);
    final createdTodoIds = <String>[];
    final createdNotes = <NotebookEntry>[];
    final previousEntries = <DiaryEntry>[];
    final previousEventRules = <String, ReminderRule?>{};
    final createdEventRuleIds = <String, String?>{};
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final tags = entry.tags;
      switch (action) {
        case _InboxBatchAction.todo:
          final todo = todoNotifier.addTodo(
            entry.content,
            category: tags.isEmpty ? 'general' : tags.first,
            tags: tags,
          );
          createdTodoIds.add(todo.id);
          previousEntries.add(entry);
          entryNotifier.deleteEntry(entry.id);
        case _InboxBatchAction.note:
          final title = entry.content.trim().split('\n').first.trim();
          final note = NotebookEntry(
            title: title.isEmpty ? '无标题' : title,
            content: entry.content,
            tags: tags,
          );
          noteNotifier.addNote(note);
          createdNotes.add(note);
          previousEntries.add(entry);
          entryNotifier.deleteEntry(entry.id);
        case _InboxBatchAction.event:
          final data = eventData!;
          final previousRule = ref
              .read(reminderRuleProvider)
              .cast<ReminderRule?>()
              .firstWhere(
                (value) =>
                    value?.targetType == 'event' && value?.targetId == entry.id,
                orElse: () => null,
              );
          previousEntries.add(entry);
          previousEventRules[entry.id] = previousRule;
          // Keep a predictable 15-minute cadence when several captures are
          // converted at once, so they do not all occupy the same slot.
          final startAt = data.eventTime.add(Duration(minutes: index * 15));
          entryNotifier.convertToEvent(
            entry.id,
            startAt,
            location: data.location,
            durationMinutes: data.durationMinutes,
          );
          final updated = ref
              .read(allEntriesProvider)
              .cast<DiaryEntry?>()
              .firstWhere((value) => value?.id == entry.id, orElse: () => null);
          if (updated != null) {
            syncEventReminderRule(ref, updated, data.reminder);
            final updatedRule = ref
                .read(reminderRuleProvider)
                .cast<ReminderRule?>()
                .firstWhere(
                  (value) =>
                      value?.targetType == 'event' &&
                      value?.targetId == entry.id,
                  orElse: () => null,
                );
            createdEventRuleIds[entry.id] = previousRule == null
                ? updatedRule?.id
                : null;
          }
      }
    }
    final count = entries.length;
    setState(() => _selectedDraftIds.clear());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已批量整理 $count 项'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            // Remove generated targets first. The original captures can then
            // be restored without a delete cascade consuming them again.
            for (final id in createdTodoIds) {
              todoNotifier.removeTodoWithoutCascade(id);
            }
            for (final note in createdNotes) {
              noteNotifier.deleteNote(note.id);
            }
            for (final entry in previousEntries) {
              if (action == _InboxBatchAction.event) {
                entryNotifier.editEntryFull(entry);
                final previousRule = previousEventRules[entry.id];
                final createdRuleId = createdEventRuleIds[entry.id];
                final notifier = ref.read(reminderRuleProvider.notifier);
                if (previousRule != null) {
                  notifier.upsertRuleForTarget(previousRule);
                } else if (createdRuleId != null) {
                  notifier.removeRuleWithoutCascade(createdRuleId);
                }
              } else {
                entryNotifier.restoreEntry(entry);
              }
            }
            if (mounted) {
              setState(() => _selectedDraftIds.clear());
            }
          },
        ),
      ),
    );
  }

  void _applyPendingAction(PendingActionPreview preview) {
    if (preview.isEmpty) return;
    final rules = ref.read(reminderRuleProvider.notifier);
    if (preview.type == PendingActionType.lowLoad) {
      rules.pauseRules(preview.rules.map((rule) => rule.id));
      ref
          .read(lowLoadStatusProvider.notifier)
          .activate(
            LowLoadStatus(
              active: true,
              reason: preview.reason,
              startedAt: DateTime.now(),
              until: preview.rangeEnd,
              affectedCount: preview.affectedCount,
            ),
          );
    } else {
      rules.disableRules(preview.rules.map((rule) => rule.id));
    }
    PendingActionService.clear(preview);
    setState(() => _pendingActions.removeWhere(_samePendingAction(preview)));
  }

  void _dismissPendingAction(PendingActionPreview preview) {
    PendingActionService.clear(preview);
    setState(() => _pendingActions.removeWhere(_samePendingAction(preview)));
  }

  bool Function(PendingActionPreview) _samePendingAction(
    PendingActionPreview expected,
  ) {
    return (actual) =>
        actual.type == expected.type &&
        actual.createdAt == expected.createdAt &&
        actual.reason == expected.reason;
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(allEntriesProvider);
    final drafts = ref.watch(draftEntriesProvider);
    final todos = ref.watch(todoListProvider);
    final notebookNotes = ref.watch(notebookListProvider);
    final recent = buildRecentCaptureItems(
      entries: entries,
      todos: todos,
      notes: notebookNotes,
      now: DateTime.now(),
    );
    String? originalTextFor(UnifiedItem item) {
      final text = switch (item.source) {
        UnifiedItemSource.todo => () {
          final todo = todos.cast<TodoTask?>().firstWhere(
            (value) => value?.id == item.id,
            orElse: () => null,
          );
          final sourceId = todo?.sourceEntryId;
          if (sourceId == null) return null;
          return entries
              .cast<DiaryEntry?>()
              .firstWhere((value) => value?.id == sourceId, orElse: () => null)
              ?.content;
        }(),
        UnifiedItemSource.note =>
          entries
                  .cast<DiaryEntry?>()
                  .firstWhere(
                    (value) =>
                        value?.id == item.id && value?.category == 'note',
                    orElse: () => null,
                  )
                  ?.content ??
              notebookNotes
                  .cast<NotebookEntry?>()
                  .firstWhere(
                    (value) => value?.id == item.id,
                    orElse: () => null,
                  )
                  ?.content,
        UnifiedItemSource.event || UnifiedItemSource.draft =>
          entries
              .cast<DiaryEntry?>()
              .firstWhere((value) => value?.id == item.id, orElse: () => null)
              ?.content,
        UnifiedItemSource.reminder => null,
      };
      final trimmed = text?.trim();
      if (trimmed == null || trimmed.isEmpty || trimmed == item.title.trim()) {
        return null;
      }
      return trimmed;
    }

    final density = ref.watch(uiDensityProvider);
    final pagePadding = switch (density) {
      UiDensity.comfortable => 20.0,
      UiDensity.standard => 16.0,
      UiDensity.compact => 10.0,
    };
    return Column(
      children: [
        WorkspaceHeader(
          title: '收件箱',
          subtitle: drafts.isEmpty ? '捕捉后会自动整理' : '${drafts.length} 条待整理',
          actions: [
            if (_selectedDraftIds.isNotEmpty)
              PopupMenuButton<_InboxBatchAction>(
                tooltip: '批量整理',
                onSelected: _batchConvert,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _InboxBatchAction.todo,
                    child: Text('批量转为待办'),
                  ),
                  PopupMenuItem(
                    value: _InboxBatchAction.event,
                    child: Text('批量转为事件'),
                  ),
                  PopupMenuItem(
                    value: _InboxBatchAction.note,
                    child: Text('批量转为笔记'),
                  ),
                ],
                child: Chip(
                  label: Text('已选 ${_selectedDraftIds.length}'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            IconButton(
              tooltip: '今天',
              onPressed: () =>
                  ref.read(navIndexProvider.notifier).setIndex(navIndexToday),
              icon: const Icon(Icons.wb_sunny_outlined),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              pagePadding,
              pagePadding,
              pagePadding,
              pagePadding + 12,
            ),
            children: [
              _CaptureBox(
                controller: _controller,
                submitting: _submitting,
                onSubmit: _submit,
              ),
              if (_pendingReminders.isNotEmpty) ...[
                const SizedBox(height: 12),
                _InboxSection(
                  title: '待确认提醒',
                  count: _pendingReminders.length,
                  children: _pendingReminders
                      .map(
                        (confirmation) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Builder(
                            builder: (context) {
                              final needsSchedule = _reminderNeedsSchedule(
                                confirmation,
                              );
                              return _PendingReminderCard(
                                confirmation: confirmation,
                                needsSchedule: needsSchedule,
                                scheduleSuggestion: needsSchedule
                                    ? _pendingReminderSuggestion(confirmation)
                                    : null,
                                onScheduleSuggestion: needsSchedule
                                    ? () =>
                                          _schedulePendingReminderBySuggestion(
                                            confirmation,
                                          )
                                    : null,
                                onConfirm: () => _confirmReminder(confirmation),
                                onDismiss: () => _dismissReminder(confirmation),
                              );
                            },
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (_pendingActions.isNotEmpty) ...[
                const SizedBox(height: 12),
                _InboxSection(
                  title: '待确认操作',
                  count: _pendingActions.length,
                  children: _pendingActions
                      .map(
                        (preview) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _PendingActionCard(
                            preview: preview,
                            onConfirm: () => _applyPendingAction(preview),
                            onDismiss: () => _dismissPendingAction(preview),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 18),
              _InboxSection(
                title: '未分类',
                count: drafts.length,
                children: drafts
                    .map(
                      (draft) => _InboxItem(
                        item: unifiedDraftItem(draft),
                        selected: _selectedDraftIds.contains(draft.id),
                        onToggleSelect: (selected) => setState(() {
                          if (selected) {
                            _selectedDraftIds.add(draft.id);
                          } else {
                            _selectedDraftIds.remove(draft.id);
                          }
                        }),
                        onTap: () => showUnifiedItemDetails(
                          context,
                          ref,
                          unifiedDraftItem(draft),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              _InboxSection(
                title: '最近捕捉',
                count: recent.length,
                children: recent
                    .map(
                      (item) => _InboxItem(
                        item: item,
                        originalText: originalTextFor(item),
                        onTap: () => showUnifiedItemDetails(context, ref, item),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CaptureBox extends StatelessWidget {
  final TextEditingController controller;
  final bool submitting;
  final VoidCallback onSubmit;

  const _CaptureBox({
    required this.controller,
    required this.submitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      decoration: BoxDecoration(
        color: ZenTheme.backgroundCard,
        border: Border.all(color: ZenTheme.borderCard),
        borderRadius: BorderRadius.circular(ZenTheme.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: draftInputFocusNode,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              onSubmitted: (_) => onSubmit(),
              decoration: const InputDecoration(
                hintText: '记下想法、任务或安排……',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          IconButton(
            tooltip: '整理',
            onPressed: submitting ? null : onSubmit,
            icon: submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}

class _InboxSection extends StatelessWidget {
  final String title;
  final int count;
  final List<Widget> children;

  const _InboxSection({
    required this.title,
    required this.count,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
          child: Row(
            children: [
              Text(title, style: ZenTheme.headingSection),
              const SizedBox(width: 6),
              Text('$count', style: ZenTheme.labelSmall),
            ],
          ),
        ),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Text('暂无内容', style: ZenTheme.emptyStateSub),
          )
        else
          ...children,
      ],
    );
  }
}

class _InboxItem extends StatelessWidget {
  final UnifiedItem item;
  final String? originalText;
  final VoidCallback onTap;
  final bool selected;
  final ValueChanged<bool>? onToggleSelect;

  const _InboxItem({
    required this.item,
    this.originalText,
    required this.onTap,
    this.selected = false,
    this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      child: ListTile(
        dense: true,
        onTap: onTap,
        leading: onToggleSelect == null
            ? Icon(
                _sourceIcon(item.source),
                size: 18,
                color: ZenTheme.textMuted,
              )
            : Checkbox(
                value: selected,
                onChanged: (value) => onToggleSelect!(value ?? false),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
        title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_sourceLabel(item.source), style: ZenTheme.labelSmall),
            if (originalText != null)
              Text(
                '原文：$originalText',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ZenTheme.labelSmall.copyWith(
                  color: ZenTheme.textCompleted,
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }
}

enum _InboxBatchAction { todo, event, note }

class _PendingReminderCard extends StatelessWidget {
  final AiReminderConfirmation confirmation;
  final bool needsSchedule;
  final DateTime? scheduleSuggestion;
  final VoidCallback? onScheduleSuggestion;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  const _PendingReminderCard({
    required this.confirmation,
    this.needsSchedule = false,
    this.scheduleSuggestion,
    this.onScheduleSuggestion,
    required this.onConfirm,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final intent = confirmation.intent;
    final scheduleLabel = switch (intent.reminder.scheduleType) {
      'daily' => '每天',
      'weekly' => '每周',
      'every_n_days' => '每 ${intent.reminder.scheduleInterval} 天',
      'monthly' => '每月',
      _ => '一次',
    };
    final detail = [
      confirmation.entry.aiSummary ?? confirmation.entry.content,
      if (needsSchedule) '还没有具体计划时间',
      if (scheduleSuggestion != null)
        '建议 ${isSameDay(scheduleSuggestion!, DateTime.now()) ? '今天 ' : ''}${DateFormat('M月d日 HH:mm').format(scheduleSuggestion!)}',
      scheduleLabel,
      intent.reminder.advanceMinutes.isEmpty
          ? '到点'
          : intent.reminder.advanceMinutes
                .map((m) => m == 0 ? '到点' : '提前$m分钟')
                .join('、'),
    ].join(' · ');
    return _PendingCard(
      icon: Icons.notifications_active_outlined,
      title: needsSchedule
          ? '待补时间的待办提醒'
          : confirmation.entry.category == 'todo'
          ? '确认待办提醒'
          : '确认提醒',
      detail: detail,
      onConfirm: onConfirm,
      onDismiss: onDismiss,
      onSecondary: onScheduleSuggestion,
      secondaryLabel: '按建议安排',
      confirmLabel: needsSchedule ? '先安排时间' : '确认',
    );
  }
}

class _PendingActionCard extends StatelessWidget {
  final PendingActionPreview preview;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  const _PendingActionCard({
    required this.preview,
    required this.onConfirm,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return _PendingCard(
      icon: Icons.auto_awesome_outlined,
      title: preview.title,
      detail: '${preview.reason} · 将影响 ${preview.affectedCount} 项',
      onConfirm: onConfirm,
      onDismiss: onDismiss,
    );
  }
}

class _PendingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;
  final VoidCallback? onSecondary;
  final String? secondaryLabel;
  final String confirmLabel;

  const _PendingCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onConfirm,
    required this.onDismiss,
    this.onSecondary,
    this.secondaryLabel,
    this.confirmLabel = '确认',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
      decoration: BoxDecoration(
        color: ZenTheme.statusUpcomingBg,
        borderRadius: BorderRadius.circular(ZenTheme.radiusLg),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 2,
            children: [
              TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text('忽略'),
              ),
              if (onSecondary != null)
                TextButton(
                  onPressed: onSecondary,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: Text(secondaryLabel ?? '更多'),
                ),
              FilledButton(
                onPressed: onConfirm,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text(confirmLabel),
              ),
            ],
          );
          final detailBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: ZenTheme.headingSection),
              const SizedBox(height: 3),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ZenTheme.labelSmall,
              ),
            ],
          );
          final summary = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: ZenTheme.statusUpcoming),
              const SizedBox(width: 10),
              Expanded(child: detailBlock),
            ],
          );
          // Keep the explanatory text readable on phones; actions get their
          // own line instead of forcing a tiny or overflowing detail column.
          if (constraints.maxWidth < 500) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summary,
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: summary),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class PlanView extends ConsumerStatefulWidget {
  const PlanView({super.key});

  @override
  ConsumerState<PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends ConsumerState<PlanView> {
  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(timelineViewModeProvider);
    final day = ref.watch(selectedDayProvider);
    final entries = ref.watch(timelineEntriesProvider);
    final todos = ref.watch(todoListProvider);
    final rules = ref.watch(reminderRuleProvider);
    final standaloneReminderItems = mode == TimelineViewMode.day
        ? buildStandaloneReminderItemsForDay(rules: rules, day: day)
        : const <UnifiedItem>[];
    final periodStart = switch (mode) {
      TimelineViewMode.day => DateTime(day.year, day.month, day.day),
      TimelineViewMode.week => startOfWeek(day),
      TimelineViewMode.month => DateTime(day.year, day.month),
    };
    final periodEnd = switch (mode) {
      TimelineViewMode.day => periodStart.add(const Duration(days: 1)),
      TimelineViewMode.week => periodStart.add(const Duration(days: 7)),
      TimelineViewMode.month => DateTime(day.year, day.month + 1),
    };
    // Include events that started before the visible range but continue into
    // it (for example a late-night study block crossing midnight), and expand
    // repeating rules into the visible range so two recurring classes that
    // overlap on a particular day also get a warning.
    final conflicts = findEventConflicts(
      eventsOverlappingPeriod(
        _eventsForPlanPeriod(entries, rules, periodStart, periodEnd),
        periodStart,
        periodEnd,
      ),
    );
    final unscheduled = todos
        .where(
          (todo) =>
              !todo.isCompleted &&
              !todo.isArchived &&
              todo.scheduledAt == null &&
              !isRoutineTodo(todo.id, rules),
        )
        .toList();
    final batchEvents = _eventsInBatchRange(entries, rules, mode, day);
    final period = switch (mode) {
      TimelineViewMode.day => DateFormat('M月d日').format(day),
      TimelineViewMode.week =>
        '${DateFormat('M月d日').format(startOfWeek(day))} – ${DateFormat('M月d日').format(startOfWeek(day).add(const Duration(days: 6)))}',
      TimelineViewMode.month => DateFormat('yyyy年M月').format(day),
    };
    return Column(
      children: [
        WorkspaceHeader(
          title: '计划',
          subtitle: conflicts.isEmpty
              ? '$period · 安排时间，也给自己留出余量'
              : '$period · ${conflicts.length} 个时间冲突',
          actions: [
            IconButton(
              tooltip: '上一页',
              onPressed: () => _move(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: '今天',
              onPressed: () =>
                  ref.read(selectedDayProvider.notifier).set(DateTime.now()),
              icon: const Icon(Icons.today_outlined),
            ),
            IconButton(
              tooltip: '下一页',
              onPressed: () => _move(1),
              icon: const Icon(Icons.chevron_right),
            ),
            IconButton(
              tooltip: '批量改期',
              onPressed: batchEvents.isEmpty
                  ? null
                  : () => _showBatchReschedulePicker(context, batchEvents),
              icon: const Icon(Icons.event_available_outlined),
            ),
            SegmentedButton<TimelineViewMode>(
              segments: const [
                ButtonSegment(value: TimelineViewMode.day, label: Text('日')),
                ButtonSegment(value: TimelineViewMode.week, label: Text('周')),
                ButtonSegment(value: TimelineViewMode.month, label: Text('月')),
              ],
              selected: {mode},
              onSelectionChanged: (value) =>
                  ref.read(timelineViewModeProvider.notifier).set(value.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: ZenTheme.accentMatcha,
                selectedForegroundColor: ZenTheme.contentOnAccent,
              ),
            ),
          ],
        ),
        if (conflicts.isNotEmpty) _ConflictBanner(count: conflicts.length),
        if (unscheduled.isNotEmpty)
          _UnscheduledStrip(
            todos: unscheduled,
            anchorDay: day,
            events: _plannerEventsForDay(ref, day),
            scheduledTodos: todos,
            onSchedule: (todo, date) {
              final safeDate = respectTodoOpening(todo, date);
              final previous = todo.scheduledAt;
              ref
                  .read(todoListProvider.notifier)
                  .rescheduleTodo(todo.id, safeDate);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    safeDate == date
                        ? '待办已安排'
                        : '待办尚未开放，已安排到 ${DateFormat('M月d日 HH:mm').format(safeDate)}',
                  ),
                  action: SnackBarAction(
                    label: '撤销',
                    onPressed: () => ref
                        .read(todoListProvider.notifier)
                        .rescheduleTodo(todo.id, previous),
                  ),
                ),
              );
            },
            onScheduleMany: (selected, date) {
              final previous = {
                for (final todo in selected) todo.id: todo.scheduledAt,
              };
              // A multi-select drop on a future day is still an execution
              // plan, not a date-only bucket. Use each task's estimate and
              // the day's events so the batch does not stack at 09:00.
              final slots = suggestTodoBatchSlots(
                selected,
                date,
                DateTime.now(),
                events: _plannerEventsForDay(ref, date),
                scheduledTodos: todos,
              );
              for (final todo in selected) {
                final slot = slots[todo.id];
                if (slot == null) continue;
                ref
                    .read(todoListProvider.notifier)
                    .rescheduleTodo(todo.id, respectTodoOpening(todo, slot));
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已错开安排 ${selected.length} 项待办'),
                  action: SnackBarAction(
                    label: '撤销',
                    onPressed: () {
                      for (final entry in previous.entries) {
                        ref
                            .read(todoListProvider.notifier)
                            .rescheduleTodo(entry.key, entry.value);
                      }
                    },
                  ),
                ),
              );
            },
          ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _planTimelineContent(
              context,
              ref,
              mode,
              day,
              standaloneReminderItems,
            ),
          ),
        ),
      ],
    );
  }

  Widget _planTimelineContent(
    BuildContext context,
    WidgetRef ref,
    TimelineViewMode mode,
    DateTime day,
    List<UnifiedItem> standaloneReminderItems,
  ) {
    final timeline = switch (mode) {
      TimelineViewMode.day => DayView(
        key: const ValueKey('plan-day'),
        day: day,
        onReschedule: (entry, startAt) => _rescheduleEvent(entry, startAt),
        onItemTap: (item) => showUnifiedItemDetails(context, ref, item),
      ),
      TimelineViewMode.week => WeekView(
        key: const ValueKey('plan-week'),
        weekStart: startOfWeek(day),
        focusDay: day,
        onItemTap: (item) => showUnifiedItemDetails(context, ref, item),
        onScheduleTodo: (todo, targetDay) =>
            _scheduleTodoFromWeekCard(context, ref, todo, targetDay),
      ),
      TimelineViewMode.month => MonthView(
        key: const ValueKey('plan-month'),
        monthStart: DateTime(day.year, day.month),
        onItemTap: (item) => showUnifiedItemDetails(context, ref, item),
      ),
    };
    if (mode != TimelineViewMode.day || standaloneReminderItems.isEmpty) {
      return timeline;
    }
    return Column(
      key: const ValueKey('plan-day-with-reminders'),
      children: [
        Expanded(child: timeline),
        _TodayReminderSection(
          title: '当日提醒',
          items: standaloneReminderItems,
          onTap: (item) => showUnifiedItemDetails(context, ref, item),
        ),
      ],
    );
  }

  void _move(int direction) {
    final mode = ref.read(timelineViewModeProvider);
    final day = ref.read(selectedDayProvider);
    final next = switch (mode) {
      TimelineViewMode.day => day.add(Duration(days: direction)),
      TimelineViewMode.week => day.add(Duration(days: direction * 7)),
      TimelineViewMode.month => DateTime(day.year, day.month + direction, 1),
    };
    ref.read(selectedDayProvider.notifier).set(next);
  }

  List<DiaryEntry> _eventsInBatchRange(
    List<DiaryEntry> events,
    List<ReminderRule> rules,
    TimelineViewMode mode,
    DateTime selectedDay,
  ) {
    final start = switch (mode) {
      TimelineViewMode.day => DateTime(
        selectedDay.year,
        selectedDay.month,
        selectedDay.day,
      ),
      TimelineViewMode.week => startOfWeek(selectedDay),
      TimelineViewMode.month => DateTime(selectedDay.year, selectedDay.month),
    };
    final end = switch (mode) {
      TimelineViewMode.day => start.add(const Duration(days: 1)),
      TimelineViewMode.week => start.add(const Duration(days: 7)),
      TimelineViewMode.month => DateTime(start.year, start.month + 1),
    };
    return _eventsForPlanPeriod(events, rules, start, end);
  }

  Future<void> _showBatchReschedulePicker(
    BuildContext context,
    List<DiaryEntry> events,
  ) async {
    final selectedIds = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        // A recurring source can occur more than once in the visible range,
        // so selection must identify the occurrence, not only the source ID.
        final selected = <String>{};
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final height = MediaQuery.sizeOf(context).height * .78;
            return SafeArea(
              child: SizedBox(
                height: height,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('批量改期', style: ZenTheme.headingZen),
                      const SizedBox(height: 4),
                      Text(
                        '选择事件后移动到同一天，原来的时刻和时长会保留；重复课程只改对应课次。',
                        style: ZenTheme.emptyStateSub,
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.separated(
                          itemCount: events.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final event = events[index];
                            final start = event.eventTime!;
                            final end = event.endTime;
                            final time = end == null
                                ? DateFormat('M月d日 HH:mm').format(start)
                                : '${DateFormat('M月d日 HH:mm').format(start)}–${DateFormat('HH:mm').format(end)}';
                            final eventKey = _batchEventKey(event);
                            return CheckboxListTile(
                              value: selected.contains(eventKey),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                compactItemTitle(event.content),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(time),
                              onChanged: (value) => setSheetState(() {
                                if (value == true) {
                                  selected.add(eventKey);
                                } else {
                                  selected.remove(eventKey);
                                }
                              }),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            '已选择 ${selected.length} 项',
                            style: ZenTheme.labelMedium,
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: selected.isEmpty
                                ? null
                                : () => Navigator.pop(
                                    sheetContext,
                                    Set<String>.from(selected),
                                  ),
                            child: const Text('选择日期'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (selectedIds == null || selectedIds.isEmpty || !context.mounted) return;
    final selectedEvents = events
        .where((event) => selectedIds.contains(_batchEventKey(event)))
        .toList();
    if (selectedEvents.isEmpty) return;
    final currentDay = ref.read(selectedDayProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: currentDay,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
      helpText: '把选中事件移动到哪一天？',
      cancelText: '取消',
      confirmText: '移动',
    );
    if (picked == null || !context.mounted) return;
    _applyBatchReschedule(
      context,
      selectedEvents,
      DateTime(picked.year, picked.month, picked.day),
    );
  }

  void _applyBatchReschedule(
    BuildContext context,
    List<DiaryEntry> selected,
    DateTime targetDay,
  ) {
    final ruleNotifier = ref.read(reminderRuleProvider.notifier);
    final previousEntries = <String, DiaryEntry>{};
    final previousRules = <String, ReminderRule?>{};
    final previousOverrides = <String, RecurrenceOverride?>{};
    final recurringDates = <String, DateTime>{};
    final recurringRuleIds = <String, String>{};
    var changed = 0;

    for (final event in selected) {
      final start = event.eventTime;
      if (start == null) continue;
      final eventKey = _batchEventKey(event);
      final movedStart = DateTime(
        targetDay.year,
        targetDay.month,
        targetDay.day,
        start.hour,
        start.minute,
        start.second,
      );
      final rule = ruleNotifier.ruleForTarget('event', event.id);
      final recurring =
          rule != null &&
          rule.isActive &&
          rule.scheduleType != 'once' &&
          rule.scheduleType != 'custom';
      if (recurring) {
        final originalDate =
            RecurrenceService.originalDateForOccurrence(rule, start) ??
            DateTime(start.year, start.month, start.day);
        RecurrenceOverride? previous;
        for (final override in rule.overrides) {
          if (isSameDay(override.originalDate, originalDate)) {
            previous = override;
            break;
          }
        }
        recurringDates[eventKey] = originalDate;
        recurringRuleIds[eventKey] = rule.id;
        previousOverrides[eventKey] = previous;
        ruleNotifier.updateOccurrence(
          rule.id,
          originalDate,
          newTime: movedStart,
          newDurationMinutes: event.durationMinutes,
          clearNewDurationMinutes: event.durationMinutes == null,
        );
      } else {
        previousEntries[eventKey] = event;
        previousRules[eventKey] = rule;
        ref
            .read(allEntriesProvider.notifier)
            .rescheduleEvent(
              event.id,
              movedStart,
              durationMinutes: event.durationMinutes,
            );
      }
      changed++;
    }

    if (changed == 0) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '已将 $changed 个事件移到 ${DateFormat('M月d日').format(targetDay)}（保留原时间）',
        ),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            final diaryNotifier = ref.read(allEntriesProvider.notifier);
            for (final entry in previousEntries.entries) {
              diaryNotifier.editEntryFull(entry.value);
              final previousRule = previousRules[entry.key];
              if (previousRule != null) {
                ruleNotifier.upsertRuleForTarget(previousRule);
              }
            }
            for (final entry in recurringDates.entries) {
              final previous = previousOverrides[entry.key];
              final ruleId = recurringRuleIds[entry.key];
              if (ruleId == null) continue;
              final rule = ref
                  .read(reminderRuleProvider)
                  .cast<ReminderRule?>()
                  .firstWhere(
                    (value) => value?.id == ruleId,
                    orElse: () => null,
                  );
              if (rule == null) continue;
              if (previous == null) {
                ruleNotifier.removeOverride(rule.id, entry.value);
              } else {
                ruleNotifier.upsertOverride(rule.id, previous);
              }
            }
          },
        ),
      ),
    );
  }

  String _batchEventKey(DiaryEntry event) =>
      '${event.id}|${event.sortTime.toIso8601String()}';

  void _scheduleTodoFromWeekCard(
    BuildContext context,
    WidgetRef ref,
    TodoTask todo,
    DateTime targetDay,
  ) {
    final now = DateTime.now();
    final target = DateTime(targetDay.year, targetDay.month, targetDay.day);
    // Treat a week-card drop as a real execution plan on every day, not as a
    // date-only bucket. The batch slot finder respects estimates, opening
    // times, events and already scheduled todos, so future-day drops do not
    // silently pile several tasks onto 09:00.
    final requested =
        suggestTodoBatchSlots(
          [todo],
          target,
          now,
          events: _plannerEventsForDay(ref, target),
          scheduledTodos: ref.read(todoListProvider),
        )[todo.id] ??
        suggestedTodoScheduleForDay(target, now);
    _scheduleTodoAt(
      context,
      ref,
      todo,
      requested,
      message:
          '已安排到 ${DateFormat('M月d日 HH:mm').format(requested)} · ${todo.title}',
    );
  }

  List<DiaryEntry> _eventsForPlanPeriod(
    List<DiaryEntry> entries,
    List<ReminderRule> rules,
    DateTime periodStart,
    DateTime periodEnd,
  ) {
    final result = <String, DiaryEntry>{};
    void add(DiaryEntry event) {
      if (event.eventTime == null) return;
      final key =
          '${event.id}|${event.sortTime.toIso8601String()}|${event.endTime?.toIso8601String()}';
      result[key] = event;
    }

    // Source events can begin before the first visible day but still occupy
    // part of the range (cross-midnight classes are the common case).
    for (final event in eventsOverlappingPeriod(
      entries,
      periodStart,
      periodEnd,
    )) {
      add(event);
    }

    // Build each day through the same projection/deduplication path used by
    // the day and week views. This keeps conflict detection consistent with
    // what the student actually sees on the planner.
    for (
      var cursor = DateTime(
        periodStart.year,
        periodStart.month,
        periodStart.day,
      );
      cursor.isBefore(periodEnd);
      cursor = cursor.add(const Duration(days: 1))
    ) {
      final summary = buildTimelineDaySummary(
        day: cursor,
        events: entries,
        todos: const [],
        floatingTodoPolicy: TimelineFloatingTodoPolicy.exclude,
        rules: rules,
      );
      for (final event in summary.events) {
        add(event);
      }
    }
    return result.values.toList();
  }

  void _rescheduleEvent(DiaryEntry entry, DateTime startAt) {
    final rule = ref
        .read(reminderRuleProvider.notifier)
        .ruleForTarget('event', entry.id);
    // Every occurrence of a repeating rule is an instance, including the
    // original anchor day. Moving that first row must create a one-off
    // override; changing only the source entry would leave future classes at
    // the old time while making the rule and the displayed source disagree.
    final isProjection =
        rule != null &&
        rule.isActive &&
        rule.scheduleType != 'once' &&
        rule.scheduleType != 'custom';
    if (isProjection) {
      final originalDate =
          RecurrenceService.originalDateForOccurrence(rule, entry.sortTime) ??
          entry.sortTime;
      RecurrenceOverride? previous;
      for (final item in rule.overrides) {
        if (isSameDay(item.originalDate, originalDate)) {
          previous = item;
          break;
        }
      }
      ref
          .read(reminderRuleProvider.notifier)
          .updateOccurrence(
            rule.id,
            originalDate,
            newTime: startAt,
            newDurationMinutes: entry.durationMinutes,
            clearNewDurationMinutes: entry.durationMinutes == null,
          );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('重复实例已调整'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () {
              if (previous == null) {
                ref
                    .read(reminderRuleProvider.notifier)
                    .removeOverride(rule.id, originalDate);
              } else {
                ref
                    .read(reminderRuleProvider.notifier)
                    .upsertOverride(rule.id, previous);
              }
            },
          ),
        ),
      );
    } else {
      final previousStart = entry.eventTime;
      ref
          .read(allEntriesProvider.notifier)
          .rescheduleEvent(
            entry.id,
            startAt,
            durationMinutes: entry.durationMinutes,
          );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('事件已调整'),
          action: previousStart == null
              ? null
              : SnackBarAction(
                  label: '撤销',
                  onPressed: () => ref
                      .read(allEntriesProvider.notifier)
                      .rescheduleEvent(
                        entry.id,
                        previousStart,
                        durationMinutes: entry.durationMinutes,
                      ),
                ),
        ),
      );
    }
  }
}

class _ConflictBanner extends StatelessWidget {
  final int count;

  const _ConflictBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: ZenTheme.statusOverdueBg,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_outlined,
            size: 16,
            color: ZenTheme.statusOverdue,
          ),
          const SizedBox(width: 8),
          Text(
            '$count 个事件时间重叠；可以继续保存，稍后再调整。',
            style: ZenTheme.labelMedium.copyWith(color: ZenTheme.statusOverdue),
          ),
        ],
      ),
    );
  }
}

class _UnscheduledStrip extends StatefulWidget {
  final List<TodoTask> todos;
  final DateTime anchorDay;
  final List<DiaryEntry> events;
  final List<TodoTask> scheduledTodos;
  final void Function(TodoTask todo, DateTime date) onSchedule;
  final void Function(List<TodoTask> todos, DateTime date)? onScheduleMany;

  const _UnscheduledStrip({
    required this.todos,
    required this.anchorDay,
    this.events = const [],
    this.scheduledTodos = const [],
    required this.onSchedule,
    this.onScheduleMany,
  });

  @override
  State<_UnscheduledStrip> createState() => _UnscheduledStripState();
}

class _UnscheduledStripState extends State<_UnscheduledStrip> {
  final Set<String> _selected = {};
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final visibleTodos = _showAll
        ? widget.todos
        : widget.todos.take(8).toList();
    // Quick targets follow the currently selected day/week instead of the
    // wall-clock week. Otherwise opening a future week and dropping a task
    // on “今” would silently schedule it back into the current week.
    final anchor = DateTime(
      widget.anchorDay.year,
      widget.anchorDay.month,
      widget.anchorDay.day,
    );
    final quickDays = List.generate(
      3,
      (index) => anchor.add(Duration(days: index)),
    );
    final today = DateTime.now();
    // Phone and tablet layouts keep capture chips wrapped so the planner does
    // not hide the primary scheduling targets behind a horizontal scroller.
    if (MediaQuery.sizeOf(context).width < 980) {
      return _buildCompact(context, quickDays: quickDays, today: today);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: ZenTheme.backgroundMuted,
      child: Row(
        children: [
          const Icon(Icons.drag_indicator, size: 16, color: ZenTheme.textMuted),
          const SizedBox(width: 6),
          Text(
            _selected.isEmpty ? '待安排' : '已选 ${_selected.length} 项',
            style: ZenTheme.labelMedium,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: visibleTodos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) => _todoChip(visibleTodos[index]),
              ),
            ),
          ),
          if (widget.todos.length > 8)
            TextButton(
              onPressed: () => setState(() => _showAll = !_showAll),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(_showAll ? '收起' : '还有 ${widget.todos.length - 8} 项'),
            ),
          for (var index = 0; index < quickDays.length; index++) ...[
            const SizedBox(width: 4),
            DragTarget<TodoTask>(
              onAcceptWithDetails: (details) {
                _scheduleQuick(index, dragged: details.data);
              },
              builder: (context, candidate, rejected) => _quickTargetChip(
                index,
                quickDays[index],
                today,
                candidate.isNotEmpty,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompact(
    BuildContext context, {
    required List<DateTime> quickDays,
    required DateTime today,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: ZenTheme.backgroundMuted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.drag_indicator,
                size: 16,
                color: ZenTheme.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                _selected.isEmpty ? '待安排' : '已选 ${_selected.length} 项',
                style: ZenTheme.labelMedium,
              ),
              const Spacer(),
              if (_selected.isNotEmpty)
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('清除选择'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final visibleTodos = _showAll
                  ? widget.todos
                  : widget.todos.take(8).toList();
              final chips = Wrap(
                spacing: 6,
                runSpacing: 6,
                children: visibleTodos.map(_todoChip).toList(),
              );
              if (!_showAll) return chips;
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 116),
                child: SingleChildScrollView(child: chips),
              );
            },
          ),
          if (widget.todos.length > 8)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _showAll = !_showAll),
                icon: Icon(
                  _showAll ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                ),
                label: Text(
                  _showAll ? '收起待安排' : '显示其余 ${widget.todos.length - 8} 项',
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('安排到', style: ZenTheme.labelSmall),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var index = 0; index < quickDays.length; index++)
                      DragTarget<TodoTask>(
                        onAcceptWithDetails: (details) =>
                            _scheduleQuick(index, dragged: details.data),
                        builder: (context, candidate, rejected) =>
                            _quickTargetChip(
                              index,
                              quickDays[index],
                              today,
                              candidate.isNotEmpty,
                            ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _todoChip(TodoTask todo) {
    return Draggable<TodoTask>(
      data: todo,
      feedback: Material(
        color: ZenTheme.transparent,
        child: Chip(label: Text(todo.title)),
      ),
      child: FilterChip(
        label: Text(todo.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        selected: _selected.contains(todo.id),
        onSelected: (selected) => setState(() {
          if (selected) {
            _selected.add(todo.id);
          } else {
            _selected.remove(todo.id);
          }
        }),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _quickTargetChip(
    int index,
    DateTime day,
    DateTime today,
    bool highlighted,
  ) {
    return Material(
      color: ZenTheme.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(ZenTheme.radiusSm),
        onTap: () => _scheduleQuick(index),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: highlighted
                ? ZenTheme.interactivePressed
                : ZenTheme.backgroundCard,
            borderRadius: BorderRadius.circular(ZenTheme.radiusSm),
            border: Border.all(color: ZenTheme.borderCard),
          ),
          child: Text(
            _quickTargetLabel(day, today),
            style: ZenTheme.labelSmall,
          ),
        ),
      ),
    );
  }

  void _scheduleQuick(int index, {TodoTask? dragged}) {
    final selectedTodos = widget.todos
        .where((todo) => _selected.contains(todo.id))
        .toList();
    final targetTodos = selectedTodos.isNotEmpty
        ? selectedTodos
        : (dragged == null ? const <TodoTask>[] : [dragged]);
    if (targetTodos.isEmpty) return;
    final quickDays = List.generate(
      3,
      (offset) => DateTime(
        widget.anchorDay.year,
        widget.anchorDay.month,
        widget.anchorDay.day + offset,
      ),
    );
    final targetDay = quickDays[index];
    final now = DateTime.now();
    final isToday = isSameDay(targetDay, now);
    // “今天” means a real execution slot, not merely today's date. Place
    // selected tasks one after another so a batch action does not create a
    // new pile-up at the same minute or collide with a class.
    if (isToday) {
      final occupied = [...widget.scheduledTodos];
      for (final todo in targetTodos) {
        if (!isTodoOpenAt(todo, now)) {
          final suggestion = suggestTodoSchedule(todo, now);
          final openingSlot = suggestion?.scheduledAt ?? todo.opensAt;
          if (openingSlot != null) {
            widget.onSchedule(todo, openingSlot);
            occupied.add(todo.copyWith(scheduledAt: openingSlot));
            continue;
          }
        }
        final date = suggestTodoScheduleSlot(
          todo,
          now,
          events: widget.events,
          scheduledTodos: occupied,
        );
        widget.onSchedule(todo, date);
        occupied.add(todo.copyWith(scheduledAt: date));
      }
    } else if (targetTodos.length > 1 && widget.onScheduleMany != null) {
      final date = suggestedTodoScheduleForDay(targetDay, now);
      widget.onScheduleMany!(targetTodos, date);
    } else {
      final date = suggestedTodoScheduleForDay(targetDay, now);
      for (final todo in targetTodos) {
        widget.onSchedule(todo, date);
      }
    }
    if (mounted) setState(() => _selected.clear());
  }

  static String _quickTargetLabel(DateTime day, DateTime today) {
    final normalizedToday = DateTime(today.year, today.month, today.day);
    if (isSameDay(day, normalizedToday)) return '今天';
    if (isSameDay(day, normalizedToday.add(const Duration(days: 1)))) {
      return '明天';
    }
    if (day.year == normalizedToday.year) {
      return '${day.month}/${day.day}';
    }
    return '${day.year}/${day.month}/${day.day}';
  }
}

Future<void> showUnifiedItemDetails(
  BuildContext context,
  WidgetRef ref,
  UnifiedItem item, {
  bool fromNotification = false,
  String? notificationPayload,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // A todo detail can contain completion, planning, deadline, reminder,
    // tags, archive and delete actions. Keep the drawer usable on short phone
    // screens instead of letting the action stack overflow vertically.
    builder: (_) => SingleChildScrollView(
      child: _UnifiedItemDetails(
        item: item,
        fromNotification: fromNotification,
        notificationPayload: notificationPayload,
      ),
    ),
  );
}

class _TodoContentDialog extends StatefulWidget {
  final TodoTask todo;

  const _TodoContentDialog({required this.todo});

  @override
  State<_TodoContentDialog> createState() => _TodoContentDialogState();
}

class _TodoContentDialogState extends State<_TodoContentDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.todo.title);
    _notesController = TextEditingController(
      text: widget.todo.subNotes.join('\n'),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑待办内容'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '标题',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesController,
              minLines: 3,
              maxLines: 7,
              decoration: const InputDecoration(
                labelText: '备注（每行一条）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final title = _titleController.text.trim();
            if (title.isEmpty) return;
            final notes = _notesController.text
                .split('\n')
                .map((line) => line.trim())
                .where((line) => line.isNotEmpty)
                .toList();
            Navigator.pop(context, (title: title, notes: notes));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _UnifiedItemDetails extends ConsumerWidget {
  final UnifiedItem item;
  final bool fromNotification;
  final String? notificationPayload;

  const _UnifiedItemDetails({
    required this.item,
    this.fromNotification = false,
    this.notificationPayload,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final time = item.startAt == null
        ? null
        : DateFormat('M月d日 HH:mm').format(item.startAt!);
    final due = item.deadline == null
        ? null
        : '截止 ${DateFormat('M月d日 HH:mm').format(item.deadline!)}';
    final scheduled = item.scheduledAt == null
        ? null
        : '计划 ${DateFormat('M月d日 HH:mm').format(item.scheduledAt!)}';
    final now = DateTime.now();
    final sourceTodo = item.source == UnifiedItemSource.todo
        ? ref
              .read(todoListProvider)
              .cast<TodoTask?>()
              .firstWhere((todo) => todo?.id == item.id, orElse: () => null)
        : null;
    final estimate = sourceTodo?.estimatedMinutes == null
        ? null
        : '预计用时 ${_formatTodoEstimate(sourceTodo!.estimatedMinutes!)}';
    final scheduleWarning = sourceTodo == null
        ? null
        : todoScheduleDeadlineWarning(sourceTodo);
    final sourceNotebookNote = item.source == UnifiedItemSource.note
        ? ref
              .read(notebookListProvider)
              .cast<NotebookEntry?>()
              .firstWhere((note) => note?.id == item.id, orElse: () => null)
        : null;
    final sourceDiaryNote = item.source == UnifiedItemSource.note
        ? ref
              .read(allEntriesProvider)
              .cast<DiaryEntry?>()
              .firstWhere(
                (entry) => entry?.id == item.id && entry?.category == 'note',
                orElse: () => null,
              )
        : null;
    DiaryEntry? sourceCapture;
    if (item.source == UnifiedItemSource.event ||
        item.source == UnifiedItemSource.draft) {
      sourceCapture = ref
          .read(allEntriesProvider)
          .cast<DiaryEntry?>()
          .firstWhere((entry) => entry?.id == item.id, orElse: () => null);
    } else if (item.source == UnifiedItemSource.todo &&
        sourceTodo?.sourceEntryId != null) {
      final sourceId = sourceTodo!.sourceEntryId;
      sourceCapture = ref
          .read(allEntriesProvider)
          .cast<DiaryEntry?>()
          .firstWhere((entry) => entry?.id == sourceId, orElse: () => null);
    }
    final noteBody = sourceNotebookNote?.content ?? sourceDiaryNote?.content;
    final originalCapture = sourceCapture?.content.trim();
    final showOriginalCapture =
        originalCapture != null &&
        originalCapture.isNotEmpty &&
        originalCapture != item.title.trim();
    final canScheduleToday =
        sourceTodo == null || isTodoOpenAt(sourceTodo, now);
    final canPlanTodo =
        item.source == UnifiedItemSource.todo &&
        sourceTodo != null &&
        !sourceTodo.isCompleted &&
        !sourceTodo.isArchived;
    final showQuickToday =
        canPlanTodo &&
        canScheduleToday &&
        (item.scheduledAt == null || !isSameDay(item.scheduledAt!, now));
    final scheduledToday =
        canPlanTodo &&
        item.scheduledAt != null &&
        isSameDay(item.scheduledAt!, now);
    final tomorrowAtSameTime = scheduledToday
        ? DateTime(
            item.scheduledAt!.year,
            item.scheduledAt!.month,
            item.scheduledAt!.day + 1,
            item.scheduledAt!.hour,
            item.scheduledAt!.minute,
          )
        : null;
    // A one-tap defer is useful when Today is already full, but must never
    // move work past its deadline. The full date/time picker remains available
    // for a deliberate exception or an earlier slot.
    final canDeferToTomorrow =
        tomorrowAtSameTime != null &&
        (sourceTodo?.deadline == null ||
            !tomorrowAtSameTime.isAfter(sourceTodo!.deadline!));
    final recurringTodo = item.source == UnifiedItemSource.todo
        ? routineRuleForTodo(item.id, ref.read(reminderRuleProvider))
        : null;
    final routineDueToday =
        recurringTodo != null &&
        (isRoutineDueOnDate(item.id, now, ref.read(reminderRuleProvider)) ||
            isRoutineSkippedOnDate(
              item.id,
              now,
              ref.read(reminderRuleProvider),
            ));
    final routineSkippedToday =
        recurringTodo != null &&
        isRoutineSkippedOnDate(item.id, now, ref.read(reminderRuleProvider));
    final reminderRules = ref.read(reminderRuleProvider);
    final sourceReminder = item.source == UnifiedItemSource.reminder
        ? reminderRules.cast<ReminderRule?>().firstWhere(
            (rule) => rule?.id == (item.sourceId ?? item.id),
            orElse: () => null,
          )
        : null;
    ReminderRule? snoozeRule;
    if (item.source == UnifiedItemSource.event) {
      snoozeRule = reminderRules.cast<ReminderRule?>().firstWhere(
        (rule) =>
            rule?.targetType == 'event' &&
            rule?.targetId == item.id &&
            rule!.isActive,
        orElse: () => null,
      );
    } else if (item.source == UnifiedItemSource.todo) {
      final todoRules = reminderRules
          .where(
            (rule) =>
                rule.targetType == 'todo' &&
                rule.targetId == item.id &&
                rule.isActive,
          )
          .toList();
      // Prefer the execution reminder for a planned occurrence; a deadline
      // reminder is the fallback when the notification was about the due date.
      snoozeRule = todoRules.cast<ReminderRule?>().firstWhere(
        (rule) => rule?.note == '事项提醒',
        orElse: () => todoRules.cast<ReminderRule?>().firstWhere(
          (_) => true,
          orElse: () => null,
        ),
      );
    } else if (item.source == UnifiedItemSource.reminder) {
      // Standalone reminders are delivered as their own unified item. Keep
      // the source rule here so a notification click can offer the same
      // temporary “稍后 15 分钟” action as event and todo notifications.
      snoozeRule = sourceReminder?.isActive == true ? sourceReminder : null;
    }
    final snoozeAnchor = item.startAt ?? item.scheduledAt ?? item.deadline;
    // Portable runtime reminders for bare timeline events use a synthetic
    // `timeline:<entryId>:...` payload instead of a persisted ReminderRule.
    // Keep that payload when opening the detail so the same event can be
    // snoozed without inventing a second rule in storage.
    final canSnoozeFallbackEvent =
        item.source == UnifiedItemSource.event &&
        fromNotification &&
        snoozeRule == null &&
        SystemNotificationService.isTimelineFallbackPayload(
          notificationPayload,
          item.id,
        );
    final snoozePayload = snoozeRule == null
        ? notificationPayload
        : snoozeAnchor == null
        ? null
        : SystemNotificationService.occurrencePayload(
            snoozeRule.id,
            snoozeAnchor,
          );
    final canSnooze =
        fromNotification &&
        !item.isCompleted &&
        snoozeAnchor != null &&
        (snoozeRule != null || canSnoozeFallbackEvent) &&
        snoozePayload != null &&
        SystemNotificationService.supportsSnooze;
    Widget snoozeButton() {
      final anchor = snoozeAnchor;
      if (!canSnooze || anchor == null) {
        return const SizedBox.shrink();
      }
      return OutlinedButton.icon(
        onPressed: () async {
          final scheduled = await SystemNotificationService.snooze(
            title: item.title,
            payload: snoozePayload,
          );
          if (!context.mounted) return;
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                scheduled ? '已设为 15 分钟后再次提醒 · ${item.title}' : '当前环境暂不能注册稍后提醒',
              ),
            ),
          );
        },
        icon: const Icon(Icons.snooze_outlined),
        label: const Text('稍后 15 分钟'),
      );
    }

    final recurringEvent = item.source == UnifiedItemSource.event
        ? ref
              .read(reminderRuleProvider)
              .cast<ReminderRule?>()
              .firstWhere(
                (rule) =>
                    rule?.targetType == 'event' &&
                    rule?.targetId == item.id &&
                    rule!.isActive &&
                    rule.scheduleType != 'once' &&
                    rule.scheduleType != 'custom',
                orElse: () => null,
              )
        : null;
    final recurringReminder =
        item.source == UnifiedItemSource.reminder &&
            sourceReminder != null &&
            sourceReminder.isActive &&
            sourceReminder.scheduleType != 'once' &&
            sourceReminder.scheduleType != 'custom'
        ? sourceReminder
        : null;
    final occurrenceRule = recurringEvent ?? recurringReminder;
    final occurrenceOriginalDate =
        occurrenceRule == null || item.startAt == null
        ? null
        : RecurrenceService.originalDateForOccurrence(
            occurrenceRule,
            item.startAt!,
          );
    final hasOccurrenceOverride =
        occurrenceRule != null &&
        occurrenceOriginalDate != null &&
        occurrenceRule.overrides.any(
          (override) =>
              isSameDay(override.originalDate, occurrenceOriginalDate) &&
              (override.newTime != null ||
                  override.newDurationMinutes != null ||
                  override.clearDurationMinutes ||
                  override.newContent != null ||
                  override.newLocation != null ||
                  override.clearLocation),
        );
    final hasOccurrenceSkip =
        occurrenceRule != null &&
        occurrenceOriginalDate != null &&
        occurrenceRule.skipDates.any(
          (date) => isSameDay(date, occurrenceOriginalDate),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_sourceIcon(item.source), color: ZenTheme.accentMatcha),
                const SizedBox(width: 8),
                Text(_sourceLabel(item.source), style: ZenTheme.labelMedium),
              ],
            ),
            const SizedBox(height: 10),
            Text(item.title, style: ZenTheme.headingZen),
            if (showOriginalCapture) ...[
              const SizedBox(height: 8),
              Text('原文', style: ZenTheme.labelMedium),
              const SizedBox(height: 4),
              SelectableText(
                originalCapture,
                style: ZenTheme.labelSmall.copyWith(
                  color: ZenTheme.textCompleted,
                ),
              ),
            ],
            if (time != null) ...[
              const SizedBox(height: 10),
              Text(
                item.endAt == null
                    ? time
                    : '$time – ${DateFormat('HH:mm').format(item.endAt!)}',
                style: ZenTheme.bodyMain,
              ),
            ],
            if (due != null) Text(due, style: ZenTheme.labelMedium),
            if (scheduled != null) Text(scheduled, style: ZenTheme.labelMedium),
            if (estimate != null) Text(estimate, style: ZenTheme.labelMedium),
            if (scheduleWarning != null)
              Text(
                scheduleWarning,
                style: ZenTheme.labelMedium.copyWith(
                  color: ZenTheme.statusOverdue,
                ),
              ),
            if (item.location != null && item.location!.isNotEmpty)
              Text(item.location!, style: ZenTheme.labelMedium),
            if (item.source == UnifiedItemSource.note &&
                noteBody != null &&
                noteBody.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('正文', style: ZenTheme.labelMedium),
              const SizedBox(height: 6),
              SelectableText(noteBody, style: ZenTheme.bodyMain),
            ],
            if (item.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: item.tags
                    .map(
                      (tag) => Chip(
                        label: Text('#$tag', style: ZenTheme.labelSmall),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    )
                    .toList(),
              ),
            ],
            if (canPlanTodo) ...[
              Wrap(
                spacing: 8,
                runSpacing: 0,
                children: [
                  TextButton.icon(
                    onPressed: () => _editTodoContent(context, ref),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('编辑内容'),
                  ),
                  TextButton.icon(
                    onPressed: () => _editTodoPriority(context, ref),
                    icon: const Icon(Icons.priority_high_outlined, size: 18),
                    label: Text('优先级 · ${_priorityLabel(item.priority)}'),
                  ),
                  TextButton.icon(
                    onPressed: () => _editTodoEstimate(context, ref),
                    icon: const Icon(Icons.timelapse_outlined, size: 18),
                    label: Text(
                      sourceTodo.estimatedMinutes == null
                          ? '设置预计用时'
                          : '预计用时 · ${_formatTodoEstimate(sourceTodo.estimatedMinutes!)}',
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            if (item.source == UnifiedItemSource.todo) ...[
              OutlinedButton.icon(
                onPressed: () async {
                  final todo = ref
                      .read(todoListProvider)
                      .where((t) => t.id == item.id)
                      .firstOrNull;
                  if (todo == null) return;
                  final updated = await showTaskAttentionDialog(context, todo);
                  if (updated == null || !context.mounted) return;
                  ref.read(todoListProvider.notifier).updateTodo(updated);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text('任务类型与关注日期'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () {
                  ref.read(todoListProvider.notifier).toggleTodo(item.id);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.check),
                label: Text(item.isCompleted ? '标记未完成' : '完成待办'),
              ),
              if (showQuickToday) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _scheduleTodoToday(context, ref),
                  icon: const Icon(Icons.today_outlined),
                  label: Text(item.scheduledAt == null ? '安排今天' : '改到今天'),
                ),
              ],
              if (canDeferToTomorrow) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _deferTodoToTomorrow(context, ref),
                  icon: const Icon(Icons.redo_outlined),
                  label: const Text('移到明天同一时间'),
                ),
              ],
              const SizedBox(height: 8),
              if (canPlanTodo)
                OutlinedButton.icon(
                  onPressed: () => _scheduleTodo(context, ref),
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text(item.scheduledAt == null ? '选择计划日期' : '调整计划时间'),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _editTodoDeadline(context, ref),
                icon: const Icon(Icons.flag_outlined),
                label: Text(item.deadline == null ? '设置截止时间' : '调整截止时间'),
              ),
              if (sourceTodo?.deadline != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _editTodoDeadlineReminder(context, ref),
                  icon: const Icon(Icons.flag_circle_outlined),
                  label: const Text('设置截止提醒'),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _editTodoOpening(context, ref),
                icon: const Icon(Icons.lock_clock_outlined),
                label: Text(sourceTodo?.opensAt == null ? '设置开放时间' : '调整开放时间'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _editTodoReminder(context, ref),
                icon: const Icon(Icons.notifications_none_outlined),
                label: const Text('设置提醒'),
              ),
              if (canSnooze) ...[const SizedBox(height: 8), snoozeButton()],
              if (routineDueToday) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    final notifier = ref.read(reminderRuleProvider.notifier);
                    final day = DateTime(now.year, now.month, now.day);
                    if (routineSkippedToday) {
                      notifier.removeSkipDate(recurringTodo.id, day);
                    } else {
                      notifier.addSkipDate(recurringTodo.id, day);
                    }
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(context);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          routineSkippedToday
                              ? '已恢复今天的例行事项 · ${item.title}'
                              : '已跳过今天的例行事项 · ${item.title}',
                        ),
                        action: SnackBarAction(
                          label: '撤销',
                          onPressed: () {
                            if (routineSkippedToday) {
                              notifier.addSkipDate(recurringTodo.id, day);
                            } else {
                              notifier.removeSkipDate(recurringTodo.id, day);
                            }
                          },
                        ),
                      ),
                    );
                  },
                  icon: Icon(
                    routineSkippedToday
                        ? Icons.event_available_outlined
                        : Icons.event_busy_outlined,
                  ),
                  label: Text(routineSkippedToday ? '恢复今天' : '跳过今天'),
                ),
              ],
            ],
            if (item.source == UnifiedItemSource.event) ...[
              FilledButton.icon(
                onPressed: () => _toggleEventCompletion(context, ref),
                icon: Icon(
                  item.isCompleted ? Icons.undo_outlined : Icons.check_outlined,
                ),
                label: Text(item.isCompleted ? '标记未完成' : '标记完成'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _editEvent(context, ref),
                icon: const Icon(Icons.notifications_none_outlined),
                label: const Text('编辑时间与提醒'),
              ),
              if (canSnooze) ...[const SizedBox(height: 8), snoozeButton()],
            ],
            if (item.source == UnifiedItemSource.reminder &&
                sourceReminder != null &&
                !item.isArchived) ...[
              OutlinedButton.icon(
                onPressed: () =>
                    _editStandaloneReminder(context, ref, sourceReminder),
                icon: const Icon(Icons.edit_notifications_outlined),
                label: const Text('编辑提醒'),
              ),
              const SizedBox(height: 8),
              Text(
                _reminderDetailSummary(sourceReminder),
                style: ZenTheme.labelMedium,
              ),
              if (canSnooze) ...[const SizedBox(height: 8), snoozeButton()],
            ],
            if (item.source == UnifiedItemSource.note &&
                sourceNotebookNote != null) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () {
                  ref
                      .read(selectedNoteIdProvider.notifier)
                      .select(sourceNotebookNote.id);
                  ref.read(navIndexProvider.notifier).setIndex(navIndexNotes);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.edit_note_outlined),
                label: const Text('打开笔记'),
              ),
            ],
            if (hasOccurrenceOverride)
              Builder(
                builder: (context) {
                  final rule = occurrenceRule;
                  final originalDate = occurrenceOriginalDate;
                  return TextButton.icon(
                    onPressed: () =>
                        _restoreOccurrence(context, ref, rule, originalDate),
                    icon: const Icon(Icons.restore_outlined, size: 18),
                    label: const Text('恢复本次原规则'),
                  );
                },
              ),
            if (occurrenceRule != null && occurrenceOriginalDate != null)
              Builder(
                builder: (context) {
                  final rule = occurrenceRule;
                  final originalDate = occurrenceOriginalDate;
                  final isReminder = item.source == UnifiedItemSource.reminder;
                  return OutlinedButton.icon(
                    onPressed: () {
                      final messenger = ScaffoldMessenger.of(context);
                      final notifier = ref.read(reminderRuleProvider.notifier);
                      if (hasOccurrenceSkip) {
                        notifier.removeSkipDate(rule.id, originalDate);
                      } else {
                        notifier.addSkipDate(rule.id, originalDate);
                      }
                      Navigator.pop(context);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            hasOccurrenceSkip
                                ? (isReminder ? '已恢复本次提醒' : '已恢复本次出现')
                                : (isReminder ? '已跳过本次提醒' : '已跳过本次出现'),
                          ),
                          action: SnackBarAction(
                            label: '撤销',
                            onPressed: () {
                              if (hasOccurrenceSkip) {
                                notifier.addSkipDate(rule.id, originalDate);
                              } else {
                                notifier.removeSkipDate(rule.id, originalDate);
                              }
                            },
                          ),
                        ),
                      );
                    },
                    icon: Icon(
                      hasOccurrenceSkip
                          ? Icons.event_available_outlined
                          : Icons.event_busy_outlined,
                    ),
                    label: Text(
                      hasOccurrenceSkip
                          ? (isReminder ? '恢复本次提醒' : '恢复本次出现')
                          : (isReminder ? '跳过本次提醒' : '跳过本次出现'),
                    ),
                  );
                },
              ),
            if (item.source != UnifiedItemSource.reminder)
              TextButton.icon(
                onPressed: () => _editTags(context, ref),
                icon: const Icon(Icons.sell_outlined, size: 18),
                label: const Text('编辑标签'),
              ),
            if (item.source == UnifiedItemSource.draft)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _convertToTodo(context, ref),
                    icon: const Icon(Icons.checklist_outlined),
                    label: const Text('转为待办'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _convertToNote(context, ref),
                    icon: const Icon(Icons.notes_outlined),
                    label: const Text('转为笔记'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _convertToEvent(context, ref),
                    icon: const Icon(Icons.schedule_outlined),
                    label: const Text('转为事件'),
                  ),
                ],
              ),
            if ((item.source == UnifiedItemSource.todo && sourceTodo != null) ||
                (item.source == UnifiedItemSource.note &&
                    (sourceNotebookNote != null || sourceDiaryNote != null)) ||
                (item.source == UnifiedItemSource.event &&
                    recurringEvent == null)) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _showConversionMenu(context, ref),
                icon: const Icon(Icons.transform_outlined),
                label: const Text('转换类型'),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _toggleArchive(context, ref),
              icon: Icon(
                item.isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
              ),
              label: Text(item.isArchived ? '恢复到工作区' : '归档事项'),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => _deleteItem(context, ref),
              icon: const Icon(
                Icons.delete_outline,
                color: ZenTheme.statusOverdue,
              ),
              label: const Text(
                '删除事项',
                style: TextStyle(color: ZenTheme.statusOverdue),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editStandaloneReminder(
    BuildContext context,
    WidgetRef ref,
    ReminderRule rule,
  ) async {
    final result = await showDialog<Object>(
      context: context,
      builder: (_) => ReminderEditDialog(existing: rule),
    );
    if (result == null || !context.mounted) return;
    final notifier = ref.read(reminderRuleProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    if (result is bool && result) {
      notifier.archiveRule(rule.id);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: const Text('提醒已归档'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => notifier.updateRule(
              rule.copyWith(
                status: rule.status == 'archived' ? 'active' : rule.status,
              ),
            ),
          ),
        ),
      );
      return;
    }
    if (result is! ReminderEditResult) return;
    final updated = rule.copyWith(
      title: result.title,
      importance: result.importance,
      disturbanceLevel: result.disturbanceLevel,
      scheduleType: result.scheduleType,
      anchorTime: result.anchorTime,
      advanceMinutes: result.advanceMinutes,
      status: result.isActive ? 'active' : 'disabled',
      displayMode: result.displayMode,
      startDate: rule.startDate ?? result.anchorTime,
      endDate: result.endDate,
      clearEndDate: result.endDate == null,
      byDay: result.byDay,
      clearByDay: result.byDay == null,
    );
    notifier.updateRule(updated);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: const Text('提醒已更新'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => notifier.updateRule(rule),
        ),
      ),
    );
  }

  String _reminderDetailSummary(ReminderRule rule) {
    final repeat = switch (rule.scheduleType) {
      'daily' => '每天',
      'weekly' => '每周',
      'every_n_days' => '每 ${rule.scheduleInterval} 天',
      'monthly' => '每月',
      _ => '单次',
    };
    final advances = rule.advanceMinutes.isEmpty
        ? '到点'
        : rule.advanceMinutes
              .map((minutes) => minutes == 0 ? '到点' : '提前 $minutes 分钟')
              .join('、');
    final state = rule.status == 'archived'
        ? '已归档'
        : rule.isActive
        ? '已启用'
        : '已暂停';
    return '$state · $repeat · $advances';
  }

  Future<void> _scheduleTodo(BuildContext context, WidgetRef ref) async {
    final todo = ref
        .read(todoListProvider)
        .cast<TodoTask?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    if (todo == null) return;
    final requested = await _pickTodoSchedule(
      context,
      todo,
      now: DateTime.now(),
    );
    if (requested == null || !context.mounted) return;
    final applied = _applyTodoSchedule(
      context,
      ref,
      todo.id,
      requested,
      closeDetails: true,
    );
    if (!applied && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('待办已更新，未保存新的计划')),
      );
    }
  }

  void _deferTodoToTomorrow(BuildContext context, WidgetRef ref) {
    final todo = ref
        .read(todoListProvider)
        .cast<TodoTask?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    final previous = todo?.scheduledAt;
    if (todo == null || previous == null) return;
    final tomorrow = DateTime(
      previous.year,
      previous.month,
      previous.day + 1,
      previous.hour,
      previous.minute,
    );
    if (todo.deadline != null && tomorrow.isAfter(todo.deadline!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('明天同一时间已晚于截止时间，请选择更早的计划时段。')),
      );
      return;
    }
    final safeDate = respectTodoOpening(todo, tomorrow);
    ref.read(todoListProvider.notifier).rescheduleTodo(todo.id, safeDate);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已移到 ${DateFormat('M月d日 HH:mm').format(safeDate)} · ${todo.title}',
        ),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => ref
              .read(todoListProvider.notifier)
              .rescheduleTodo(todo.id, previous),
        ),
      ),
    );
  }

  Future<void> _editTodoDeadline(BuildContext context, WidgetRef ref) async {
    final todo = ref
        .read(todoListProvider)
        .cast<TodoTask?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    if (todo == null) return;

    final previous = todo.deadline;
    final initial =
        previous ??
        todo.scheduledAt ??
        DateTime.now().add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: DateTime(initial.year, initial.month, initial.day),
      helpText: '选择截止日期',
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: previous == null
          ? const TimeOfDay(hour: 23, minute: 59)
          : TimeOfDay.fromDateTime(previous),
      helpText: '选择截止时间',
    );
    if (time == null || !context.mounted) return;

    final deadline = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final issue = todo.copyWith(deadline: deadline).validationMessage;
    if (issue != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(issue)));
      return;
    }
    ref.read(todoListProvider.notifier).setDeadline(item.id, deadline);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('截止时间已设为 ${DateFormat('M月d日 HH:mm').format(deadline)}'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => ref
              .read(todoListProvider.notifier)
              .setDeadline(item.id, previous),
        ),
      ),
    );
  }

  Future<void> _editTodoContent(BuildContext context, WidgetRef ref) async {
    final todo = ref
        .read(todoListProvider)
        .cast<TodoTask?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    if (todo == null || todo.isCompleted || todo.isArchived) return;

    final updatedValues =
        await showDialog<({String title, List<String> notes})>(
          context: context,
          builder: (_) => _TodoContentDialog(todo: todo),
        );
    if (updatedValues == null || !context.mounted) return;
    final updated = todo.copyWith(
      title: updatedValues.title,
      subNotes: updatedValues.notes,
    );
    ref.read(todoListProvider.notifier).updateTodo(updated);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('待办内容已更新 · ${updated.title}'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => ref.read(todoListProvider.notifier).updateTodo(todo),
        ),
      ),
    );
  }

  Future<void> _editTodoPriority(BuildContext context, WidgetRef ref) async {
    final todo = ref
        .read(todoListProvider)
        .cast<TodoTask?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    if (todo == null || todo.isCompleted || todo.isArchived) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('设置优先级', style: ZenTheme.headingZen),
              const SizedBox(height: 6),
              Text('优先级只影响今天的建议顺序，不会改变截止时间。', style: ZenTheme.emptyStateSub),
              const SizedBox(height: 8),
              for (final option in const [
                ('A', '重要 · 今天优先'),
                ('B', '普通 · 按截止时间'),
                ('C', '次要 · 有空再做'),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    option.$1 == todo.priority
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: option.$1 == todo.priority
                        ? ZenTheme.accentMatcha
                        : ZenTheme.textMuted,
                  ),
                  title: Text(option.$2),
                  onTap: () => Navigator.pop(sheetContext, option.$1),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || selected == todo.priority || !context.mounted) {
      return;
    }
    final previous = todo.priority;
    ref.read(todoListProvider.notifier).setPriority(todo.id, selected);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('优先级已调整为 ${_priorityLabel(selected)}'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => ref
              .read(todoListProvider.notifier)
              .setPriority(todo.id, previous),
        ),
      ),
    );
  }

  Future<void> _editTodoEstimate(BuildContext context, WidgetRef ref) async {
    final todo = ref
        .read(todoListProvider)
        .cast<TodoTask?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    if (todo == null || todo.isCompleted || todo.isArchived) return;

    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('预计用时'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final minutes in const [15, 30, 60, 90, 120, 180])
              ChoiceChip(
                label: Text('$minutes 分钟'),
                selected: todo.estimatedMinutes == minutes,
                onSelected: (_) => Navigator.pop(dialogContext, minutes),
                showCheckmark: false,
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 0),
            child: const Text('清除估算'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;
    final previous = todo.estimatedMinutes;
    final updated = selected == 0
        ? todo.copyWith(clearEstimatedMinutes: true)
        : todo.copyWith(estimatedMinutes: selected);
    ref.read(todoListProvider.notifier).updateTodo(updated);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          selected == 0
              ? '已清除预计用时'
              : '预计用时已设为 ${_formatTodoEstimate(selected)}',
        ),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            final restored = previous == null
                ? todo.copyWith(clearEstimatedMinutes: true)
                : todo.copyWith(estimatedMinutes: previous);
            ref.read(todoListProvider.notifier).updateTodo(restored);
          },
        ),
      ),
    );
  }

  Future<void> _editTodoOpening(BuildContext context, WidgetRef ref) async {
    final todo = ref
        .read(todoListProvider)
        .cast<TodoTask?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    if (todo == null) return;

    final previousOpening = todo.opensAt;
    final previousScheduled = todo.scheduledAt;
    final initial = previousOpening ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: DateTime(initial.year, initial.month, initial.day),
      helpText: '选择开放日期',
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: previousOpening == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay.fromDateTime(previousOpening),
      helpText: '选择开放时间',
    );
    if (time == null || !context.mounted) return;

    final opening = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final adjustedScheduled =
        previousScheduled != null && previousScheduled.isBefore(opening)
        ? opening
        : previousScheduled;
    final issue = todo.copyWith(opensAt: opening).validationMessage;
    if (issue != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(issue)));
      return;
    }
    ref.read(todoListProvider.notifier).setOpensAt(item.id, opening);
    if (adjustedScheduled != previousScheduled) {
      ref
          .read(todoListProvider.notifier)
          .rescheduleTodo(item.id, adjustedScheduled);
    }
    Navigator.pop(context);
    final message = adjustedScheduled != previousScheduled
        ? '开放时间已更新，执行计划已顺延到 ${DateFormat('M月d日 HH:mm').format(opening)}'
        : '开放时间已设为 ${DateFormat('M月d日 HH:mm').format(opening)}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            ref
                .read(todoListProvider.notifier)
                .setOpensAt(item.id, previousOpening);
            ref
                .read(todoListProvider.notifier)
                .rescheduleTodo(item.id, previousScheduled);
          },
        ),
      ),
    );
  }

  void _scheduleTodoToday(BuildContext context, WidgetRef ref) {
    final todo = ref
        .read(todoListProvider)
        .cast<TodoTask?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    if (todo == null) return;
    final now = DateTime.now();
    final slot = suggestTodoScheduleSlot(
      todo,
      now,
      events: _plannerEventsForDay(ref, now),
      scheduledTodos: ref.read(todoListProvider),
    );
    _scheduleTodoAt(
      context,
      ref,
      todo,
      slot,
      message: '已安排到 ${DateFormat('HH:mm').format(slot)} · ${todo.title}',
    );
    Navigator.pop(context);
  }

  Future<void> _editTodoReminder(BuildContext context, WidgetRef ref) async {
    final todo = ref
        .read(todoListProvider)
        .cast<TodoTask?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    if (todo == null) return;
    final anchor = todo.scheduledAt;
    if (anchor == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先为待办安排执行时间')));
      return;
    }
    final notifier = ref.read(reminderRuleProvider.notifier);
    final existing = notifier.ruleForTodoExecution(todo.id);
    var enabled = existing?.isActive ?? true;
    final advances = <int>{
      ...(existing?.advanceMinutes.isNotEmpty == true
          ? existing!.advanceMinutes
          : const [0]),
    };
    final result = await showDialog<_TodoReminderFormResult>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void toggleAdvance(int minutes) {
            setDialogState(() {
              if (!advances.add(minutes) && advances.length > 1) {
                advances.remove(minutes);
              }
            });
          }

          return AlertDialog(
            title: const Text('待办提醒'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('在计划时间提醒'),
                    subtitle: Text(DateFormat('M月d日 HH:mm').format(anchor)),
                    value: enabled,
                    onChanged: (value) => setDialogState(() => enabled = value),
                  ),
                  if (enabled) ...[
                    const SizedBox(height: 8),
                    const Text('提前提醒', style: ZenTheme.labelMedium),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        AdvanceChip(
                          label: '到点',
                          minutes: 0,
                          selected: advances.contains(0),
                          onTap: toggleAdvance,
                        ),
                        AdvanceChip(
                          label: '5 分钟',
                          minutes: 5,
                          selected: advances.contains(5),
                          onTap: toggleAdvance,
                        ),
                        AdvanceChip(
                          label: '15 分钟',
                          minutes: 15,
                          selected: advances.contains(15),
                          onTap: toggleAdvance,
                        ),
                        AdvanceChip(
                          label: '1 小时',
                          minutes: 60,
                          selected: advances.contains(60),
                          onTap: toggleAdvance,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _TodoReminderFormResult(
                    enabled: enabled,
                    advanceMinutes: advances.toList()..sort((a, b) => b - a),
                  ),
                ),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || !context.mounted) return;
    notifier.upsertRuleForTarget(
      ReminderRule(
        id: existing?.id,
        title: todo.title,
        targetType: 'todo',
        targetId: todo.id,
        category: todo.category,
        scheduleType: 'once',
        anchorTime: anchor,
        advanceMinutes: result.advanceMinutes,
        status: result.enabled ? 'active' : 'disabled',
        note: '事项提醒',
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _editTodoDeadlineReminder(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final todo = ref
        .read(todoListProvider)
        .cast<TodoTask?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    final deadline = todo?.deadline;
    if (todo == null || deadline == null) return;

    final notifier = ref.read(reminderRuleProvider.notifier);
    final existing = notifier.ruleForTodoDeadline(todo.id);
    var enabled = existing?.isActive ?? true;
    final advances = <int>{
      ...(existing?.advanceMinutes.isNotEmpty == true
          ? existing!.advanceMinutes
          : const [60]),
    };
    final result = await showDialog<_TodoReminderFormResult>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void toggleAdvance(int minutes) {
            setDialogState(() {
              if (!advances.add(minutes) && advances.length > 1) {
                advances.remove(minutes);
              }
            });
          }

          return AlertDialog(
            title: const Text('截止提醒'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('在截止前提醒'),
                    subtitle: Text(
                      '截止 ${DateFormat('M月d日 HH:mm').format(deadline)}',
                    ),
                    value: enabled,
                    onChanged: (value) => setDialogState(() => enabled = value),
                  ),
                  if (enabled) ...[
                    const SizedBox(height: 8),
                    const Text('提前提醒', style: ZenTheme.labelMedium),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        AdvanceChip(
                          label: '1 天',
                          minutes: 1440,
                          selected: advances.contains(1440),
                          onTap: toggleAdvance,
                        ),
                        AdvanceChip(
                          label: '3 小时',
                          minutes: 180,
                          selected: advances.contains(180),
                          onTap: toggleAdvance,
                        ),
                        AdvanceChip(
                          label: '1 小时',
                          minutes: 60,
                          selected: advances.contains(60),
                          onTap: toggleAdvance,
                        ),
                        AdvanceChip(
                          label: '15 分钟',
                          minutes: 15,
                          selected: advances.contains(15),
                          onTap: toggleAdvance,
                        ),
                        AdvanceChip(
                          label: '到点',
                          minutes: 0,
                          selected: advances.contains(0),
                          onTap: toggleAdvance,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _TodoReminderFormResult(
                    enabled: enabled,
                    advanceMinutes: advances.toList()..sort((a, b) => b - a),
                  ),
                ),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || !context.mounted) return;
    final updatedRule = ReminderRule(
      id: existing?.id ?? 'todo-deadline-${todo.id}',
      title: todo.title,
      targetType: 'todo',
      targetId: todo.id,
      category: todo.category,
      scheduleType: 'once',
      anchorTime: deadline,
      advanceMinutes: result.advanceMinutes,
      status: result.enabled ? 'active' : 'disabled',
      note: '作业截止提醒',
    );
    notifier.upsertRuleForTarget(updatedRule);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.enabled ? '截止提醒已更新' : '截止提醒已关闭'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            if (existing == null) {
              notifier.removeRuleWithoutCascade(updatedRule.id);
            } else {
              notifier.upsertRuleForTarget(existing);
            }
          },
        ),
      ),
    );
  }

  Future<void> _editEvent(BuildContext context, WidgetRef ref) async {
    final entry = ref
        .read(allEntriesProvider)
        .cast<DiaryEntry?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    if (entry == null) return;
    final rule = ref
        .read(reminderRuleProvider.notifier)
        .ruleForTarget('event', entry.id);
    final isRecurring =
        rule != null &&
        rule.isActive &&
        rule.scheduleType != 'once' &&
        rule.scheduleType != 'custom';
    final initialStart = item.startAt ?? entry.eventTime ?? DateTime.now();
    final initialDuration = item.endAt != null
        ? item.endAt!.difference(initialStart).inMinutes
        : entry.durationMinutes;
    final data = await showDialog<TimelineEventFormData>(
      context: context,
      builder: (_) => TimelineEventDialog(
        initialContent: item.title,
        initialTime: initialStart,
        initialDurationMinutes: initialDuration,
        initialLocation: item.location ?? entry.location ?? '',
        initialReminder: ReminderFormData.fromRule(rule),
        reminderEditable: !isRecurring,
        isEdit: true,
      ),
    );
    if (data == null || !context.mounted) return;
    if (isRecurring) {
      // A shared recurring item is edited as a single occurrence. Do not
      // mutate the source entry or the recurrence rule for future dates.
      final originalDate =
          RecurrenceService.originalDateForOccurrence(rule, initialStart) ??
          initialStart;
      RecurrenceOverride? previous;
      for (final override in rule.overrides) {
        if (isSameDay(override.originalDate, originalDate)) {
          previous = override;
          break;
        }
      }
      ref
          .read(reminderRuleProvider.notifier)
          .updateOccurrence(
            rule.id,
            originalDate,
            newTime: data.eventTime,
            clearNewTime: false,
            newDurationMinutes: data.durationMinutes,
            clearNewDurationMinutes: data.durationMinutes == null,
            newContent: data.content,
            newLocation: data.location,
            clearNewLocation: data.location.isEmpty,
          );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('重复实例已调整（仅影响当天）'),
          duration: Duration(seconds: 2),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () {
              final notifier = ref.read(reminderRuleProvider.notifier);
              if (previous == null) {
                notifier.removeOverride(rule.id, originalDate);
              } else {
                notifier.upsertOverride(rule.id, previous);
              }
            },
          ),
        ),
      );
      Navigator.pop(context);
      return;
    }
    final updated = entry.copyWith(
      content: data.content,
      eventTime: data.eventTime,
      durationMinutes: data.durationMinutes,
      clearDurationMinutes: data.durationMinutes == null,
      location: data.location,
      clearLocation: data.location.isEmpty,
    );
    final previousEntry = entry;
    final previousRule = rule;
    ref.read(allEntriesProvider.notifier).editEntryFull(updated);
    syncEventReminderRule(ref, updated, data.reminder);
    final updatedRule = ref
        .read(reminderRuleProvider)
        .cast<ReminderRule?>()
        .firstWhere(
          (value) =>
              value?.targetType == 'event' && value?.targetId == entry.id,
          orElse: () => null,
        );
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '事件已调整到 ${DateFormat('M月d日 HH:mm').format(updated.sortTime)}',
        ),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            ref.read(allEntriesProvider.notifier).editEntryFull(previousEntry);
            final notifier = ref.read(reminderRuleProvider.notifier);
            if (previousRule != null) {
              notifier.upsertRuleForTarget(previousRule);
            } else if (updatedRule != null) {
              notifier.removeRuleWithoutCascade(updatedRule.id);
            }
          },
        ),
      ),
    );
  }

  void _toggleEventCompletion(BuildContext context, WidgetRef ref) {
    final source = ref
        .read(allEntriesProvider)
        .cast<DiaryEntry?>()
        .firstWhere((entry) => entry?.id == item.id, orElse: () => null);
    if (source == null) return;
    final rule = ref
        .read(reminderRuleProvider.notifier)
        .ruleForTarget('event', source.id);
    final recurring =
        rule != null &&
        rule.isActive &&
        rule.scheduleType != 'once' &&
        rule.scheduleType != 'custom';
    final occurrenceTime = item.startAt ?? source.sortTime;
    if (recurring) {
      final originalDate =
          RecurrenceService.originalDateForOccurrence(rule, occurrenceTime) ??
          DateTime(
            occurrenceTime.year,
            occurrenceTime.month,
            occurrenceTime.day,
          );
      RecurrenceOverride? previous;
      for (final override in rule.overrides) {
        if (isSameDay(override.originalDate, originalDate)) {
          previous = override;
          break;
        }
      }
      final notifier = ref.read(reminderRuleProvider.notifier);
      if (!item.isCompleted) {
        notifier.upsertOverride(
          rule.id,
          previous?.copyWith(isCompleted: true, completedAt: DateTime.now()) ??
              RecurrenceOverride(
                originalDate: originalDate,
                isCompleted: true,
                completedAt: DateTime.now(),
              ),
        );
      } else if (previous == null) {
        if (isSameDay(occurrenceTime, source.sortTime)) {
          ref
              .read(allEntriesProvider.notifier)
              .editEntryFull(source.copyWith(isCompleted: false));
        }
      } else if (previous.newContent != null ||
          previous.newTime != null ||
          previous.newDurationMinutes != null ||
          previous.clearDurationMinutes ||
          previous.newLocation != null ||
          previous.clearLocation ||
          previous.note != null) {
        notifier.upsertOverride(
          rule.id,
          previous.copyWith(isCompleted: false, clearCompletedAt: true),
        );
      } else {
        notifier.removeOverride(rule.id, originalDate);
      }
    } else {
      final completed = !source.isCompleted;
      ref
          .read(allEntriesProvider.notifier)
          .editEntryFull(source.copyWith(isCompleted: completed));
      if (completed) {
        ref
            .read(reminderRuleProvider.notifier)
            .archiveActiveRulesForCompletion('event', source.id);
      } else {
        ref
            .read(reminderRuleProvider.notifier)
            .restoreCompletedRulesForTarget('event', source.id);
      }
    }
    Navigator.pop(context);
  }

  void _restoreOccurrence(
    BuildContext context,
    WidgetRef ref,
    ReminderRule rule,
    DateTime originalDate,
  ) {
    ref
        .read(reminderRuleProvider.notifier)
        .removeOverride(rule.id, originalDate);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已恢复本次原规则'), duration: Duration(seconds: 2)),
    );
  }

  void _convertToTodo(BuildContext context, WidgetRef ref) {
    final source = ref
        .read(allEntriesProvider)
        .cast<DiaryEntry?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    if (source == null) return;
    final todo = ref
        .read(todoListProvider.notifier)
        .addTodo(
          item.title,
          sourceEntryId: source.id,
          priority: item.priority,
          tags: item.tags,
        );
    ref.read(allEntriesProvider.notifier).archiveEntry(source.id);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('已转为待办 · ${todo.title}'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            ref.read(todoListProvider.notifier).archiveTodo(todo.id);
            ref
                .read(allEntriesProvider.notifier)
                .archiveEntry(source.id, archived: false);
          },
        ),
      ),
    );
  }

  void _convertToNote(BuildContext context, WidgetRef ref) {
    final source = ref
        .read(allEntriesProvider)
        .cast<DiaryEntry?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    if (source == null) return;
    final lines = item.title.split('\n');
    final title = lines.first.trim();
    final note = NotebookEntry(
      title: title.isEmpty ? '无标题' : title,
      content: item.title,
      tags: item.tags,
    );
    ref.read(notebookListProvider.notifier).addNote(note);
    ref.read(allEntriesProvider.notifier).archiveEntry(source.id);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('已转为笔记 · ${note.title}'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            ref.read(notebookListProvider.notifier).archiveNote(note.id);
            ref
                .read(allEntriesProvider.notifier)
                .archiveEntry(source.id, archived: false);
          },
        ),
      ),
    );
  }

  Future<void> _convertToEvent(BuildContext context, WidgetRef ref) async {
    final source = ref
        .read(allEntriesProvider)
        .cast<DiaryEntry?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    if (source == null) return;
    final previousRule = ref
        .read(reminderRuleProvider)
        .cast<ReminderRule?>()
        .firstWhere(
          (value) =>
              value?.targetType == 'event' && value?.targetId == source.id,
          orElse: () => null,
        );
    final data = await showDialog<TimelineEventFormData>(
      context: context,
      builder: (_) => TimelineEventDialog(
        initialContent: item.title,
        initialTime: DateTime.now(),
        initialReminder: ReminderFormData.defaults(),
      ),
    );
    if (data == null || !context.mounted) return;
    ref
        .read(allEntriesProvider.notifier)
        .convertToEvent(
          source.id,
          data.eventTime,
          location: data.location,
          durationMinutes: data.durationMinutes,
        );
    final updated = ref
        .read(allEntriesProvider)
        .cast<DiaryEntry?>()
        .firstWhere((value) => value?.id == source.id, orElse: () => null);
    if (updated == null) return;
    syncEventReminderRule(ref, updated, data.reminder);
    final updatedRule = ref
        .read(reminderRuleProvider)
        .cast<ReminderRule?>()
        .firstWhere(
          (value) =>
              value?.targetType == 'event' && value?.targetId == source.id,
          orElse: () => null,
        );
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('已转为事件 · ${updated.content}'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            ref.read(allEntriesProvider.notifier).editEntryFull(source);
            final notifier = ref.read(reminderRuleProvider.notifier);
            if (previousRule != null) {
              notifier.upsertRuleForTarget(previousRule);
            } else if (updatedRule != null) {
              notifier.removeRuleWithoutCascade(updatedRule.id);
            }
          },
        ),
      ),
    );
  }

  Future<void> _showConversionMenu(BuildContext context, WidgetRef ref) async {
    final choices = switch (item.source) {
      UnifiedItemSource.todo => const [
        ('todo_note', '转为笔记'),
        ('todo_event', '转为事件'),
      ],
      UnifiedItemSource.note => const [
        ('note_todo', '转为待办'),
        ('note_event', '转为事件'),
      ],
      UnifiedItemSource.event => const [
        ('event_todo', '转为待办'),
        ('event_note', '转为笔记'),
      ],
      _ => const <(String, String)>[],
    };
    if (choices.isEmpty) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('转换类型', style: ZenTheme.headingZen),
              const SizedBox(height: 6),
              Text('原事项会先归档；新事项创建成功后可随时撤销。', style: ZenTheme.emptyStateSub),
              const SizedBox(height: 10),
              ...choices.map(
                (choice) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    choice.$1.endsWith('note')
                        ? Icons.notes_outlined
                        : choice.$1.endsWith('event')
                        ? Icons.schedule_outlined
                        : Icons.checklist_outlined,
                  ),
                  title: Text(choice.$2),
                  onTap: () => Navigator.pop(sheetContext, choice.$1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case 'todo_note':
        _convertTodoToNote(context, ref);
      case 'todo_event':
        await _convertTodoToEvent(context, ref);
      case 'note_todo':
        _convertNoteToTodo(context, ref);
      case 'note_event':
        await _convertNoteToEvent(context, ref);
      case 'event_todo':
        _convertEventToTodo(context, ref);
      case 'event_note':
        _convertEventToNote(context, ref);
    }
  }

  void _convertTodoToNote(BuildContext context, WidgetRef ref) {
    final todo = ref
        .read(todoListProvider)
        .cast<TodoTask?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    if (todo == null) return;
    final body = todo.subNotes
        .where((line) => line.trim().isNotEmpty)
        .join('\n');
    final note = NotebookEntry(
      title: todo.title,
      content: body.trim().isEmpty ? todo.title : body,
      tags: todo.tags,
    );
    ref.read(notebookListProvider.notifier).addNote(note);
    ref.read(todoListProvider.notifier).archiveTodo(todo.id);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('已转为笔记 · ${todo.title}'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            ref.read(notebookListProvider.notifier).archiveNote(note.id);
            ref
                .read(todoListProvider.notifier)
                .archiveTodo(todo.id, archived: false);
          },
        ),
      ),
    );
  }

  void _convertNoteToTodo(BuildContext context, WidgetRef ref) {
    final notebook = ref
        .read(notebookListProvider)
        .cast<NotebookEntry?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    final diary = ref
        .read(allEntriesProvider)
        .cast<DiaryEntry?>()
        .firstWhere(
          (value) => value?.id == item.id && value?.category == 'note',
          orElse: () => null,
        );
    if (notebook == null && diary == null) return;
    final title = (notebook?.title ?? item.title).trim();
    final todo = ref
        .read(todoListProvider.notifier)
        .addTodo(
          title.isEmpty ? '无标题' : title,
          priority: item.priority,
          tags: item.tags,
        );
    if (notebook != null) {
      ref.read(notebookListProvider.notifier).archiveNote(notebook.id);
    } else {
      ref.read(allEntriesProvider.notifier).archiveEntry(diary!.id);
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('已转为待办 · ${todo.title}'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            ref.read(todoListProvider.notifier).archiveTodo(todo.id);
            if (notebook != null) {
              ref
                  .read(notebookListProvider.notifier)
                  .archiveNote(notebook.id, archived: false);
            } else {
              ref
                  .read(allEntriesProvider.notifier)
                  .archiveEntry(diary!.id, archived: false);
            }
          },
        ),
      ),
    );
  }

  Future<void> _convertTodoToEvent(BuildContext context, WidgetRef ref) async {
    final todo = ref
        .read(todoListProvider)
        .cast<TodoTask?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    if (todo == null) return;
    final data = await showDialog<TimelineEventFormData>(
      context: context,
      builder: (_) => TimelineEventDialog(
        initialContent: todo.title,
        initialTime: todo.scheduledAt ?? DateTime.now(),
        initialReminder: ReminderFormData.defaults(),
      ),
    );
    if (data == null || !context.mounted) return;
    final entry = ref
        .read(allEntriesProvider.notifier)
        .addEvent(
          data.content,
          data.eventTime,
          location: data.location,
          durationMinutes: data.durationMinutes,
        );
    if (entry == null) return;
    syncEventReminderRule(ref, entry, data.reminder);
    ref.read(todoListProvider.notifier).archiveTodo(todo.id);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('已转为事件 · ${entry.content}'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            ref.read(allEntriesProvider.notifier).archiveEntry(entry.id);
            ref
                .read(todoListProvider.notifier)
                .archiveTodo(todo.id, archived: false);
          },
        ),
      ),
    );
  }

  Future<void> _convertNoteToEvent(BuildContext context, WidgetRef ref) async {
    final notebook = ref
        .read(notebookListProvider)
        .cast<NotebookEntry?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    final diary = ref
        .read(allEntriesProvider)
        .cast<DiaryEntry?>()
        .firstWhere(
          (value) => value?.id == item.id && value?.category == 'note',
          orElse: () => null,
        );
    if (notebook == null && diary == null) return;
    final content = notebook?.content.trim().isNotEmpty == true
        ? notebook!.content
        : diary?.content ?? item.title;
    final data = await showDialog<TimelineEventFormData>(
      context: context,
      builder: (_) => TimelineEventDialog(
        initialContent: content,
        initialTime: DateTime.now(),
        initialReminder: ReminderFormData.defaults(),
      ),
    );
    if (data == null || !context.mounted) return;
    final entry = ref
        .read(allEntriesProvider.notifier)
        .addEvent(
          data.content,
          data.eventTime,
          location: data.location,
          durationMinutes: data.durationMinutes,
        );
    if (entry == null) return;
    syncEventReminderRule(ref, entry, data.reminder);
    if (notebook != null) {
      ref.read(notebookListProvider.notifier).archiveNote(notebook.id);
    } else {
      ref.read(allEntriesProvider.notifier).archiveEntry(diary!.id);
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('已转为事件 · ${entry.content}'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            ref.read(allEntriesProvider.notifier).archiveEntry(entry.id);
            if (notebook != null) {
              ref
                  .read(notebookListProvider.notifier)
                  .archiveNote(notebook.id, archived: false);
            } else {
              ref
                  .read(allEntriesProvider.notifier)
                  .archiveEntry(diary!.id, archived: false);
            }
          },
        ),
      ),
    );
  }

  void _convertEventToTodo(BuildContext context, WidgetRef ref) {
    final entry = ref
        .read(allEntriesProvider)
        .cast<DiaryEntry?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    if (entry == null) return;
    final todo = ref
        .read(todoListProvider.notifier)
        .addTodo(
          item.title,
          priority: item.priority,
          scheduledAt: entry.eventTime,
          tags: entry.tags,
        );
    ref.read(allEntriesProvider.notifier).archiveEntry(entry.id);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('已转为待办 · ${todo.title}'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            ref.read(todoListProvider.notifier).archiveTodo(todo.id);
            ref
                .read(allEntriesProvider.notifier)
                .archiveEntry(entry.id, archived: false);
          },
        ),
      ),
    );
  }

  void _convertEventToNote(BuildContext context, WidgetRef ref) {
    final entry = ref
        .read(allEntriesProvider)
        .cast<DiaryEntry?>()
        .firstWhere((value) => value?.id == item.id, orElse: () => null);
    if (entry == null) return;
    final note = NotebookEntry(
      title: item.title,
      content: entry.content,
      tags: entry.tags,
    );
    ref.read(notebookListProvider.notifier).addNote(note);
    ref.read(allEntriesProvider.notifier).archiveEntry(entry.id);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('已转为笔记 · ${note.title}'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            ref.read(notebookListProvider.notifier).archiveNote(note.id);
            ref
                .read(allEntriesProvider.notifier)
                .archiveEntry(entry.id, archived: false);
          },
        ),
      ),
    );
  }

  void _toggleArchive(BuildContext context, WidgetRef ref) {
    final archived = !item.isArchived;
    final messenger = ScaffoldMessenger.of(context);

    void apply(bool value) {
      switch (item.source) {
        case UnifiedItemSource.event:
        case UnifiedItemSource.draft:
          ref
              .read(allEntriesProvider.notifier)
              .archiveEntry(item.id, archived: value);
          break;
        case UnifiedItemSource.todo:
          ref
              .read(todoListProvider.notifier)
              .archiveTodo(item.id, archived: value);
          break;
        case UnifiedItemSource.note:
          if (ref
              .read(notebookListProvider)
              .any((note) => note.id == item.id)) {
            ref
                .read(notebookListProvider.notifier)
                .archiveNote(item.id, archived: value);
          } else {
            ref
                .read(allEntriesProvider.notifier)
                .archiveEntry(item.id, archived: value);
          }
          break;
        case UnifiedItemSource.reminder:
          final rule = ref
              .read(reminderRuleProvider)
              .cast<ReminderRule?>()
              .firstWhere(
                (value) => value?.id == (item.sourceId ?? item.id),
                orElse: () => null,
              );
          if (rule != null) {
            ref
                .read(reminderRuleProvider.notifier)
                .updateRule(
                  rule.copyWith(status: value ? 'archived' : 'active'),
                );
          }
          break;
      }
    }

    apply(archived);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(archived ? '已归档事项' : '已恢复事项'),
        action: SnackBarAction(label: '撤销', onPressed: () => apply(!archived)),
      ),
    );
  }

  Future<void> _deleteItem(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('永久删除事项？'),
        content: Text(
          '“${item.title}”将从工作区删除，关联的提醒和来源内容也可能被移除。若只是暂时不处理，建议使用“归档事项”。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ZenTheme.statusOverdue,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    switch (item.source) {
      case UnifiedItemSource.event:
      case UnifiedItemSource.draft:
        ref.read(allEntriesProvider.notifier).deleteEntry(item.id);
        break;
      case UnifiedItemSource.todo:
        ref.read(todoListProvider.notifier).deleteTodo(item.id);
        break;
      case UnifiedItemSource.note:
        if (ref.read(notebookListProvider).any((note) => note.id == item.id)) {
          ref.read(notebookListProvider.notifier).deleteNote(item.id);
        } else {
          ref.read(allEntriesProvider.notifier).deleteEntry(item.id);
        }
        break;
      case UnifiedItemSource.reminder:
        ref
            .read(reminderRuleProvider.notifier)
            .deleteRule(item.sourceId ?? item.id);
        break;
    }
    Navigator.pop(context);
  }

  Future<void> _editTags(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: item.tags.join('，'));
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '用逗号或空格分隔标签'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !context.mounted) return;
    final tags = value
        .split(RegExp('[,，\\s]+'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
    switch (item.source) {
      case UnifiedItemSource.event:
      case UnifiedItemSource.draft:
        final entry = ref
            .read(allEntriesProvider)
            .cast<DiaryEntry?>()
            .firstWhere((value) => value?.id == item.id, orElse: () => null);
        if (entry != null) {
          ref
              .read(allEntriesProvider.notifier)
              .editEntryFull(entry.copyWith(tags: tags));
        }
        break;
      case UnifiedItemSource.todo:
        final todo = ref
            .read(todoListProvider)
            .cast<TodoTask?>()
            .firstWhere((value) => value?.id == item.id, orElse: () => null);
        if (todo != null) {
          todo.tags = tags;
          ref.read(todoListProvider.notifier).updateTodo(todo);
        }
        break;
      case UnifiedItemSource.note:
        final note = ref
            .read(notebookListProvider)
            .cast<NotebookEntry?>()
            .firstWhere((value) => value?.id == item.id, orElse: () => null);
        if (note != null) {
          ref
              .read(notebookListProvider.notifier)
              .updateNote(note.copyWith(tags: tags));
        } else {
          final diaryNote = ref
              .read(allEntriesProvider)
              .cast<DiaryEntry?>()
              .firstWhere((value) => value?.id == item.id, orElse: () => null);
          if (diaryNote != null) {
            ref
                .read(allEntriesProvider.notifier)
                .editEntryFull(diaryNote.copyWith(tags: tags));
          }
        }
        break;
      case UnifiedItemSource.reminder:
        break;
    }
    Navigator.pop(context);
  }
}

class _WorkspaceItemTile extends StatelessWidget {
  final UnifiedItem item;
  final VoidCallback? onToggle;
  final VoidCallback onTap;
  final Widget? trailing;
  final String? hint;

  const _WorkspaceItemTile({
    required this.item,
    required this.onTap,
    this.onToggle,
    this.trailing,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final metadata = <String>[
      if (item.startAt != null)
        item.endAt == null
            ? DateFormat('HH:mm').format(item.startAt!)
            : '${DateFormat('HH:mm').format(item.startAt!)}–${DateFormat('HH:mm').format(item.endAt!)}',
      if (item.scheduledAt != null)
        '计划 ${DateFormat('M/d HH:mm').format(item.scheduledAt!)}',
      if (item.deadline != null)
        '截止 ${DateFormat('M/d HH:mm').format(item.deadline!)}',
    ].join(' · ');
    final fullMetadata = hint == null || metadata.isEmpty
        ? hint ?? metadata
        : '$metadata · $hint';
    return Material(
      color: ZenTheme.transparent,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 2),
        leading: onToggle == null
            ? Icon(
                _sourceIcon(item.source),
                size: 17,
                color: _sourceColor(item),
              )
            : Checkbox(
                value: item.isCompleted,
                onChanged: (_) => onToggle!(),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
        title: Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: ZenTheme.textStyle(
            fontSize: 14,
            color: item.isCompleted
                ? ZenTheme.textCompleted
                : ZenTheme.textBody,
            decoration: item.isCompleted ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: fullMetadata.isEmpty
            ? null
            : Text(fullMetadata, style: ZenTheme.labelSmall),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

List<DiaryEntry> _plannerEventsForDay(WidgetRef ref, DateTime day) {
  final entries = ref.read(timelineEntriesProvider);
  final projected = buildTimelineDaySummary(
    day: day,
    events: entries,
    todos: ref.read(todoListProvider),
    rules: ref.read(reminderRuleProvider),
    floatingTodoPolicy: TimelineFloatingTodoPolicy.exclude,
  ).events;
  return [...entries, ...projected];
}

TodoTask? _currentTodo(WidgetRef ref, String id) {
  for (final todo in ref.read(todoListProvider)) {
    if (todo.id == id) return todo;
  }
  return null;
}

TodoTask? _currentTodoInContainer(ProviderContainer container, String id) {
  for (final todo in container.read(todoListProvider)) {
    if (todo.id == id) return todo;
  }
  return null;
}

Future<DateTime?> _pickTodoSchedule(
  BuildContext context,
  TodoTask todo, {
  required DateTime now,
}) async {
  final initial =
      todo.scheduledAt ??
      suggestTodoSchedule(todo, now)?.scheduledAt ??
      now;
  final date = await showDatePicker(
    context: context,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
    initialDate: DateTime(initial.year, initial.month, initial.day),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
    // The stock dial has a fixed portrait width and can place its action
    // buttons outside a narrow phone surface. Input mode scales to the
    // available width while still allowing a normal date/time choice.
    initialEntryMode: TimePickerEntryMode.input,
  );
  if (time == null || !context.mounted) return null;
  return DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
}

bool _applyTodoSchedule(
  BuildContext context,
  WidgetRef ref,
  String todoId,
  DateTime requested, {
  bool closeDetails = false,
}) {
  // Dialogs can stay open while a notification, another view, or an undo
  // action changes the source task. Read it again immediately before saving
  // so only scheduledAt is changed and a completed task is never revived.
  final latest = _currentTodo(ref, todoId);
  if (latest == null || latest.isCompleted || latest.isArchived) return false;
  final previous = latest.scheduledAt;
  final safeDate = respectTodoOpening(latest, requested);
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  container.read(todoListProvider.notifier).rescheduleTodo(latest.id, safeDate);
  if (closeDetails && context.mounted) Navigator.pop(context);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        safeDate.isAtSameMomentAs(requested)
            ? '计划已调整到 ${DateFormat('M月d日 HH:mm').format(safeDate)}'
            : '待办尚未开放，计划已调整到 ${DateFormat('M月d日 HH:mm').format(safeDate)}',
      ),
      action: SnackBarAction(
        label: '撤销',
        onPressed: () {
          final current = _currentTodoInContainer(container, todoId);
          if (current == null || current.isCompleted || current.isArchived) {
            return;
          }
          final currentSchedule = current.scheduledAt;
          if (currentSchedule == null ||
              !currentSchedule.isAtSameMomentAs(safeDate)) {
            return;
          }
          container
              .read(todoListProvider.notifier)
              .rescheduleTodo(todoId, previous);
        },
      ),
    ),
  );
  return true;
}

Future<void> _rescheduleMissedTodo(
  BuildContext context,
  WidgetRef ref,
  TodoTask todo, {
  required DateTime now,
}) async {
  final latest = _currentTodo(ref, todo.id);
  if (latest == null || latest.isCompleted || latest.isArchived) return;
  final requested = await _pickTodoSchedule(context, latest, now: now);
  if (requested == null || !context.mounted) return;
  final applied = _applyTodoSchedule(context, ref, todo.id, requested);
  if (!applied && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('待办已更新，未保存新的计划')),
    );
  }
}

void _unscheduleMissedTodo(
  BuildContext context,
  WidgetRef ref,
  TodoTask todo,
) {
  final latest = _currentTodo(ref, todo.id);
  if (latest == null ||
      latest.isCompleted ||
      latest.isArchived ||
      latest.scheduledAt == null) {
    return;
  }
  final previous = latest.scheduledAt!;
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  container.read(todoListProvider.notifier).rescheduleTodo(latest.id, null);
  messenger.showSnackBar(
    SnackBar(
      content: Text('已暂不安排 · ${latest.title}'),
      action: SnackBarAction(
        label: '撤销',
        onPressed: () {
          final current = _currentTodoInContainer(container, todo.id);
          if (current == null || current.isCompleted || current.isArchived) {
            return;
          }
          // Do not undo over a new explicit schedule chosen after this action.
          if (current.scheduledAt != null) return;
          container
              .read(todoListProvider.notifier)
              .rescheduleTodo(todo.id, previous);
        },
      ),
    ),
  );
}

void _toggleTodayTodo(BuildContext context, WidgetRef ref, TodoTask todo) {
  final wasCompleted = todo.isCompleted;
  ref.read(todoListProvider.notifier).toggleTodo(todo.id);
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          wasCompleted ? '已恢复为未完成 · ${todo.title}' : '已完成 · ${todo.title}',
        ),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => ref.read(todoListProvider.notifier).completeTodos([
            todo.id,
          ], completed: wasCompleted),
        ),
      ),
    );
}

void _scheduleTodoAt(
  BuildContext context,
  WidgetRef ref,
  TodoTask todo,
  DateTime scheduledAt, {
  required String message,
}) {
  final previous = todo.scheduledAt;
  final safeDate = respectTodoOpening(todo, scheduledAt);
  ref.read(todoListProvider.notifier).rescheduleTodo(todo.id, safeDate);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        safeDate == scheduledAt
            ? message
            : '待办尚未开放，已安排到 ${DateFormat('M月d日 HH:mm').format(safeDate)}',
      ),
      action: SnackBarAction(
        label: '撤销',
        onPressed: () => ref
            .read(todoListProvider.notifier)
            .rescheduleTodo(todo.id, previous),
      ),
    ),
  );
}

class _TodoReminderFormResult {
  final bool enabled;
  final List<int> advanceMinutes;

  const _TodoReminderFormResult({
    required this.enabled,
    required this.advanceMinutes,
  });
}

IconData _sourceIcon(UnifiedItemSource source) => switch (source) {
  UnifiedItemSource.event => Icons.schedule_outlined,
  UnifiedItemSource.todo => Icons.check_box_outlined,
  UnifiedItemSource.reminder => Icons.notifications_none_outlined,
  UnifiedItemSource.draft => Icons.inbox_outlined,
  UnifiedItemSource.note => Icons.notes_outlined,
};

String _sourceLabel(UnifiedItemSource source) => switch (source) {
  UnifiedItemSource.event => '事件',
  UnifiedItemSource.todo => '待办',
  UnifiedItemSource.reminder => '提醒',
  UnifiedItemSource.draft => '未分类',
  UnifiedItemSource.note => '笔记',
};

String _priorityLabel(String priority) => switch (priority) {
  'A' => '重要',
  'C' => '次要',
  _ => '普通',
};

String _formatTodoEstimate(int minutes) {
  if (minutes < 60) return '$minutes 分钟';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '$hours 小时' : '$hours 小时 $remainder 分';
}

Color _sourceColor(UnifiedItem item) {
  if (item.isOverdue) return ZenTheme.statusOverdue;
  if (item.source == UnifiedItemSource.event) return ZenTheme.accentMatcha;
  return ZenTheme.textMuted;
}
