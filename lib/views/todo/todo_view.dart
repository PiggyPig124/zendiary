import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/zen_theme.dart';
import '../../models/reminder_rule.dart';
import '../../models/todo_task.dart';
import '../../providers/app_providers.dart';
import '../../providers/reminder_rule_provider.dart';
import '../common/multi_select_bar.dart';
import '../common/page_header.dart';
import '../common/shared_dialog_widgets.dart';
import 'todo_create_dialog.dart';

/// Combines a date picked from the quick todo row with a safe default time.
///
/// A deadline entered for the first time is a date-level commitment, not an
/// event at midnight. Using the end of that day avoids immediately marking a
/// newly-created task overdue and keeps the default deadline reminder useful.
DateTime todoDeadlineForPickedDate(DateTime picked, DateTime? previous) {
  final source = previous;
  return DateTime(
    picked.year,
    picked.month,
    picked.day,
    source?.hour ?? 23,
    source?.minute ?? 59,
  );
}

/// Returns the next occurrence for a monthly routine while preserving the
/// user's preferred clock time. Days past the end of a month are clamped to
/// that month's last day (for example, the 31st becomes the 30th in April).
DateTime monthlyAnchorAfter(
  DateTime now,
  int requestedDay, {
  DateTime? preferredTime,
}) {
  // Monthly routines need a stable clock time even when no deadline was
  // entered.  09:00 keeps the reminder predictable and leaves room for the
  // user to adjust the occurrence later.
  final hour = preferredTime?.hour ?? 9;
  final minute = preferredTime?.minute ?? 0;

  final today = DateTime(now.year, now.month, now.day);
  final preferredDate = preferredTime == null
      ? null
      : DateTime(preferredTime.year, preferredTime.month, preferredTime.day);
  final usePreferredMonth =
      preferredDate != null && !preferredDate.isBefore(today);
  var year = usePreferredMonth ? preferredTime!.year : now.year;
  var month = usePreferredMonth ? preferredTime!.month : now.month;

  DateTime candidateFor(int y, int m) {
    final lastDay = DateTime(y, m + 1, 0).day;
    final day = requestedDay.clamp(1, lastDay);
    return DateTime(y, m, day, hour, minute);
  }

  var candidate = candidateFor(year, month);
  if (!candidate.isAfter(now)) {
    if (month == 12) {
      year += 1;
      month = 1;
    } else {
      month += 1;
    }
    candidate = candidateFor(year, month);
  }
  return candidate;
}

class TodoView extends ConsumerStatefulWidget {
  const TodoView({super.key});

  @override
  ConsumerState<TodoView> createState() => _TodoViewState();
}

class _TodoViewState extends ConsumerState<TodoView> {
  final Set<String> _selectedIds = {};
  bool _showCompleted = false;

