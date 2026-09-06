import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/zen_theme.dart';
import '../../models/diary_entry.dart';
import '../../models/notebook_entry.dart';
import '../../models/pending_action_preview.dart';
import '../../providers/app_providers.dart';
import '../../providers/notebook_provider.dart';
import '../../providers/reminder_rule_provider.dart';
import '../../services/pending_action_service.dart';
import '../../services/pending_confirmation_service.dart';
import '../../views/settings/settings_view.dart';
import '../common/multi_select_bar.dart';
import '../common/page_header.dart';
import '../timeline/timeline_shared.dart';

final draftInputFocusNode = FocusNode();

class DraftView extends ConsumerStatefulWidget {
  const DraftView({super.key});

  @override
  DraftViewState createState() => DraftViewState();
}

class DraftViewState extends ConsumerState<DraftView> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _selectedIds = {};

  void focusInput() {
    draftInputFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    draftInputFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submitEntry() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('已保存到随笔，正在尝试 AI 整理...'),
        duration: Duration(seconds: 2),
      ),
    );

    final result = await ref.read(allEntriesProvider.notifier).addEntry(text);
    if (!mounted) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(_messageForOutcome(result.outcome)),
        duration: const Duration(seconds: 2),
      ),
    );

    if (result.reminderConfirmation != null) {
      await _showReminderConfirmation(result.reminderConfirmation!);
    } else if (result.pendingActionPreview != null) {
      await _showPendingActionPreview(result.pendingActionPreview!);
    }
  }

  String _messageForOutcome(DiaryAddOutcome outcome) {
    return switch (outcome) {
      DiaryAddOutcome.savedOnly => '已保存到随笔',
      DiaryAddOutcome.aiDisabled => '已保存到随笔，AI 未启用',
      DiaryAddOutcome.aiNotConfigured => '已保存到随笔，AI 配置不完整',
      DiaryAddOutcome.aiFailed => '已保存到随笔，AI 暂时不可用',
      DiaryAddOutcome.localUpdated => '已用本地规则整理',
      DiaryAddOutcome.localTodoCreated => '已用本地规则整理到待办',
      DiaryAddOutcome.aiUpdated => '已保存，AI 已完成整理',
      DiaryAddOutcome.todoCreated => '已保存，AI 已生成待办',
      DiaryAddOutcome.noteCreated => '已保存，AI 已归档到笔记',
      DiaryAddOutcome.reminderNeedsConfirmation => 'AI 已生成提醒候选，请确认',
      DiaryAddOutcome.localReminderNeedsConfirmation => '已识别提醒候选，请确认',
      DiaryAddOutcome.pendingActionNeedsConfirmation => 'AI 已生成操作预览，请确认',
    };
  }

  Future<void> _showReminderConfirmation(
    AiReminderConfirmation confirmation,
  ) async {
    final intent = confirmation.intent;
    final entry = confirmation.entry;
    final advanceText = intent.reminder.advanceMinutes.isEmpty
        ? '到点'
        : intent.reminder.advanceMinutes
              .map((minutes) => minutes == 0 ? '到点' : '提前 $minutes 分钟')
              .join('、');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认重要提醒'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.aiSummary ?? entry.content),
              const SizedBox(height: 10),
              Text('重要度：${_importanceLabel(intent.importance)}'),
              Text('打扰级别：${_disturbanceLabel(intent.disturbanceLevel)}'),
              Text('重复：${_scheduleLabel(intent.reminder.scheduleType)}'),
              Text('提醒：$advanceText'),
              if (intent.missingInfo.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('缺少信息：${intent.missingInfo.join('、')}'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('不保存提醒'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认保存'),
          ),
        ],
      ),
    );
    if (confirmed == false) {
      PendingConfirmationService.clear(entry.id);
    }
    if (confirmed != true || !mounted) return;
    ref.read(allEntriesProvider.notifier).confirmAiReminder(confirmation);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('提醒规则已保存'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _showPendingActionPreview(PendingActionPreview preview) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(preview.title),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(preview.reason),
                const SizedBox(height: 12),
                if (preview.rangeStart != null && preview.rangeEnd != null)
                  Text(
                    '范围：${DateFormat('MM-dd').format(preview.rangeStart!)} 至 ${DateFormat('MM-dd').format(preview.rangeEnd!)}',
                  ),
                const SizedBox(height: 8),
                Text('将影响 ${preview.affectedCount} 项'),
                const SizedBox(height: 12),
                ..._previewLines(preview),
                if (preview.protectedItems.isNotEmpty) ...[
                  const Divider(height: 24),
                  const Text('保留不处理'),
                  const SizedBox(height: 6),
                  ...preview.protectedItems
                      .take(6)
                      .map((item) => Text('• $item')),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: preview.isEmpty
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('确认执行'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      PendingActionService.clear(preview);
      return;
    }
    _applyPendingActionPreview(preview);
  }

  List<Widget> _previewLines(PendingActionPreview preview) {
    final lines = <String>[
      ...preview.events.map(
        (entry) => '时间线：${entry.aiSummary ?? entry.content}',
      ),
      ...preview.todos.map((todo) => '待办：${todo.title}'),
      ...preview.rules.map((rule) => '提醒：${rule.title}'),
    ];
    if (lines.isEmpty) return [const Text('没有找到可处理的事项')];
    return lines.take(12).map((line) => Text('• $line')).toList();
  }

  void _applyPendingActionPreview(PendingActionPreview preview) {
    PendingActionService.clear(preview);
    final ruleIds = preview.rules.map((rule) => rule.id).toSet();
    if (preview.type == PendingActionType.lowLoad) {
      ref.read(reminderRuleProvider.notifier).pauseRules(ruleIds);
      ref
          .read(lowLoadStatusProvider.notifier)
          .activate(
            LowLoadStatus(
              active: true,
              reason: preview.reason,
              startedAt: DateTime.now(),
              until: preview.rangeEnd,
              affectedCount: preview.affectedCount,
            ),
          );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('低负荷安排已开启'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    ref.read(reminderRuleProvider.notifier).disableRules(ruleIds);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('未来提醒规则已停用'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  static String _importanceLabel(String value) {
    return switch (value) {
      'important' => '重要',
      'minor' => '小事',
      _ => '普通',
    };
  }

  static String _disturbanceLabel(String value) {
    return switch (value) {
      'strong' => '强提醒',
      'silent' => '静默',
      _ => '普通提醒',
    };
  }

  static String _scheduleLabel(String value) {
    return switch (value) {
      'daily' => '每天',
      'weekly' => '每周',
      'every_n_days' => '重复',
      'monthly' => '每月',
      _ => '不重复',
    };
  }

  @override
  Widget build(BuildContext context) {
    final drafts = ref.watch(draftEntriesProvider);
    final aiSettings = ref.watch(aiSettingsProvider);
    final isSelecting = _selectedIds.isNotEmpty;

    return Column(
      children: [
        PageHeader(
          title: '随笔',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AiStatusSwitch(
                enabled: aiSettings.enabled,
                configured: aiSettings.isConfigured,
                onChanged: (value) async {
                  await ref
                      .read(aiSettingsProvider.notifier)
                      .save(aiSettings.copyWith(enabled: value));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        value
                            ? (aiSettings.isConfigured
                                  ? 'AI 已开启'
                                  : 'AI 已开启，但配置还不完整')
                            : 'AI 已关闭',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                icon: Icon(
                  isSelecting ? Icons.select_all : Icons.checklist,
                  size: 16,
                ),
                label: Text(isSelecting ? '全选' : '多选'),
                onPressed: drafts.isEmpty
                    ? null
                    : () {
                        setState(() {
                          if (isSelecting &&
                              _selectedIds.length != drafts.length) {
                            _selectedIds
                              ..clear()
                              ..addAll(drafts.map((entry) => entry.id));
                          } else if (isSelecting) {
                            _selectedIds.clear();
                          } else {
                            _selectedIds.add(drafts.first.id);
                          }
                        });
                      },
              ),
            ],
          ),
        ),
        Expanded(
          child: drafts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.auto_awesome_outlined,
                        size: 48,
                        color: ZenTheme.textCompleted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '在下方写下第一条随笔',
                        style: TextStyle(
                          color: ZenTheme.textCompleted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  itemCount: drafts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 1),
                  itemBuilder: (context, i) => _DraftCard(
                    entry: drafts[i],
                    isSelecting: isSelecting,
                    isSelected: _selectedIds.contains(drafts[i].id),
                    onToggleSelected: () => _toggleSelection(drafts[i].id),
                  ),
                ),
        ),
        if (isSelecting)
          MultiSelectBar(
            count: _selectedIds.length,
            onCancel: () => setState(_selectedIds.clear),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('转待办'),
                onPressed: () => _bulkAddToTodo(drafts),
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('删除'),
                onPressed: _bulkDelete,
              ),
            ],
          )
        else
          _buildInputArea(),
      ],
    );
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.add(id)) {
        _selectedIds.remove(id);
      }
    });
  }

  void _bulkAddToTodo(List<DiaryEntry> drafts) {
    final selected = drafts.where((entry) => _selectedIds.contains(entry.id));
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

  void _bulkDelete() {
    final count = _selectedIds.length;
    ref.read(allEntriesProvider.notifier).deleteEntries(_selectedIds);
    setState(_selectedIds.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除 $count 条随笔'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      decoration: BoxDecoration(
        color: ZenTheme.backgroundWarm,
        border: Border(top: BorderSide(color: ZenTheme.borderSubtle)),
        boxShadow: [
          BoxShadow(
            color: ZenTheme.shadowInk.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.enter) {
                  if (HardwareKeyboard.instance.isShiftPressed) {
                    return KeyEventResult.ignored;
                  }
                  _submitEntry();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _controller,
                focusNode: draftInputFocusNode,
                maxLines: null,
                minLines: 1,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontSize: 15, height: 1.6),
                decoration: InputDecoration(
                  hintText: '随便写点什么... 时间、任务、灵感都可以',
                  hintStyle: TextStyle(
                    color: ZenTheme.textCompleted,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SendButton(onTap: _submitEntry),
        ],
      ),
    );
  }
}

class _AiStatusSwitch extends StatelessWidget {
  final bool enabled;
  final bool configured;
  final ValueChanged<bool> onChanged;

  const _AiStatusSwitch({
    required this.enabled,
    required this.configured,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? (configured ? ZenTheme.accentGreen : ZenTheme.statusToday)
        : ZenTheme.textMuted;
    return Tooltip(
      message: enabled ? (configured ? 'AI 已开启' : 'AI 已开启，但配置不完整') : 'AI 已关闭',
      child: Container(
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          color: enabled ? ZenTheme.statusSuccessBg : ZenTheme.backgroundWarm,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: enabled
                ? ZenTheme.statusSuccessBorder
                : ZenTheme.borderButton,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              'AI ${enabled ? '开' : '关'}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            Transform.scale(
              scale: 0.72,
              child: Switch(
                value: enabled,
                onChanged: onChanged,
                activeThumbColor: ZenTheme.accentGreen,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftCard extends ConsumerWidget {
  final DiaryEntry entry;
  final bool isSelecting;
  final bool isSelected;
  final VoidCallback onToggleSelected;

  const _DraftCard({
    required this.entry,
    required this.isSelecting,
    required this.isSelected,
    required this.onToggleSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeStr = DateFormat('HH:mm').format(entry.timestamp);
    final dateStr = DateFormat('MM-dd').format(entry.timestamp);

    return GestureDetector(
      onTap: isSelecting ? onToggleSelected : null,
      onLongPress: onToggleSelected,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
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
              width: 44,
              child: Column(
                children: [
                  Text(
                    timeStr,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ZenTheme.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 10,
                      color: ZenTheme.textCompleted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 1.5,
              height: 48,
              color: ZenTheme.borderButton,
              margin: const EdgeInsets.symmetric(horizontal: 12),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.content,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: ZenTheme.textHeading,
                    ),
                  ),
                  if (entry.aiSummary != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '摘要：${entry.aiSummary}',
                      style: TextStyle(
                        fontSize: 12,
                        color: ZenTheme.textMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  if (entry.sentimentReply != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.sentimentReply!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ZenTheme.textMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!isSelecting)
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: ZenTheme.textCompleted,
                ),
                onSelected: (val) {
                  if (val == 'todo') {
                    ref
                        .read(todoListProvider.notifier)
                        .addTodo(
                          entry.aiSummary ?? entry.content,
                          sourceEntryId: entry.id,
                        );
                    _showSnack(context, '已添加到待办');
                  } else if (val == 'event') {
                    _showEventDialog(context, ref);
                  } else if (val == 'note') {
                    _createNote(ref);
                    _showSnack(context, '已转为笔记');
                  } else if (val == 'edit') {
                    _showEditDialog(context, ref);
                  } else if (val == 'delete') {
                    ref.read(allEntriesProvider.notifier).deleteEntry(entry.id);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'todo', child: Text('转为待办')),
                  PopupMenuItem(value: 'event', child: Text('转为时间线事件')),
                  PopupMenuItem(value: 'note', child: Text('转为笔记')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      '删除',
                      style: TextStyle(color: ZenTheme.statusError),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _createNote(WidgetRef ref) {
    final titleSource = entry.aiSummary ?? entry.content;
    final title = titleSource.length > 18
        ? '${titleSource.substring(0, 18)}...'
        : titleSource;
    ref
        .read(notebookListProvider.notifier)
        .addNote(
          NotebookEntry(
            title: title.trim().isEmpty ? '无标题' : title.trim(),
            content: entry.content,
            tags: entry.tags,
          ),
        );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: entry.content);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('编辑随笔'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                ref.read(allEntriesProvider.notifier).editEntry(entry.id, text);
              }
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEventDialog(BuildContext context, WidgetRef ref) async {
    final data = await showDialog<TimelineEventFormData>(
      context: context,
      builder: (_) => TimelineEventDialog(
        initialContent: entry.aiSummary ?? entry.content,
        initialTime: DateTime.now(),
        initialDurationMinutes: entry.durationMinutes,
        initialLocation: entry.location ?? '',
        initialReminder: ReminderFormData.defaults(),
        isEdit: false,
      ),
    );
    if (data == null || !context.mounted) return;

    final updatedEntry = entry.copyWith(
      category: 'event',
      eventTime: data.eventTime,
      durationMinutes: data.durationMinutes,
      location: data.location,
      clearLocation: data.location.isEmpty,
    );
    ref.read(allEntriesProvider.notifier).editEntryFull(updatedEntry);
    syncEventReminderRule(ref, updatedEntry, data.reminder);
    _showSnack(context, '已加入时间线');
  }

  void _showSnack(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }
}

class _SendButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SendButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: ZenTheme.accentMatcha,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.arrow_upward_rounded,
          color: ZenTheme.backgroundCard,
          size: 18,
        ),
      ),
    );
  }
}
