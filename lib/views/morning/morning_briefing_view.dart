import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/zen_theme.dart';
import '../../models/diary_entry.dart';
import '../../models/pending_action_preview.dart';
import '../../models/reminder_rule.dart';
import '../../models/todo_task.dart';
import '../../providers/app_providers.dart';
import '../../providers/reminder_rule_provider.dart';
import '../common/page_header.dart';
import '../main_layout.dart';
import '../timeline/timeline_shared.dart';

class MorningBriefingView extends ConsumerStatefulWidget {
  const MorningBriefingView({super.key});

  @override
  ConsumerState<MorningBriefingView> createState() =>
      _MorningBriefingViewState();
}

class _MorningBriefingViewState extends ConsumerState<MorningBriefingView> {
  final Map<_BriefingSectionKey, bool> _expanded = {
    _BriefingSectionKey.events: true,
    _BriefingSectionKey.important: true,
    _BriefingSectionKey.overdue: false,
    _BriefingSectionKey.ordinary: false,
    _BriefingSectionKey.small: false,
    _BriefingSectionKey.rules: false,
  };

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));

    final events = ref.watch(timelineEntriesProvider).where((entry) {
      final time = entry.sortTime;
      return !time.isBefore(todayStart) && time.isBefore(tomorrowStart);
    }).toList();

    final todos = ref.watch(todoListProvider);
    final pendingTodos = todos.where((todo) => !todo.isCompleted).toList();
    final rules = ref.watch(reminderRuleProvider);
    final overdueTodos = pendingTodos
        .where(
          (todo) =>
              todo.deadline != null &&
              todo.deadline!.isBefore(now) &&
              !isRoutineTodo(todo.id, rules),
        )
        .toList();
    final importantTodos = pendingTodos
        .where((todo) => todo.priority == 'A')
        .toList();
    final smallTodos = pendingTodos.where(_isSmallTask).toList();
    final ordinaryTodos = pendingTodos
        .where((todo) => todo.priority != 'A' && !_isSmallTask(todo))
        .toList();

    final completedTodos = todos.where((todo) => todo.isCompleted).toList();
    final completedImportantCount = completedTodos
        .where((t) => t.priority == 'A')
        .length;
    final completedOverdueCount = completedTodos
        .where(
          (t) =>
              t.deadline != null &&
              t.deadline!.isBefore(now) &&
              !isRoutineTodo(t.id, rules),
        )
        .length;
    final completedOrdinaryCount = completedTodos
        .where((t) => t.priority != 'A' && !_isSmallTask(t))
        .length;

    final activeRules = ref.watch(activeReminderRulesProvider);
    final strongRules = activeRules.where((rule) => rule.isStrong).toList();
    final lowLoadStatus = ref.watch(lowLoadStatusProvider);

    final focusCount =
        events.length + importantTodos.length + overdueTodos.length;

    return Column(
      children: [
        PageHeader(
          title: '早报',
          trailing: _BriefingCountBadge(count: focusCount),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              ZenTheme.pagePaddingHorizontal,
              20,
              ZenTheme.pagePaddingHorizontal,
              ZenTheme.listBottomPadding,
            ),
            children: [
              _GreetingCard(now: now, lowLoadStatus: lowLoadStatus),
              const SizedBox(height: ZenTheme.spaceXxl),
              if (focusCount > 0) ...[
                _FocusCard(
                  events: events,
                  importantTodos: importantTodos,
                  overdueTodos: overdueTodos,
                  onNavigateTimeline: () => ref
                      .read(navIndexProvider.notifier)
                      .setIndex(navIndexTimeline),
                  onNavigateTodo: () => ref
                      .read(navIndexProvider.notifier)
                      .setIndex(navIndexTodo),
                ),
                const SizedBox(height: ZenTheme.sectionGap),
              ],
              // ── 可折叠的详细安排 ──
              _CollapsibleSection(
                sectionKey: _BriefingSectionKey.events,
                title: '固定时间事件',
                icon: Icons.event_note_outlined,
                accentColor: ZenTheme.accentMatcha,
                count: events.length,
                expanded: _expanded[_BriefingSectionKey.events]!,
                onToggle: () => _toggleSection(_BriefingSectionKey.events),
                completedCount: 0,
                children: events
                    .map(
                      (event) => _BriefingLine(
                        leading: DateFormat('HH:mm').format(event.sortTime),
                        leadingColor: ZenTheme.accentMatcha,
                        title: event.aiSummary ?? event.content,
                        subtitle: event.location,
                        onTap: () {
                          ref
                              .read(selectedDayProvider.notifier)
                              .set(event.sortTime);
                          ref
                              .read(navIndexProvider.notifier)
                              .setIndex(navIndexTimeline);
                        },
                      ),
                    )
                    .toList(),
              ),
              _CollapsibleSection(
                sectionKey: _BriefingSectionKey.important,
                title: '重要待办',
                icon: Icons.priority_high_outlined,
                accentColor: ZenTheme.statusOverdue,
                count: importantTodos.length,
                expanded: _expanded[_BriefingSectionKey.important]!,
                onToggle: () => _toggleSection(_BriefingSectionKey.important),
                completedCount: completedImportantCount,
                children: importantTodos
                    .map(
                      (todo) => _BriefingLine(
                        leading: todo.priority,
                        title: todo.title,
                        subtitle: _todoSubtitle(todo),
                        onTap: () => ref
                            .read(navIndexProvider.notifier)
                            .setIndex(navIndexTodo),
                      ),
                    )
                    .toList(),
              ),
              _CollapsibleSection(
                sectionKey: _BriefingSectionKey.overdue,
                title: '已过期截止',
                icon: Icons.warning_amber_outlined,
                accentColor: ZenTheme.statusToday,
                count: overdueTodos.length,
                expanded: _expanded[_BriefingSectionKey.overdue]!,
                onToggle: () => _toggleSection(_BriefingSectionKey.overdue),
                completedCount: completedOverdueCount,
                children: overdueTodos
                    .map(
                      (todo) => _BriefingLine(
                        leading: '过期',
                        leadingBgColor: ZenTheme.statusOverdueBg,
                        leadingTextColor: ZenTheme.statusOverdue,
                        title: todo.title,
                        subtitle: _todoSubtitle(todo),
                        onTap: () => ref
                            .read(navIndexProvider.notifier)
                            .setIndex(navIndexTodo),
                      ),
                    )
                    .toList(),
              ),
              _CollapsibleSection(
                sectionKey: _BriefingSectionKey.ordinary,
                title: '普通事项',
                icon: Icons.list_alt_outlined,
                accentColor: ZenTheme.accentMatcha.withValues(alpha: 0.7),
                count: ordinaryTodos.length,
                expanded: _expanded[_BriefingSectionKey.ordinary]!,
                onToggle: () => _toggleSection(_BriefingSectionKey.ordinary),
                completedCount: completedOrdinaryCount,
                children: ordinaryTodos
                    .map(
                      (todo) => _BriefingLine(
                        leading: todo.priority.isEmpty ? '普' : todo.priority,
                        title: todo.title,
                        subtitle: _todoSubtitle(todo),
                        onTap: () => ref
                            .read(navIndexProvider.notifier)
                            .setIndex(navIndexTodo),
                      ),
                    )
                    .toList(),
              ),
              _CollapsibleSection(
                sectionKey: _BriefingSectionKey.small,
                title: '小事/杂事池',
                icon: Icons.spa_outlined,
                accentColor: ZenTheme.textCompleted,
                count: smallTodos.length,
                expanded: _expanded[_BriefingSectionKey.small]!,
                onToggle: () => _toggleSection(_BriefingSectionKey.small),
                completedCount: 0,
                children: smallTodos
                    .map(
                      (todo) => _BriefingLine(
                        leading: '小事',
                        title: todo.title,
                        subtitle: _smallTaskReason(todo),
                        onTap: () => ref
                            .read(navIndexProvider.notifier)
                            .setIndex(navIndexTodo),
                      ),
                    )
                    .toList(),
              ),
              _CollapsibleSection(
                sectionKey: _BriefingSectionKey.rules,
                title: '强提醒规则',
                icon: Icons.notifications_active_outlined,
                accentColor: ZenTheme.accentMatcha,
                count: strongRules.length,
                expanded: _expanded[_BriefingSectionKey.rules]!,
                onToggle: () => _toggleSection(_BriefingSectionKey.rules),
                completedCount: 0,
                children: strongRules
                    .map(
                      (rule) => _BriefingLine(
                        leading: _importanceLabel(rule.importance),
                        title: rule.title,
                        subtitle: _ruleSubtitle(rule),
                        onTap: () => ref
                            .read(navIndexProvider.notifier)
                            .setIndex(navIndexReminder),
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

  void _toggleSection(_BriefingSectionKey key) {
    setState(() {
      _expanded[key] = !(_expanded[key] ?? false);
    });
  }

  static bool _isSmallTask(TodoTask todo) {
    return _smallTaskReason(todo) != null;
  }

  static String? _smallTaskReason(TodoTask todo) {
    if (todo.priority == 'C') return '优先级: C';
    for (final tag in todo.tags) {
      final lower = tag.toLowerCase();
      if (lower == 'game' || lower == '游戏') return '分类: 游戏';
      if (lower == 'misc' || lower == '杂事') return '分类: 杂事';
      if (lower == 'low_energy' || lower == '低能量任务') return '分类: 低能量任务';
    }
    return null;
  }

  static String? _todoSubtitle(TodoTask todo) {
    final parts = <String>[];
    final reason = _smallTaskReason(todo);
    if (reason != null) parts.add(reason);
    if (todo.category != 'general') parts.add(todo.category);
    if (todo.deadline != null) {
      parts.add('截止 ${DateFormat('MM-dd').format(todo.deadline!)}');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _importanceLabel(String value) {
    return switch (value) {
      'important' => '重',
      'minor' => '轻',
      _ => '普',
    };
  }

  static String? _ruleSubtitle(ReminderRule rule) {
    final parts = <String>[rule.category, rule.scheduleType];
    if (rule.advanceMinutes.isNotEmpty) {
      parts.add('提前 ${rule.advanceMinutes.join('/')} 分钟');
    }
    return parts.join(' · ');
  }
}

enum _BriefingSectionKey { events, important, overdue, ordinary, small, rules }

// ── 关注点数 pill ──

class _BriefingCountBadge extends StatelessWidget {
  final int count;

  const _BriefingCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: ZenTheme.accentMatcha.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ZenTheme.radiusFull),
      ),
      child: Text(
        '$count 个关注点',
        style: ZenTheme.textStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: ZenTheme.accentMatcha,
        ),
      ),
    );
  }
}

// ── 问候卡片 ──

class _GreetingCard extends StatelessWidget {
  final DateTime now;
  final LowLoadStatus? lowLoadStatus;

  const _GreetingCard({required this.now, this.lowLoadStatus});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('M月d日', 'zh_CN').format(now),
            style: ZenTheme.textStyle(
              fontSize: 28,
              fontWeight: FontWeight.w300,
              color: ZenTheme.textHeading,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _weekday(now),
            style: ZenTheme.textStyle(fontSize: 14, color: ZenTheme.textMuted),
          ),
          const SizedBox(height: 8),
          Text(
            '今天有需要关注的事，普通小事会安静待在下方',
            style: ZenTheme.textStyle(
              fontSize: 13,
              color: ZenTheme.textCompleted,
            ),
          ),
          if (lowLoadStatus != null && lowLoadStatus!.active) ...[
            const SizedBox(height: 10),
            _LowLoadPill(status: lowLoadStatus!),
          ],
        ],
      ),
    );
  }

  static String _weekday(DateTime value) {
    const names = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return names[value.weekday - 1];
  }
}

