import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/zen_theme.dart';
import '../../models/diary_entry.dart';
import '../../models/reminder_rule.dart';
import '../../models/todo_task.dart';
import '../../models/unified_item.dart';
import '../../providers/app_providers.dart';
import '../../providers/reminder_rule_provider.dart';
import '../../services/unified_item_service.dart';
import 'timeline_data.dart';
import 'timeline_shared.dart';

/// 月视图 —— 低压力未来地图。
///
/// - 7 列月历网格
/// - 每天最多 2 条短标题（来自 monthVisibility=true 的 deadline 待办、重要事件、重要提醒）
/// - 超出用 +N chip 折叠
/// - 今天高亮
/// - 点击某天 → 摘要 bottom sheet
/// - "回到今天"按钮
class MonthView extends ConsumerWidget {
  final DateTime monthStart; // 当月第一天
  final ValueChanged<UnifiedItem>? onItemTap;

  const MonthView({super.key, required this.monthStart, this.onItemTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 1);
    final daysInMonth = monthEnd.difference(monthStart).inDays;
    final firstWeekday = monthStart.weekday; // DateTime.monday=1
    final startOffset = firstWeekday - 1; // 0=周一

    final allEvents = ref.watch(timelineEntriesProvider);
    final allTodos = ref.watch(todoListProvider);
    final rules = ref.watch(reminderRuleProvider);

    // 构建每天的数据（月视图显示待办 + 真实事件 + 重复事件虚拟投影）
    final Map<int, List<_DayEntry>> byDay = {};

    // 从真实事件收集（仅当月内存储的真实事件）
    for (final entry in allEvents) {
      if (entry.isArchived) continue;
      final entryDay = entry.sortTime.day;
      if (entry.sortTime.year == monthStart.year &&
          entry.sortTime.month == monthStart.month &&
          entryDay >= 1 &&
          entryDay <= daysInMonth) {
        byDay
            .putIfAbsent(entryDay, () => [])
            .add(
              _DayEntry(
                title: compactItemTitle(entry.aiSummary ?? entry.content),
                type: 'event',
                source: entry,
              ),
            );
      }
    }

    // 重复事件虚拟投影（每月最多 31 天，性能可忽略）
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(monthStart.year, monthStart.month, day);
      final projected = projectRecurringEvents(
        day: date,
        events: allEvents,
        rules: rules,
      );
      for (final proj in projected) {
        byDay
            .putIfAbsent(day, () => [])
            .add(
              _DayEntry(
                title: compactItemTitle(proj.aiSummary ?? proj.content),
                type: 'projected_event',
                source: proj,
              ),
            );
      }
    }

    // 从待办收集（monthVisibility=true 的计划 / 截止；例行任务由提醒
    // 负责，不占月历格子）。同一待办在计划日和截止日不同的时候各留
    // 一个标记，让学生能看见“什么时候做”和“什么时候必须交”。
    for (final todo in allTodos) {
      if (todo.isCompleted ||
          todo.isArchived ||
          !todo.monthVisibility ||
          isRoutineTodo(todo.id, rules)) {
        continue;
      }
      final deadline = todo.deadline;
      final scheduled = todo.scheduledAt;
      final deadlineInMonth =
          deadline != null &&
          deadline.year == monthStart.year &&
          deadline.month == monthStart.month;
      final scheduledInMonth =
          scheduled != null &&
          scheduled.year == monthStart.year &&
          scheduled.month == monthStart.month;

      if (deadlineInMonth) {
        byDay
            .putIfAbsent(deadline.day, () => [])
            .add(_DayEntry(title: todo.title, type: 'todo', source: todo));
      }
      if (scheduledInMonth &&
          (deadline == null || !isSameDay(deadline, scheduled))) {
        byDay
            .putIfAbsent(scheduled.day, () => [])
            .add(
              _DayEntry(
                title: todo.title,
                type: 'scheduled_todo',
                source: todo,
              ),
            );
      }
      if (!deadlineInMonth &&
          !scheduledInMonth &&
          deadline == null &&
          scheduled == null &&
          todo.priority == 'A' &&
          today.year == monthStart.year &&
          today.month == monthStart.month) {
        byDay
            .putIfAbsent(today.day, () => [])
            .add(_DayEntry(title: todo.title, type: 'todo', source: todo));
      }
    }

