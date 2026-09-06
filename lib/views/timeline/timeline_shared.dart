import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/zen_theme.dart';
import '../../models/diary_entry.dart';
import '../../models/reminder_rule.dart';
import '../../providers/reminder_rule_provider.dart';

// ── 共享工具 ──

/// 返回指定日期所在周的周一（weekday=1 为周一）。
DateTime startOfWeek(DateTime date) {
  return DateTime(date.year, date.month, date.day - (date.weekday - 1));
}

// ── 视图模式 ──

enum TimelineViewMode { day, week, month }

final timelineViewModeProvider =
    NotifierProvider<_ViewModeNotifier, TimelineViewMode>(
      _ViewModeNotifier.new,
    );

class _ViewModeNotifier extends Notifier<TimelineViewMode> {
  @override
  TimelineViewMode build() => TimelineViewMode.week;

  void set(TimelineViewMode mode) => state = mode;
}

final selectedDayProvider = NotifierProvider<_SelectedDayNotifier, DateTime>(
  _SelectedDayNotifier.new,
);

class _SelectedDayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime.now();

  void set(DateTime day) => state = day;
}

// ── 共享样式 ──

const TextStyle timelineDialogTitleStyle = ZenTheme.headingDialog;

const TextStyle timelineDialogTextStyle = ZenTheme.bodyDialog;

const TextStyle timelineDialogLabelStyle = ZenTheme.labelLarge;

final TextStyle timelineDialogControlStyle = ZenTheme.textStyle(
  fontSize: 13,
  fontWeight: FontWeight.w400,
);

// ── 表单数据类 ──

class TimelineEventFormData {
  final String content;
  final DateTime eventTime;
  final int? durationMinutes;
  final String location;
  final ReminderFormData reminder;

  const TimelineEventFormData({
    required this.content,
    required this.eventTime,
    this.durationMinutes,
    required this.location,
    required this.reminder,
  });
}

class ReminderFormData {
  final bool enabled;
  final String importance;
  final String disturbanceLevel;
  final String scheduleType;
  final int scheduleInterval;
  final int? scheduleDay;
  final List<int> advanceMinutes;
  final String displayMode;
  final int? customSpanDays;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? endCount;
  final List<int>? byDay;

  const ReminderFormData({
    required this.enabled,
    required this.importance,
    required this.disturbanceLevel,
    required this.scheduleType,
    this.scheduleInterval = 1,
    this.scheduleDay,
    required this.advanceMinutes,
    this.displayMode = 'punctual',
    this.customSpanDays,
    this.startDate,
    this.endDate,
    this.endCount,
    this.byDay,
  });

  factory ReminderFormData.defaults() => const ReminderFormData(
    enabled: true,
    importance: 'important',
    disturbanceLevel: 'strong',
    scheduleType: 'once',
    scheduleInterval: 1,
    advanceMinutes: [0],
    displayMode: 'punctual',
    byDay: null,
  );

  factory ReminderFormData.fromRule(ReminderRule? rule) {
    if (rule == null) return ReminderFormData.defaults();
    return ReminderFormData(
      enabled: rule.isActive,
      importance: rule.importance,
      disturbanceLevel: rule.disturbanceLevel,
      scheduleType: rule.scheduleType,
      scheduleInterval: rule.scheduleInterval,
      scheduleDay: rule.scheduleDay ?? rule.byMonthDay?.first,
      advanceMinutes:
          rule.advanceMinutes.isEmpty
                ? [0] // 可变列表，允许后续 sort
                : List<int>.from(rule.advanceMinutes)
            ..sort(),
      displayMode: rule.displayMode,
      customSpanDays: rule.customSpanDays,
      startDate: rule.startDate,
      endDate: rule.endDate,
      endCount: rule.endCount,
      byDay: rule.byDay,
    );
  }
}

// ── 同步提醒规则 ──

