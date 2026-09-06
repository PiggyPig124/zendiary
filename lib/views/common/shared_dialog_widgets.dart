import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/zen_theme.dart';

/// 星期多选 chip 行，用于选择重复提醒的生效星期。
///
/// 在所有提醒/例行编辑对话框中复用（替代各文件中重复的 _weekdayPicker）。
class WeekdayPicker extends StatelessWidget {
  final Set<int> selectedDays;
  final ValueChanged<Set<int>> onChanged;

  const WeekdayPicker({
    super.key,
    required this.selectedDays,
    required this.onChanged,
  });

  static const _days = [
    (1, '一'),
    (2, '二'),
    (3, '三'),
    (4, '四'),
    (5, '五'),
    (6, '六'),
    (7, '日'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 54,
          child: Text(
            '星期',
            style: TextStyle(fontSize: 13, color: ZenTheme.interactiveBrown),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final day in _days)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(day.$2, style: const TextStyle(fontSize: 13)),
                      selected: selectedDays.contains(day.$1),
                      onSelected: (sel) {
                        final updated = Set<int>.from(selectedDays);
                        if (sel) {
                          updated.add(day.$1);
                        } else {
                          updated.remove(day.$1);
                        }
                        if (updated.isEmpty) updated.add(day.$1);
                        onChanged(updated);
                      },
                      selectedColor: ZenTheme.interactiveBrown,
                      labelStyle: TextStyle(
                        color: selectedDays.contains(day.$1)
                            ? ZenTheme.contentOnAccent
                            : ZenTheme.interactiveBrown,
                      ),
                      showCheckmark: false,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 截止日期选择行，用于设置重复提醒的结束日期。
///
/// 在所有提醒/例行编辑对话框中复用（替代各文件中重复的 _endDatePicker）。
class EndDatePickerRow extends StatelessWidget {
  final DateTime? endDate;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const EndDatePickerRow({
    super.key,
    required this.endDate,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 54,
          child: Text(
            '截止',
            style: TextStyle(fontSize: 13, color: ZenTheme.interactiveBrown),
          ),
        ),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(
              endDate != null
                  ? DateFormat('yyyy-MM-dd').format(endDate!)
                  : '不限',
              style: const TextStyle(fontSize: 13),
            ),
            onPressed: onPick,
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              foregroundColor: ZenTheme.interactiveBrown,
            ),
          ),
        ),
        if (endDate != null) ...[
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.clear, size: 18),
            onPressed: onClear,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ],
    );
  }
}
