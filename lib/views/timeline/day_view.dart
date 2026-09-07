import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/zen_theme.dart';
import '../../models/diary_entry.dart';
import '../../models/recurrence_override.dart';
import '../../models/reminder_rule.dart';
import '../../models/todo_task.dart';
import '../../models/unified_item.dart';
import '../../providers/app_providers.dart';
import '../../providers/reminder_rule_provider.dart';
import '../../services/planner_service.dart';
import '../../services/recurrence_service.dart';
import '../../services/today_list_service.dart';
import 'timeline_data.dart';
import 'timeline_shared.dart';

class DayView extends ConsumerWidget {
  final DateTime day;
  final void Function(DiaryEntry entry, DateTime startAt)? onReschedule;
  final ValueChanged<UnifiedItem>? onItemTap;

  const DayView({
    super.key,
    required this.day,
    this.onReschedule,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(timelineEntriesProvider);
    final todos = ref.watch(todoListProvider);
    final rules = ref.watch(reminderRuleProvider);
    final now = DateTime.now();
    final baseSummary = buildTimelineDaySummary(
      day: day,
      events: events,
      todos: todos,
      // Historical overdue work belongs on Today. A future (or historical)
      // day should stay focused on that day's own deadlines.
      includeOverdueDeadlines: isSameDay(day, now),
      // Floating tasks are managed from Plan's unscheduled strip. Including
      // them here would repeat the same task on every day in the calendar.
      floatingTodoPolicy: TimelineFloatingTodoPolicy.exclude,
      rules: rules,
    );
    final summary = isSameDay(day, now)
        ? _mergeTodayActionables(
            baseSummary,
            TodayListService.build(
              todos: todos,
              rules: rules,
              now: now,
            ).actionable,
          )
        : baseSummary;

    if (summary.totalCount == 0 && summary.completedCount == 0) {
      return _EmptyDay(day: day);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ZenTheme.pagePaddingHorizontal,
        ZenTheme.pagePaddingVertical,
        ZenTheme.pagePaddingHorizontal,
        ZenTheme.listBottomPadding,
      ),
      children: [
        _DaySummaryHeader(summary: summary),
        const SizedBox(height: ZenTheme.sectionGap),
        DayTimelineSection(
          day: day,
          events: summary.events,
          onEdit: (entry) => _showEditDialog(context, ref, entry),
          onReschedule: onReschedule,
          onItemTap: onItemTap,
        ),
        const SizedBox(height: ZenTheme.sectionGap),
        _TodoSection(
          deadlineTodos: summary.deadlineTodos,
          actionTodos: summary.actionTodos,
          completedTodos: summary.completedTodos,
          onItemTap: onItemTap,
        ),
      ],
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, DiaryEntry event) {
    final rule = ref
        .read(reminderRuleProvider.notifier)
        .ruleForTarget('event', event.id);
    final isRecurring =
        rule != null &&
        rule.isActive &&
        rule.scheduleType != 'once' &&
        rule.scheduleType != 'custom';
    showDialog<TimelineEventFormData>(
      context: context,
      builder: (_) => TimelineEventDialog(
        initialContent: event.content,
        initialTime: event.sortTime,
        initialDurationMinutes: event.durationMinutes,
        initialLocation: event.location ?? '',
        initialReminder: ReminderFormData.fromRule(rule),
        reminderEditable: !isRecurring,
        isEdit: true,
      ),
    ).then((data) {
      if (data == null || !context.mounted) return;
      if (isRecurring) {
        // Editing a repeating row edits this occurrence only. The source
        // event and future classes keep the rule's original schedule.
        final originalDate =
            RecurrenceService.originalDateForOccurrence(rule, event.sortTime) ??
            event.sortTime;
        RecurrenceOverride? previous;
        for (final override in rule.overrides) {
          if (RecurrenceService.isSameDate(
            override.originalDate,
            originalDate,
          )) {
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
        return;
      }
      final updatedEntry = event.copyWith(
        content: data.content,
        category: 'event',
        eventTime: data.eventTime,
        durationMinutes: data.durationMinutes,
        clearDurationMinutes: data.durationMinutes == null,
        location: data.location,
        clearLocation: data.location.isEmpty,
      );
      final previousEntry = event;
      final previousRule = rule;
      ref.read(allEntriesProvider.notifier).editEntryFull(updatedEntry);
      syncEventReminderRule(ref, updatedEntry, data.reminder);
      final updatedRule = ref
          .read(reminderRuleProvider)
          .cast<ReminderRule?>()
          .firstWhere(
            (value) =>
                value?.targetType == 'event' && value?.targetId == event.id,
            orElse: () => null,
          );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '事件已调整到 ${DateFormat('M月d日 HH:mm').format(updatedEntry.sortTime)}',
          ),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () {
              ref
                  .read(allEntriesProvider.notifier)
                  .editEntryFull(previousEntry);
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
    });
  }
}

TimelineDaySummary _mergeTodayActionables(
  TimelineDaySummary summary,
  Iterable<TodoTask> todayActionables,
) {
  final existingIds = {
    ...summary.deadlineTodos.map((todo) => todo.id),
    ...summary.actionTodos.map((todo) => todo.id),
  };
  final additions = todayActionables
      .where((todo) => existingIds.add(todo.id))
      .toList();
  if (additions.isEmpty) return summary;
  final actionTodos = [...summary.actionTodos, ...additions]
    ..sort(TodayListService.compare);
  return TimelineDaySummary(
    day: summary.day,
    events: summary.events,
    deadlineTodos: summary.deadlineTodos,
    actionTodos: actionTodos,
    completedTodos: summary.completedTodos,
    items: [
      ...summary.items,
      ...additions.map(
        (todo) => TimelineDayItem(
          type: TimelineDayItemType.todo,
          id: todo.id,
          title: todo.title,
          time: todo.scheduledAt ?? todo.deadline,
          meta: todo.scheduledAt == null ? 'today' : 'scheduled',
        ),
      ),
    ],
  );
}

// ── 日摘要头部 ──

class _DaySummaryHeader extends StatelessWidget {
  final TimelineDaySummary summary;

  const _DaySummaryHeader({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZenTheme.spaceXl),
      decoration: BoxDecoration(
        color: ZenTheme.backgroundPale,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ZenTheme.borderSage),
        boxShadow: [ZenTheme.shadowSubtle()],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('M月d日 EEEE', 'zh_CN').format(summary.day),
                style: ZenTheme.dateDisplay,
              ),
              const SizedBox(height: ZenTheme.spaceXs),
              Text('先看固定时间，再处理截止和可推进事项', style: ZenTheme.labelMedium),
            ],
          );
          final chips = Wrap(
            spacing: ZenTheme.spaceSm,
            runSpacing: ZenTheme.spaceSm,
            alignment: WrapAlignment.end,
            children: [
              _CountChip(label: '${summary.eventCount} 个固定事件'),
              _CountChip(label: '${summary.deadlineCount} 个截止'),
              _CountChip(label: '${summary.todoCount} 个可做'),
              if (summary.completedCount > 0)
                _CountChip(
                  label: '${summary.completedCount} 个已完成',
                  color: ZenTheme.surfaceWarm,
                  textColor: ZenTheme.textMuted,
                ),
            ],
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 2,
                height: constraints.maxWidth < 760 ? 58 : 44,
                decoration: BoxDecoration(
                  color: ZenTheme.accentMatcha,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: ZenTheme.spaceLg),
              Expanded(
                child: constraints.maxWidth < 760
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, const SizedBox(height: 10), chips],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: title),
                          chips,
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── 固定时间 section ──

class DayTimelineSection extends StatelessWidget {
  final DateTime day;
  final List<DiaryEntry> events;
  final ValueChanged<DiaryEntry> onEdit;
  final void Function(DiaryEntry entry, DateTime startAt)? onReschedule;
  final ValueChanged<UnifiedItem>? onItemTap;

  const DayTimelineSection({
    required this.day,
    required this.events,
    required this.onEdit,
    this.onReschedule,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '固定时间',
      accentColor: ZenTheme.accentMatcha,
      child: _FixedTimeRail(
        day: day,
        events: events,
        onEdit: onEdit,
        onReschedule: onReschedule,
        onItemTap: onItemTap,
      ),
    );
  }
}

// ── 固定时间轴 ──

class TimelineRailLayout {
  static const int startHour = 0;
  static const int endHour = 24;
  static const int totalMinutes = (endHour - startHour) * 60;
  static const double emptyHeight = 96;
  static const double minHeight = 180;
  static const double eventHeight = 34;
  static const double minContentGap = 42;
  static const double heightPerEvent = 80;

  final double height;
  final Map<int, double> _contentTops;

  const TimelineRailLayout._({
    required this.height,
    required this._contentTops,
  });

  factory TimelineRailLayout.compute(List<DateTime> times) {
    if (times.isEmpty) {
      return const TimelineRailLayout._(height: emptyHeight, contentTops: {});
    }

    final height = (times.length * heightPerEvent).clamp(
      minHeight,
      double.infinity,
    );
    final sortedTimes = [...times]..sort();
    final contentTops = <int, double>{};
    var lastTop = double.negativeInfinity;

    for (final time in sortedTimes) {
      final anchor = _anchorTopFor(time, height);
      var contentTop = anchor - eventHeight / 2;
      if (contentTop < lastTop + minContentGap) {
        contentTop = lastTop + minContentGap;
      }
      contentTop = contentTop.clamp(0, double.infinity);
      contentTops[time.microsecondsSinceEpoch] = contentTop;
      lastTop = contentTop;
    }

    return TimelineRailLayout._(height: height, contentTops: contentTops);
  }

  double anchorTop(DateTime time) => _anchorTopFor(time, height);

  double contentTop(DateTime time) {
    return _contentTops[time.microsecondsSinceEpoch] ??
        (anchorTop(time) - eventHeight / 2).clamp(0, double.infinity);
  }

  static double _anchorTopFor(DateTime time, double height) {
    final minutes = ((time.hour - startHour) * 60 + time.minute).clamp(
      0,
      totalMinutes,
    );
    return minutes / totalMinutes * height;
  }
}

class _FixedTimeRail extends StatelessWidget {
  // Keep the rail compact enough to fit when reused inside Today's narrower
  // content column. The event card still gets at least ~100 px on a 390 px
  // phone with the desktop navigation rail visible.
  static const double railLeft = 40;
  static const double eventLeft = 68;
  static const double topInset = 22;
  static const double bottomInset = 22;
  static const double endpointSize = 10;

  final DateTime day;
  final List<DiaryEntry> events;
  final ValueChanged<DiaryEntry> onEdit;
  final void Function(DiaryEntry entry, DateTime startAt)? onReschedule;
  final ValueChanged<UnifiedItem>? onItemTap;

  const _FixedTimeRail({
    required this.day,
    required this.events,
    required this.onEdit,
    this.onReschedule,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    final layout = TimelineRailLayout.compute(
      events.map((entry) => entry.sortTime).toList(),
    );
    final now = DateTime.now();
    final showNow = isSameDay(day, now);
    final stackHeight = topInset + layout.height + bottomInset;

    Widget rail = SizedBox(
      height: stackHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: railLeft,
            top: topInset,
            height: layout.height,
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: ZenTheme.oatmeal,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          _Endpoint(
            top: topInset,
            railLeft: railLeft,
            size: endpointSize,
            label: '0:00',
          ),
          _Endpoint(
            top: topInset + layout.height,
            railLeft: railLeft,
            size: endpointSize,
            label: '24:00',
          ),
          if (showNow)
            _NowLine(
              top: topInset + layout.anchorTop(now),
              railLeft: railLeft,
              label: DateFormat('HH:mm').format(now),
            ),
          if (events.isEmpty)
            Positioned(
              left: eventLeft,
              top: topInset + 32,
              right: 0,
              child: const _EmptyLine(text: '这一天没有固定时间事件'),
            ),
          for (final entry in events)
            _EventConnector(
              anchorTop: topInset + layout.anchorTop(entry.sortTime),
              contentTop: topInset + layout.contentTop(entry.sortTime),
              railLeft: railLeft,
              eventLeft: eventLeft,
            ),
          for (final entry in events)
            Positioned(
              left: eventLeft,
              right: 0,
              top: topInset + layout.contentTop(entry.sortTime),
              child: _TimelineEventRow(
                entry: entry,
                onEdit: () => onEdit(entry),
                onReschedule: onReschedule,
                onTap: onItemTap == null
                    ? null
                    : () => onItemTap!(unifiedEventItem(entry)),
              ),
            ),
        ],
      ),
    );
    if (onReschedule == null) return rail;
    return DragTarget<DiaryEntry>(
      onAcceptWithDetails: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final localY = (details.offset.dy - box.localToGlobal(Offset.zero).dy)
            .clamp(topInset, topInset + layout.height);
        final minutes = (localY - topInset) / layout.height * 1440;
        final snapped = snapToQuarterHour(
          DateTime(
            day.year,
            day.month,
            day.day,
          ).add(Duration(minutes: minutes.round())),
        );
        onReschedule!(details.data, snapped);
      },
      builder: (context, candidate, rejected) => rail,
    );
  }
}

