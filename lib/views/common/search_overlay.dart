import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/zen_theme.dart';
import '../../models/diary_entry.dart';
import '../../models/notebook_entry.dart';
import '../../models/reminder_rule.dart';
import '../../models/todo_task.dart';
import '../../models/unified_item.dart';
import '../../providers/app_providers.dart';
import '../../providers/notebook_provider.dart';
import '../../providers/reminder_rule_provider.dart';
import '../main_layout.dart';
import '../timeline/timeline_shared.dart';
import '../workspace/workspace_views.dart';

enum _SearchTypeFilter { all, todo, event, note, draft, reminder }

enum _SearchStatusFilter { all, open, completed, overdue }

enum _SearchDateFilter { all, today, upcoming, overdue }

/// 全局搜索浮层。
///
/// 搜索随笔、时间线事件、待办、笔记的标题和内容。
/// 点击结果跳转到对应视图。
class SearchOverlay extends ConsumerStatefulWidget {
  const SearchOverlay({super.key});

  @override
  ConsumerState<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends ConsumerState<SearchOverlay> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  _SearchTypeFilter _typeFilter = _SearchTypeFilter.all;
  _SearchStatusFilter _statusFilter = _SearchStatusFilter.all;
  _SearchDateFilter _dateFilter = _SearchDateFilter.all;
  String? _tagFilter;
  String? _priorityFilter;

