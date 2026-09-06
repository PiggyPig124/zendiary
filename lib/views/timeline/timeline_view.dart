import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/zen_theme.dart';
import '../../models/diary_entry.dart';
import '../../models/recurrence_override.dart';
import '../../models/reminder_rule.dart';
import '../../providers/app_providers.dart';
import '../../providers/reminder_rule_provider.dart';
import '../../services/recurrence_service.dart';
import '../common/multi_select_bar.dart';
import 'day_view.dart';
import 'month_view.dart';
import 'timeline_data.dart';
import 'timeline_shared.dart';
import 'week_view.dart';

class TimelineView extends ConsumerStatefulWidget {
  const TimelineView({super.key});

  @override
  ConsumerState<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends ConsumerState<TimelineView> {
  final Set<String> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(timelineViewModeProvider);
    final selectedDay = ref.watch(selectedDayProvider);
    final weekStart = startOfWeek(selectedDay);
    final monthStart = DateTime(selectedDay.year, selectedDay.month);
    final allEvents = ref.watch(timelineEntriesProvider);
    final rangeEvents = _eventsInRange(allEvents, mode, selectedDay);
    final isSelecting = _selectedIds.isNotEmpty;

    return Column(
      children: [
        _TopBar(
          mode: mode,
          selectedDay: selectedDay,
          canSelect: rangeEvents.isNotEmpty,
          isSelecting: isSelecting,
          selectedCount: _selectedIds.length,
          totalCount: rangeEvents.length,
          onToggleSelectMode: () => _toggleSelectMode(rangeEvents),
        ),
        const Divider(height: 1, thickness: 0.5),
        Expanded(
          child: isSelecting
              ? ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  itemCount: rangeEvents.length,
                  itemBuilder: (context, index) => _TimelineEventTile(
                    entry: rangeEvents[index],
                    isSelecting: true,
                    isSelected: _selectedIds.contains(rangeEvents[index].id),
                    onToggleSelected: () =>
                        _toggleSelection(rangeEvents[index].id),
                  ),
                )
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeInOut,
                  switchOutCurve: Curves.easeInOut,
                  child: _buildModeView(
                    mode,
                    selectedDay,
                    weekStart,
                    monthStart,
                  ),
                ),
        ),
        if (isSelecting)
          AnimatedSlide(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            offset: const Offset(0, 0),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: 1.0,
              child: MultiSelectBar(
                count: _selectedIds.length,
                onCancel: () => setState(_selectedIds.clear),
                actions: [
                  TextButton.icon(
                    icon: const Icon(Icons.event_available_outlined, size: 16),
                    label: const Text('批量改期'),
                    onPressed: () => _bulkReschedule(rangeEvents),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('转待办'),
                    onPressed: () => _bulkAddToTodo(rangeEvents),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('删除'),
                    onPressed: _bulkDelete,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildModeView(
    TimelineViewMode mode,
    DateTime selectedDay,
    DateTime weekStart,
    DateTime monthStart,
  ) {
    return switch (mode) {
      TimelineViewMode.day => DayView(
        key: const ValueKey('day'),
        day: selectedDay,
      ),
      TimelineViewMode.week => WeekView(
        key: const ValueKey('week'),
        weekStart: weekStart,
        focusDay: selectedDay,
      ),
      TimelineViewMode.month => MonthView(
        key: const ValueKey('month'),
        monthStart: monthStart,
      ),
    };
  }

  List<DiaryEntry> _eventsInRange(
    List<DiaryEntry> events,
    TimelineViewMode mode,
    DateTime selectedDay,
  ) {
    final weekStart = startOfWeek(selectedDay);
    final weekEnd = weekStart.add(const Duration(days: 7));
    return switch (mode) {
      TimelineViewMode.day =>
        events
            .where((entry) => isSameDay(entry.sortTime, selectedDay))
            .toList(),
      TimelineViewMode.week =>
        events
            .where(
              (entry) =>
                  !entry.sortTime.isBefore(weekStart) &&
                  entry.sortTime.isBefore(weekEnd),
            )
            .toList(),
      TimelineViewMode.month =>
        events
            .where(
              (entry) =>
                  entry.sortTime.year == selectedDay.year &&
                  entry.sortTime.month == selectedDay.month,
            )
            .toList(),
    };
  }

  void _toggleSelectMode(List<DiaryEntry> events) {
    setState(() {
      if (_selectedIds.isEmpty) {
        _selectedIds.add(events.first.id);
      } else if (_selectedIds.length == events.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(events.map((entry) => entry.id));
      }
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  void _bulkAddToTodo(List<DiaryEntry> events) {
    final selected = events.where((entry) => _selectedIds.contains(entry.id));
    final todoNotifier = ref.read(todoListProvider.notifier);
    for (final entry in selected) {
      todoNotifier.addTodo(
        entry.aiSummary ?? entry.content,
        sourceEntryId: entry.id,
      );
    }
    final count = _selectedIds.length;
    setState(_selectedIds.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已添加 $count 条到待办'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _bulkReschedule(List<DiaryEntry> events) async {
    final selected = events
        .where((entry) => _selectedIds.contains(entry.id))
        .where((entry) => entry.eventTime != null)
        .toList();
    if (selected.isEmpty) return;

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
    if (picked == null || !mounted) return;

    final targetDay = DateTime(picked.year, picked.month, picked.day);
    final ruleNotifier = ref.read(reminderRuleProvider.notifier);
    final previousEntries = <String, DiaryEntry>{};
    final previousRules = <String, ReminderRule?>{};
    final previousOverrides = <String, RecurrenceOverride?>{};
    final recurringDates = <String, DateTime>{};
    var changed = 0;

    for (final event in selected) {
      final start = event.eventTime!;
      final movedStart = DateTime(
        targetDay.year,
        targetDay.month,
        targetDay.day,
        start.hour,
        start.minute,
        start.second,
      );
      final rule = ruleNotifier.ruleForTarget('event', event.id);
      final isRecurring =
          rule != null &&
          rule.isActive &&
          rule.scheduleType != 'once' &&
          rule.scheduleType != 'custom';
      if (isRecurring) {
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
        recurringDates[event.id] = originalDate;
        previousOverrides[event.id] = previous;
        ruleNotifier.updateOccurrence(
          rule.id,
          originalDate,
          newTime: movedStart,
          newDurationMinutes: event.durationMinutes,
          clearNewDurationMinutes: event.durationMinutes == null,
        );
      } else {
        previousEntries[event.id] = event;
        previousRules[event.id] = rule;
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
    setState(_selectedIds.clear);
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
            for (final entry in previousEntries.values) {
              diaryNotifier.editEntryFull(entry);
              final previousRule = previousRules[entry.id];
              if (previousRule != null) {
                ruleNotifier.upsertRuleForTarget(previousRule);
              }
            }
            for (final entry in recurringDates.entries) {
              final previous = previousOverrides[entry.key];
              final rule = ruleNotifier.ruleForTarget('event', entry.key);
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

  void _bulkDelete() {
    final count = _selectedIds.length;
    final reminderNotifier = ref.read(reminderRuleProvider.notifier);
    for (final id in _selectedIds) {
      reminderNotifier.archiveRulesForTarget('event', id);
    }
    ref.read(allEntriesProvider.notifier).deleteEntries(_selectedIds);
    setState(_selectedIds.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除 $count 条时间线事件'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ── TopBar ──

class _TopBar extends ConsumerWidget {
  final TimelineViewMode mode;
  final DateTime selectedDay;
  final bool canSelect;
  final bool isSelecting;
  final int selectedCount;
  final int totalCount;
  final VoidCallback onToggleSelectMode;

  const _TopBar({
    required this.mode,
    required this.selectedDay,
    required this.canSelect,
    required this.isSelecting,
    required this.selectedCount,
    required this.totalCount,
    required this.onToggleSelectMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = _title();
    final subtitle = _subtitle();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ZenTheme.backgroundCanvas,
            ZenTheme.backgroundWarm.withValues(alpha: 0.1),
          ],
        ),
        border: const Border(bottom: BorderSide(color: ZenTheme.borderCard)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZenTheme.headingPage,
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZenTheme.labelMedium,
                ),
              ],
            ),
          ),
          Flexible(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    tooltip: '手动添加事件',
                    hoverColor: ZenTheme.interactivePressed,
                    onPressed: () => _showCreateEventDialog(context, ref),
                  ),
                  IconButton(
                    icon: Icon(
                      isSelecting ? Icons.select_all : Icons.checklist,
                      size: 20,
                    ),
                    tooltip: isSelecting && selectedCount != totalCount
                        ? '全选'
                        : '多选',
                    hoverColor: ZenTheme.interactivePressed,
                    onPressed: canSelect ? onToggleSelectMode : null,
                  ),
                  SegmentedButton<TimelineViewMode>(
                    segments: const [
                      ButtonSegment(
                        value: TimelineViewMode.day,
                        label: Text('日'),
                      ),
                      ButtonSegment(
                        value: TimelineViewMode.week,
                        label: Text('周'),
                      ),
                      ButtonSegment(
                        value: TimelineViewMode.month,
                        label: Text('月'),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (value) {
                      ref
                          .read(timelineViewModeProvider.notifier)
                          .set(value.first);
                    },
                    style: SegmentedButton.styleFrom(
                      foregroundColor: ZenTheme.interactiveBrown,
                      selectedForegroundColor: ZenTheme.contentOnAccent,
                      selectedBackgroundColor: ZenTheme.interactiveBrown,
                      backgroundColor: ZenTheme.backgroundWarm,
                      animationDuration: const Duration(milliseconds: 200),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 18),
                    tooltip: _previousTooltip(),
                    hoverColor: ZenTheme.interactivePressed,
                    onPressed: () => _move(ref, -1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 18),
                    tooltip: _nextTooltip(),
                    hoverColor: ZenTheme.interactivePressed,
                    onPressed: () => _move(ref, 1),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      ref
                          .read(selectedDayProvider.notifier)
                          .set(DateTime.now());
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ZenTheme.interactiveBrown,
                      side: const BorderSide(color: ZenTheme.borderButton),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZenTheme.radiusSm),
                      ),
                    ),
                    child: const Text('今天'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _title() {
    final weekStart = startOfWeek(selectedDay);
    final weekEnd = weekStart.add(const Duration(days: 6));
    return switch (mode) {
      TimelineViewMode.day => DateFormat(
        'M月d日 EEEE',
        'zh_CN',
      ).format(selectedDay),
      TimelineViewMode.week =>
        '${DateFormat('M月d日').format(weekStart)} - ${DateFormat('M月d日').format(weekEnd)}',
      TimelineViewMode.month => DateFormat('yyyy年M月').format(selectedDay),
    };
  }

  String _subtitle() {
    return switch (mode) {
      TimelineViewMode.day => _relativeDay(selectedDay),
      TimelineViewMode.week => _relativeWeek(startOfWeek(selectedDay)),
      TimelineViewMode.month => '低压力未来地图',
    };
  }

  String _previousTooltip() {
    return switch (mode) {
      TimelineViewMode.day => '前一天',
      TimelineViewMode.week => '上一周',
      TimelineViewMode.month => '上个月',
    };
  }

  String _nextTooltip() {
    return switch (mode) {
      TimelineViewMode.day => '后一天',
      TimelineViewMode.week => '下一周',
      TimelineViewMode.month => '下个月',
    };
  }

  void _move(WidgetRef ref, int direction) {
    final day = ref.read(selectedDayProvider);
    final next = switch (mode) {
      TimelineViewMode.day => day.add(Duration(days: direction)),
      TimelineViewMode.week => day.add(Duration(days: 7 * direction)),
      TimelineViewMode.month => DateTime(day.year, day.month + direction, 1),
    };
    ref.read(selectedDayProvider.notifier).set(next);
  }

  String _relativeDay(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(day.year, day.month, day.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '明天';
    if (diff == -1) return '昨天';
    if (diff > 0) return '$diff 天后';
    return '${-diff} 天前';
  }

  String _relativeWeek(DateTime weekStart) {
    final now = DateTime.now();
    final thisWeekStart = startOfWeek(now);
    final diff = weekStart.difference(thisWeekStart).inDays;
    if (diff == 0) return '本周';
    if (diff == 7) return '下周';
    if (diff == -7) return '上周';
    if (diff > 0) return '${diff ~/ 7 + 1} 周后';
    return '${(-diff) ~/ 7 + 1} 周前';
  }

  Future<void> _showCreateEventDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final day = ref.read(selectedDayProvider);
    final baseTime = DateTime(
      day.year,
      day.month,
      day.day,
      TimeOfDay.now().hour,
      TimeOfDay.now().minute,
    );
    final data = await showDialog<TimelineEventFormData>(
      context: context,
      builder: (_) => TimelineEventDialog(
        initialTime: baseTime,
        initialReminder: ReminderFormData.defaults(),
      ),
    );
    if (data == null) return;
    final entry = ref
        .read(allEntriesProvider.notifier)
        .addEvent(
          data.content,
          data.eventTime,
          location: data.location,
          durationMinutes: data.durationMinutes,
        );
    if (entry != null) {
      syncEventReminderRule(ref, entry, data.reminder);
    }
    ref.read(selectedDayProvider.notifier).set(data.eventTime);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已添加到时间线'), duration: Duration(seconds: 2)),
    );
  }
}

// ── 多选模式事件卡片 ──

class _TimelineEventTile extends ConsumerWidget {
  final DiaryEntry entry;
  final bool isSelecting;
  final bool isSelected;
  final VoidCallback onToggleSelected;

  const _TimelineEventTile({
    required this.entry,
    required this.isSelecting,
    required this.isSelected,
    required this.onToggleSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: isSelecting ? onToggleSelected : null,
      onLongPress: onToggleSelected,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
        decoration: BoxDecoration(
          color: isSelected
              ? ZenTheme.backgroundMuted
              : ZenTheme.backgroundCard,
          borderRadius: BorderRadius.circular(ZenTheme.radiusCard),
          border: Border.all(color: ZenTheme.borderCard),
          boxShadow: [ZenTheme.shadowSubtle()],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isSelecting) ...[
              Checkbox(
                value: isSelected,
                onChanged: (_) => onToggleSelected(),
                activeColor: ZenTheme.interactiveBrown,
              ),
              const SizedBox(width: 6),
            ],
            SizedBox(
              width: 56,
              child: Text(
                DateFormat('HH:mm').format(entry.sortTime),
                style: ZenTheme.textStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: ZenTheme.textMuted,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry.location != null && entry.location!.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 12,
                          color: ZenTheme.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            entry.location!,
                            overflow: TextOverflow.ellipsis,
                            style: ZenTheme.labelSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    entry.aiSummary ?? entry.content,
                    style: ZenTheme.textStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: ZenTheme.textHeading,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
