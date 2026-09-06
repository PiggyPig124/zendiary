import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/zen_theme.dart';
import '../providers/app_providers.dart';
import 'common/search_overlay.dart';
import 'navigation_state.dart';
export 'navigation_state.dart';
import 'draft/draft_view.dart';
import 'settings/settings_view.dart';
import 'notebook/notebook_view.dart';
import 'workspace/workspace_views.dart';

final GlobalKey<ScaffoldState> mainScaffoldKey = GlobalKey<ScaffoldState>();

// Compatibility aliases for existing pages and global shortcuts.
const int navIndexMorning = navIndexToday;
const int navIndexDraft = navIndexInbox;
const int navIndexTimeline = navIndexPlan;
const int navIndexReminder = navIndexPlan;
const int navIndexTodo = navIndexPlan;
const int navIndexNotebook = navIndexNotes;

class MainLayout extends ConsumerWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navIndex = ref.watch(navIndexProvider);
    final density = ref.watch(uiDensityProvider);
    final visualDensity = switch (density) {
      // Comfortable gives controls their platform default hit area. Standard
      // is intentionally a little tighter for the desktop workbench, while
      // compact also reduces vertical growth on small phone screens.
      UiDensity.comfortable => VisualDensity.standard,
      UiDensity.standard => VisualDensity.compact,
      UiDensity.compact => const VisualDensity(horizontal: -2, vertical: -2),
    };
    return Theme(
      data: Theme.of(context).copyWith(visualDensity: visualDensity),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 600;
          final selectedContentIndex = navIndex.clamp(0, 4).toInt();
          final content = IndexedStack(
            index: selectedContentIndex,
            children: const [
              TodayView(),
              PlanView(),
              InboxView(),
              NotebookView(pageTitle: '笔记', createLabel: '新建笔记'),
              SettingsView(),
            ],
          );

          if (isMobile) {
            return Scaffold(
              key: mainScaffoldKey,
              body: SafeArea(
                child: Column(
                  children: [
                    SizedBox(
                      height: 38,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '搜索（Ctrl + F）',
                              onPressed: () => showDialog(
                                context: context,
                                builder: (_) => const SearchOverlay(),
                              ),
                              icon: const Icon(Icons.search, size: 19),
                            ),
                            IconButton(
                              tooltip: navIndex == navIndexSettings
                                  ? '返回今天'
                                  : '设置',
                              onPressed: () => ref
                                  .read(navIndexProvider.notifier)
                                  .setIndex(
                                    navIndex == navIndexSettings
                                        ? navIndexToday
                                        : navIndexSettings,
                                  ),
                              icon: Icon(
                                navIndex == navIndexSettings
                                    ? Icons.arrow_back
                                    : Icons.settings_outlined,
                                size: 19,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(child: content),
                  ],
                ),
              ),
              floatingActionButton: navIndex == navIndexInbox
                  ? null
                  : FloatingActionButton.small(
                      backgroundColor: ZenTheme.accentMatcha,
                      foregroundColor: ZenTheme.contentOnAccent,
                      tooltip: '快速捕捉',
                      onPressed: () {
                        ref
                            .read(navIndexProvider.notifier)
                            .setIndex(navIndexInbox);
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => draftInputFocusNode.requestFocus(),
                        );
                      },
                      child: const Icon(Icons.add),
                    ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: navIndex < 4 ? navIndex : 0,
                onDestinationSelected: (index) =>
                    ref.read(navIndexProvider.notifier).setIndex(index),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.wb_sunny_outlined),
                    selectedIcon: Icon(Icons.wb_sunny),
                    label: '今天',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.calendar_view_week_outlined),
                    selectedIcon: Icon(Icons.calendar_view_week),
                    label: '计划',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.inbox_outlined),
                    selectedIcon: Icon(Icons.inbox),
                    label: '收件箱',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.notes_outlined),
                    selectedIcon: Icon(Icons.notes),
                    label: '笔记',
                  ),
                ],
              ),
            );
          }

          return Scaffold(
            key: mainScaffoldKey,
            body: Row(
              children: [
                _DesktopRail(
                  selectedIndex: navIndex < 4 ? navIndex : null,
                  onSelected: (index) =>
                      ref.read(navIndexProvider.notifier).setIndex(index),
                  onCapture: () {
                    ref.read(navIndexProvider.notifier).setIndex(navIndexInbox);
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => draftInputFocusNode.requestFocus(),
                    );
                  },
                  onSearch: () => showDialog(
                    context: context,
                    builder: (_) => const SearchOverlay(),
                  ),
                  onSettings: () => ref
                      .read(navIndexProvider.notifier)
                      .setIndex(navIndexSettings),
                  settingsSelected: navIndex == navIndexSettings,
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1280),
                      child: SizedBox.expand(child: content),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DesktopRail extends StatelessWidget {
  final int? selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onCapture;
  final VoidCallback onSearch;
  final VoidCallback onSettings;
  final bool settingsSelected;

  const _DesktopRail({
    required this.selectedIndex,
    required this.onSelected,
    required this.onCapture,
    required this.onSearch,
    required this.onSettings,
    required this.settingsSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      decoration: const BoxDecoration(
        color: ZenTheme.backgroundMuted,
        border: Border(right: BorderSide(color: ZenTheme.borderSubtle)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 18),
          Text(
            'Z',
            style: ZenTheme.headingZen.copyWith(color: ZenTheme.accentMatcha),
          ),
          const SizedBox(height: 10),
          Tooltip(
            message: '快速捕捉（Alt + Space）',
            child: IconButton(
              onPressed: onCapture,
              icon: const Icon(Icons.add, size: 19),
              style: IconButton.styleFrom(
                backgroundColor: ZenTheme.accentMatcha,
                foregroundColor: ZenTheme.contentOnAccent,
                minimumSize: const Size(38, 38),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Tooltip(
            message: '搜索（Ctrl + F）',
            child: IconButton(
              onPressed: onSearch,
              icon: const Icon(Icons.search, size: 19),
              style: IconButton.styleFrom(
                foregroundColor: ZenTheme.textMuted,
                minimumSize: const Size(38, 38),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 4),
          NavigationRail(
            backgroundColor: ZenTheme.transparent,
            selectedIndex: selectedIndex,
            onDestinationSelected: onSelected,
            labelType: NavigationRailLabelType.all,
            groupAlignment: -0.9,
            minWidth: 80,
            selectedIconTheme: const IconThemeData(
              color: ZenTheme.accentMatcha,
            ),
            unselectedIconTheme: const IconThemeData(color: ZenTheme.textMuted),
            selectedLabelTextStyle: ZenTheme.labelSmall.copyWith(
              color: ZenTheme.accentMatcha,
            ),
            unselectedLabelTextStyle: ZenTheme.labelSmall,
            indicatorColor: ZenTheme.interactivePressed,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.wb_sunny_outlined, size: 19),
                selectedIcon: Icon(Icons.wb_sunny, size: 19),
                label: Text('今天'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.calendar_view_week_outlined, size: 19),
                selectedIcon: Icon(Icons.calendar_view_week, size: 19),
                label: Text('计划'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.inbox_outlined, size: 19),
                selectedIcon: Icon(Icons.inbox, size: 19),
                label: Text('收件箱'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.notes_outlined, size: 19),
                selectedIcon: Icon(Icons.notes, size: 19),
                label: Text('笔记'),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            tooltip: '设置',
            onPressed: onSettings,
            style: IconButton.styleFrom(
              backgroundColor: settingsSelected
                  ? ZenTheme.interactivePressed
                  : ZenTheme.transparent,
            ),
            icon: Icon(
              settingsSelected ? Icons.settings : Icons.settings_outlined,
              size: 19,
              color: settingsSelected
                  ? ZenTheme.accentMatcha
                  : ZenTheme.textMuted,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