  @override
  void dispose() {
    _queryCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _queryCtrl.text.trim().toLowerCase();
    final knownTags =
        ref
            .watch(unifiedItemsProvider)
            .expand((item) => item.tags)
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final hasFilters =
        _typeFilter != _SearchTypeFilter.all ||
        _statusFilter != _SearchStatusFilter.all ||
        _dateFilter != _SearchDateFilter.all ||
        _tagFilter != null ||
        _priorityFilter != null;
    final results = query.isEmpty && !hasFilters
        ? const <_SearchResult>[]
        : _search(
            ref,
            query,
            typeFilter: _typeFilter,
            statusFilter: _statusFilter,
            dateFilter: _dateFilter,
            priorityFilter: _priorityFilter,
            tagFilter: _tagFilter,
          );

    return AlertDialog(
      backgroundColor: ZenTheme.backgroundCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: TextField(
        controller: _queryCtrl,
        focusNode: _focusNode,
        autofocus: true,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: '搜索随笔、事件、待办、笔记...',
          hintStyle: TextStyle(color: ZenTheme.textCompleted, fontSize: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: ZenTheme.borderCard),
          ),
          prefixIcon: const Icon(
            Icons.search,
            size: 20,
            color: ZenTheme.interactiveBrown,
          ),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => setState(() => _queryCtrl.clear()),
                )
              : null,
          filled: true,
          fillColor: ZenTheme.backgroundWarm,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
        onChanged: (_) => setState(() {}),
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFilters(knownTags),
            const SizedBox(height: 8),
            if (query.isEmpty && !hasFilters)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    '输入关键词开始搜索，或先选择筛选条件',
                    style: TextStyle(
                      fontSize: 13,
                      color: ZenTheme.textCompleted,
                    ),
                  ),
                ),
              )
            else if (results.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    query.isEmpty ? '没有符合筛选条件的内容' : '没有找到匹配"$query"的内容',
                    style: TextStyle(
                      fontSize: 13,
                      color: ZenTheme.textCompleted,
                    ),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (context, i) => _ResultTile(
                    result: results[i],
                    query: query,
                    onTap: () {
                      final result = results[i];
                      _navigateTo(ref, result);
                      Navigator.pop(context);
                      final item = result.item;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final rootContext = mainScaffoldKey.currentContext;
                        if (rootContext != null) {
                          showUnifiedItemDetails(rootContext, ref, item);
                        }
                      });
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildFilters(List<String> knownTags) {
    Widget menu<T>({
      required String label,
      required List<(T, String)> options,
      required ValueChanged<T> onSelected,
    }) {
      return PopupMenuButton<T>(
        tooltip: label,
        onSelected: onSelected,
        itemBuilder: (_) => options
            .map(
              (option) =>
                  PopupMenuItem<T>(value: option.$1, child: Text(option.$2)),
            )
            .toList(),
        child: Chip(
          label: Text(label),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          menu<_SearchTypeFilter>(
            label: _typeLabel(_typeFilter),
            options: const [
              (_SearchTypeFilter.all, '全部类型'),
              (_SearchTypeFilter.todo, '待办'),
              (_SearchTypeFilter.event, '事件'),
              (_SearchTypeFilter.note, '笔记'),
              (_SearchTypeFilter.draft, '随笔'),
              (_SearchTypeFilter.reminder, '提醒'),
            ],
            onSelected: (value) => setState(() => _typeFilter = value),
          ),
          const SizedBox(width: 4),
          menu<_SearchStatusFilter>(
            label: _statusLabel(_statusFilter),
            options: const [
              (_SearchStatusFilter.all, '全部状态'),
              (_SearchStatusFilter.open, '未完成'),
              (_SearchStatusFilter.completed, '已完成'),
              (_SearchStatusFilter.overdue, '逾期'),
            ],
            onSelected: (value) => setState(() => _statusFilter = value),
          ),
          const SizedBox(width: 4),
          menu<_SearchDateFilter>(
            label: _dateLabel(_dateFilter),
            options: const [
              (_SearchDateFilter.all, '全部日期'),
              (_SearchDateFilter.today, '今天'),
              (_SearchDateFilter.upcoming, '未来'),
              (_SearchDateFilter.overdue, '已逾期'),
            ],
            onSelected: (value) => setState(() => _dateFilter = value),
          ),
          const SizedBox(width: 4),
          menu<String>(
            label: _priorityFilter == null ? '优先级' : '优先级 $_priorityFilter',
            options: const [
              ('__all__', '全部优先级'),
              ('A', 'A · 重要'),
              ('B', 'B · 普通'),
              ('C', 'C · 次要'),
            ],
            onSelected: (value) => setState(
              () => _priorityFilter = value == '__all__' ? null : value,
            ),
          ),
          if (knownTags.isNotEmpty) ...[
            const SizedBox(width: 4),
            menu<String>(
              label: _tagFilter == null ? '标签' : '#$_tagFilter',
              options: [
                ('__all__', '全部标签'),
                ...knownTags.map((tag) => (tag, '#$tag')),
              ],
              onSelected: (value) => setState(
                () => _tagFilter = value == '__all__' ? null : value,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _typeLabel(_SearchTypeFilter value) => switch (value) {
    _SearchTypeFilter.all => '类型',
    _SearchTypeFilter.todo => '待办',
    _SearchTypeFilter.event => '事件',
    _SearchTypeFilter.note => '笔记',
    _SearchTypeFilter.draft => '随笔',
    _SearchTypeFilter.reminder => '提醒',
  };

  static String _statusLabel(_SearchStatusFilter value) => switch (value) {
    _SearchStatusFilter.all => '状态',
    _SearchStatusFilter.open => '未完成',
    _SearchStatusFilter.completed => '已完成',
    _SearchStatusFilter.overdue => '逾期',
  };

  static String _dateLabel(_SearchDateFilter value) => switch (value) {
    _SearchDateFilter.all => '日期',
    _SearchDateFilter.today => '今天',
    _SearchDateFilter.upcoming => '未来',
    _SearchDateFilter.overdue => '已逾期',
  };

  static List<_SearchResult> _search(
    WidgetRef ref,
    String query, {
    required _SearchTypeFilter typeFilter,
    required _SearchStatusFilter statusFilter,
    required _SearchDateFilter dateFilter,
    required String? priorityFilter,
    required String? tagFilter,
  }) {
    final results = <_SearchResult>[];
    final now = DateTime.now();

    void addResult({
      required UnifiedItem item,
      required String searchable,
      required String type,
      required IconData icon,
    }) {
      if (query.isNotEmpty && !searchable.toLowerCase().contains(query)) {
        return;
      }
      if (!_matchesFilters(
        item,
        now: now,
        typeFilter: typeFilter,
        statusFilter: statusFilter,
        dateFilter: dateFilter,
        priorityFilter: priorityFilter,
        tagFilter: tagFilter,
      )) {
        return;
      }
      results.add(
        _SearchResult(
          item: item,
          title: item.title,
          subtitle: _itemSubtitle(item),
          type: type,
          icon: icon,
          navCallback: (ref) => _navigateItem(ref, item),
        ),
      );
    }

    // Search the same presentation model used by Today, Plan and Inbox.
    // Besides keeping labels and status consistent, this prevents a note
    // copied from the legacy diary box from appearing twice in search.
    final entries = ref.read(allEntriesProvider);
    final todos = ref.read(todoListProvider);
    final notes = ref.read(notebookListProvider);
    final rules = ref.read(reminderRuleProvider);
    final items = ref.read(unifiedItemsProvider);
    for (final item in items) {
      final extraText = switch (item.source) {
        UnifiedItemSource.event || UnifiedItemSource.draft => entries
            .cast<DiaryEntry?>()
            .firstWhere(
              (entry) => entry?.id == item.id,
              orElse: () => null,
            )
            ?.content,
        UnifiedItemSource.note =>
          entries
              .cast<DiaryEntry?>()
              .firstWhere(
                (entry) => entry?.id == item.id && entry?.category == 'note',
                orElse: () => null,
              )
              ?.content ??
          notes
              .cast<NotebookEntry?>()
              .firstWhere(
                (note) => note?.id == item.id,
                orElse: () => null,
              )
              ?.content,
        UnifiedItemSource.todo => todos
            .cast<TodoTask?>()
            .firstWhere(
              (todo) => todo?.id == item.id,
              orElse: () => null,
            )
            ?.category,
        UnifiedItemSource.reminder => rules
            .cast<ReminderRule?>()
            .firstWhere(
              (rule) => rule?.id == item.id,
              orElse: () => null,
            )
            ?.note,
      };
      addResult(
        item: item,
        searchable:
            '${item.title} ${extraText ?? ''} ${item.tags.join(' ')}',
        type: _typeForSource(item.source),
        icon: _iconForSource(item.source),
      );
    }

    // 按匹配质量排序：标题完全匹配优先，其它按字母序
    results.sort((a, b) {
      final aExact = a.title.toLowerCase() == query;
      final bExact = b.title.toLowerCase() == query;
      if (aExact != bExact) return aExact ? -1 : 1;
      return a.title.compareTo(b.title);
    });

    return results.take(30).toList();
  }

  static bool _matchesFilters(
    UnifiedItem item, {
    required DateTime now,
    required _SearchTypeFilter typeFilter,
    required _SearchStatusFilter statusFilter,
    required _SearchDateFilter dateFilter,
    required String? priorityFilter,
    required String? tagFilter,
  }) {
    final typeMatches = switch (typeFilter) {
      _SearchTypeFilter.all => true,
      _SearchTypeFilter.todo => item.source == UnifiedItemSource.todo,
      _SearchTypeFilter.event => item.source == UnifiedItemSource.event,
      _SearchTypeFilter.note => item.source == UnifiedItemSource.note,
      _SearchTypeFilter.draft => item.source == UnifiedItemSource.draft,
      _SearchTypeFilter.reminder => item.source == UnifiedItemSource.reminder,
    };
    if (!typeMatches) return false;

    final statusMatches = switch (statusFilter) {
      _SearchStatusFilter.all => true,
      _SearchStatusFilter.open => !item.isCompleted && !item.isArchived,
      _SearchStatusFilter.completed => item.isCompleted,
      _SearchStatusFilter.overdue => item.isOverdue,
    };
    if (!statusMatches) return false;
    if (priorityFilter != null && item.priority != priorityFilter) return false;
    if (tagFilter != null && !item.tags.contains(tagFilter)) return false;

    // A task can have two intentionally independent dates: when to work and
    // when it must be finished. Filtering by only the first one makes a task
    // scheduled tomorrow but due today disappear from Today's search. Treat
    // any relevant date as a match while keeping navigation anchored on the
    // execution time when one exists.
    final dates = [item.startAt, item.scheduledAt, item.deadline]
        .whereType<DateTime>()
        .toList();
    return switch (dateFilter) {
      _SearchDateFilter.all => true,
      _SearchDateFilter.today => dates.any(
        (date) =>
            date.year == now.year &&
            date.month == now.month &&
            date.day == now.day,
      ),
      _SearchDateFilter.upcoming =>
        dates.any((date) => date.isAfter(_endOfToday(now))),
      _SearchDateFilter.overdue => item.isOverdue,
    };
  }

  static DateTime _endOfToday(DateTime now) =>
      DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

  static String _typeForSource(UnifiedItemSource source) => switch (source) {
    UnifiedItemSource.event => '事件',
    UnifiedItemSource.note => '笔记',
    UnifiedItemSource.draft => '随笔',
    UnifiedItemSource.todo => '待办',
    UnifiedItemSource.reminder => '提醒',
  };

  static IconData _iconForSource(UnifiedItemSource source) => switch (source) {
    UnifiedItemSource.event => Icons.event_note_outlined,
    UnifiedItemSource.note => Icons.notes_outlined,
    UnifiedItemSource.draft => Icons.edit_outlined,
    UnifiedItemSource.todo => Icons.check_circle_outline,
    UnifiedItemSource.reminder => Icons.notifications_none_outlined,
  };

  static String _itemSubtitle(UnifiedItem item) {
    final parts = <String>[];
    if (item.isArchived) {
      parts.add('已归档');
    } else if (item.isCompleted) {
      parts.add('已完成');
    } else if (item.isOverdue) {
      parts.add('逾期');
    }
    if (item.priority == 'A') parts.add('重要');
    if (item.tags.isNotEmpty) parts.add(item.tags.join(' · '));
    return parts.join(' · ');
  }

  static void _navigateTo(WidgetRef ref, _SearchResult result) {
    result.navCallback(ref);
  }

  static void _navigateItem(WidgetRef ref, UnifiedItem item) {
    final targetDay = item.startAt ?? item.scheduledAt ?? item.deadline;
    if (targetDay != null) {
      ref.read(selectedDayProvider.notifier).set(targetDay);
    }
    if (item.source == UnifiedItemSource.note) {
      ref.read(selectedNoteIdProvider.notifier).select(item.id);
    }
    final targetIndex = switch (item.source) {
      UnifiedItemSource.event => navIndexPlan,
      UnifiedItemSource.todo => navIndexPlan,
      UnifiedItemSource.reminder => navIndexPlan,
      UnifiedItemSource.note => navIndexNotes,
      UnifiedItemSource.draft => navIndexInbox,
    };
    ref.read(navIndexProvider.notifier).setIndex(targetIndex);
  }
}

class _SearchResult {
  final UnifiedItem item;
  final String title;
  final String subtitle;
  final String type;
  final IconData icon;
  final void Function(WidgetRef ref) navCallback;

  const _SearchResult({
    required this.item,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.icon,
    required this.navCallback,
  });
}

class _ResultTile extends StatelessWidget {
  final _SearchResult result;
  final String query;
  final VoidCallback onTap;

  const _ResultTile({
    required this.result,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(result.icon, size: 18, color: ZenTheme.interactiveBrown),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _highlightedText(result.title, query),
                  if (result.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      result.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: ZenTheme.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: ZenTheme.backgroundWarm,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                result.type,
                style: const TextStyle(
                  fontSize: 10,
                  color: ZenTheme.interactiveBrown,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _highlightedText(String text, String query) {
    final lower = text.toLowerCase();
    final index = lower.indexOf(query);
    if (index < 0) {
      return Text(
        text,
        style: const TextStyle(fontSize: 14, color: ZenTheme.textHeading),
      );
    }
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 14, color: ZenTheme.textHeading),
        children: [
          TextSpan(text: text.substring(0, index)),
          TextSpan(
            text: text.substring(index, index + query.length),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              backgroundColor: ZenTheme.backgroundToday,
            ),
          ),
          TextSpan(text: text.substring(index + query.length)),
        ],
      ),
    );
  }
}
