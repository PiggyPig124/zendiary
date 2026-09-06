import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/zen_theme.dart';
import '../../models/reminder_rule.dart';
import '../../models/todo_task.dart';
import '../../providers/app_providers.dart';
import '../../providers/reminder_rule_provider.dart';
import '../common/multi_select_bar.dart';
import '../common/page_header.dart';
import '../common/shared_dialog_widgets.dart';

class ReminderView extends ConsumerStatefulWidget {
  const ReminderView({super.key});

  @override
  ConsumerState<ReminderView> createState() => _ReminderViewState();
}

class _ReminderViewState extends ConsumerState<ReminderView> {
  final Set<String> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    final allRules = ref.watch(allNonArchivedRulesProvider);
    final todos = ref.watch(todoListProvider);

    final strongRules = allRules
        .where((r) => r.disturbanceLevel == 'strong')
        .toList();
    final normalRules = allRules
        .where((r) => r.disturbanceLevel == 'normal')
        .toList();
    final silentRules = allRules
        .where((r) => r.disturbanceLevel == 'silent')
        .toList();

    final activeCount = allRules.where((r) => r.isActive).length;
    final isSelecting = _selectedIds.isNotEmpty;

    return Column(
      children: [
        PageHeader(
          title: '提醒',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: ZenTheme.interactiveBrown,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$activeCount',
                  style: const TextStyle(
                    fontSize: 11,
                    color: ZenTheme.contentOnAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  isSelecting ? Icons.select_all : Icons.checklist,
                  size: 20,
                ),
                tooltip: isSelecting ? '全选' : '多选',
                hoverColor: ZenTheme.interactivePressed,
                onPressed: allRules.isNotEmpty
                    ? () => _toggleSelectMode(allRules)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                tooltip: '新建提醒',
                hoverColor: ZenTheme.interactivePressed,
                onPressed: () => _showReminderDialog(context, ref, null),
              ),
            ],
          ),
        ),
        Expanded(
          child: allRules.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.notifications_off_outlined,
                        size: 48,
                        color: ZenTheme.textCompleted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '暂无活跃提醒',
                        style: TextStyle(
                          fontSize: 14,
                          color: ZenTheme.textCompleted,
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('创建第一个提醒'),
                        onPressed: () =>
                            _showReminderDialog(context, ref, null),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
                  children: [
                    if (strongRules.isNotEmpty) ...[
                      _ReminderGroup(
                        title: '强提醒',
                        icon: Icons.notifications_active_outlined,
                        color: ZenTheme.statusOverdue,
                        rules: strongRules,
                        todos: todos,
                        isSelecting: isSelecting,
                        selectedIds: _selectedIds,
                        onEdit: (rule) =>
                            _showReminderDialog(context, ref, rule),
                        onToggleSelect: _toggleSelection,
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (normalRules.isNotEmpty) ...[
                      _ReminderGroup(
                        title: '普通提醒',
                        icon: Icons.notifications_outlined,
                        color: ZenTheme.accentMatcha,
                        rules: normalRules,
                        todos: todos,
                        isSelecting: isSelecting,
                        selectedIds: _selectedIds,
                        onEdit: (rule) =>
                            _showReminderDialog(context, ref, rule),
                        onToggleSelect: _toggleSelection,
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (silentRules.isNotEmpty) ...[
                      _ReminderGroup(
                        title: '静默提醒',
                        icon: Icons.notifications_off_outlined,
                        color: ZenTheme.textMuted,
                        rules: silentRules,
                        todos: todos,
                        isSelecting: isSelecting,
                        selectedIds: _selectedIds,
                        onEdit: (rule) =>
                            _showReminderDialog(context, ref, rule),
                        onToggleSelect: _toggleSelection,
                      ),
                    ],
                  ],
                ),
        ),
        if (isSelecting)
          MultiSelectBar(
            count: _selectedIds.length,
            onCancel: () => setState(_selectedIds.clear),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('删除'),
                onPressed: _bulkDelete,
              ),
            ],
          ),
      ],
    );
  }

  void _toggleSelectMode(List<ReminderRule> allRules) {
    setState(() {
      if (_selectedIds.isEmpty) {
        _selectedIds.add(allRules.first.id);
      } else if (_selectedIds.length == allRules.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(allRules.map((r) => r.id));
      }
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  void _bulkDelete() {
    final count = _selectedIds.length;
    final notifier = ref.read(reminderRuleProvider.notifier);
    for (final id in _selectedIds) {
      notifier.archiveRule(id);
    }
    setState(_selectedIds.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已归档 $count 条提醒'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showReminderDialog(
    BuildContext context,
    WidgetRef ref,
    ReminderRule? existing,
  ) {
    showDialog(
      context: context,
      builder: (_) => ReminderEditDialog(existing: existing),
    ).then((result) {
      if (result == null || !context.mounted) return;
      final notifier = ref.read(reminderRuleProvider.notifier);
      if (result is ReminderEditResult) {
        final rule = ReminderRule(
          id: existing?.id,
          title: result.title,
          targetType: existing?.targetType ?? 'standalone',
          targetId: existing?.targetId,
          category: existing?.category ?? 'general',
          importance: result.importance,
          disturbanceLevel: result.disturbanceLevel,
          scheduleType: result.scheduleType,
          scheduleInterval: existing?.scheduleInterval ?? 1,
          anchorTime: result.anchorTime,
          advanceMinutes: result.advanceMinutes,
          status: result.isActive ? 'active' : 'disabled',
          generatedByAi: existing?.generatedByAi ?? false,
          requiresConfirmation: existing?.requiresConfirmation ?? false,
          createdAt: existing?.createdAt,
          note: existing?.note,
          displayMode: result.displayMode,
          startDate: existing?.startDate ?? result.anchorTime,
          endDate: result.endDate,
          byDay: result.byDay,
        );
        if (existing != null) {
          notifier.updateRule(rule);
        } else {
          notifier.addRule(rule);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(existing != null ? '提醒已更新' : '提醒已创建'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else if (result is bool && result == true && existing != null) {
        // delete
        notifier.archiveRule(existing.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('提醒已归档'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }
}

class _ReminderGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<ReminderRule> rules;
  final List<TodoTask> todos;
  final bool isSelecting;
  final Set<String> selectedIds;
  final void Function(ReminderRule rule) onEdit;
  final void Function(String id) onToggleSelect;

  const _ReminderGroup({
    required this.title,
    required this.icon,
    required this.color,
    required this.rules,
    required this.todos,
    required this.isSelecting,
    required this.selectedIds,
    required this.onEdit,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ZenTheme.backgroundCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ZenTheme.borderCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const Spacer(),
              Text(
                '${rules.length}',
                style: TextStyle(fontSize: 12, color: ZenTheme.textCompleted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...rules.asMap().entries.expand(
            (entry) => [
              _ReminderTile(
                rule: entry.value,
                todos: todos,
                isSelecting: isSelecting,
                isSelected: selectedIds.contains(entry.value.id),
                onEdit: () => onEdit(entry.value),
                onToggleSelect: () => onToggleSelect(entry.value.id),
              ),
              if (entry.key < rules.length - 1)
                const Divider(
                  height: 8,
                  thickness: 0.5,
                  color: ZenTheme.borderCard,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReminderTile extends ConsumerWidget {
  final ReminderRule rule;
  final List<TodoTask> todos;
  final bool isSelecting;
  final bool isSelected;
  final VoidCallback onEdit;
  final VoidCallback onToggleSelect;

  const _ReminderTile({
    required this.rule,
    required this.todos,
    required this.isSelecting,
    required this.isSelected,
    required this.onEdit,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeStr = rule.anchorTime != null
        ? DateFormat('MM-dd HH:mm').format(rule.anchorTime!)
        : '';
    final scheduleLabel = _scheduleLabel(
      rule.scheduleType,
      scheduleInterval: rule.scheduleInterval,
    );
    final advanceLabel =
        rule.advanceMinutes.isEmpty || rule.advanceMinutes.first == 0
        ? null
        : '提前 ${rule.advanceMinutes.first} 分钟';

    return Opacity(
      opacity: rule.isActive ? 1.0 : 0.45,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: isSelecting ? onToggleSelect : onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isSelecting) ...[
                Checkbox(
                  value: isSelected,
                  onChanged: (_) => onToggleSelect(),
                  activeColor: ZenTheme.interactiveBrown,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
              ],
              Container(
                width: 44,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ZenTheme.backgroundWarm,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  rule.importance == 'important'
                      ? '重要'
                      : rule.importance == 'minor'
                      ? '小事'
                      : '普通',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: ZenTheme.interactiveBrown,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: ZenTheme.textHeading,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        timeStr,
                        scheduleLabel,
                        ?advanceLabel,
                      ].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: ZenTheme.textMuted),
                    ),
                  ],
                ),
              ),
              _ZenToggle(
                value: rule.isActive,
                onChanged: (active) {
                  ref
                      .read(reminderRuleProvider.notifier)
                      .updateRule(
                        rule.copyWith(status: active ? 'active' : 'disabled'),
                      );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _scheduleLabel(String value, {int? scheduleInterval}) {
    return switch (value) {
      'daily' => '每天',
      'weekly' => '每周',
      'every_n_days' =>
        scheduleInterval != null ? '每 $scheduleInterval 天' : '重复',
      'monthly' => '每月',
      _ => '单次',
    };
  }
}

// ── 自定义小巧滑动开关 ──

class _ZenToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ZenToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: 38,
        height: 22,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          color: value
              ? ZenTheme.accentMatcha
              : ZenTheme.borderWarm,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: ZenTheme.contentOnAccent,
            ),
          ),
        ),
      ),
    );
  }
}

// ── 提醒编辑/创建对话框 ──

class ReminderEditResult {
  final String title;
  final String importance;
  final String disturbanceLevel;
  final String scheduleType;
  final DateTime anchorTime;
  final List<int> advanceMinutes;
  final String displayMode;
  final DateTime? endDate;
  final List<int>? byDay;
  final bool isActive;

  const ReminderEditResult({
    required this.title,
    required this.importance,
    required this.disturbanceLevel,
    required this.scheduleType,
    required this.anchorTime,
    required this.advanceMinutes,
    required this.displayMode,
    this.endDate,
    this.byDay,
    this.isActive = true,
  });
}

class ReminderEditDialog extends StatefulWidget {
  final ReminderRule? existing;

  const ReminderEditDialog({super.key, this.existing});

  @override
  State<ReminderEditDialog> createState() => _ReminderEditDialogState();
}

class _ReminderEditDialogState extends State<ReminderEditDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _customAdvanceCtrl;
  late String _importance;
  late String _disturbanceLevel;
  late String _scheduleType;
  late String _displayMode;
  late bool _isActive;
  late Set<int> _advanceMinutes;
  late Set<int> _byDay;
  late DateTime _anchorTime;
  DateTime? _endDate;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _titleCtrl = TextEditingController(text: r?.title ?? '');
    _customAdvanceCtrl = TextEditingController();
    _importance = r?.importance ?? 'normal';
    _disturbanceLevel = r?.disturbanceLevel ?? 'normal';
    _scheduleType = r?.scheduleType ?? 'once';
    _displayMode = r?.displayMode ?? 'punctual';
    _isActive = r?.isActive ?? true;
    _advanceMinutes =
        (r?.advanceMinutes.isEmpty == true
                ? [10]
                : List<int>.from(r?.advanceMinutes ?? [10]))
            .toSet();
    _anchorTime = r?.anchorTime ?? DateTime.now().add(const Duration(hours: 1));
    _byDay = (r?.byDay ?? [r?.anchorTime?.weekday ?? DateTime.now().weekday])
        .toSet();
    _endDate = r?.endDate;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _customAdvanceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEdit ? '编辑提醒' : '新建提醒',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleCtrl,
                maxLines: 3,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  labelText: '提醒内容',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              _segRow(
                '重要度',
                _importance,
                const ['important', 'normal', 'minor'],
                const {'important': '重要', 'normal': '普通', 'minor': '小事'},
                (v) => setState(() => _importance = v),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _pickAnchorTime,
                icon: const Icon(Icons.schedule_outlined, size: 16),
                label: Text(
                  '发生时间 ${DateFormat('yyyy-MM-dd HH:mm').format(_anchorTime)}',
                ),
              ),
              const SizedBox(height: 10),
              _segRow(
                '打扰',
                _disturbanceLevel,
                const ['strong', 'normal', 'silent'],
                {'strong': '强提醒', 'normal': '普通', 'silent': '静默'},
                (v) => setState(() => _disturbanceLevel = v),
              ),
              const SizedBox(height: 10),
              _segRow(
                '重复',
                _scheduleType,
                const ['once', 'daily', 'weekly', 'every_n_days', 'monthly'],
                {
                  'once': '不重复',
                  'daily': '每天',
                  'weekly': '每周',
                  'every_n_days': '每N天',
                  'monthly': '每月',
                },
                (v) => setState(() => _scheduleType = v),
              ),
              if (_scheduleType == 'weekly') ...[
                const SizedBox(height: 10),
                WeekdayPicker(
                  selectedDays: _byDay,
                  onChanged: (days) => setState(() => _byDay = days),
                ),
              ],
              if (_scheduleType != 'once') ...[
                const SizedBox(height: 10),
                _segRow(
                  '可见',
                  _displayMode,
                  const ['punctual', 'spanning'],
                  {'punctual': '仅当天', 'spanning': '跨天可见'},
                  (v) => setState(() => _displayMode = v),
                ),
                const SizedBox(height: 10),
                EndDatePickerRow(
                  endDate: _endDate,
                  onPick: _pickEndDate,
                  onClear: () => setState(() => _endDate = null),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                '提前提醒',
                style: TextStyle(
                  fontSize: 13,
                  color: ZenTheme.interactiveBrown,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _advChip('到点', 0),
                  _advChip('5 分钟', 5),
                  _advChip('15 分钟', 15),
                  _advChip('1 小时', 60),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customAdvanceCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        labelText: '自定义分钟',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _addCustomAdvance,
                    child: const Text('添加'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_isEdit)
          TextButton(
            onPressed: () => _confirmDelete(),
            child: const Text(
              '删除',
              style: TextStyle(color: ZenTheme.statusError),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('保存')),
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
      ],
    );
  }

  Widget _advChip(String label, int minutes) {
    final selected = _advanceMinutes.contains(minutes);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _toggleAdvance(minutes),
      selectedColor: ZenTheme.interactiveBrown,
      labelStyle: TextStyle(
        color: selected
            ? ZenTheme.contentOnAccent
            : ZenTheme.interactiveBrown,
        fontSize: 13,
      ),
      showCheckmark: false,
    );
  }

  void _toggleAdvance(int minutes) {
    setState(() {
      if (!_advanceMinutes.add(minutes)) {
        _advanceMinutes.remove(minutes);
      }
      if (_advanceMinutes.isEmpty) _advanceMinutes.add(0);
    });
  }

  void _addCustomAdvance() {
    final min = int.tryParse(_customAdvanceCtrl.text.trim());
    if (min == null || min < 0 || min > 1440) return;
    setState(() {
      _advanceMinutes.add(min);
      _customAdvanceCtrl.clear();
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

  Future<void> _pickAnchorTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _anchorTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '选择发生日期',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_anchorTime),
      helpText: '选择发生时间',
    );
    if (time == null) return;
    setState(() {
      _anchorTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (_scheduleType == 'weekly' && _byDay.isEmpty) {
        _byDay = {_anchorTime.weekday};
      }
    });
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请填写提醒内容'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final advances = _advanceMinutes.toList()..sort((a, b) => b.compareTo(a));
    Navigator.pop(
      context,
      ReminderEditResult(
        title: title,
        importance: _importance,
        disturbanceLevel: _disturbanceLevel,
        scheduleType: _scheduleType,
        anchorTime: _anchorTime,
        advanceMinutes: advances,
        displayMode: _displayMode,
        endDate: _endDate,
        byDay: _scheduleType == 'weekly' ? (_byDay.toList()..sort()) : null,
        isActive: _isActive,
      ),
    );
  }

  void _confirmDelete() {
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除提醒'),
        content: Text('确定要删除"${_titleCtrl.text.trim()}"吗？'),
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
      if (confirmed == true && mounted) {
        Navigator.pop(context, true); // signal delete to caller
      }
    });
  }
}
