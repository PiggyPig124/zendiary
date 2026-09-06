import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/zen_theme.dart';
import '../../services/today_focus_service.dart';

/// A compact, read-only cue for the item currently occupying the student's
/// attention and the next explicitly scheduled item.
class TodayFocusCard extends StatelessWidget {
  final TodayFocus focus;
  final ValueChanged<TodayFocusItem> onItemTap;

  const TodayFocusCard({
    super.key,
    required this.focus,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: ZenTheme.backgroundPale,
        border: Border.all(color: ZenTheme.borderSage),
        borderRadius: BorderRadius.circular(ZenTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.schedule_outlined,
                size: 18,
                color: ZenTheme.accentMatcha,
              ),
              const SizedBox(width: 8),
              Text('当前安排', style: ZenTheme.labelMedium),
            ],
          ),
          const SizedBox(height: 6),
          if (focus.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('现在没有安排，按自己的节奏选择下一件事。'),
            )
          else ...[
            if (focus.current.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Text('现在没有正在进行的安排', style: ZenTheme.labelSmall),
              ),
            if (focus.current.isNotEmpty)
              ...focus.current.map((item) => _itemTile(item)),
            if (focus.next.isNotEmpty) ...[
              if (focus.current.isNotEmpty)
                const Divider(height: 16, color: ZenTheme.borderSubtle),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('接下来', style: ZenTheme.labelMedium),
              ),
              ...focus.next.map((item) => _itemTile(item)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _itemTile(TodayFocusItem focusItem) {
    final item = focusItem.item;
    final time = focusItem.endAt == null
        ? '${DateFormat('HH:mm').format(focusItem.startAt)} · 未设置结束时间'
        : '${DateFormat('HH:mm').format(focusItem.startAt)}–${DateFormat('HH:mm').format(focusItem.endAt!)}';
    final kind = focusItem.isEvent ? '课程 / 日程' : '待办';
    final metadata = [
      time,
      kind,
      if (focusItem.warning != null) focusItem.warning!,
    ].join(' · ');
    return Material(
      color: ZenTheme.transparent,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        leading: Icon(
          focusItem.isEvent ? Icons.event_outlined : Icons.check_box_outlined,
          size: 18,
          color: focusItem.isEvent ? ZenTheme.accentMatcha : ZenTheme.textMuted,
        ),
        title: Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: ZenTheme.textStyle(fontSize: 14),
        ),
        subtitle: Text(metadata, style: ZenTheme.labelSmall),
        onTap: () => onItemTap(focusItem),
      ),
    );
  }
}