void syncEventReminderRule(
  WidgetRef ref,
  DiaryEntry entry,
  ReminderFormData reminder,
) {
  final eventTime = entry.eventTime;
  if (eventTime == null) return;
  if (!reminder.enabled) {
    ref
        .read(reminderRuleProvider.notifier)
        .upsertRuleForTarget(
          ReminderRule(
            title: entry.content,
            targetType: 'event',
            targetId: entry.id,
            category: entry.tags.isEmpty ? 'timeline' : entry.tags.first,
            importance: reminder.importance,
            disturbanceLevel: reminder.disturbanceLevel,
            scheduleType: reminder.scheduleType,
            scheduleInterval: reminder.scheduleInterval,
            scheduleDay: reminder.scheduleDay,
            anchorTime: eventTime,
            advanceMinutes: reminder.advanceMinutes,
            status: 'disabled',
            note: entry.location,
            displayMode: reminder.displayMode,
            customSpanDays: reminder.customSpanDays,
            startDate: reminder.startDate,
            endDate: reminder.endDate,
            endCount: reminder.endCount,
            byDay: reminder.byDay,
            byMonthDay: reminder.scheduleDay == null
                ? null
                : [reminder.scheduleDay!],
          ),
        );
    return;
  }
  ref
      .read(reminderRuleProvider.notifier)
      .upsertRuleForTarget(
        ReminderRule(
          title: entry.content,
          targetType: 'event',
          targetId: entry.id,
          category: entry.tags.isEmpty ? 'timeline' : entry.tags.first,
          importance: reminder.importance,
          disturbanceLevel: reminder.disturbanceLevel,
          scheduleType: reminder.scheduleType,
          scheduleInterval: reminder.scheduleInterval,
          scheduleDay: reminder.scheduleDay,
          anchorTime: eventTime,
          advanceMinutes: reminder.advanceMinutes,
          status: 'active',
          note: entry.location,
          displayMode: reminder.displayMode,
          customSpanDays: reminder.customSpanDays,
          startDate: reminder.startDate,
          endDate: reminder.endDate,
          endCount: reminder.endCount,
          byDay: reminder.byDay,
          byMonthDay: reminder.scheduleDay == null
              ? null
              : [reminder.scheduleDay!],
        ),
      );
}

// ── 通用 SegmentRow ──

