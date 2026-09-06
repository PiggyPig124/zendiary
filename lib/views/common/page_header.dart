import 'package:flutter/material.dart';

import '../../core/theme/zen_theme.dart';

class PageHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const PageHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 20, 0),
            child: Row(
              children: [
                Text(title, style: ZenTheme.headingPage),
                if (trailing != null) ...[const Spacer(), trailing!],
              ],
            ),
          ),
        ),
        Container(
          height: 1,
          color: ZenTheme.borderSubtle.withValues(alpha: 0.5),
        ),
      ],
    );
  }
}