class _Endpoint extends StatelessWidget {
  final double top;
  final double railLeft;
  final double size;
  final String label;

  const _Endpoint({
    required this.top,
    required this.railLeft,
    required this.size,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top - size / 2,
      left: 0,
      right: 0,
      child: Row(
        children: [
          SizedBox(
            width: railLeft - 10,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: ZenTheme.textStyle(
                fontSize: 11,
                color: ZenTheme.textCompleted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: ZenTheme.accentMatcha,
            ),
          ),
        ],
      ),
    );
  }
}

class _NowLine extends StatelessWidget {
  final double top;
  final double railLeft;
  final String label;

  const _NowLine({
    required this.top,
    required this.railLeft,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: top - 9,
      child: Row(
        children: [
          SizedBox(
            width: railLeft - 4,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.right,
                style: ZenTheme.textStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ZenTheme.statusToday,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ZenTheme.statusToday,
              border: Border.all(color: ZenTheme.backgroundCard, width: 2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1.5,
              color: ZenTheme.statusToday.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventConnector extends StatelessWidget {
  final double anchorTop;
  final double contentTop;
  final double railLeft;
  final double eventLeft;

  const _EventConnector({
    required this.anchorTop,
    required this.contentTop,
    required this.railLeft,
    required this.eventLeft,
  });

  @override
  Widget build(BuildContext context) {
    final rowCenter = contentTop + TimelineRailLayout.eventHeight / 2;
    final startX = railLeft + 5;
    final endX = eventLeft - 8;

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _EventConnectorPainter(
            start: Offset(startX, anchorTop),
            end: Offset(endX, rowCenter),
          ),
        ),
      ),
    );
  }
}

class _EventConnectorPainter extends CustomPainter {
  final Offset start;
  final Offset end;

  const _EventConnectorPainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ZenTheme.borderSubtle
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo((start.dx + end.dx) / 2, start.dy)
      ..lineTo((start.dx + end.dx) / 2, end.dy)
      ..lineTo(end.dx, end.dy);
    canvas.drawPath(path, paint);

    final dotPaint = Paint()
      ..color = ZenTheme.accentMatcha
      ..style = PaintingStyle.fill;
    canvas.drawCircle(start, 4, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _EventConnectorPainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}

// ── 时间线事件行 ──

class _TimelineEventRow extends ConsumerStatefulWidget {
  final DiaryEntry entry;
  final VoidCallback onEdit;
  final void Function(DiaryEntry entry, DateTime startAt)? onReschedule;
  final VoidCallback? onTap;

  const _TimelineEventRow({
    required this.entry,
    required this.onEdit,
    this.onReschedule,
    this.onTap,
  });

  @override
  ConsumerState<_TimelineEventRow> createState() => _TimelineEventRowState();
}

class _TimelineEventRowState extends ConsumerState<_TimelineEventRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final completed = widget.entry.isCompleted;

    // 判断是否为重复事件的投影实例（非锚点日）
    bool isProjectedInstance() {
      final rule = ref
          .read(reminderRuleProvider.notifier)
          .ruleForTarget('event', widget.entry.id);
      if (rule?.isActive != true ||
          rule!.scheduleType == 'once' ||
          rule.scheduleType == 'custom') {
        return false;
      }
      final anchorDay = DateTime(
        (rule.anchorTime ?? widget.entry.sortTime).year,
        (rule.anchorTime ?? widget.entry.sortTime).month,
        (rule.anchorTime ?? widget.entry.sortTime).day,
      );
      final today = DateTime(
        widget.entry.sortTime.year,
        widget.entry.sortTime.month,
        widget.entry.sortTime.day,
      );
      return !isSameDay(today, anchorDay);
    }

    final isProjected = isProjectedInstance();

    final content = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: ZenTheme.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(ZenTheme.radiusSm),
          hoverColor: ZenTheme.backgroundMuted,
          onTap: widget.onTap,
          onDoubleTap: widget.onEdit,
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
            decoration: BoxDecoration(
              color: completed
                  ? ZenTheme.backgroundWarm.withValues(alpha: 0.55)
                  : ZenTheme.backgroundCard.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(ZenTheme.radiusSm),
              border: Border.all(color: ZenTheme.borderSubtle),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: completed,
                  onChanged: (value) => _toggleCompleted(value ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeColor: ZenTheme.accentMatcha,
                  checkColor: ZenTheme.contentOnAccent,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ZenTheme.radiusXs),
                  ),
                ),
                _timeNode(completed),
                const SizedBox(width: ZenTheme.spaceSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isProjected) ...[
                            const Tooltip(
                              message: '重复实例（完成仅影响当天）',
                              child: Icon(
                                Icons.repeat,
                                size: 13,
                                color: ZenTheme.textMuted,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              '${DateFormat('HH:mm').format(widget.entry.sortTime)}'
                              '${widget.entry.endTime == null ? '' : '–${DateFormat('HH:mm').format(widget.entry.endTime!)}'}'
                              '${widget.entry.location?.trim().isNotEmpty == true ? ' · ${widget.entry.location!.trim()}' : ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: ZenTheme.textStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: completed
                                    ? ZenTheme.textCompleted
                                    : ZenTheme.accentMatcha,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        compactItemTitle(
                          widget.entry.content.trim().isNotEmpty
                              ? widget.entry.content
                              : widget.entry.aiSummary ?? '',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: ZenTheme.textStyle(
                          fontSize: 14,
                          color: completed
                              ? ZenTheme.textCompleted
                              : ZenTheme.textBody,
                          decoration: completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (MediaQuery.sizeOf(context).width >= 560)
                  AnimatedOpacity(
                    opacity: _isHovered ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _actionButton(
                          icon: Icons.edit_outlined,
                          tooltip: '编辑',
                          color: ZenTheme.textMuted,
                          onPressed: widget.onEdit,
                        ),
                        _actionButton(
                          icon: Icons.close,
                          tooltip: '删除',
                          color: ZenTheme.textCompleted,
                          onPressed: () => _confirmDelete(context),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (widget.onReschedule == null) return content;
    return LongPressDraggable<DiaryEntry>(
      data: widget.entry,
      feedback: Material(
        color: ZenTheme.transparent,
        child: SizedBox(width: 280, child: content),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: content),
      child: content,
    );
  }

  Widget _timeNode(bool completed) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: completed
              ? ZenTheme.textCompleted
              : ZenTheme.accentMatcha.withValues(alpha: 0.45),
          width: 1.5,
        ),
        color: completed
            ? ZenTheme.textCompleted.withValues(alpha: 0.12)
            : ZenTheme.accentMatcha.withValues(alpha: 0.08),
      ),
      child: Center(
        child: Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: completed ? ZenTheme.textCompleted : ZenTheme.accentMatcha,
          ),
        ),
      ),
    );
  }

  void _toggleCompleted(bool completed) {
    // 检查是否是重复事件的投影实例
    final rule = ref
        .read(reminderRuleProvider.notifier)
        .ruleForTarget('event', widget.entry.id);

    final isRecurring =
        rule != null &&
        rule.isActive &&
        rule.scheduleType != 'once' &&
        rule.scheduleType != 'custom';

    if (isRecurring) {
      final occurrenceDay = DateTime(
        widget.entry.sortTime.year,
        widget.entry.sortTime.month,
        widget.entry.sortTime.day,
      );
      final anchor = rule.anchorTime ?? widget.entry.sortTime;
      final anchorDay = DateTime(anchor.year, anchor.month, anchor.day);

      // Every recurring occurrence, including the anchor day, keeps its
      // completion state in the override. This preserves an edited time or
      // title when the user later unchecks the same occurrence.
      final originalDate =
          RecurrenceService.originalDateForOccurrence(
            rule,
            widget.entry.sortTime,
          ) ??
          (isSameDay(occurrenceDay, anchorDay)
              ? anchorDay
              : lastProjectionDay(rule, occurrenceDay, anchor));
      if (originalDate != null) {
        RecurrenceOverride? previous;
        for (final value in rule.overrides) {
          if (isSameDay(value.originalDate, originalDate)) {
            previous = value;
            break;
          }
        }
        final notifier = ref.read(reminderRuleProvider.notifier);
        if (completed) {
          final override =
              previous?.copyWith(
                isCompleted: true,
                completedAt: DateTime.now(),
              ) ??
              RecurrenceOverride(
                originalDate: originalDate,
                isCompleted: true,
                completedAt: DateTime.now(),
              );
          notifier.upsertOverride(rule.id, override);
        } else if (previous == null) {
          // Legacy anchor rows may have stored completion on the source
          // event before occurrence overrides were introduced.
          if (isSameDay(occurrenceDay, anchorDay)) {
            ref
                .read(allEntriesProvider.notifier)
                .editEntryFull(widget.entry.copyWith(isCompleted: false));
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
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(completed ? '已标记当天实例为完成' : '已恢复当天实例'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return; // recurring rows are represented by overrides, not source edits
    }

    // 非重复事件 或 锚点日重复事件：正常更新原始条目
    final updated = widget.entry.copyWith(isCompleted: completed);
    ref.read(allEntriesProvider.notifier).editEntryFull(updated);

    if (completed && !isRecurring) {
      // 非重复事件完成时归档规则（现有逻辑）
      ref
          .read(reminderRuleProvider.notifier)
          .archiveActiveRulesForCompletion('event', widget.entry.id);
    } else if (!completed && !isRecurring) {
      ref
          .read(reminderRuleProvider.notifier)
          .restoreCompletedRulesForTarget('event', widget.entry.id);
    }
  }

  Widget _actionButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 16),
      tooltip: tooltip,
      onPressed: onPressed,
      splashRadius: 14,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      color: color,
    );
  }

  void _confirmDelete(BuildContext context) {
    final content = widget.entry.aiSummary ?? widget.entry.content;
    final rule = ref
        .read(reminderRuleProvider.notifier)
        .ruleForTarget('event', widget.entry.id);
    final isRecurring =
        rule != null &&
        rule.isActive &&
        rule.scheduleType != 'once' &&
        rule.scheduleType != 'custom';

    // A projected row represents one class/session, not the source event.
    // Make the safe action explicit so a student cannot accidentally erase
    // an entire semester of recurring classes while trying to cancel today.
    if (isRecurring) {
      final originalDate =
          RecurrenceService.originalDateForOccurrence(
            rule,
            widget.entry.sortTime,
          ) ??
          DateTime(
            widget.entry.sortTime.year,
            widget.entry.sortTime.month,
            widget.entry.sortTime.day,
          );
      showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('处理重复事件'),
          content: Text('“$content”是重复安排。只处理这一次，还是删除整条安排？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'skip'),
              child: const Text('跳过本次'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'delete'),
              child: const Text(
                '删除整条',
                style: TextStyle(color: ZenTheme.statusError),
              ),
            ),
          ],
        ),
      ).then((choice) {
        if (choice == null || !context.mounted) return;
        final notifier = ref.read(reminderRuleProvider.notifier);
        if (choice == 'skip') {
          notifier.addSkipDate(rule.id, originalDate);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('已跳过本次重复事件'),
              action: SnackBarAction(
                label: '撤销',
                onPressed: () => notifier.removeSkipDate(rule.id, originalDate),
              ),
            ),
          );
          return;
        }
        notifier.archiveRulesForTarget('event', widget.entry.id);
        ref.read(allEntriesProvider.notifier).deleteEntry(widget.entry.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('重复事件已删除'),
            duration: Duration(seconds: 2),
          ),
        );
      });
      return;
    }

    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除事件'),
        content: Text('确定要删除"$content"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              '删除',
              style: TextStyle(color: ZenTheme.statusError),
            ),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed != true || !context.mounted) return;
      ref
          .read(reminderRuleProvider.notifier)
          .archiveRulesForTarget('event', widget.entry.id);
      ref.read(allEntriesProvider.notifier).deleteEntry(widget.entry.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('事件已删除'), duration: Duration(seconds: 2)),
      );
    });
  }
}

