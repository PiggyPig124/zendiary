import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/zen_theme.dart';
import '../../models/diary_entry.dart';
import '../../models/todo_task.dart';
import '../../models/unified_item.dart';
import '../../providers/app_providers.dart';
import '../../providers/reminder_rule_provider.dart';
import '../../services/planner_service.dart';
import 'timeline_data.dart';
import 'timeline_shared.dart';

class WeekView extends ConsumerWidget {
  final DateTime weekStart;

  /// The day that should be visible first when the week is paged on a phone.
  /// Desktop keeps all seven cards in view, but a phone must not open on
  /// Monday when the user is actually planning Friday.
  final DateTime? focusDay;
  final ValueChanged<UnifiedItem>? onItemTap;
  final void Function(TodoTask todo, DateTime date)? onScheduleTodo;

  const WeekView({
    super.key,
    required this.weekStart,
    this.focusDay,
    this.onItemTap,
    this.onScheduleTodo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(timelineEntriesProvider);
    final todos = ref.watch(todoListProvider);
    final rules = ref.watch(reminderRuleProvider);
    final week = buildWeekTimelineSummary(
      weekStart: weekStart,
      events: events,
      todos: todos,
      completedPriorityFilter: const ['A', 'B'],
      // Once a student places a task on the plan, its priority must not make
      // it disappear from the weekly schedule. Low-priority floating backlog
      // remains collected below to keep the compact overview calm.
      actionPriorityFilter: null,
      rules: rules,
    );

    // A/B 浮动待办（周级别统一收集，避免每天重复）
    final floatingTodos = todos.where((todo) {
      if (todo.isCompleted ||
          todo.isArchived ||
          isRoutineTodo(todo.id, rules) ||
          todo.deadline != null ||
          todo.scheduledAt != null) {
        return false;
      }
      if (!const ['A', 'B'].contains(todo.priority)) return false;
      return true;
    }).toList();

    if (week.eventCount == 0 &&
        week.deadlineCount == 0 &&
        week.todoCount == 0 &&
        week.completedCount == 0 &&
        floatingTodos.isEmpty) {
      return const _EmptyWeek();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ZenTheme.spaceXl,
        ZenTheme.spaceLg,
        ZenTheme.spaceXl,
        28,
      ),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isTablet =
                constraints.maxWidth >= 600 && constraints.maxWidth < 980;
            final cardHeight = isTablet ? 206.0 : 224.0;
            final visibleCount = ((cardHeight - 102) / 28).floor().clamp(2, 7);
            final today = DateTime.now();
            final cards = week.days
                .map(
                  (day) => _WeekDayCard(
                    summary: day,
                    visibleCount: visibleCount,
                    distanceFromToday: _distanceDays(day.day, today),
                    isToday: isSameDay(day.day, today),
                    isWeekend: day.day.weekday == 6 || day.day.weekday == 7,
                    todoForId: (id) => todos.cast<TodoTask?>().firstWhere(
                      (todo) => todo?.id == id,
                      orElse: () => null,
                    ),
                    onItemTap: onItemTap == null
                        ? null
                        : (item) {
                            final todo = todos.cast<TodoTask?>().firstWhere(
                              (value) => value?.id == item.id,
                              orElse: () => null,
                            );
                            if (item.type == TimelineDayItemType.event) {
                              final source = events
                                  .cast<DiaryEntry?>()
                                  .firstWhere(
                                    (value) => value?.id == item.id,
                                    orElse: () => null,
                                  );
                              if (source != null) {
                                onItemTap!(
                                  UnifiedItem(
                                    id: source.id,
                                    source: UnifiedItemSource.event,
                                    sourceId: source.id,
                                    title: item.title,
                                    startAt: item.time ?? source.eventTime,
                                    endAt: item.endTime,
                                    status: item.isCompleted
                                        ? 'completed'
                                        : 'active',
                                    tags: source.tags,
                                    location: item.meta ?? source.location,
                                  ),
                                );
                              }
                            } else if (todo != null) {
                              onItemTap!(unifiedTodoItem(todo, DateTime.now()));
                            }
                          },
                    onScheduleTodo: (todo, date) {
                      if (onScheduleTodo != null) {
                        onScheduleTodo!(todo, date);
                        return;
                      }
                      _scheduleTodoFromWeekCard(context, ref, todo, date);
                    },
                    onTap: () {
                      ref.read(selectedDayProvider.notifier).set(day.day);
                      ref
                          .read(timelineViewModeProvider.notifier)
                          .set(TimelineViewMode.day);
                    },
                  ),
                )
                .toList();

            if (constraints.maxWidth < 600) {
              return SizedBox(
                height: cardHeight,
                child: Column(
                  children: [
                    Expanded(
                      child: _PhoneWeekPager(
                        cards: cards,
                        initialPage: _initialPageIndex,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('左右滑动查看每天', style: ZenTheme.caption),
                    ),
                  ],
                ),
              );
            }

            if (isTablet) {
              return Column(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    SizedBox(height: cardHeight, child: cards[i]),
                    if (i != cards.length - 1)
                      const SizedBox(height: ZenTheme.spaceMd),
                  ],
                ],
              );
            }

            return SizedBox(
              height: cardHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    Expanded(child: cards[i]),
                    if (i != cards.length - 1)
                      SizedBox(width: ZenTheme.spaceMd),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        _WeekSummary(week: week, floatingTodos: floatingTodos),
      ],
    );
  }

  int get _initialPageIndex {
    final target = focusDay ?? DateTime.now();
    final offset = DateTime(target.year, target.month, target.day)
        .difference(DateTime(weekStart.year, weekStart.month, weekStart.day))
        .inDays;
    return offset.clamp(0, 6);
  }

  int _distanceDays(DateTime a, DateTime b) {
    final da = DateTime(a.year, a.month, a.day);
    final db = DateTime(b.year, b.month, b.day);
    return (da.difference(db).inDays).abs();
  }

  void _scheduleTodoFromWeekCard(
    BuildContext context,
    WidgetRef ref,
    TodoTask todo,
    DateTime date,
  ) {
    final now = DateTime.now();
    final targetDay = DateTime(date.year, date.month, date.day);
    // A week-card drop is still a real execution plan. Use the same
    // estimate-aware slot finder as batch planning so dragging two tasks to
    // one day does not silently stack both at 09:00 or overlap a class.
    final requested = suggestTodoBatchSlots(
      [todo],
      targetDay,
      now,
      events: _eventsForDay(ref, targetDay),
      scheduledTodos: ref.read(todoListProvider),
    )[todo.id] ?? suggestedTodoScheduleForDay(targetDay, now);
    final safeDate = respectTodoOpening(todo, requested);
    final previous = todo.scheduledAt;
    ref.read(todoListProvider.notifier).rescheduleTodo(todo.id, safeDate);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          safeDate == requested
              ? '待办已安排到 ${DateFormat('M月d日 HH:mm').format(safeDate)}'
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

  List<DiaryEntry> _eventsForDay(WidgetRef ref, DateTime day) {
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
}

class _PhoneWeekPager extends StatefulWidget {
  final List<Widget> cards;
  final int initialPage;

  const _PhoneWeekPager({required this.cards, required this.initialPage});

  @override
  State<_PhoneWeekPager> createState() => _PhoneWeekPagerState();
}

class _PhoneWeekPagerState extends State<_PhoneWeekPager> {
  late final PageController _controller;
  var _page = 0;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    _controller = PageController(initialPage: _page);
  }

  @override
  void didUpdateWidget(covariant _PhoneWeekPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPage == _page || !_controller.hasClients) return;
    _page = widget.initialPage;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.hasClients) {
        _controller.jumpToPage(_page);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _controller,
      itemCount: widget.cards.length,
      onPageChanged: (page) => _page = page,
      itemBuilder: (_, index) => widget.cards[index],
    );
  }
}