class SegmentRow<T extends Object> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> values;
  final Map<T, String> labels;
  final ValueChanged<T> onChanged;

  const SegmentRow({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(label, style: timelineDialogLabelStyle),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<T>(
              segments: values
                  .map(
                    (item) => ButtonSegment<T>(
                      value: item,
                      label: Text(
                        labels[item] ?? item.toString(),
                        style: timelineDialogControlStyle,
                      ),
                    ),
                  )
                  .toList(),
              selected: {value},
              onSelectionChanged: (selection) => onChanged(selection.first),
              style: SegmentedButton.styleFrom(
                textStyle: timelineDialogControlStyle,
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
}

// ── 通用 AdvanceChip ──

class AdvanceChip extends StatelessWidget {
  final String label;
  final int minutes;
  final bool selected;
  final ValueChanged<int> onTap;

  const AdvanceChip({
    super.key,
    required this.label,
    required this.minutes,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(minutes),
      selectedColor: ZenTheme.interactiveBrown,
      labelStyle: TextStyle(
                color: selected
                    ? ZenTheme.contentOnAccent
                    : ZenTheme.interactiveBrown,
        fontSize: timelineDialogControlStyle.fontSize,
        fontWeight: timelineDialogControlStyle.fontWeight,
        fontFamilyFallback: ZenTheme.fontFallback,
        letterSpacing: 0,
      ),
      side: const BorderSide(color: ZenTheme.borderButton),
      showCheckmark: false,
    );
  }
}

// ── 事件编辑/创建对话框 ──

class TimelineEventDialog extends StatefulWidget {
  final String initialContent;
  final DateTime initialTime;
  final String initialLocation;
  final int? initialDurationMinutes;
  final ReminderFormData initialReminder;
  final bool isEdit;

  /// Projected recurring occurrences can override their time/content, while
  /// reminders remain owned by the shared recurrence rule.
  final bool reminderEditable;

  const TimelineEventDialog({
    super.key,
    required this.initialTime,
    required this.initialReminder,
    this.initialContent = '',
    this.initialLocation = '',
    this.initialDurationMinutes,
    this.isEdit = false,
    this.reminderEditable = true,
  });

  @override
  State<TimelineEventDialog> createState() => _TimelineEventDialogState();
}

class _TimelineEventDialogState extends State<TimelineEventDialog> {
  late final TextEditingController _contentCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _durationCtrl;
  late final TextEditingController _customAdvanceCtrl;
  late DateTime _eventTime;
  late bool _reminderEnabled;
  late String _importance;
  late String _disturbanceLevel;
  late String _scheduleType;
  late int _scheduleInterval;
  late int _scheduleDay;
  late String _displayMode;
  DateTime? _endDate;
  late Set<int> _byDay; // 选中的星期几
  late Set<int> _advanceMinutes;
  late final TextEditingController _intervalCtrl;
  late final TextEditingController _monthDayCtrl;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _contentCtrl = TextEditingController(text: widget.initialContent);
    _locationCtrl = TextEditingController(text: widget.initialLocation);
    _durationCtrl = TextEditingController(
      text: widget.initialDurationMinutes?.toString() ?? '',
    );
    _customAdvanceCtrl = TextEditingController();
    _eventTime = widget.initialTime;
    _reminderEnabled = widget.initialReminder.enabled;
    _importance = widget.initialReminder.importance;
    _disturbanceLevel = widget.initialReminder.disturbanceLevel;
    _scheduleType = widget.initialReminder.scheduleType;
    _scheduleInterval = widget.initialReminder.scheduleInterval;
    _scheduleDay = widget.initialReminder.scheduleDay ?? widget.initialTime.day;
    _displayMode = widget.initialReminder.displayMode;
    _endDate = widget.initialReminder.endDate;
    _byDay = (widget.initialReminder.byDay ?? [widget.initialTime.weekday])
        .toSet();
    _advanceMinutes = widget.initialReminder.advanceMinutes.toSet();
    _intervalCtrl = TextEditingController(text: '$_scheduleInterval');
    _monthDayCtrl = TextEditingController(text: '$_scheduleDay');
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    _locationCtrl.dispose();
    _durationCtrl.dispose();
    _customAdvanceCtrl.dispose();
    _intervalCtrl.dispose();
    _monthDayCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.isEdit ? '编辑时间线事件' : '手动添加事件',
        style: timelineDialogTitleStyle,
      ),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 64).clamp(280.0, 520.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _contentCtrl,
                maxLines: 4,
                style: timelineDialogTextStyle,
                decoration: InputDecoration(
                  labelText: '内容',
                  labelStyle: timelineDialogLabelStyle,
                  border: const OutlineInputBorder(),
                  errorText: _errorText,
                ),
                onChanged: (_) {
                  if (_errorText != null) setState(() => _errorText = null);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(
                        DateFormat('yyyy-MM-dd').format(_eventTime),
                        style: timelineDialogControlStyle,
                      ),
                      onPressed: _pickDate,
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        foregroundColor: ZenTheme.interactiveBrown,
                        side: const BorderSide(color: ZenTheme.borderButton),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time_outlined, size: 16),
                      label: Text(
                        DateFormat('HH:mm').format(_eventTime),
                        style: timelineDialogControlStyle,
                      ),
                      onPressed: _pickTime,
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        foregroundColor: ZenTheme.interactiveBrown,
                        side: const BorderSide(color: ZenTheme.borderButton),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _durationCtrl,
                keyboardType: TextInputType.number,
                style: timelineDialogTextStyle,
                decoration: const InputDecoration(
                  labelText: '时长（分钟，可选）',
                  hintText: '例如 90',
                  labelStyle: timelineDialogLabelStyle,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.timelapse_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _locationCtrl,
                style: timelineDialogTextStyle,
                decoration: const InputDecoration(
                  labelText: '地点（可选）',
                  labelStyle: timelineDialogLabelStyle,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 14),
              _buildReminderEditor(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('取消', style: timelineDialogControlStyle),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text('保存', style: timelineDialogControlStyle),
        ),
      ],
    );
  }

  Widget _buildReminderEditor() {
    if (!widget.reminderEditable) {
      return Container(
        padding: const EdgeInsets.all(ZenTheme.cardPadding),
        decoration: BoxDecoration(
          color: ZenTheme.backgroundMuted,
          borderRadius: BorderRadius.circular(ZenTheme.radiusCard),
          border: Border.all(color: ZenTheme.borderCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_none_outlined),
              title: const Text('提醒规则（整条重复安排）'),
              subtitle: Text(
                _reminderSummary(),
                style: timelineDialogLabelStyle,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '本次只修改时间、时长、内容和地点。提醒设置沿用整条重复安排；如需调整，请编辑整条规则。',
              style: timelineDialogLabelStyle,
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(ZenTheme.cardPadding),
      decoration: BoxDecoration(
        color: ZenTheme.backgroundMuted,
        borderRadius: BorderRadius.circular(ZenTheme.radiusCard),
        border: Border.all(color: ZenTheme.borderCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: ZenTheme.transparent,
            child: SwitchListTile(
              value: _reminderEnabled,
              onChanged: (value) => setState(() => _reminderEnabled = value),
              contentPadding: EdgeInsets.zero,
              title: const Text('提醒', style: timelineDialogTextStyle),
              subtitle: Text(
                _reminderSummary(),
                style: timelineDialogLabelStyle,
              ),
              activeThumbColor: ZenTheme.interactiveBrown,
            ),
          ),
          if (_reminderEnabled) ...[
            const SizedBox(height: 8),
            SegmentRow<String>(
              label: '重要度',
              value: _importance,
              values: const ['important', 'normal', 'minor'],
              labels: const {'important': '重要', 'normal': '普通', 'minor': '小事'},
              onChanged: (value) => setState(() => _importance = value),
            ),
            const SizedBox(height: 10),
            SegmentRow<String>(
              label: '打扰',
              value: _disturbanceLevel,
              values: const ['strong', 'normal', 'silent'],
              labels: const {'strong': '强提醒', 'normal': '普通', 'silent': '静默'},
              onChanged: (value) => setState(() => _disturbanceLevel = value),
            ),
            const SizedBox(height: 10),
            SegmentRow<String>(
              label: '重复',
              value: _scheduleType,
              values: const [
                'once',
                'daily',
                'weekly',
                'every_n_days',
                'monthly',
              ],
              labels: const {
                'once': '不重复',
                'daily': '每天',
                'weekly': '每周',
                'every_n_days': '每N天',
                'monthly': '每月',
              },
              onChanged: (value) => setState(() => _scheduleType = value),
            ),
            if (_scheduleType == 'weekly') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    width: 54,
                    child: Text('星期', style: timelineDialogLabelStyle),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final day in const [
                            (1, '一'),
                            (2, '二'),
                            (3, '三'),
                            (4, '四'),
                            (5, '五'),
                            (6, '六'),
                            (7, '日'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(
                                  day.$2,
                                  style: timelineDialogControlStyle,
                                ),
                                selected: _byDay.contains(day.$1),
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _byDay.add(day.$1);
                                    } else {
                                      _byDay.remove(day.$1);
                                    }
                                    if (_byDay.isEmpty) _byDay.add(day.$1);
                                  });
                                },
                                selectedColor: ZenTheme.interactiveBrown,
                                labelStyle: TextStyle(
                                  color: _byDay.contains(day.$1)
                                      ? ZenTheme.contentOnAccent
                                      : ZenTheme.interactiveBrown,
                                ),
                                side: const BorderSide(
                                  color: ZenTheme.borderButton,
                                ),
                                showCheckmark: false,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_scheduleType == 'every_n_days') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    width: 54,
                    child: Text('间隔', style: timelineDialogLabelStyle),
                  ),
                  SizedBox(
                    width: 82,
                    child: TextField(
                      controller: _intervalCtrl,
                      keyboardType: TextInputType.number,
                      style: timelineDialogTextStyle,
                      decoration: const InputDecoration(
                        labelText: '天数',
                        labelStyle: timelineDialogLabelStyle,
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        final interval = int.tryParse(value);
                        if (interval != null &&
                            interval >= 1 &&
                            interval <= 365) {
                          _scheduleInterval = interval;
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('天', style: timelineDialogLabelStyle),
                ],
              ),
            ],
            if (_scheduleType == 'monthly') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    width: 54,
                    child: Text('每月', style: timelineDialogLabelStyle),
                  ),
                  SizedBox(
                    width: 82,
                    child: TextField(
                      controller: _monthDayCtrl,
                      keyboardType: TextInputType.number,
                      style: timelineDialogTextStyle,
                      decoration: const InputDecoration(
                        labelText: '几号',
                        labelStyle: timelineDialogLabelStyle,
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
                      style: TextStyle(fontSize: 12, color: ZenTheme.textMuted),
                    ),
                  ),
                ],
              ),
            ],
            if (_scheduleType != 'once') ...[
              const SizedBox(height: 10),
              SegmentRow<String>(
                label: '持续',
                value: _displayMode,
                values: const ['punctual', 'spanning'],
                labels: const {'punctual': '仅当天', 'spanning': '跨期可见'},
                onChanged: (value) => setState(() => _displayMode = value),
              ),
            ],
            if (_scheduleType != 'once') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    width: 54,
                    child: Text('截止', style: timelineDialogLabelStyle),
                  ),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(
                        _endDate != null
                            ? DateFormat('yyyy-MM-dd').format(_endDate!)
                            : '不限',
                        style: timelineDialogControlStyle,
                      ),
                      onPressed: _pickEndDate,
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        foregroundColor: ZenTheme.interactiveBrown,
                        side: const BorderSide(color: ZenTheme.borderButton),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  if (_endDate != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _endDate = null),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Text('提前提醒', style: timelineDialogLabelStyle),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AdvanceChip(
                  label: '到点',
                  minutes: 0,
                  selected: _advanceMinutes.contains(0),
                  onTap: _toggleAdvance,
                ),
                AdvanceChip(
                  label: '5 分钟',
                  minutes: 5,
                  selected: _advanceMinutes.contains(5),
                  onTap: _toggleAdvance,
                ),
                AdvanceChip(
                  label: '15 分钟',
                  minutes: 15,
                  selected: _advanceMinutes.contains(15),
                  onTap: _toggleAdvance,
                ),
                AdvanceChip(
                  label: '1 小时',
                  minutes: 60,
                  selected: _advanceMinutes.contains(60),
                  onTap: _toggleAdvance,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customAdvanceCtrl,
                    keyboardType: TextInputType.number,
                    style: timelineDialogTextStyle,
                    decoration: const InputDecoration(
                      labelText: '自定义提前分钟',
                      labelStyle: timelineDialogLabelStyle,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _addCustomAdvance,
                  child: Text('添加', style: timelineDialogControlStyle),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _reminderSummary() {
    if (!_reminderEnabled) return '关闭后不会触发提醒，也不会被时间线兜底提醒';
    final advances = _normalizedAdvances();
    final advanceText = advances
        .map((minutes) => minutes == 0 ? '到点' : '提前 $minutes 分钟')
        .join('、');
    return '$advanceText · ${_scheduleLabel(_scheduleType)} · ${_disturbanceLabel(_disturbanceLevel)}';
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
    final minutes = int.tryParse(_customAdvanceCtrl.text.trim());
    if (minutes == null || minutes < 0 || minutes > 1440) return;
    setState(() {
      _advanceMinutes.add(minutes);
      _customAdvanceCtrl.clear();
    });
  }

  List<int> _normalizedAdvances() {
    final values = _advanceMinutes.where((minutes) => minutes >= 0).toSet();
    if (values.isEmpty) values.add(0);
    return values.toList()..sort((a, b) => b.compareTo(a));
  }

  String _scheduleLabel(String value) {
    return switch (value) {
      'daily' => '每天',
      'weekly' => '每周',
      'every_n_days' => '每 $_scheduleInterval 天',
      'monthly' => '每月$_scheduleDay号',
      _ => '不重复',
    };
  }

  static String _disturbanceLabel(String value) {
    return switch (value) {
      'strong' => '强提醒',
      'silent' => '静默',
      _ => '普通提醒',
    };
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventTime,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
      helpText: '选择事件日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null) return;
    setState(() {
      _eventTime = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _eventTime.hour,
        _eventTime.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_eventTime),
      helpText: '选择事件时间',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null) return;
    setState(() {
      _eventTime = DateTime(
        _eventTime.year,
        _eventTime.month,
        _eventTime.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _eventTime.add(const Duration(days: 30)),
      firstDate: _eventTime,
      lastDate: DateTime(2100),
      helpText: '选择重复截止日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null) return;
    setState(() => _endDate = picked);
  }

  void _submit() {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      setState(() => _errorText = '请填写事件内容');
      return;
    }
    Navigator.pop(
      context,
      TimelineEventFormData(
        content: content,
        eventTime: _eventTime,
        durationMinutes: _parseDuration(),
        location: _locationCtrl.text.trim(),
        reminder: ReminderFormData(
          enabled: _reminderEnabled,
          importance: _importance,
          disturbanceLevel: _disturbanceLevel,
          scheduleType: _scheduleType,
          scheduleInterval: _scheduleInterval,
          scheduleDay: _scheduleType == 'monthly' ? _scheduleDay : null,
          advanceMinutes: _normalizedAdvances(),
          displayMode: _displayMode,
          endDate: _endDate,
          byDay: _scheduleType == 'weekly' ? (_byDay.toList()..sort()) : null,
        ),
      ),
    );
  }

  int? _parseDuration() {
    final value = int.tryParse(_durationCtrl.text.trim());
    return value != null && value > 0 && value <= 1440 ? value : null;
  }
}