// ── 待办 section ──

class _TodoSection extends StatelessWidget {
  final List<TodoTask> deadlineTodos;
  final List<TodoTask> actionTodos;
  final List<TodoTask> completedTodos;
  final ValueChanged<UnifiedItem>? onItemTap;

  const _TodoSection({
    required this.deadlineTodos,
    required this.actionTodos,
    required this.completedTodos,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    // 已完成待办已包含在 deadlineTodos / actionTodos 中，直接合并即可
    final todos = [...deadlineTodos, ...actionTodos];
    final totalCount = todos.length;
    final deadlineIds = deadlineTodos.map((t) => t.id).toSet();

    return _SectionCard(
      title: '截止与待办',
      accentColor: ZenTheme.statusToday,
      child: totalCount == 0
          ? const _EmptyLine(text: '这一天没有需要推进的待办')
          : Column(
              children: [
                for (final todo in todos)
                  _TodoRow(
                    key: ValueKey('todo_${todo.id}'),
                    todo: todo,
                    isDeadline: deadlineIds.contains(todo.id),
                    onTap: onItemTap == null
                        ? null
                        : () =>
                              onItemTap!(unifiedTodoItem(todo, DateTime.now())),
                  ),
              ],
            ),
    );
  }
}

// ── 待办行 ──
// 编辑/删除使用 showDialog，但 provider 修改通过 Future.microtask 延迟，
// 避免 dialog route 退出期间修改被父级 watch 的 todoListProvider 触发
// _dependent.isempty 断言

class _TodoRow extends ConsumerStatefulWidget {
  final TodoTask todo;
  final bool isDeadline;
  final VoidCallback? onTap;