  @override
  Widget build(BuildContext context) {
    final todos = ref.watch(todoListProvider);
    final now = DateTime.now();
    final upcoming = todos
        .where((t) => t.lifecycleAt(now) == TodoLifecycle.upcoming)
        .toList();
    final active = todos
        .where((t) => t.lifecycleAt(now) == TodoLifecycle.active)
        .toList();
    final overdue = todos
        .where((t) => t.lifecycleAt(now) == TodoLifecycle.overdue)
        .toList();
    final pending = [...upcoming, ...active, ...overdue];
    final done = todos.where((t) => t.isCompleted).toList();
    final isSelecting = _selectedIds.isNotEmpty;

    return Column(
      children: [
        PageHeader(
          title: '待办',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pending.isNotEmpty) ...[
                _PendingBadge(count: pending.length),
                const SizedBox(width: 10),
              ],
              TextButton.icon(
                icon: Icon(
                  isSelecting ? Icons.select_all : Icons.checklist,
                  size: 16,
                ),
                label: Text(isSelecting ? '全选' : '多选'),
                onPressed: todos.isEmpty
                    ? null
                    : () => _toggleSelectMode(todos),
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              todos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 48,
                            color: ZenTheme.textCompleted,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '暂无待办',
                            style: TextStyle(
                              color: ZenTheme.textCompleted,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        ..._lifecycleSection('即将开放', upcoming, isSelecting),
                        ..._lifecycleSection('进行中', active, isSelecting),
                        ..._lifecycleSection('逾期', overdue, isSelecting),
                        if (done.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => setState(
                                () => _showCompleted = !_showCompleted,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '已完成 (${done.length})',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: ZenTheme.textCompleted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  AnimatedRotation(
                                    turns: _showCompleted ? 0.5 : 0.0,
                                    duration: const Duration(milliseconds: 200),
                                    child: Icon(
                                      Icons.expand_less,
                                      size: 16,
                                      color: ZenTheme.textCompleted,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  TextButton(
                                    onPressed: () {
                                      final doneIds = done
                                          .map((t) => t.id)
                                          .toSet();
                                      ref
                                          .read(todoListProvider.notifier)
                                          .deleteTodos(doneIds);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '已清空 ${done.length} 条已完成待办',
                                          ),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    child: Text(
                                      '清空',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: ZenTheme.textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            alignment: Alignment.topCenter,
                            child: _showCompleted
                                ? Column(
                                    children: done
                                        .map(
                                          (task) => _TodoTile(
                                            task: task,
                                            isSelecting: isSelecting,
                                            isSelected: _selectedIds.contains(
                                              task.id,
                                            ),
                                            onToggleSelected: () =>
                                                _toggleSelection(task.id),
                                          ),
                                        )
                                        .toList(),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                        const SizedBox(height: 72), // space for FAB
                      ],
                    ),
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton(
                  backgroundColor: ZenTheme.accentMatcha,
                  onPressed: () => _showCreateTodoDialog(),
                  child: const Icon(Icons.add, color: ZenTheme.contentOnAccent),
                ),
              ),
            ],
          ),
        ),
        if (isSelecting)
          MultiSelectBar(
            count: _selectedIds.length,
            onCancel: () => setState(_selectedIds.clear),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.done_all_outlined, size: 16),
                label: const Text('完成'),
                onPressed: () => _bulkComplete(true),
              ),
              TextButton.icon(
                icon: const Icon(Icons.flag_outlined, size: 16),
                label: const Text('优先级'),
                onPressed: _bulkSetPriority,
              ),
              TextButton.icon(
                icon: const Icon(Icons.label_outline, size: 16),
                label: const Text('标签'),
                onPressed: () => _bulkSetTag(todos),
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('删除'),
                onPressed: _bulkDelete,
              ),
            ],
          ),
      ],
    );
  }

