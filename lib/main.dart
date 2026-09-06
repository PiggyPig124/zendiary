import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import 'core/database/db_service.dart';
import 'core/theme/zen_theme.dart';
import 'providers/app_providers.dart';
import 'providers/reminder_rule_provider.dart';
import 'services/data_migration_service.dart';
import 'services/launch_options.dart';
import 'services/notification_target_resolver.dart';
import 'services/startup_service.dart';
import 'services/system_notification_service.dart';
import 'views/common/search_overlay.dart';
import 'views/draft/draft_view.dart';
import 'views/main_layout.dart';
import 'views/timeline/timeline_shared.dart';
import 'views/workspace/workspace_views.dart';

int? _pendingNavIndex;
bool _pendingSearch = false;
bool _shouldQuitApp = false;
bool _startInTray = false;
final _appKey = GlobalKey<_ZenDiaryAppState>();

const String _trayShowKey = 'show_window';
const String _trayHideKey = 'hide_window';
const String _trayExitKey = 'exit_app';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final dataDirectory = LaunchOptions.dataDirectoryFromArgs(args);
  if (dataDirectory != null) {
    DBService.configureDataDirectoryOverride(dataDirectory);
  }
  _startInTray = StartupService.hasBackgroundArgument(args);

  await initializeDateFormatting('zh_CN', null);
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    await hotKeyManager.unregisterAll();
  }
  await DBService.init();
  await DataMigrationService.migrateIfNeeded();
  await SystemNotificationService.setup();
  if (Platform.isWindows) {
    await _initTray();
  }

  const windowOptions = WindowOptions(
    size: Size(1100, 750),
    center: true,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  if (Platform.isWindows) {
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (_startInTray) {
        await windowManager.setSkipTaskbar(true);
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    });
  }

  final altSpace = HotKey(
    key: LogicalKeyboardKey.space,
    modifiers: [HotKeyModifier.alt],
    scope: HotKeyScope.system,
  );
  if (Platform.isWindows) {
    await hotKeyManager.register(
      altSpace,
      keyDownHandler: (_) async {
        await windowManager.show();
        await windowManager.focus();
        final app = _appKey.currentState;
        if (app == null) {
          _pendingNavIndex = navIndexDraft;
        } else {
          app.openCapture();
        }
      },
    );
  }

  final altD = HotKey(
    key: LogicalKeyboardKey.keyD,
    modifiers: [HotKeyModifier.alt],
    scope: HotKeyScope.system,
  );
  if (Platform.isWindows) {
    await hotKeyManager.register(
      altD,
      keyDownHandler: (_) async {
        await windowManager.show();
        await windowManager.focus();
        final app = _appKey.currentState;
        if (app == null) {
          _pendingNavIndex = navIndexTodo;
        } else {
          app.openPlan();
        }
      },
    );
  }

  final ctrlF = HotKey(
    key: LogicalKeyboardKey.keyF,
    modifiers: [HotKeyModifier.control],
    scope: HotKeyScope.system,
  );
  if (Platform.isWindows) {
    await hotKeyManager.register(
      ctrlF,
      keyDownHandler: (_) async {
        await windowManager.show();
        await windowManager.focus();
        final app = _appKey.currentState;
        if (app == null) {
          _pendingNavIndex = null; // 不切换 tab，在当前视图上弹出搜索
          _pendingSearch = true;
        } else {
          app.openSearch();
        }
      },
    );
  }

  runApp(ProviderScope(child: ZenDiaryApp(key: _appKey)));
}

Future<void> _initTray() async {
  final iconPath = await _prepareTrayIcon();
  await tray.trayManager.setIcon(iconPath);
  await tray.trayManager.setToolTip('ZenDiary');
  await tray.trayManager.setContextMenu(
    tray.Menu(
      items: [
        tray.MenuItem(key: _trayShowKey, label: '打开 ZenDiary'),
        tray.MenuItem(key: _trayHideKey, label: '隐藏到托盘'),
        tray.MenuItem.separator(),
        tray.MenuItem(key: _trayExitKey, label: '退出'),
      ],
    ),
  );
}