  const _TodoRow({
    super.key,
    required this.todo,
    required this.isDeadline,
    this.onTap,
  });

  @override
  ConsumerState<_TodoRow> createState() => _TodoRowState();
}

class _TodoRowState extends ConsumerState<_TodoRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final completed = widget.todo.isCompleted;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: ZenTheme.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(ZenTheme.radiusSm),
          hoverColor: ZenTheme.backgroundMuted,
          onTap: widget.onTap,
          onDoubleTap: completed ? null : () => _showEditDialog(context),
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ZenTheme.radiusSm),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: completed,
                    onChanged: (_) => ref
                        .read(todoListProvider.notifier)
                        .toggleTodo(widget.todo.id),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    activeColor: ZenTheme.accentMatcha,
                    checkColor: ZenTheme.contentOnAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ZenTheme.radiusXs),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: ZenTheme.textStyle(
                          fontSize: 14,
                          color: completed
                              ? ZenTheme.textCompleted
                              : ZenTheme.textBody,
                          decoration: completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        child: Text(
                          widget.todo.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!completed &&
                          (widget.isDeadline ||
                              widget.todo.scheduledAt != null)) ...[
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 4,
                          runSpacing: 3,
                          children: [
                            if (widget.todo.scheduledAt != null)
                              _buildScheduleChip(),
                            if (widget.isDeadline) _buildDeadlineChip(),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                AnimatedOpacity(
                  opacity: _isHovered ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.todo.priority.isNotEmpty)
                        _InfoChip(label: '优先级 ${widget.todo.priority}'),
                      ...widget.todo.tags.map(
                        (tag) => _InfoChip(
                          label: tag,
                          color: ZenTheme.surfaceWarm,
                          textColor: ZenTheme.interactiveBrown,
                        ),
                      ),
                      _actionButton(
                        icon: Icons.edit_outlined,
                        tooltip: '编辑',
                        color: ZenTheme.textMuted,
                        onPressed: () => _showEditDialog(context),
                      ),
                      _actionButton(
                        icon: Icons.close,
                        tooltip: '删除',
                        color: ZenTheme.textCompleted,
                        onPressed: () => _confirmDelete(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleChip() {
    final scheduledAt = widget.todo.scheduledAt!;
    final missed = shouldSurfaceMissedScheduledTodo(
      widget.todo,
      DateTime.now(),
    );
    final deadlineWarning = todoScheduleDeadlineWarning(widget.todo);
    final scheduleText = widget.todo.estimatedMinutes == null
        ? '计划 ${DateFormat('HH:mm').format(scheduledAt)}'
        : '计划 ${DateFormat('HH:mm').format(scheduledAt)}–${DateFormat('HH:mm').format(scheduledAt.add(Duration(minutes: todoPlanningMinutes(widget.todo))))}';
    return _InfoChip(
      label: missed
          ? '错过计划 · 原定 ${DateFormat('M月d日 HH:mm').format(scheduledAt)}'
          : deadlineWarning == null
          ? scheduleText
          : '$scheduleText · 来不及',
      color: missed || deadlineWarning != null
          ? ZenTheme.statusOverdueBg
          : ZenTheme.backgroundMuted,
      textColor: missed || deadlineWarning != null
          ? ZenTheme.statusOverdue
          : ZenTheme.textMuted,
    );
  }

  Widget _buildDeadlineChip() {
    final rules = ref.watch(reminderRuleProvider);
    if (isRoutineTodo(widget.todo.id, rules)) {
      return _InfoChip(
        label: '例行',
        color: ZenTheme.surfaceWarm,
        textColor: ZenTheme.textMuted,
      );
    }
    if (widget.todo.deadline != null) {
      final diff = _daysUntil(widget.todo.deadline!);
      final labelText = switch (diff) {
        < 0 => '已过期',
        0 => '今天截止',
        1 => '明天截止',
        _ => '还剩 $diff 天',
      };
      return _InfoChip(
        label: labelText,
        color: _deadlineBgColor(diff),
        textColor: _deadlineTextColor(diff),
      );
    }
    return const SizedBox.shrink();
  }

  int _daysUntil(DateTime deadline) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(deadline.year, deadline.month, deadline.day);
    return target.difference(today).inDays;
  }

  Color _deadlineBgColor(int diff) {
    if (diff < 0) return ZenTheme.statusOverdueBg;
    if (diff == 0) return ZenTheme.statusTodayBg;
    if (diff <= 3) return ZenTheme.statusUpcomingBg;
    return ZenTheme.backgroundWarm;
  }

  Color _deadlineTextColor(int diff) {
    if (diff < 0) return ZenTheme.statusOverdue;
    if (diff == 0) return ZenTheme.statusToday;
    if (diff <= 3) return ZenTheme.statusUpcoming;
    return ZenTheme.interactiveBrown;
  }

  // ── hover 操作按钮 ──

  Widget _actionButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 16),
      tooltip: tooltip,
      onPressed: onPressed,
      splashRadius: 14,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      color: color,
    );
  }

  // ── 编辑对话框 ──
  // 在 Navigator.pop 之前修改 provider，避免 dialog route 退出期间
  // 触发 Riverpod _dependent 断言

  void _showEditDialog(BuildContext ctx) {
    final controller = TextEditingController(text: widget.todo.title);
    void saveAndPop() {
      final newTitle = controller.text.trim();
      if (newTitle.isNotEmpty && newTitle != widget.todo.title) {
        ref.read(todoListProvider.notifier).editTitle(widget.todo.id, newTitle);
      }
      Navigator.pop(ctx);
    }

    showDialog<void>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('编辑待办'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '待办标题',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => saveAndPop(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(onPressed: saveAndPop, child: const Text('保存')),
        ],
      ),
    ).then((_) {
      controller.dispose();
    });
  }

  // ── 删除确认对话框 ──

  void _confirmDelete(BuildContext ctx) {
    showDialog<void>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('删除待办'),
        content: Text('确定要删除"${widget.todo.title}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(reminderRuleProvider.notifier)
                  .archiveRulesForTarget('todo', widget.todo.id);
              ref.read(todoListProvider.notifier).deleteTodo(widget.todo.id);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('待办已删除'),
                  duration: Duration(seconds: 2),
                ),
              );
              Navigator.pop(ctx);
            },
            child: const Text(
              '删除',
              style: TextStyle(color: ZenTheme.statusError),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section 卡片（参数化，含 accent 色条）──

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Color accentColor;

  const _SectionCard({
    required this.title,
    required this.child,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZenTheme.cardPadding),
      decoration: BoxDecoration(
        color: ZenTheme.backgroundCard,
        borderRadius: BorderRadius.circular(ZenTheme.radiusCard),
        border: Border.all(color: ZenTheme.borderCard),
        boxShadow: [ZenTheme.shadowCard()],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 2,
                height: 14,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: ZenTheme.spaceSm),
              Text(title, style: ZenTheme.headingSection),
            ],
          ),
          const SizedBox(height: ZenTheme.spaceMd),
          child,
        ],
      ),
    );
  }
}

// ── 小标签组件 ──

class _CountChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const _CountChip({
    required this.label,
    this.color = ZenTheme.backgroundCard,
    this.textColor = ZenTheme.interactiveBrown,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(ZenTheme.radiusSm),
        border: Border.all(color: ZenTheme.borderWarm),
      ),
      child: Text(label, style: ZenTheme.chipText),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const _InfoChip({
    required this.label,
    this.color = ZenTheme.backgroundWarm,
    this.textColor = ZenTheme.interactiveBrown,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(ZenTheme.radiusChip),
      ),
      child: Text(label, style: ZenTheme.caption),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  final String text;

  const _EmptyLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: ZenTheme.textStyle(fontSize: 13, color: ZenTheme.textMuted),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  final DateTime day;

  const _EmptyDay({required this.day});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.event_available_outlined,
            size: 48,
            color: ZenTheme.textCompleted,
          ),
          const SizedBox(height: ZenTheme.spaceLg),
          Text(
            '${DateFormat('M月d日').format(day)} 暂无安排',
            style: ZenTheme.emptyState,
          ),
          const SizedBox(height: ZenTheme.spaceSm),
          Text('今天可以保持一点余量', style: ZenTheme.emptyStateSub),
        ],
      ),
    );
  }
}
