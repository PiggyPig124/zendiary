import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/todo_task.dart';

/// Shared calendar-only attention and real opening/deadline controls.
class TaskAttentionFields extends StatelessWidget {
  final TodoTask value;
  final ValueChanged<TodoTask> onChanged;
  const TaskAttentionFields({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<TaskKind>(
          key: ValueKey(value.taskKind),
          initialValue: value.taskKind,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '任务类型'),
          items: TaskKind.values
              .map(
                (kind) =>
                    DropdownMenuItem(value: kind, child: Text(kind.label)),
              )
              .toList(),
          onChanged: (kind) {
            if (kind == null) return;
            onChanged(
              value.copyWith(
                taskKind: kind,
                clearAttentionDate: kind != value.taskKind,
                attentionConfirmed: kind != TaskKind.preparation,
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(switch (value.taskKind) {
          TaskKind.ordinary => '不选关注日就从今天保留，直到完成。',
          TaskKind.timed => '开放后一直保留，越接近截止越靠前。',
          TaskKind.preparation => '必须选择开始关注日，不需要估算用时。',
        }),
        if (value.taskKind != TaskKind.timed)
          _dateRow(
            context,
            '开始关注日',
            value.attentionDate,
            false,
            (date) => onChanged(
              value.copyWith(
                attentionDate: date,
                clearAttentionDate: date == null,
                attentionConfirmed: date != null,
              ),
            ),
          ),
        _dateRow(
          context,
          '开放时间',
          value.opensAt,
          true,
          (date) => onChanged(
            value.copyWith(opensAt: date, clearOpensAt: date == null),
          ),
        ),
        _dateRow(
          context,
          '截止时间',
          value.deadline,
          true,
          (date) => onChanged(
            value.copyWith(deadline: date, clearDeadline: date == null),
          ),
        ),
      ],
    );
  }

  Widget _dateRow(
    BuildContext context,
    String label,
    DateTime? date,
    bool withTime,
    ValueChanged<DateTime?> change,
  ) {
    return Row(
      children: [
        Expanded(
          child: TextButton.icon(
            onPressed: () async {
              final selected = await showDatePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(2200),
                initialDate: date ?? DateTime.now(),
                helpText: '选择$label',
              );
              if (selected == null || !context.mounted) return;
              if (!withTime) {
                change(selected);
                return;
              }
              final time = await showTimePicker(
                context: context,
                initialTime: date != null
                    ? TimeOfDay.fromDateTime(date)
                    : label == '截止时间'
                    ? const TimeOfDay(hour: 23, minute: 59)
                    : const TimeOfDay(hour: 0, minute: 0),
                helpText: '选择$label',
              );
              if (time != null) {
                change(
                  DateTime(
                    selected.year,
                    selected.month,
                    selected.day,
                    time.hour,
                    time.minute,
                  ),
                );
              }
            },
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(
              '$label：${date == null ? '未选择' : DateFormat(withTime ? 'yyyy/M/d HH:mm' : 'yyyy/M/d').format(date)}',
            ),
          ),
        ),
        if (date != null)
          IconButton(
            tooltip: '清除$label',
            onPressed: () => change(null),
            icon: const Icon(Icons.close, size: 18),
          ),
      ],
    );
  }
}

Future<TodoTask?> showTaskAttentionDialog(BuildContext context, TodoTask todo) {
  var edited = todo;
  String? error;
  return showDialog<TodoTask>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('任务类型与关注日期'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(todo.title),
                const SizedBox(height: 12),
                TaskAttentionFields(
                  value: edited,
                  onChanged: (value) => setState(() {
                    edited = value;
                    error = null;
                  }),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final confirmed = edited.copyWith(attentionConfirmed: true);
              final message = confirmed.validationMessage;
              if (message != null) {
                setState(() => error = message);
                return;
              }
              Navigator.pop(context, confirmed);
            },
            child: const Text('确认保存'),
          ),
        ],
      ),
    ),
  );
}
