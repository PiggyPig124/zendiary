import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/zen_theme.dart';
import '../../models/todo_task.dart';
import '../../providers/app_providers.dart';
import '../../providers/reminder_rule_provider.dart';

/// 周视图顶部 deadline 轨道组件。
///
/// 展示本周范围内有 deadline 且未完成的待办，每天最多显示 2 条，
/// 超出用 "+N" chip 折叠。
class DeadlineRail extends ConsumerWidget {
  final DateTime weekStart;
  final int maxPerDay;

  const DeadlineRail({super.key, required this.weekStart, this.maxPerDay = 2});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(todoListProvider);
    final rules = ref.watch(reminderRuleProvider);
    final weekEnd = weekStart.add(const Duration(days: 7));

    // 筛选本周有 deadline 且未完成且非例行的待办
    final weekDeadlines = todos.where((todo) {
      if (todo.isCompleted ||
          todo.deadline == null ||
          isRoutineTodo(todo.id, rules)) {
        return false;
      }
      final d = todo.deadline!;
      return !d.isBefore(weekStart) && d.isBefore(weekEnd);
    }).toList();

    if (weekDeadlines.isEmpty) return const SizedBox.shrink();

    // 按 deadline 日期分组
    final Map<int, List<TodoTask>> byDay = {};
    for (final todo in weekDeadlines) {
      final day = todo.deadline!.difference(weekStart).inDays; // 0=周一…6=周日
      byDay.putIfAbsent(day, () => []).add(todo);
    }

    const dayNames = ['一', '二', '三', '四', '五', '六', '日'];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(ZenTheme.cardPadding),
      decoration: BoxDecoration(
        color: ZenTheme.backgroundDeadlineRail,
        borderRadius: BorderRadius.circular(ZenTheme.radiusCard),
        border: Border.all(color: ZenTheme.borderDeadlineRail),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.flag_outlined,
                size: 14,
                color: ZenTheme.textMuted,
              ),
              const SizedBox(width: 6),
              const Text('本周截止', style: ZenTheme.headingSection),
              const Spacer(),
              Text('${weekDeadlines.length} 项', style: ZenTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 7,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final items = byDay[index] ?? [];
                final date = weekStart.add(Duration(days: index));
                final isToday = _isSameDay(date, DateTime.now());
                final isPast =
                    date.isBefore(DateTime.now()) &&
                    !_isSameDay(date, DateTime.now());

                return Container(
                  width: 100,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isToday
                        ? ZenTheme.backgroundToday
                        : ZenTheme.backgroundMuted,
                    borderRadius: BorderRadius.circular(ZenTheme.radiusSm),
                    border: Border.all(
                      color: isToday
                          ? ZenTheme.statusToday
                          : ZenTheme.borderCard,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '周${dayNames[index]} ${DateFormat('d日').format(date)}',
                        style: ZenTheme.textStyle(
                          fontSize: 10,
                          fontWeight: isToday
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isToday
                              ? ZenTheme.statusToday
                              : ZenTheme.textMuted,
                        ),
                      ),
                      const Spacer(),
                      if (items.isEmpty)
                        Text(
                          '—',
                          style: ZenTheme.textStyle(
                            fontSize: 11,
                            color: ZenTheme.textCompleted,
                          ),
                        )
                      else ...[
                        for (var i = 0; i < items.length && i < maxPerDay; i++)
                          Text(
                            items[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ZenTheme.textStyle(
                              fontSize: 10,
                              color: isPast
                                  ? ZenTheme.textCompleted
                                  : ZenTheme.statusDeadlineStrong,
                              decoration: isPast
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        if (items.length > maxPerDay)
                          Text(
                            '+${items.length - maxPerDay}',
                            style: ZenTheme.textStyle(
                              fontSize: 10,
                              color: ZenTheme.textCompleted,
                            ),
                          ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