// ── 低负荷 pill ──

class _LowLoadPill extends StatelessWidget {
  final LowLoadStatus status;

  const _LowLoadPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final until = status.until == null
        ? null
        : DateFormat('MM月dd日').format(status.until!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: ZenTheme.statusSuccessBg,
        borderRadius: BorderRadius.circular(ZenTheme.radiusFull),
        border: Border.all(color: ZenTheme.statusSuccessBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.self_improvement_outlined,
            size: 14,
            color: ZenTheme.statusSuccess,
          ),
          const SizedBox(width: 6),
          Text(
            ['低负荷安排中', if (until != null) '持续到 $until'].join(' · '),
            style: const TextStyle(
              fontSize: 12,
              color: ZenTheme.statusSuccessStrong,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Focus Card：今日核心关注 ──

class _FocusCard extends StatelessWidget {
  final List<DiaryEntry> events;
  final List<TodoTask> importantTodos;
  final List<TodoTask> overdueTodos;
  final VoidCallback onNavigateTimeline;
  final VoidCallback onNavigateTodo;

  const _FocusCard({
    required this.events,
    required this.importantTodos,
    required this.overdueTodos,
    required this.onNavigateTimeline,
    required this.onNavigateTodo,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    for (final event in events) {
      items.add(
        _FocusItem(
          leading: DateFormat('HH:mm').format(event.sortTime),
          leadingColor: ZenTheme.accentMatcha,
          title: event.aiSummary ?? event.content,
          subtitle: event.location,
          onTap: onNavigateTimeline,
        ),
      );
    }

    for (final todo in importantTodos) {
      items.add(
        _FocusItem(
          leading: 'A',
          leadingColor: ZenTheme.statusOverdue,
          title: todo.title,
          subtitle: todo.deadline != null
              ? '截止 ${DateFormat('MM-dd').format(todo.deadline!)}'
              : null,
          onTap: onNavigateTodo,
        ),
      );
    }

    for (final todo in overdueTodos) {
      items.add(
        _FocusItem(
          leading: '过期',
          leadingBgColor: ZenTheme.statusOverdueBg,
          leadingTextColor: ZenTheme.statusOverdue,
          title: todo.title,
          subtitle: todo.deadline != null
              ? '截止 ${DateFormat('MM-dd').format(todo.deadline!)}'
              : null,
          onTap: onNavigateTodo,
        ),
      );
    }

    final maxVisible = 6;
    final visible = items.take(maxVisible).toList();
    final overflow = items.length - maxVisible;

    return Container(
      padding: const EdgeInsets.all(ZenTheme.cardPadding),
      decoration: BoxDecoration(
        color: ZenTheme.backgroundCard,
        borderRadius: BorderRadius.circular(ZenTheme.radiusCard),
        border: Border.all(color: ZenTheme.borderCard),
        boxShadow: [ZenTheme.shadowSubtle()],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 2,
                height: 16,
                decoration: BoxDecoration(
                  color: ZenTheme.accentMatcha,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: 8),
              Text('今日关注', style: ZenTheme.headingZen),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('今天可以保持一点余量', style: ZenTheme.emptyState),
            )
          else ...[
            ...visible,
            if (overflow > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '下方还有 $overflow 项完整安排',
                  style: ZenTheme.textStyle(
                    fontSize: 12,
                    color: ZenTheme.textMuted,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Focus Item 行 ──

class _FocusItem extends StatelessWidget {
  final String leading;
  final Color? leadingColor;
  final Color? leadingBgColor;
  final Color? leadingTextColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _FocusItem({
    required this.leading,
    this.leadingColor,
    this.leadingBgColor,
    this.leadingTextColor,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = leadingBgColor ?? ZenTheme.backgroundWarm;
    final textColor =
        leadingTextColor ?? leadingColor ?? ZenTheme.interactiveBrown;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZenTheme.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 40),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(ZenTheme.radiusSm),
                ),
                child: Text(
                  leading,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: ZenTheme.textStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ZenTheme.textStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: ZenTheme.textHeading,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZenTheme.textStyle(
                          fontSize: 12,
                          color: ZenTheme.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 可折叠 Section ──

class _CollapsibleSection extends StatelessWidget {
  final _BriefingSectionKey sectionKey;
  final String title;
  final IconData icon;
  final Color accentColor;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;
  final int completedCount;
  final List<Widget> children;

  const _CollapsibleSection({
    required this.sectionKey,
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.count,
    required this.expanded,
    required this.onToggle,
    this.completedCount = 0,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final hasContent = children.isNotEmpty || completedCount > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: ZenTheme.backgroundMuted,
          borderRadius: BorderRadius.circular(ZenTheme.radiusCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(ZenTheme.radiusCard),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  ZenTheme.cardPadding,
                  10,
                  ZenTheme.cardPadding - 4,
                  10,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: accentColor),
                    const SizedBox(width: 8),
                    Text(title, style: ZenTheme.headingSection),
                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '$count',
                        style: ZenTheme.textStyle(
                          fontSize: 12,
                          color: accentColor,
                        ),
                      ),
                    ],
                    if (completedCount > 0) ...[
                      const SizedBox(width: 4),
                      Text('✓$completedCount', style: ZenTheme.labelSmall),
                    ],
                    if (!hasContent) ...[
                      const SizedBox(width: 6),
                      Text(
                        '暂无',
                        style: ZenTheme.textStyle(
                          fontSize: 12,
                          color: ZenTheme.textCompleted,
                        ),
                      ),
                    ],
                    const Spacer(),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_less,
                        size: 18,
                        color: ZenTheme.textMuted,
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
              child: expanded && hasContent
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(
                        ZenTheme.cardPadding,
                        0,
                        ZenTheme.cardPadding,
                        10,
                      ),
                      child: Column(children: children),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Briefing 列表行 ──

class _BriefingLine extends StatelessWidget {
  final String leading;
  final Color? leadingColor;
  final Color? leadingBgColor;
  final Color? leadingTextColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _BriefingLine({
    required this.leading,
    this.leadingColor,
    this.leadingBgColor,
    this.leadingTextColor,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = leadingBgColor ?? ZenTheme.backgroundCard;
    final textColor =
        leadingTextColor ?? leadingColor ?? ZenTheme.interactiveBrown;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZenTheme.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(ZenTheme.radiusSm),
                ),
                child: Text(
                  leading,
                  textAlign: TextAlign.center,
                  style: ZenTheme.textStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ZenTheme.textStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: ZenTheme.textHeading,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZenTheme.textStyle(
                          fontSize: 12,
                          color: ZenTheme.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