    // 独立提醒不再作为一级页面，但重要提醒仍需要出现在“未来地图”里。
    // 只把重要项压缩成低密度标记；普通提醒会在点开某天后完整查看，
    // 避免月历被通知类内容重新淹没。
    final standaloneReminders = rules
        .where(
          (rule) =>
              rule.importance == 'important' &&
              (rule.targetType == 'standalone' || rule.targetType == 'rule'),
        )
        .toList();
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(monthStart.year, monthStart.month, day);
      for (final reminder in buildStandaloneReminderItemsForDay(
        rules: standaloneReminders,
        day: date,
      )) {
        if (reminder.startAt!.year != monthStart.year ||
            reminder.startAt!.month != monthStart.month) {
          continue;
        }
        byDay
            .putIfAbsent(day, () => [])
            .add(
              _DayEntry(
                title: reminder.title,
                type: 'reminder',
                source: reminder,
              ),
            );
      }
    }

    // 每天只保留前 2 条
    final maxPerDay = 2;
    final overflowCounts = <int, int>{};
    for (final day in byDay.keys) {
      if (byDay[day]!.length > maxPerDay) {
        overflowCounts[day] = byDay[day]!.length - maxPerDay;
        byDay[day] = byDay[day]!.sublist(0, maxPerDay);
      }
    }

    const dayNames = ['一', '二', '三', '四', '五', '六', '日'];

    return Column(
      children: [
        // ── 周头 ──
        if (MediaQuery.sizeOf(context).width >= 600) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: dayNames.map((name) {
                final index = dayNames.indexOf(name);
                final isWeekend = index >= 5;
                return Expanded(
                  child: Center(
                    child: Text(
                      name,
                      style: ZenTheme.textStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isWeekend
                            ? ZenTheme.textWeekend
                            : ZenTheme.textMuted,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
        ],

        // ── 日历网格 ──
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 600) {
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: daysInMonth,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: ZenTheme.borderSubtle),
                  itemBuilder: (context, index) {
                    final day = index + 1;
                    final date = DateTime(
                      monthStart.year,
                      monthStart.month,
                      day,
                    );
                    final entries = byDay[day] ?? const <_DayEntry>[];
                    final overflow = overflowCounts[day] ?? 0;
                    final isToday = date == today;
                    final isWeekend = date.weekday >= 6;
                    return Material(
                      color: isToday
                          ? ZenTheme.backgroundToday
                          : ZenTheme.transparent,
                      child: InkWell(
                        onTap: () => _showDaySummary(
                          context,
                          ref,
                          date,
                          entries,
                          overflow,
                          allEvents,
                          allTodos,
                          rules,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 4,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 58,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${date.month}/${date.day}',
                                      style: ZenTheme.dateDisplay.copyWith(
                                        fontSize: 16,
                                        color: isToday
                                            ? ZenTheme.statusToday
                                            : isWeekend
                                            ? ZenTheme.textWeekend
                                            : ZenTheme.textHeading,
                                      ),
                                    ),
                                    Text(
                                      dayNames[date.weekday - 1],
                                      style: ZenTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: entries.isEmpty
                                    ? Text('无安排', style: ZenTheme.emptyStateSub)
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          for (final entry in entries)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 3,
                                              ),
                                              child: Text(
                                                entry.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: ZenTheme.bodyMain,
                                              ),
                                            ),
                                          if (overflow > 0)
                                            Text(
                                              '+$overflow 项',
                                              style: ZenTheme.labelSmall,
                                            ),
                                        ],
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              }
              final totalRows = ((startOffset + daysInMonth) / 7).ceil();
              final rowHeight = (constraints.maxHeight - 40) / totalRows;
              final dayWidth = constraints.maxWidth / 7;

              return SingleChildScrollView(
                child: Column(
                  children: List.generate(totalRows, (row) {
                    return SizedBox(
                      height: rowHeight.clamp(80, double.infinity),
                      child: Row(
                        children: List.generate(7, (col) {
                          final cellIndex = row * 7 + col;
                          final day = cellIndex - startOffset + 1;

                          if (day < 1 || day > daysInMonth) {
                            return SizedBox(width: dayWidth, height: rowHeight);
                          }

                          final date = DateTime(
                            monthStart.year,
                            monthStart.month,
                            day,
                          );
                          final isToday = date == today;
                          final entries = byDay[day] ?? [];
                          final overflow = overflowCounts[day] ?? 0;
                          final isWeekend = col >= 5;

                          return SizedBox(
                            width: dayWidth,
                            height: rowHeight,
                            child: Material(
                              color: ZenTheme.transparent,
                              child: InkWell(
                                hoverColor: ZenTheme.backgroundToday.withValues(
                                  alpha: 0.3,
                                ),
                                onTap: () => _showDaySummary(
                                  context,
                                  ref,
                                  date,
                                  entries,
                                  overflow,
                                  allEvents,
                                  allTodos,
                                  rules,
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isToday
                                        ? ZenTheme.backgroundToday
                                        : null,
                                    border: Border(
                                      right: BorderSide(
                                        color: ZenTheme.borderCard,
                                        width: 0.5,
                                      ),
                                      bottom: BorderSide(
                                        color: ZenTheme.borderCard,
                                        width: 0.5,
                                      ),
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(3),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // 日期数字
                                      Container(
                                        width: 22,
                                        height: 22,
                                        alignment: Alignment.center,
                                        decoration: isToday
                                            ? const BoxDecoration(
                                                color: ZenTheme.statusToday,
                                                shape: BoxShape.circle,
                                              )
                                            : null,
                                        child: Text(
                                          '$day',
                                          style: ZenTheme.textStyle(
                                            fontSize: 11,
                                            fontWeight: isToday
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: isToday
                                                ? ZenTheme.contentOnAccent
                                                : isWeekend
                                                ? ZenTheme.textWeekend
                                                : ZenTheme.textHeading,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      // 每天最多 2 条短标题
                                      ...entries.map(
                                        (e) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 1,
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 4,
                                                height: 4,
                                                margin: const EdgeInsets.only(
                                                  right: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color:
                                                      e.type ==
                                                          'projected_event'
                                                      ? ZenTheme.textMuted
                                                      : e.type == 'event'
                                                      ? ZenTheme
                                                            .interactiveBrown
                                                      : e.type ==
                                                            'scheduled_todo'
                                                      ? ZenTheme.accentMatcha
                                                      : e.type == 'reminder'
                                                      ? ZenTheme.textMuted
                                                      : ZenTheme.statusToday,
                                                  border:
                                                      e.type ==
                                                          'projected_event'
                                                      ? Border.all(
                                                          color: ZenTheme
                                                              .textMuted,
                                                          width: 0.5,
                                                        )
                                                      : null,
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  e.title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: ZenTheme.textStyle(
                                                    fontSize: 9,
                                                    color:
                                                        e.type ==
                                                            'projected_event'
                                                        ? ZenTheme.textCompleted
                                                        : ZenTheme.textMuted,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // +N 折叠
                                      if (overflow > 0)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: ZenTheme.backgroundWarm,
                                            borderRadius: BorderRadius.circular(
                                              ZenTheme.radiusXs,
                                            ),
                                          ),
                                          child: Text(
                                            '+$overflow',
                                            style: ZenTheme.textStyle(
                                              fontSize: 9,
                                              color: ZenTheme.textMuted,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    );
                  }),
                ),
              );
            },
          ),
        ),

        // ── 底部 "回到今天" 按钮 ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.today_outlined, size: 16),
              label: const Text('回到今天'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ZenTheme.interactiveBrown,
                side: const BorderSide(color: ZenTheme.borderButton),
              ),
              onPressed: () {
                ref.read(selectedDayProvider.notifier).set(DateTime.now());
              },
            ),
          ),
        ),
      ],
    );
  }

  void _showDaySummary(
    BuildContext context,
    WidgetRef ref,
    DateTime date,
    List<_DayEntry> entries,
    int overflow,
    List<DiaryEntry> allEvents,
    List<TodoTask> allTodos,
    List<ReminderRule> rules,
  ) {
    final daySummary = buildTimelineDaySummary(
      day: date,
      events: allEvents,
      todos: allTodos,
      includeOverdueDeadlines: isSameDay(date, DateTime.now()),
      // The unscheduled strip owns floating tasks; a date sheet should only
      // show work actually planned for this day or due on this day.
      floatingTodoPolicy: TimelineFloatingTodoPolicy.exclude,
      rules: rules,
    );
    final dayEvents = daySummary.events;
    final dayTodos = [
      ...daySummary.deadlineTodos,
      ...daySummary.actionTodos,
    ].where((todo) => !todo.isCompleted).toList();
    final dayReminders = buildStandaloneReminderItemsForDay(
      rules: rules,
      day: date,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: _DaySummarySheet(
            date: date,
            events: dayEvents,
            todos: dayTodos,
            reminders: dayReminders,
            completedTodos: daySummary.completedTodos,
            onEventTap: onItemTap == null
                ? null
                : (event) => onItemTap!(unifiedEventItem(event)),
            onTodoTap: onItemTap == null
                ? null
                : (todo) => onItemTap!(unifiedTodoItem(todo, DateTime.now())),
            onReminderTap: onItemTap == null
                ? null
                : (reminder) => onItemTap!(reminder),
          ),
        ),
      ),
    );
  }
}

// ── 日摘要数据类 ──

class _DayEntry {
  final String title;
  final String type; // 'event' | 'todo' | 'scheduled_todo' | 'reminder'
  final Object source;

  const _DayEntry({
    required this.title,
    required this.type,
    required this.source,
  });
}

// ── 日摘要 Bottom Sheet ──

class _DaySummarySheet extends StatefulWidget {
  final DateTime date;
  final List<DiaryEntry> events;
  final List<TodoTask> todos;
  final List<UnifiedItem> reminders;
  final List<TodoTask> completedTodos;
  final ValueChanged<DiaryEntry>? onEventTap;
  final ValueChanged<TodoTask>? onTodoTap;
  final ValueChanged<UnifiedItem>? onReminderTap;

  const _DaySummarySheet({
    required this.date,
    required this.events,
    required this.todos,
    required this.reminders,
    required this.completedTodos,
    this.onEventTap,
    this.onTodoTap,
    this.onReminderTap,
  });

  @override
  State<_DaySummarySheet> createState() => _DaySummarySheetState();
}

class _DaySummarySheetState extends State<_DaySummarySheet> {
  bool _showCompleted = true;

  @override
  Widget build(BuildContext context) {
    final weekdayNames = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final title =
        '${DateFormat('MM月dd日').format(widget.date)} ${weekdayNames[widget.date.weekday - 1]}';
    final hasCompleted = widget.completedTodos.isNotEmpty;
    final hasReminders = widget.reminders.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 拖动指示条
          Center(
            child: Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: ZenTheme.borderWarm,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(title, style: ZenTheme.dateDisplay),
          const SizedBox(height: 12),
          if (widget.events.isEmpty &&
              widget.todos.isEmpty &&
              !hasReminders &&
              !hasCompleted)
            Text(
              '这天没有安排',
              style: ZenTheme.textStyle(
                fontSize: 14,
                color: ZenTheme.textCompleted,
              ),
            )
          else ...[
            if (widget.events.isNotEmpty) ...[
              const Text('事件', style: ZenTheme.headingSection),
              const SizedBox(height: 6),
              ...widget.events.map(
                (e) => Material(
                  color: ZenTheme.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(ZenTheme.radiusSm),
                    onTap: widget.onEventTap == null
                        ? null
                        : () => widget.onEventTap!(e),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('HH:mm').format(e.sortTime),
                            style: ZenTheme.labelMedium,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              e.aiSummary ?? e.content,
                              style: ZenTheme.textStyle(
                                fontSize: 14,
                                color: ZenTheme.textHeading,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.todos.isNotEmpty || hasCompleted)
                const SizedBox(height: 8),
            ],
            if (widget.todos.isNotEmpty) ...[
              const Text(
                '待办',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ZenTheme.statusToday,
                ),
              ),
              const SizedBox(height: 6),
              ...widget.todos.map(
                (t) => Material(
                  color: ZenTheme.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(ZenTheme.radiusSm),
                    onTap: widget.onTodoTap == null
                        ? null
                        : () => widget.onTodoTap!(t),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.flag_outlined,
                            size: 14,
                            color: ZenTheme.statusToday,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.title,
                                  style: ZenTheme.textStyle(
                                    fontSize: 14,
                                    color: ZenTheme.textHeading,
                                  ),
                                ),
                                if (t.scheduledAt != null || t.deadline != null)
                                  Text(
                                    [
                                      if (t.scheduledAt != null)
                                        '计划 ${DateFormat('HH:mm').format(t.scheduledAt!)}',
                                      if (t.deadline != null)
                                        '截止 ${DateFormat('HH:mm').format(t.deadline!)}',
                                    ].join(' · '),
                                    style: ZenTheme.labelSmall,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (hasReminders) ...[
              if (widget.events.isNotEmpty || widget.todos.isNotEmpty)
                const SizedBox(height: 4),
              const Text(
                '提醒',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ZenTheme.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              ...widget.reminders.map(
                (reminder) => Material(
                  color: ZenTheme.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(ZenTheme.radiusSm),
                    onTap: widget.onReminderTap == null
                        ? null
                        : () => widget.onReminderTap!(reminder),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.notifications_none_outlined,
                            size: 14,
                            color: ZenTheme.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              reminder.startAt == null
                                  ? reminder.title
                                  : '${DateFormat('HH:mm').format(reminder.startAt!)}  ${reminder.title}',
                              style: ZenTheme.textStyle(
                                fontSize: 14,
                                color: ZenTheme.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (hasCompleted) ...[
              if (widget.events.isNotEmpty ||
                  widget.todos.isNotEmpty ||
                  hasReminders)
                const Divider(height: 16, color: ZenTheme.borderCard),
              GestureDetector(
                onTap: () => setState(() => _showCompleted = !_showCompleted),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      AnimatedRotation(
                        turns: _showCompleted ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.expand_less,
                          size: 16,
                          color: ZenTheme.textMuted,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '已完成 (${widget.completedTodos.length})',
                        style: ZenTheme.labelMedium,
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
                        children: widget.completedTodos
                            .map(
                              (t) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check,
                                      size: 14,
                                      color: ZenTheme.textCompleted,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        t.title,
                                        style: ZenTheme.textStyle(
                                          fontSize: 14,
                                          color: ZenTheme.textCompleted,
                                          decoration:
                                              TextDecoration.lineThrough,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
