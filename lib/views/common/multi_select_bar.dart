import 'package:flutter/material.dart';

import '../../core/theme/zen_theme.dart';

class MultiSelectBar extends StatelessWidget {
  final int count;
  final VoidCallback onCancel;
  final List<Widget> actions;

  const MultiSelectBar({
    super.key,
    required this.count,
    required this.onCancel,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      decoration: BoxDecoration(
        color: ZenTheme.backgroundCard,
        border: const Border(top: BorderSide(color: ZenTheme.borderButton)),
        boxShadow: [
          BoxShadow(
            color: ZenTheme.shadowInk.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            '已选择 $count 项',
            style: ZenTheme.textStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ZenTheme.interactiveBrown,
            ),
          ),
          const Spacer(),
          ...actions,
          const SizedBox(width: 8),
          TextButton(onPressed: onCancel, child: const Text('取消')),
        ],
      ),
    );
  }
}