  List<Widget> _lifecycleSection(
    String title,
    List<TodoTask> tasks,
    bool isSelecting,
  ) {
    if (tasks.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
        child: Text(
          '$title (${tasks.length})',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ZenTheme.interactiveBrown,
          ),
        ),
      ),
      ...tasks.map(
        (task) => _TodoTile(
          task: task,
          isSelecting: isSelecting,
          isSelected: _selectedIds.contains(task.id),
          onToggleSelected: () => _toggleSelection(task.id),
        ),
      ),
    ];
  }

  void _toggleSelectMode(List<TodoTask> todos) {
    setState(() {
      if (_selectedIds.isEmpty) {
        _selectedIds.add(todos.first.id);
      } else if (_selectedIds.length == todos.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(todos.map((todo) => todo.id));
      }
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.add(id)) {
        _selectedIds.remove(id);
      }
    });
  }

  void _bulkComplete(bool completed) {
    final count = _selectedIds.length;
    ref
        .read(todoListProvider.notifier)
        .completeTodos(_selectedIds, completed: completed);
    setState(_selectedIds.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已完成 $count 条待办'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _bulkSetPriority() async {
    final priority = await showDialog<String>(
      context: context,
      builder: (_) => const _PriorityDialog(initialPriority: 'B'),
    );
    if (priority == null) return;
    if (!mounted) return;
    final count = _selectedIds.length;
    ref
        .read(todoListProvider.notifier)
        .setPriorityForTodos(_selectedIds, priority);
    setState(_selectedIds.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已更新 $count 条待办优先级'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _bulkSetTag(List<TodoTask> todos) async {
    final knownTags = <String>{};
    for (final todo in todos) {
      for (final tag in todo.tags) {
        if (tag.trim().isNotEmpty) knownTags.add(tag.trim());
      }
      final cat = todo.category.trim();
      if (cat.isNotEmpty && cat != 'general') knownTags.add(cat);
    }
    final result = await showDialog<_MultiTagDialogResult>(
      context: context,
      builder: (_) => _MultiTagDialog(
        initialTags: const [],
        knownTags: knownTags.toList()..sort(),
      ),
    );
    if (result == null) return;
    if (!mounted) return;
    final count = _selectedIds.length;
    ref
        .read(todoListProvider.notifier)
        .setTagsForTodos(_selectedIds, result.tags);
    if (result.tags.isNotEmpty) {
      ref
          .read(todoListProvider.notifier)
          .setCategoryForTodos(_selectedIds, result.tags.first);
    }
    setState(_selectedIds.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已更新 $count 条待办标签'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showCreateTodoDialog() async {
    final result = await showDialog<TodoCreateResult>(
      context: context,
      builder: (_) => const TodoCreateDialog(),
    );
    if (result == null) return;

    final notifier = ref.read(todoListProvider.notifier);
    final todo = notifier.addTodo(
      result.title,
      priority: result.priority,
      category: result.tags.isNotEmpty ? result.tags.first : 'general',
      opensAt: result.opensAt,
      taskKind: result.taskKind,
      attentionDate: result.attentionDate,
      estimatedMinutes: result.estimatedMinutes,
      deadline: result.deadline,
      tags: result.tags,
    );

    // 如果是例行任务，创建关联的 ReminderRule
    if (result.scheduleType != 'once') {
      final todoId = todo.id;
      final now = DateTime.now();
      final anchorTime = result.scheduleType == 'monthly'
          ? monthlyAnchorAfter(
              now,
              result.scheduleDay ?? now.day,
              preferredTime: result.deadline,
            )
          : result.deadline ?? now.add(const Duration(hours: 1));
      ref
          .read(reminderRuleProvider.notifier)
          .upsertRuleForTarget(
            ReminderRule(
              title: result.title,
              targetType: 'todo',
              targetId: todoId,
              importance: 'normal',
              disturbanceLevel: 'normal',
              scheduleType: result.scheduleType,
              scheduleInterval: result.scheduleInterval,
              anchorTime: anchorTime,
              advanceMinutes: const [60],
              endDate: result.endDate,
              byDay: result.byDay,
              scheduleDay: result.scheduleDay,
              byMonthDay: result.scheduleDay == null
                  ? null
                  : [result.scheduleDay!],
            ),
          );
    }
  }

  void _bulkDelete() {
    final count = _selectedIds.length;
    final reminderNotifier = ref.read(reminderRuleProvider.notifier);
    for (final id in _selectedIds) {
      reminderNotifier.archiveRulesForTarget('todo', id);
    }
    ref.read(todoListProvider.notifier).deleteTodos(_selectedIds);
    setState(_selectedIds.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除 $count 条待办'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _PendingBadge extends StatelessWidget {
  final int count;

  const _PendingBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: ZenTheme.interactiveBrown,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 11,
          color: ZenTheme.backgroundCard,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TodoTile extends ConsumerStatefulWidget {
  final TodoTask task;
  final bool isSelecting;
  final bool isSelected;
  final VoidCallback onToggleSelected;

  const _TodoTile({
    required this.task,
    required this.isSelecting,
    required this.isSelected,
    required this.onToggleSelected,
  });

  @override
  ConsumerState<_TodoTile> createState() => _TodoTileState();
}

class _TodoTileState extends ConsumerState<_TodoTile> {
  bool _isEditing = false;
  late TextEditingController _editController;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.task.title);
  }

  @override
  void didUpdateWidget(covariant _TodoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.title != widget.task.title && !_isEditing) {
      _editController.text = widget.task.title;
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final rules = ref.watch(activeReminderRulesProvider);
    final routineRule = routineRuleForTodo(task.id, rules);
    final today = DateTime.now();
    final routineOccurrenceToday =
        !task.isCompleted &&
        routineRule != null &&
        (isRoutineDueOnDate(task.id, today, rules) ||
            isRoutineSkippedOnDate(task.id, today, rules));
    final skippedToday =
        routineRule != null && isRoutineSkippedOnDate(task.id, today, rules);
    final priorityColor = switch (task.priority) {
      'A' => ZenTheme.statusOverdue,
      'B' => ZenTheme.statusToday,
      _ => ZenTheme.textCompleted,
    };

    return GestureDetector(
      onTap: widget.isSelecting ? widget.onToggleSelected : null,
      onLongPress: widget.onToggleSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: widget.isSelected || task.isCompleted
              ? ZenTheme.backgroundMuted
              : ZenTheme.backgroundCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ZenTheme.borderCard),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _showPriorityMenu(context),
                child: Container(
                  width: 4,
                  height: 36,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: priorityColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(
                width: 20,
                height: 20,
                child: widget.isSelecting
                    ? Checkbox(
                        value: widget.isSelected,
                        onChanged: (_) => widget.onToggleSelected(),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        activeColor: ZenTheme.interactiveBrown,
                      )
                    : Checkbox(
                        value: task.isCompleted,
                        onChanged: (_) => ref
                            .read(todoListProvider.notifier)
                            .toggleTodo(task.id),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        activeColor: ZenTheme.interactiveBrown,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _isEditing
                    ? TextField(
                        controller: _editController,
                        autofocus: true,
                        style: const TextStyle(
                          fontSize: 14,
                          fontFamily: ZenTheme.appFontFamily,
                          fontFamilyFallback: ZenTheme.fontFallback,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: _commitEdit,
                        onTapOutside: (_) => _commitEdit(_editController.text),
                      )
                    : GestureDetector(
                        onDoubleTap: () => setState(() => _isEditing = true),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.title,
                              style: TextStyle(
                                fontSize: 14,
                                fontFamily: ZenTheme.appFontFamily,
                                fontFamilyFallback: ZenTheme.fontFallback,
                                color: task.isCompleted
                                    ? ZenTheme.textCompleted
                                    : ZenTheme.textHeading,
                                decoration: task.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                // 例行标签（可点击编辑）
                                if (isRoutineTodo(task.id, rules))
                                  GestureDetector(
                                    onTap: () =>
                                        _showRoutineEditDialog(context),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: ZenTheme.surfaceWarm,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.repeat,
                                            size: 10,
                                            color: ZenTheme.textMuted,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            _routineLabel(task, rules),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: ZenTheme.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                // 截止时间 chip（非例行才显示原截止样式）
                                if (!isRoutineTodo(task.id, rules) &&
                                    task.deadline != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _deadlineBgColor(task.deadline!),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.event_outlined,
                                          size: 10,
                                          color: _deadlineTextColor(
                                            task.deadline!,
                                          ),
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${DateFormat('MM-dd').format(task.deadline!)}${_deadlineLabel(task.deadline!)}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: _deadlineTextColor(
                                              task.deadline!,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (task.estimatedMinutes != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: ZenTheme.statusTodoBg,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.timelapse_outlined,
                                          size: 10,
                                          color: ZenTheme.statusUpcoming,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          _estimateLabel(
                                            task.estimatedMinutes!,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: ZenTheme.statusUpcoming,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                // 用户 tags
                                ...task.tags.map(
                                  (tag) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: ZenTheme.statusUpcomingBg,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      tag,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: ZenTheme.statusUpcoming,
                                      ),
                                    ),
                                  ),
                                ),
                                // category 标签
                                GestureDetector(
                                  onTap: () => _showCategoryMenu(context),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: ZenTheme.backgroundWarm,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _categoryLabel(task.category),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: ZenTheme.textMuted,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
              ),
              if (!widget.isSelecting) ...[
                IconButton(
                  icon: Icon(
                    Icons.flag_outlined,
                    size: 17,
                    color: priorityColor,
                  ),
                  tooltip: '设置优先级',
                  onPressed: () => _showPriorityDialog(context),
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.label_outline,
                    size: 17,
                    color: ZenTheme.textMuted,
                  ),
                  tooltip: '设置标签',
                  onPressed: () => _showTagDialog(context),
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                if (routineOccurrenceToday)
                  IconButton(
                    icon: Icon(
                      skippedToday
                          ? Icons.event_available_outlined
                          : Icons.event_busy_outlined,
                      size: 17,
                      color: skippedToday
                          ? ZenTheme.accentGreen
                          : ZenTheme.textMuted,
                    ),
                    tooltip: skippedToday ? '恢复今天' : '跳过今天',
                    onPressed: () =>
                        _toggleRoutineToday(routineRule, today, skippedToday),
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                IconButton(
                  icon: Icon(
                    Icons.calendar_today,
                    size: 15,
                    color: task.deadline != null
                        ? ZenTheme.statusDeadlineIcon
                        : ZenTheme.textCompleted,
                  ),
                  tooltip: '设置截止日期',
                  onPressed: () => _editDeadline(context),
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 16,
                    color: ZenTheme.textCompleted,
                  ),
                  tooltip: '删除',
                  onPressed: () {
                    ref
                        .read(reminderRuleProvider.notifier)
                        .archiveRulesForTarget('todo', task.id);
                    ref.read(todoListProvider.notifier).deleteTodo(task.id);
                  },
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _toggleRoutineToday(ReminderRule rule, DateTime day, bool skipped) {
    final notifier = ref.read(reminderRuleProvider.notifier);
    if (skipped) {
      notifier.removeSkipDate(rule.id, day);
    } else {
      notifier.addSkipDate(rule.id, day);
    }
    final action = skipped ? '恢复' : '跳过';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已$action今天的例行事项 · ${widget.task.title}'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            if (skipped) {
              notifier.addSkipDate(rule.id, day);
            } else {
              notifier.removeSkipDate(rule.id, day);
            }
          },
        ),
      ),
    );
  }

  void _commitEdit(String value) {
    final title = value.trim();
    if (title.isNotEmpty) {
      ref.read(todoListProvider.notifier).editTitle(widget.task.id, title);
    }
    if (mounted) setState(() => _isEditing = false);
  }

  void _showPriorityMenu(BuildContext context) {
    _showPriorityDialog(context);
  }

  void _showCategoryMenu(BuildContext context) {
    _showTagDialog(context);
  }

  Future<void> _editDeadline(BuildContext context) async {
    final initialDate = widget.task.deadline ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    // Preserve the time portion if there was one. For a new deadline, use the
    // end of the picked day rather than silently creating a midnight deadline.
    final newDeadline = todoDeadlineForPickedDate(picked, widget.task.deadline);
    ref
        .read(todoListProvider.notifier)
        .setDeadline(widget.task.id, newDeadline);
  }

  Future<void> _showPriorityDialog(BuildContext context) async {
    final priority = await showDialog<String>(
      context: context,
      builder: (_) => _PriorityDialog(initialPriority: widget.task.priority),
    );
    if (priority == null) return;
    ref.read(todoListProvider.notifier).setPriority(widget.task.id, priority);
  }

  Future<void> _showTagDialog(BuildContext context) async {
    final allTodos = ref.read(todoListProvider);
    final knownTags = <String>{};
    for (final todo in allTodos) {
      for (final tag in todo.tags) {
        if (tag.trim().isNotEmpty) knownTags.add(tag.trim());
      }
      final cat = todo.category.trim();
      if (cat.isNotEmpty && cat != 'general') knownTags.add(cat);
    }
    final result = await showDialog<_MultiTagDialogResult>(
      context: context,
      builder: (_) => _MultiTagDialog(
        initialTags: widget.task.tags,
        knownTags: knownTags.toList()..sort(),
      ),
    );
    if (result == null) return;
    ref.read(todoListProvider.notifier).setTags(widget.task.id, result.tags);
    // Also update category for backward compatibility
    if (result.tags.isNotEmpty) {
      ref
          .read(todoListProvider.notifier)
          .setCategory(widget.task.id, result.tags.first);
    }
  }

  Future<void> _showRoutineEditDialog(BuildContext context) async {
    final task = widget.task;
    final rules = ref.read(reminderRuleProvider);
    final existingRule = rules.cast<ReminderRule?>().firstWhere(
      (r) =>
          r?.targetId == task.id &&
          r?.targetType == 'todo' &&
          r?.note != '事项提醒' &&
          r?.scheduleType != 'once' &&
          r?.scheduleType != 'custom',
      orElse: () => null,
    );
    final result = await showDialog<_RoutineEditResult>(
      context: context,
      builder: (_) =>
          _RoutineEditDialog(existingRule: existingRule, todoTitle: task.title),
    );
    if (result == null) return;

    final reminderNotifier = ref.read(reminderRuleProvider.notifier);

    if (result.scheduleType == 'once') {
      // Stop the recurring rule first. The separate deadline rule, if any,
      // remains responsible only for the due date.
      if (existingRule != null) {
        reminderNotifier.archiveRule(existingRule.id);
      }
      if (task.deadline != null) {
        reminderNotifier.upsertRuleForTarget(
          ReminderRule(
            title: task.title,
            targetType: 'todo',
            targetId: task.id,
            scheduleType: 'once',
            anchorTime: task.deadline,
            advanceMinutes: const [60],
            status: 'active',
            note: '作业截止前一小时提醒',
          ),
        );
      }
    } else {
      // 创建或更新 ReminderRule（isRoutine 已移除，仅管理 ReminderRule 即可）
      final anchorTime = result.scheduleType == 'monthly'
          ? monthlyAnchorAfter(
              DateTime.now(),
              result.scheduleDay ??
                  existingRule?.scheduleDay ??
                  existingRule?.byMonthDay?.first ??
                  DateTime.now().day,
              preferredTime: task.deadline ?? existingRule?.anchorTime,
            )
          : task.deadline ??
                existingRule?.anchorTime ??
                DateTime.now().add(const Duration(hours: 1));
      final rule = ReminderRule(
        id: existingRule?.id,
        title: task.title,
        targetType: 'todo',
        targetId: task.id,
        importance: 'normal',
        disturbanceLevel: 'normal',
        scheduleType: result.scheduleType,
        scheduleInterval: result.scheduleInterval,
        anchorTime: anchorTime,
        advanceMinutes: existingRule?.advanceMinutes ?? const [60],
        status: existingRule?.status == 'archived'
            ? 'active'
            : existingRule?.status ?? 'active',
        generatedByAi: existingRule?.generatedByAi ?? false,
        requiresConfirmation: false,
        createdAt: existingRule?.createdAt,
        note: existingRule?.note,
        endDate: result.endDate,
        byDay: result.byDay,
        scheduleDay: result.scheduleDay,
        byMonthDay: result.scheduleDay == null ? null : [result.scheduleDay!],
      );
      if (existingRule != null) {
        reminderNotifier.updateRule(rule);
      } else {
        reminderNotifier.addRule(rule);
      }
    }
  }

  String _categoryLabel(String value) {
    return value == 'general' ? '常规' : value;
  }

  String _estimateLabel(int minutes) {
    if (minutes < 60) return '约 $minutes 分钟';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return remainder == 0 ? '约 $hours 小时' : '约 $hours 小时 $remainder 分';
  }

  String _deadlineLabel(DateTime deadline) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(deadline.year, deadline.month, deadline.day);
    final diff = target.difference(today).inDays;
    if (diff < 0) return ' · 已过期';
    if (diff == 0) return ' · 今天截止';
    if (diff == 1) return ' · 明天截止';
    return ' · 还剩 $diff 天';
  }

  Color _deadlineBgColor(DateTime deadline) {
    final diff = _daysUntil(deadline);
    if (diff < 0) return ZenTheme.statusOverdueBg;
    if (diff == 0) return ZenTheme.statusTodayBg;
    if (diff <= 3) return ZenTheme.statusUpcomingBg;
    return ZenTheme.backgroundWarm;
  }

  Color _deadlineTextColor(DateTime deadline) {
    final diff = _daysUntil(deadline);
    if (diff < 0) return ZenTheme.statusOverdue;
    if (diff == 0) return ZenTheme.statusToday;
    if (diff <= 3) return ZenTheme.statusUpcoming;
    return ZenTheme.interactiveBrown;
  }

  int _daysUntil(DateTime deadline) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(deadline.year, deadline.month, deadline.day);
    return target.difference(today).inDays;
  }

  String _routineLabel(TodoTask task, List<ReminderRule> rules) {
    final rule = rules.cast<ReminderRule?>().firstWhere(
      (r) =>
          r?.targetId == task.id &&
          r?.targetType == 'todo' &&
          r?.note != '事项提醒' &&
          r?.scheduleType != 'once' &&
          r?.scheduleType != 'custom',
      orElse: () => null,
    );
    return switch (rule?.scheduleType) {
      'daily' => '每日',
      'weekly' => '每周',
      'every_n_days' => '每 ${rule!.scheduleInterval} 天',
      'monthly' => '每月',
      _ => '例行',
    };
  }
}

class _PriorityDialog extends StatefulWidget {
  final String initialPriority;

  const _PriorityDialog({required this.initialPriority});

  @override
  State<_PriorityDialog> createState() => _PriorityDialogState();
}

class _PriorityDialogState extends State<_PriorityDialog> {
  late String _priority;

  static const _textStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    fontFamilyFallback: ZenTheme.fontFallback,
    letterSpacing: 0,
  );

  static const _priorities = [('A', 'A 紧急'), ('B', 'B 重要'), ('C', 'C 一般')];

  @override
  void initState() {
    super.initState();
    _priority = widget.initialPriority;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置优先级'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _DialogLabel('优先级'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _priorities
                  .map(
                    (item) => ChoiceChip(
                      label: Text(item.$2, style: _textStyle),
                      selected: _priority == item.$1,
                      onSelected: (_) => setState(() => _priority = item.$1),
                      selectedColor: ZenTheme.interactivePressed,
                      side: const BorderSide(color: ZenTheme.borderButton),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, _priority);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _MultiTagDialogResult {
  final List<String> tags;

  const _MultiTagDialogResult({required this.tags});
}

class _MultiTagDialog extends StatefulWidget {
  final List<String> initialTags;
  final List<String> knownTags;

  const _MultiTagDialog({required this.initialTags, required this.knownTags});

  @override
  State<_MultiTagDialog> createState() => _MultiTagDialogState();
}

class _MultiTagDialogState extends State<_MultiTagDialog> {
  late Set<String> _selectedTags;
  late TextEditingController _tagCtrl;

  static const _textStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    fontFamilyFallback: ZenTheme.fontFallback,
    letterSpacing: 0,
  );

  static const _suggestedTags = ['工作', '课程', '游戏', '家务', '杂事', '低能量任务'];

  @override
  void initState() {
    super.initState();
    _selectedTags = Set<String>.from(widget.initialTags);
    _tagCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _tagCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allTags = {..._suggestedTags, ...widget.knownTags}.toList()..sort();

    return AlertDialog(
      title: const Text('设置标签（可多选）'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_selectedTags.isNotEmpty) ...[
              const _DialogLabel('已选标签'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _selectedTags
                    .map(
                      (tag) => Chip(
                        label: Text(tag, style: const TextStyle(fontSize: 12)),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () =>
                            setState(() => _selectedTags.remove(tag)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        backgroundColor: ZenTheme.interactivePressed,
                        side: BorderSide.none,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
            ],
            const _DialogLabel('可选标签'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: allTags
                  .map(
                    (tag) => FilterChip(
                      label: Text(tag, style: _textStyle),
                      selected: _selectedTags.contains(tag),
                      onSelected: (sel) {
                        setState(() {
                          if (sel) {
                            _selectedTags.add(tag);
                          } else {
                            _selectedTags.remove(tag);
                          }
                        });
                      },
                      selectedColor: ZenTheme.interactivePressed,
                      checkmarkColor: ZenTheme.interactiveBrown,
                      side: const BorderSide(color: ZenTheme.borderButton),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            const _DialogLabel('新增标签'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagCtrl,
                    style: _textStyle,
                    decoration: const InputDecoration(
                      hintText: '例如：健身、购物、项目',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addCustomTag(),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加'),
                  onPressed: _addCustomTag,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '点击标签即可多选，支持自定义标签。',
              style: TextStyle(fontSize: 12, color: ZenTheme.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(
              context,
              _MultiTagDialogResult(tags: _selectedTags.toList()..sort()),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _addCustomTag() {
    final value = _tagCtrl.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _selectedTags.add(value);
      _tagCtrl.clear();
    });
  }
}

class _DialogLabel extends StatelessWidget {
  final String text;

  const _DialogLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: ZenTheme.interactiveBrown,
        fontFamilyFallback: ZenTheme.fontFallback,
        letterSpacing: 0,
      ),
    );
  }
}

// ── 例行编辑对话框 ──

class _RoutineEditResult {
  final String scheduleType;
  final int scheduleInterval;
  final int? scheduleDay;
  final DateTime? endDate;
  final List<int>? byDay;

  const _RoutineEditResult({
    required this.scheduleType,
    required this.scheduleInterval,
    this.scheduleDay,
    this.endDate,
    this.byDay,
  });
}

class _RoutineEditDialog extends StatefulWidget {
  final ReminderRule? existingRule;
  final String todoTitle;

  const _RoutineEditDialog({this.existingRule, required this.todoTitle});

  @override
  State<_RoutineEditDialog> createState() => _RoutineEditDialogState();
}

class _RoutineEditDialogState extends State<_RoutineEditDialog> {
  late String _scheduleType;
  late int _scheduleInterval;
  late int _scheduleDay;
  late Set<int> _byDay;
  DateTime? _endDate;
  late TextEditingController _intervalCtrl;
  late TextEditingController _monthDayCtrl;

  @override
  void initState() {
    super.initState();
    final r = widget.existingRule;
    _scheduleType = r?.scheduleType ?? 'daily';
    _scheduleInterval = r?.scheduleInterval ?? 1;
    _scheduleDay = r?.scheduleDay ?? r?.byMonthDay?.first ?? DateTime.now().day;
    _byDay = (r?.byDay ?? [DateTime.now().weekday]).toSet();
    _endDate = r?.endDate;
    _intervalCtrl = TextEditingController(text: '$_scheduleInterval');
    _monthDayCtrl = TextEditingController(text: '$_scheduleDay');
  }

  @override
  void dispose() {
    _intervalCtrl.dispose();
    _monthDayCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        '编辑例行 — ${widget.todoTitle}',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _segRow(
                '重复',
                _scheduleType,
                const ['once', 'daily', 'weekly', 'every_n_days', 'monthly'],
                {
                  'once': '不重复',
                  'daily': '每天',
                  'weekly': '每周',
                  'every_n_days': '每N天',
                  'monthly': '每月',
                },
                (v) => setState(() => _scheduleType = v),
              ),
              if (_scheduleType == 'weekly') ...[
                const SizedBox(height: 10),
                WeekdayPicker(
                  selectedDays: _byDay,
                  onChanged: (days) => setState(() => _byDay = days),
                ),
              ],
              if (_scheduleType == 'every_n_days') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(
                      width: 54,
                      child: Text(
                        '间隔',
                        style: TextStyle(
                          fontSize: 13,
                          color: ZenTheme.interactiveBrown,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _intervalCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 14),
                        decoration: const InputDecoration(
                          labelText: '天数',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) {
                          final n = int.tryParse(v);
                          if (n != null && n > 0) _scheduleInterval = n;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '天',
                      style: TextStyle(
                        fontSize: 13,
                        color: ZenTheme.interactiveBrown,
                      ),
                    ),
                  ],
                ),
              ],
              if (_scheduleType != 'once') ...[
                const SizedBox(height: 10),
                EndDatePickerRow(
                  endDate: _endDate,
                  onPick: _pickEndDate,
                  onClear: () => setState(() => _endDate = null),
                ),
              ],
              if (_scheduleType == 'monthly') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(
                      width: 54,
                      child: Text(
                        '每月',
                        style: TextStyle(
                          fontSize: 13,
                          color: ZenTheme.interactiveBrown,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _monthDayCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 14),
                        decoration: const InputDecoration(
                          labelText: '几号',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (value) {
                          final day = int.tryParse(value);
                          if (day != null && day >= 1 && day <= 31) {
                            _scheduleDay = day;
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '号（31 号在短月按月底）',
                        style: TextStyle(
                          fontSize: 12,
                          color: ZenTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(
              context,
              _RoutineEditResult(
                scheduleType: _scheduleType,
                scheduleInterval: _scheduleInterval,
                scheduleDay: _scheduleType == 'monthly' ? _scheduleDay : null,
                endDate: _endDate,
                byDay: _scheduleType == 'weekly'
                    ? (_byDay.toList()..sort())
                    : null,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  Widget _segRow(
    String label,
    String value,
    List<String> options,
    Map<String, String> labels,
    ValueChanged<String> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: ZenTheme.interactiveBrown,
            ),
          ),
        ),
        Expanded(
          child: SegmentedButton<String>(
            segments: options
                .map(
                  (o) => ButtonSegment<String>(
                    value: o,
                    label: Text(
                      labels[o] ?? o,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                )
                .toList(),
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
            style: SegmentedButton.styleFrom(
              foregroundColor: ZenTheme.interactiveBrown,
              selectedForegroundColor: ZenTheme.contentOnAccent,
              selectedBackgroundColor: ZenTheme.interactiveBrown,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickEndDate() async {
    final initial = _endDate ?? DateTime.now().add(const Duration(days: 30));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      helpText: '选择重复截止日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked != null) setState(() => _endDate = picked);
  }
}