// ── 周卡片 ──

class _WeekDayCard extends StatelessWidget {
  final TimelineDaySummary summary;
  final int visibleCount;
  final int distanceFromToday;
  final bool isToday;
  final bool isWeekend;
  final TodoTask? Function(String id) todoForId;
  final ValueChanged<TimelineDayItem>? onItemTap;
  final void Function(TodoTask todo, DateTime date)? onScheduleTodo;
  final VoidCallback onTap;

  const _WeekDayCard({
    required this.summary,
    required this.visibleCount,
    required this.distanceFromToday,
    required this.isToday,
    required this.isWeekend,
    required this.todoForId,
    this.onItemTap,
    this.onScheduleTodo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final visibleItems = summary.items.take(visibleCount).toList();
    final overflow = summary.items.length - visibleItems.length;
    final completedOverflow = summary.completedCount;
    final visibleCompleted = summary.completedTodos.take(2).toList();
    final completedExtra = summary.completedCount - visibleCompleted.length;

    // 顶部 accent bar 颜色
    final Color accentBarColor;
    if (isToday) {
      accentBarColor = ZenTheme.statusToday;
    } else if (summary.totalCount == 0) {
      accentBarColor = ZenTheme.borderCard;
    } else if (isWeekend) {
      accentBarColor = ZenTheme.textWeekend.withValues(alpha: 0.3);
    } else {
      accentBarColor = ZenTheme.accentMatcha.withValues(alpha: 0.3);
    }

    // 卡片背景（温度渐变）
    final Color cardBg;
    if (isToday) {
      cardBg = ZenTheme.backgroundToday;
    } else if (distanceFromToday <= 2) {
      cardBg = ZenTheme.backgroundWeekNear;
    } else if (isWeekend) {
      cardBg = ZenTheme.backgroundWeekend;
    } else {
      cardBg = ZenTheme.backgroundCard;
    }

    // 提取 spanning 条（仅 event 类型且标记了 spanning 边界）
    final spanningItems = summary.items
        .where(
          (item) =>
              item.type == TimelineDayItemType.event &&
              (item.isSpanningStart ||
                  item.isSpanningMiddle ||
                  item.isSpanningEnd),
        )
        .toList();

    final card = Material(
      color: ZenTheme.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(ZenTheme.radiusCard),
        hoverColor: ZenTheme.backgroundToday.withValues(alpha: 0.4),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(ZenTheme.spaceLg),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(ZenTheme.radiusCard),
            border: Border.all(
              color: isToday ? ZenTheme.statusToday : ZenTheme.borderSubtle,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部 accent bar
              Container(
                height: 2,
                decoration: BoxDecoration(
                  color: accentBarColor,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              // spanning 跨天条
              if (spanningItems.isNotEmpty) ...[
                const SizedBox(height: 4),
                ...spanningItems.map(
                  (item) => _SpanningBar(
                    item: item,
                    isStart: item.isSpanningStart,
                    isEnd: item.isSpanningEnd,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              const SizedBox(height: ZenTheme.spaceMd),
              // 星期 + 日期
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _weekdayLabel(summary.day.weekday),
                    style: ZenTheme.textStyle(
                      fontSize: 12,
                      color: isWeekend
                          ? ZenTheme.textWeekend
                          : ZenTheme.textMuted,
                    ),
                  ),
                  Text(
                    DateFormat('d').format(summary.day),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: ZenTheme.textBody,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ZenTheme.spaceMd),
              _Badges(summary: summary),
              const SizedBox(height: 7),
              Expanded(
                child: visibleItems.isEmpty
                    ? Align(
                        alignment: Alignment.topLeft,
                        child: const SizedBox.shrink(),
                      )
                    : Column(
                        children: [
                          for (final item in visibleItems)
                            _WeekItemLine(
                              item: item,
                              todo: todoForId(item.id),
                              onTap: onItemTap == null
                                  ? null
                                  : () => onItemTap!(item),
                            ),
                        ],
                      ),
              ),
              if (overflow > 0)
                Padding(
                  padding: const EdgeInsets.only(top: ZenTheme.spaceXs),
                  child: Text(
                    '+$overflow 条 · 点击进入日视图',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZenTheme.textStyle(
                      fontSize: 11,
                      color: ZenTheme.textMuted,
                    ),
                  ),
                ),
              if (completedOverflow > 0) ...[
                for (final c in visibleCompleted)
                  _WeekCompletedLine(title: c.title),
                if (completedExtra > 0)
                  Text(
                    '+ $completedExtra 已完成',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZenTheme.caption,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    if (onScheduleTodo == null) return card;
    return DragTarget<TodoTask>(
      onAcceptWithDetails: (details) => onScheduleTodo!(
        details.data,
        suggestedTodoScheduleForDay(summary.day, DateTime.now()),
      ),
      builder: (context, candidate, rejected) => DecoratedBox(
        decoration: candidate.isNotEmpty
            ? BoxDecoration(
                border: Border.all(color: ZenTheme.accentMatcha, width: 2),
                borderRadius: BorderRadius.circular(ZenTheme.radiusCard),
              )
            : const BoxDecoration(),
        child: card,
      ),
    );
  }

  static String _weekdayLabel(int weekday) {
    return const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];
  }
}

// ── 徽章 ──

class _Badges extends StatelessWidget {
  final TimelineDaySummary summary;

  const _Badges({required this.summary});

  @override
  Widget build(BuildContext context) {
    final activeEventCount = summary.events.where((e) => !e.isCompleted).length;
    final completedEventCount = summary.events
        .where((e) => e.isCompleted)
        .length;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (activeEventCount > 0)
          _Badge(
            label: '$activeEventCount 事',
            dotColor: ZenTheme.interactiveBrown,
          ),
        if (completedEventCount > 0)
          _Badge(
            label: '✓$completedEventCount',
            color: ZenTheme.backgroundWarm,
            textColor: ZenTheme.textCompleted,
            dotColor: ZenTheme.textCompleted,
          ),
        if (summary.deadlineCount > 0)
          _Badge(
            label: '${summary.deadlineCount} 截',
            color: ZenTheme.statusDeadlineBg,
            textColor: ZenTheme.statusDeadlineText,
            dotColor: ZenTheme.statusToday,
          ),
        if (summary.todoCount > 0)
          _Badge(
            label: '${summary.todoCount} 待',
            color: ZenTheme.statusTodoBg,
            textColor: ZenTheme.statusUpcoming,
            dotColor: ZenTheme.statusUpcoming,
          ),
      ],
    );
  }
}

// ── 周条目行 ──

class _WeekItemLine extends StatelessWidget {
  final TimelineDayItem item;
  final TodoTask? todo;
  final VoidCallback? onTap;

  const _WeekItemLine({required this.item, this.todo, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDeadline = item.type == TimelineDayItemType.deadline;
    final isCompleted = item.isCompleted;
    final textColor = isDeadline
        ? ZenTheme.statusDeadlineText
        : isCompleted
        ? ZenTheme.textCompleted
        : ZenTheme.textMuted;

    final line = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ZenTheme.radiusXs),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            if (isCompleted) ...[
              const Icon(Icons.check, size: 10, color: ZenTheme.textCompleted),
              const SizedBox(width: 3),
            ],
            SizedBox(
              width: 36,
              child: Text(
                _leadingText(item),
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: ZenTheme.textStyle(fontSize: 11, color: textColor),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZenTheme.textStyle(
                  fontSize: 12,
                  color: isDeadline
                      ? ZenTheme.statusDeadlineText
                      : isCompleted
                      ? ZenTheme.textCompleted
                      : ZenTheme.textHeading,
                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (todo == null || item.type == TimelineDayItemType.event) return line;
    return LongPressDraggable<TodoTask>(
      data: todo,
      feedback: Material(
        color: ZenTheme.transparent,
        child: SizedBox(width: 180, child: line),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: line),
      child: line,
    );
  }

  String _leadingText(TimelineDayItem item) {
    if (item.type == TimelineDayItemType.deadline) return '截止';
    if (item.type == TimelineDayItemType.todo) {
      return switch (item.meta) {
        'tonight' => '今晚',
        'today' => '今天',
        'missed' => '错过',
        _ => '待办',
      };
    }
    final time = item.time;
    return time == null ? '事件' : DateFormat('HH:mm').format(time);
  }
}

class _WeekCompletedLine extends StatelessWidget {
  final String title;

  const _WeekCompletedLine({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.check, size: 10, color: ZenTheme.textCompleted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: ZenTheme.textCompleted,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 周汇总 ──

/// 周视图只保留数字摘要；具体事项已经按日期显示在上方卡片中。
class _WeekSummary extends StatelessWidget {
  final WeekTimelineSummary week;
  final List<TodoTask> floatingTodos;

  const _WeekSummary({required this.week, required this.floatingTodos});

  @override
  Widget build(BuildContext context) {
    final eventCount = week.days.fold<int>(
      0,
      (sum, day) => sum + day.events.length,
    );
    final deadlineCount = week.days.fold<int>(
      0,
      (sum, day) => sum + day.deadlineTodos.length,
    );
    // Keep floating backlog separate from work actually placed on a day.
    // Counting both as “待办” makes a future week look overloaded before the
    // student has chosen when to do those tasks.
    final scheduledTodoCount = week.days.fold<int>(
      0,
      (sum, day) => sum + day.todoCount,
    );
    final unscheduledCount = floatingTodos.length;
    final completedCount = week.completedCount;
    final total =
        eventCount +
        deadlineCount +
        scheduledTodoCount +
        unscheduledCount +
        completedCount;
    if (total == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: ZenTheme.spaceSm),
      child: Wrap(
        spacing: ZenTheme.spaceLg,
        runSpacing: ZenTheme.spaceXs,
        children: [
          if (eventCount > 0)
            _CompactSummaryMetric(
              icon: Icons.schedule_outlined,
              label: '事件',
              count: eventCount,
            ),
          if (scheduledTodoCount > 0)
            _CompactSummaryMetric(
              icon: Icons.checklist_outlined,
              label: '待办',
              count: scheduledTodoCount,
              color: ZenTheme.statusUpcoming,
            ),
          if (unscheduledCount > 0)
            _CompactSummaryMetric(
              icon: Icons.inbox_outlined,
              label: '待安排',
              count: unscheduledCount,
              color: ZenTheme.textMuted,
            ),
          if (deadlineCount > 0)
            _CompactSummaryMetric(
              icon: Icons.flag_outlined,
              label: '截止',
              count: deadlineCount,
              color: ZenTheme.statusDeadlineText,
            ),
          if (completedCount > 0)
            _CompactSummaryMetric(
              icon: Icons.check_circle_outline,
              label: '已完成',
              count: completedCount,
              color: ZenTheme.textCompleted,
            ),
        ],
      ),
    );
  }
}

class _CompactSummaryMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  const _CompactSummaryMetric({
    required this.icon,
    required this.label,
    required this.count,
    this.color = ZenTheme.textMuted,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          '$label $count',
          style: ZenTheme.labelSmall.copyWith(color: color),
        ),
      ],
    );
  }
}

// ── Spanning 跨天条 ──

class _SpanningBar extends StatelessWidget {
  final TimelineDayItem item;
  final bool isStart;
  final bool isEnd;

  const _SpanningBar({
    required this.item,
    required this.isStart,
    required this.isEnd,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.horizontal(
      left: isStart ? const Radius.circular(4) : Radius.zero,
      right: isEnd ? const Radius.circular(4) : Radius.zero,
    );

    return Container(
      height: 14,
      decoration: BoxDecoration(
        color: ZenTheme.accentMatcha.withValues(alpha: 0.12),
        borderRadius: radius,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ZenTheme.accentMatcha.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ZenTheme.textStyle(
                fontSize: 9,
                color: ZenTheme.accentMatcha,
              ),
            ),
          ),
          if (item.isCompleted)
            const Icon(Icons.check, size: 10, color: ZenTheme.textCompleted),
        ],
      ),
    );
  }
}

// ── 徽章组件（胶囊形 + 前导色点）──

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final Color dotColor;

  const _Badge({
    required this.label,
    this.color = ZenTheme.backgroundWarm,
    this.textColor = ZenTheme.interactiveBrown,
    this.dotColor = ZenTheme.interactiveBrown,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(ZenTheme.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ZenTheme.textStyle(fontSize: 10, color: textColor),
          ),
        ],
      ),
    );
  }
}

// ── 空状态 ──

class _EmptyWeek extends StatelessWidget {
  const _EmptyWeek();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _ZenEmptyCircle(),
          const SizedBox(height: ZenTheme.spaceXl),
          Text('这周暂无安排', style: ZenTheme.emptyState),
          const SizedBox(height: ZenTheme.spaceSm),
          Text('写下带时间的内容后，ZenDiary 会把它放到这里', style: ZenTheme.emptyStateSub),
        ],
      ),
    );
  }
}

// ── Zen 圆形 ──

class _ZenEmptyCircle extends StatelessWidget {
  const _ZenEmptyCircle();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(64, 64), painter: _ZenCirclePainter());
  }
}

class _ZenCirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    final circlePaint = Paint()
      ..color = ZenTheme.accentMatcha.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    const dashCount = 12;
    const dashAngle = (3.14159 * 2) / dashCount;
    const gapRatio = 0.45;
    for (var i = 0; i < dashCount; i++) {
      final startAngle = i * dashAngle;
      final sweepAngle = dashAngle * (1 - gapRatio);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        circlePaint,
      );
    }

    final dotPaint = Paint()
      ..color = ZenTheme.accentMatcha
      ..style = PaintingStyle.fill;
    const dotAngle = -3.14159 * 5 / 6;
    final dotRadius = 3.5;
    final dotCenter = Offset(
      center.dx + radius * cos(dotAngle),
      center.dy + radius * sin(dotAngle),
    );
    canvas.drawCircle(dotCenter, dotRadius, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
