import 'package:flutter/material.dart';

import '../../core/theme/zen_theme.dart';
import '../../models/todo_task.dart';
import '../common/task_attention_fields.dart';

import '../common/shared_dialog_widgets.dart';

class TodoCreateResult {
  final TaskKind taskKind;
  final DateTime? attentionDate;
  final String title;
  final String priority;
  final List<String> tags;
  final DateTime? opensAt;
  final int? estimatedMinutes;
  final DateTime? deadline;
  final String scheduleType;
  final int scheduleInterval;
  final int? scheduleDay;
  final DateTime? endDate;
  final List<int>? byDay;

  const TodoCreateResult({
    this.taskKind = TaskKind.ordinary,
    this.attentionDate,
    required this.title,
    required this.priority,
    required this.tags,
    this.opensAt,
    this.estimatedMinutes,
    this.deadline,
    required this.scheduleType,
    required this.scheduleInterval,
    this.scheduleDay,
    this.endDate,
    this.byDay,
  });
}

class TodoCreateDialog extends StatefulWidget {
  const TodoCreateDialog({super.key});

  @override
  State<TodoCreateDialog> createState() => _TodoCreateDialogState();
}

class _TodoCreateDialogState extends State<TodoCreateDialog> {
  late TextEditingController _titleCtrl;
  String _priority = 'B';
  final Set<String> _selectedTags = {};
  TodoTask _details = TodoTask(
    id: 'form',
    title: 'form',
    createdAt: DateTime.now(),
  );
  String? _validationError;
  String _scheduleType = 'once';
  int _scheduleInterval = 1;
  int _scheduleDay = DateTime.now().day;
  final Set<int> _byDay = {};
  DateTime? _endDate;
  late TextEditingController _intervalCtrl;
  late TextEditingController _monthDayCtrl;
  late TextEditingController _tagInputCtrl;

  static const _suggestedTags = ['工作', '课程', '游戏', '家务', '杂事', '低能量任务'];

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _intervalCtrl = TextEditingController(text: '1');
    _monthDayCtrl = TextEditingController(text: '$_scheduleDay');
    _tagInputCtrl = TextEditingController();
    _byDay.add(DateTime.now().weekday);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _intervalCtrl.dispose();
    _monthDayCtrl.dispose();
    _tagInputCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        '添加待办',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleCtrl,
                autofocus: true,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  labelText: '待办内容',
                  hintText: '输入待办标题...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              _segRow(
                '优先级',
                _priority,
                const ['A', 'B', 'C'],
                const {'A': 'A 紧急', 'B': 'B 重要', 'C': 'C 一般'},
                (v) => setState(() => _priority = v),
              ),
              const SizedBox(height: 10),
              _tagSection(),
              const SizedBox(height: 10),
              TaskAttentionFields(
                value: _details,
                onChanged: (value) => setState(() {
                  _details = value;
                  _validationError = null;
                }),
              ),
              if (_validationError != null)
                Text(
                  _validationError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              const Text(
                '例行设置',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ZenTheme.interactiveBrown,
                ),
              ),
              const SizedBox(height: 6),
              _segRow(
                '重复',
                _scheduleType,
                const ['once', 'daily', 'weekly', 'every_n_days', 'monthly'],
                const {
                  'once': '不重复',
                  'daily': '每天',
                  'weekly': '每周',
                  'every_n_days': '每N天',
                  'monthly': '每月',
                },
                (v) => setState(() => _scheduleType = v),
              ),
              if (_scheduleType == 'weekly') ...[
                const SizedBox(height: 8),
                WeekdayPicker(
                  selectedDays: _byDay,
                  onChanged: (days) => setState(() {
                    _byDay.clear();
                    _byDay.addAll(days);
                  }),
                ),
              ],
              if (_scheduleType == 'every_n_days') ...[
                const SizedBox(height: 8),
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
                const SizedBox(height: 8),
                EndDatePickerRow(
                  endDate: _endDate,
                  onPick: _pickEndDate,
                  onClear: () => setState(() => _endDate = null),
                ),
              ],
              if (_scheduleType == 'monthly') ...[
                const SizedBox(height: 8),
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
            final title = _titleCtrl.text.trim();
            if (title.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('请填写待办内容'),
                  duration: Duration(seconds: 2),
                ),
              );
              return;
            }
            final validated = _details.copyWith(
              title: title,
              attentionConfirmed: true,
            );
            if (validated.validationMessage != null) {
              setState(() => _validationError = validated.validationMessage);
              return;
            }
            Navigator.pop(
              context,
              TodoCreateResult(
                title: title,
                priority: _priority,
                tags: _selectedTags.toList()..sort(),
                taskKind: _details.taskKind,
                attentionDate: _details.attentionDate,
                opensAt: _details.opensAt,
                deadline: _details.deadline,
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
          child: const Text('创建'),
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
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
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
        ),
      ],
    );
  }

  Widget _tagSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '标签',
          style: TextStyle(fontSize: 13, color: ZenTheme.interactiveBrown),
        ),
        const SizedBox(height: 6),
        if (_selectedTags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
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
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _suggestedTags
              .map(
                (tag) => FilterChip(
                  label: Text(tag, style: const TextStyle(fontSize: 13)),
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
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tagInputCtrl,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: '自定义标签...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _addTag(),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加'),
              onPressed: _addTag,
            ),
          ],
        ),
      ],
    );
  }

  void _addTag() {
    final value = _tagInputCtrl.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _selectedTags.add(value);
      _tagInputCtrl.clear();
    });
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
