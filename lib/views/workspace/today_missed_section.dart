import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/zen_theme.dart';
import '../../models/todo_task.dart';
import '../../services/planner_service.dart';

/// Gives a missed explicit plan a small, reversible set of next actions.
class TodayMissedSection extends StatelessWidget {
  final List<TodoTask> todos;
  final DateTime now;
  final ValueChanged<TodoTask> onTap;
  final ValueChanged<TodoTask> onComplete;
  final ValueChanged<TodoTask> onReschedule;
  final ValueChanged<TodoTask> onUnschedule;

  const TodayMissedSection({
    super.key,
    required this.todos,
    required this.now,
    required this.onTap,
    required this.onComplete,
    required this.onReschedule,
    required this.onUnschedule,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.history_toggle_off_outlined,
                  size: 19,
                  color: ZenTheme.statusOverdue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '安排已过，尚未完成 (${todos.length})',
                    style: ZenTheme.labelMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text('没做完也没关系，重新安排或先保留为待办。'),
            const SizedBox(height: 4),
            ...todos.map(_item),
          ],
        ),
      ),
    );
  }

  Widget _item(TodoTask todo) {
    final scheduledAt = todo.scheduledAt!;
    final endAt = scheduledAt.add(Duration(minutes: todoPlanningMinutes(todo)));
    String formatOriginalTime(DateTime value) {
      final pattern = value.year == now.year ? 'M月d日 HH:mm' : 'yyyy年M月d日 HH:mm';
      return DateFormat(pattern).format(value);
    }

    final originalTime =
        '原定 ${formatOriginalTime(scheduledAt)}–${formatOriginalTime(endAt)}';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            leading: const Icon(
              Icons.check_box_outline_blank,
              size: 18,
              color: ZenTheme.textMuted,
            ),
            title: Text(
              todo.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ZenTheme.textStyle(fontSize: 14),
            ),
            subtitle: Text(originalTime, style: ZenTheme.labelSmall),
            onTap: () => onTap(todo),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 2,
            runSpacing: 0,
            children: [
              TextButton.icon(
                onPressed: () => onComplete(todo),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                ),
                icon: const Icon(Icons.check, size: 17),
                label: const Text('完成'),
              ),
              TextButton.icon(
                onPressed: () => onReschedule(todo),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                ),
                icon: const Icon(Icons.event_available_outlined, size: 17),
                label: const Text('调整时间'),
              ),
              TextButton(
                onPressed: () => onUnschedule(todo),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                ),
                child: const Text('暂不安排'),
              ),
            ],
          ),
          if (todo != todos.last)
            const Divider(height: 12, color: ZenTheme.borderSubtle),
        ],
      ),
    );
  }
}