Future<String> _prepareTrayIcon() async {
  final directory = DBService.dataDirectoryPath == null
      ? await getApplicationSupportDirectory()
      : Directory(DBService.dataDirectoryPath!);
  final iconFile = File(
    '${directory.path}${Platform.pathSeparator}app_icon.ico',
  );
  final bytes = await rootBundle.load('assets/app_icon.ico');
  final iconBytes = bytes.buffer.asUint8List();
  if (!await iconFile.exists() || await iconFile.length() != iconBytes.length) {
    await iconFile.writeAsBytes(iconBytes, flush: true);
  }
  return iconFile.path;
}

class ZenDiaryApp extends ConsumerStatefulWidget {
  const ZenDiaryApp({super.key});

  @override
  ConsumerState<ZenDiaryApp> createState() => _ZenDiaryAppState();
}

class _ZenDiaryAppState extends ConsumerState<ZenDiaryApp>
    with WidgetsBindingObserver, WindowListener, tray.TrayListener {
  Timer? _midnightResetTimer;
  Timer? _runtimeReminderTimer;
  bool _runtimeReminderCheckInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isWindows) {
      windowManager.addListener(this);
      tray.trayManager.addListener(this);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingNav();
      _resetRecurringTodos();
      SystemNotificationService.setup(onClick: _openFromNotification);
      _reconcileSystemNotifications();
      _startRuntimeReminderFallback();
      _scheduleMidnightReset();
    });
  }

  void _scheduleMidnightReset() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final durationUntilMidnight = midnight.difference(now);
    _midnightResetTimer = Timer(durationUntilMidnight, () {
      _resetRecurringTodos();
      _midnightResetTimer = Timer.periodic(
        const Duration(days: 1),
        (_) => _resetRecurringTodos(),
      );
    });
  }

  void _resetRecurringTodos() {
    if (!mounted) return;
    final now = DateTime.now();
    ref.read(dayBoundaryProvider.notifier).refresh(now);
    ref.read(currentTimeProvider.notifier).refresh();
    ref.read(todoListProvider.notifier).refreshRecurringTodos(now);
  }

  @override
  void dispose() {
    _midnightResetTimer?.cancel();
    _runtimeReminderTimer?.cancel();
    if (Platform.isWindows) {
      tray.trayManager.removeListener(this);
      windowManager.removeListener(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (_shouldQuitApp) {
      await windowManager.destroy();
      return;
    }
    await _hideToTray();
  }

  @override
  void onTrayIconMouseDown() {
    _showMainWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    tray.trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(tray.MenuItem menuItem) async {
    switch (menuItem.key) {
      case _trayShowKey:
        await _showMainWindow();
        return;
      case _trayHideKey:
        await _hideToTray();
        return;
      case _trayExitKey:
        await _quitFromTray();
        return;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_pendingNavIndex != null) _checkPendingNav();
      _resetRecurringTodos();
      _runRuntimeReminderFallback();
    }
  }

  void _checkPendingNav() {
    if (_pendingSearch) {
      _pendingSearch = false;
      _openSearchOverlay();
    }
    if (_pendingNavIndex != null) {
      final target = _pendingNavIndex!;
      if (target == navIndexPlan ||
          target == navIndexTimeline ||
          target == navIndexTodo) {
        ref.read(selectedDayProvider.notifier).set(DateTime.now());
      }
      ref.read(navIndexProvider.notifier).setIndex(target);
      _pendingNavIndex = null;
      if (target == navIndexInbox || target == navIndexDraft) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => draftInputFocusNode.requestFocus(),
        );
      }
    }
  }

  /// Handles global shortcuts while the app is already mounted and visible.
  /// The old pending-only path works when the window is being restored, but a
  /// foreground window does not emit a lifecycle transition to consume it.
  void openCapture() {
    if (!mounted) return;
    ref.read(navIndexProvider.notifier).setIndex(navIndexInbox);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) draftInputFocusNode.requestFocus();
    });
  }

  void openPlan() {
    if (!mounted) return;
    // The global shortcut is an execution entry point, not a way to restore
    // an old calendar cursor. Always start from today so a student can reach
    // the next actionable plan in one step.
    ref.read(selectedDayProvider.notifier).set(DateTime.now());
    ref.read(navIndexProvider.notifier).setIndex(navIndexPlan);
  }

  void openSearch() {
    if (!mounted) return;
    _openSearchOverlay();
  }

  void _openSearchOverlay() {
    final context = mainScaffoldKey.currentContext;
    if (context == null) return;
    showDialog(context: context, builder: (_) => const SearchOverlay());
  }

  Future<void> _showMainWindow() async {
    if (!Platform.isWindows) return;
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  Future<void> _hideToTray() async {
    if (!Platform.isWindows) return;
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }

  Future<void> _quitFromTray() async {
    if (!Platform.isWindows) return;
    // A portable build relies on the running tray process for its reminder
    // fallback. Make the consequence of a true exit explicit; hiding the
    // window remains the safe default for students who still need alerts.
    await _showMainWindow();
    if (!mounted) return;
    final shouldQuit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出 ZenDiary？'),
        content: const Text(
          '退出后，便携版不会继续检查课程和待办提醒。\n\n'
          '如果只是暂时不看，关闭窗口或选择“隐藏到托盘”即可继续提醒。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('留在托盘'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('仍然退出'),
          ),
        ],
      ),
    );
    if (shouldQuit != true) {
      await _hideToTray();
      return;
    }
    _shouldQuitApp = true;
    await tray.trayManager.destroy();
    await hotKeyManager.unregisterAll();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  Future<void> _openFromNotification(String? payload) async {
    await _showMainWindow();
    if (!mounted) return;
    final date = SystemNotificationService.notificationDateFromPayload(payload);
    final item = NotificationTargetResolver.resolve(
      payload: payload,
      occurrenceTime: date,
      rules: ref.read(reminderRuleProvider),
      todos: ref.read(todoListProvider),
      events: ref.read(allEntriesProvider),
      now: DateTime.now(),
    );
    if (date != null) {
      ref.read(selectedDayProvider.notifier).set(date);
      ref.read(timelineViewModeProvider.notifier).set(TimelineViewMode.day);
    }
    ref
        .read(navIndexProvider.notifier)
        .setIndex(date == null ? navIndexToday : navIndexPlan);
    if (item != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = mainScaffoldKey.currentContext;
        if (context != null && mounted) {
          showUnifiedItemDetails(
            context,
            ref,
            item,
            fromNotification: true,
            notificationPayload: payload,
          );
        }
      });
    }
  }

  Future<void> _reconcileSystemNotifications() {
    return SystemNotificationService.reconcile(
      rules: ref.read(activeReminderRulesProvider),
      todos: ref.read(todoListProvider),
      events: ref.read(allEntriesProvider),
    );
  }

  void _startRuntimeReminderFallback() {
    if (!SystemNotificationService.isPortableWindows) return;
    _runRuntimeReminderFallback();
    _runtimeReminderTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _runRuntimeReminderFallback(),
    );
  }

  Future<void> _runRuntimeReminderFallback() async {
    if (_runtimeReminderCheckInFlight || !mounted) return;
    _runtimeReminderCheckInFlight = true;
    try {
      await SystemNotificationService.runPortableRuntimeFallback(
        rules: ref.read(activeReminderRulesProvider),
        allRules: ref.read(reminderRuleProvider),
        todos: ref.read(todoListProvider),
        events: ref.read(allEntriesProvider),
      );
    } finally {
      _runtimeReminderCheckInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activeReminderRulesProvider, (_, _) {
      _reconcileSystemNotifications();
    });
    ref.listen(todoListProvider, (_, _) {
      _reconcileSystemNotifications();
    });
    ref.listen(allEntriesProvider, (_, _) {
      _reconcileSystemNotifications();
    });
    return MaterialApp(
      title: 'Zen Diary',
      theme: ZenTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const MainLayout(),
    );
  }
}
