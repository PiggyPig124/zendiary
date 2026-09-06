import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/diary_entry.dart';
import '../models/reminder_rule.dart';
import '../models/todo_task.dart';
import 'recurrence_service.dart';
import 'runtime_reminder_service.dart';

typedef NotificationClickCallback = void Function(String? payload);

abstract class NotificationSchedulingAdapter {
  Future<void> cancel(int id);

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  });

  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime triggerAt,
    String? payload,
  });
}

class _PluginSchedulingAdapter implements NotificationSchedulingAdapter {
  final FlutterLocalNotificationsPlugin plugin;

  const _PluginSchedulingAdapter(this.plugin);

  @override
  Future<void> cancel(int id) => plugin.cancel(id: id);

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) => plugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: SystemNotificationService._details,
    payload: payload,
  );

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime triggerAt,
    String? payload,
  }) => plugin.zonedSchedule(
    id: id,
    title: title,
    body: body,
    scheduledDate: tz.TZDateTime.from(triggerAt, tz.local),
    notificationDetails: SystemNotificationService._details,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    payload: payload,
  );
}

class NotificationHealth {
  final bool initialized;
  final bool? notificationsAllowed;
  final bool? exactAlarmsAllowed;
  final bool windowsHasPackageIdentity;
  final int pendingCount;
  final String? error;

  const NotificationHealth({
    required this.initialized,
    required this.notificationsAllowed,
    required this.exactAlarmsAllowed,
    required this.windowsHasPackageIdentity,
    required this.pendingCount,
    this.error,
  });

  bool get reliable =>
      initialized &&
      error == null &&
      (notificationsAllowed ?? true) &&
      (exactAlarmsAllowed ?? true) &&
      (!Platform.isWindows || windowsHasPackageIdentity);

  /// Whether the student needs to take an action before Android reminders
  /// can be trusted. Portable Windows intentionally reports a different
  /// delivery model and is handled by the tray, not this warning.
  bool get needsAction =>
      error != null ||
      notificationsAllowed == false ||
      exactAlarmsAllowed == false;

  String get actionMessage {
    if (notificationsAllowed == false) return '系统通知权限未开启，提醒可能不会出现';
    if (exactAlarmsAllowed == false) return '精确闹钟权限未开启，提醒可能延迟';
    if (error != null) return '提醒状态检查失败，请到设置确认';
    return '提醒状态需要确认';
  }
}

class _DesiredNotification {
  final String key;
  final int id;
  final String title;
  final String body;
  final DateTime triggerAt;
  final bool showImmediately;
  final String? payload;

  const _DesiredNotification({
    required this.key,
    required this.id,
    required this.title,
    required this.body,
    required this.triggerAt,
    this.showImmediately = false,
    this.payload,
  });

  // Include the scheduling mode so switching from a portable build (which
  // cannot register future Windows toasts) to a packaged build causes the
  // same reminder to be registered instead of being treated as unchanged.
  String get fingerprint =>
      '$id|${triggerAt.toIso8601String()}|$title|$body|'
      '${SystemNotificationService.isPortableWindows ? 'portable' : 'system'}|'
      '${payload ?? key}';
}

/// 将提醒幂等地同步到操作系统。应用退出后由系统负责触发。
class SystemNotificationService {
  static const String appName = 'ZenDiary';
  // Keep the OS queue useful when a student has several daily habits. The
  // app reconciles on launch and after edits, so a rolling window is enough
  // while avoiding hundreds of alarms per rule.
  static const int _recurringNotificationHorizonDays = 30;
  static const String _registryKey =
      'zendiary_scheduled_notification_registry_v1';
  static const String _runtimeFiredRegistryKey =
      'zendiary_runtime_fired_notification_registry_v1';
  static const String _portableSnoozeRegistryKey =
      'zendiary_portable_snooze_registry_v1';
  static const String _channelId = 'zendiary_reminders';
  static const String _channelName = 'ZenDiary 提醒';
  static const String _timeZoneName = 'Asia/Hong_Kong';
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static Future<void> _reconcileChain = Future<void>.value();
  static NotificationClickCallback? _onClick;
  static String? _pendingLaunchPayload;
  static bool _launchDetailsConsumed = false;
  static String? _lastError;
  static bool? _portableWindowsOverride;
  static bool _androidPermissionPrompted = false;
  static NotificationSchedulingAdapter _adapter = _PluginSchedulingAdapter(
    _plugin,
  );

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: '课程开始与作业截止提醒',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
    windows: WindowsNotificationDetails(),
  );

  static Future<void> setup({NotificationClickCallback? onClick}) async {
    _onClick = onClick ?? _onClick;
    if (_initialized) {
      _dispatchPendingLaunchPayload();
      return;
    }
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(_timeZoneName));
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      windows: WindowsInitializationSettings(
        appName: appName,
        appUserModelId: 'com.example.zendiary',
        guid: 'e91a4647-d6fb-46fc-81cb-6906ea0992ce',
      ),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) =>
          _onClick?.call(response.payload),
    );
    _initialized = true;
    // A notification can launch a process that was not already mounted. The
    // normal response callback covers a running tray process, while this
    // launch-details path preserves the payload for the first mounted frame.
    // The initial setup happens before runApp, so defer delivery until a
    // later setup call has installed the UI callback when necessary.
    if (!_launchDetailsConsumed) {
      _launchDetailsConsumed = true;
      try {
        final details = await _plugin.getNotificationAppLaunchDetails();
        final payload = details?.didNotificationLaunchApp == true
            ? details?.notificationResponse?.payload
            : null;
        if (payload != null && payload.isNotEmpty) {
          _pendingLaunchPayload = payload;
          _dispatchPendingLaunchPayload();
        }
      } catch (error) {
        // Launch details are an enhancement to the running-process callback;
        // a platform that cannot expose them must still start normally.
        debugPrint('读取启动提醒信息失败：${error.runtimeType}');
      }
    }
  }

  static void _dispatchPendingLaunchPayload() {
    final payload = _pendingLaunchPayload;
    final callback = _onClick;
    if (payload == null || callback == null) return;
    _pendingLaunchPayload = null;
    scheduleMicrotask(() => callback(payload));
  }

  static Future<void> requestPermissions() async {
    if (!_initialized) await setup();
    if (!Platform.isAndroid) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  /// Ask at the first moment a real reminder exists, rather than interrupting
  /// an empty first launch. The Settings action still calls
  /// [requestPermissions] directly so a student can retry after changing a
  /// system permission.
  static Future<void> _requestAndroidPermissionsForActiveReminders() async {
    if (!Platform.isAndroid || _androidPermissionPrompted) return;
    _androidPermissionPrompted = true;
    try {
      await requestPermissions();
    } catch (error) {
      // Permission prompts are best-effort. Reconciliation still records the
      // health error and Settings exposes a manual retry path.
      debugPrint('Android 提醒权限请求失败：$error');
    }
  }

  static Future<NotificationHealth> health() async {
    try {
      if (!_initialized) await setup();
      bool? notificationsAllowed;
      bool? exactAlarmsAllowed;
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        notificationsAllowed = await android?.areNotificationsEnabled();
        exactAlarmsAllowed = await android?.canScheduleExactNotifications();
      }
      final pending = await _plugin.pendingNotificationRequests();
      return NotificationHealth(
        initialized: true,
        notificationsAllowed: notificationsAllowed,
        exactAlarmsAllowed: exactAlarmsAllowed,
        windowsHasPackageIdentity: _windowsHasPackageIdentity,
        pendingCount: pending.length,
        error: _lastError,
      );
    } catch (error) {
      return NotificationHealth(
        initialized: _initialized,
        notificationsAllowed: null,
        exactAlarmsAllowed: null,
        windowsHasPackageIdentity: _windowsHasPackageIdentity,
        pendingCount: 0,
        error: error.toString(),
      );
    }
  }

  static Future<void> reconcile({
    required List<ReminderRule> rules,
    required List<TodoTask> todos,
    List<DiaryEntry> events = const [],
    DateTime? now,
  }) {
    final requestedAt = now ?? DateTime.now();
    _reconcileChain = _reconcileChain
        .then(
          (_) => _reconcile(
            rules: rules,
            todos: todos,
            events: events,
            now: requestedAt,
          ),
        )
        .then((_) {
          _lastError = null;
        })
        .catchError((Object error, StackTrace stackTrace) {
          _lastError = error.toString();
          debugPrint('系统提醒同步失败：$error');
        });
    return _reconcileChain;
  }

  static Future<void> _reconcile({
    required List<ReminderRule> rules,
    required List<TodoTask> todos,
    required List<DiaryEntry> events,
    required DateTime now,
  }) async {
    if (!_initialized) await setup();
    final desired = _buildDesired(
      rules: rules,
      todos: todos,
      events: events,
      now: now,
    );
    if (desired.isNotEmpty) {
      await _requestAndroidPermissionsForActiveReminders();
    }
    final prefs = await SharedPreferences.getInstance();
    final previous = _readRegistry(prefs);
    final desiredByKey = {for (final item in desired) item.key: item};

    for (final entry in previous.entries) {
      if (!desiredByKey.containsKey(entry.key)) {
        final id = int.tryParse(entry.value.split('|').first);
        if (id != null) await _adapter.cancel(id);
      }
    }

    final next = <String, String>{};
    for (final item in desired) {
      final oldFingerprint = previous[item.key];
      if (oldFingerprint == item.fingerprint) {
        next[item.key] = oldFingerprint!;
        continue;
      }
      if (oldFingerprint != null) {
        await _adapter.cancel(int.parse(oldFingerprint.split('|').first));
      }
      if (item.showImmediately && !isPortableWindows) {
        await _adapter.show(
          id: item.id,
          title: item.title,
          body: item.body,
          payload: item.payload ?? item.key,
        );
      } else if (!isPortableWindows) {
        await _adapter.schedule(
          id: item.id,
          title: item.title,
          body: item.body,
          triggerAt: item.triggerAt,
          payload: item.payload ?? item.key,
        );
      }
      next[item.key] = item.fingerprint;
    }
    await prefs.setString(_registryKey, jsonEncode(next));
  }

  static List<_DesiredNotification> _buildDesired({
    required List<ReminderRule> rules,
    required List<TodoTask> todos,
    List<DiaryEntry> events = const [],
    required DateTime now,
  }) {
    final todoById = {for (final todo in todos) todo.id: todo};
    final eventById = {for (final event in events) event.id: event};
    final desired = <_DesiredNotification>[];
    for (final rule in rules.where(
      (item) => item.isActive && item.disturbanceLevel != 'silent',
    )) {
      if (rule.targetType == 'todo') {
        final todo = todoById[rule.targetId];
        final recurring = _isRecurringSchedule(rule.scheduleType);
        // A completed one-off task has no future notification. A recurring
        // task, however, still needs the next occurrence scheduled so that
        // completing today's study session does not erase tomorrow's cue.
        if (todo == null ||
            todo.isArchived ||
            todo.validationMessage != null ||
            (!recurring && todo.isCompleted)) {
          continue;
        }
        if (recurring) {
          final advances = rule.advanceMinutes.isEmpty
              ? const [60]
              : rule.advanceMinutes;
          final endDate = rule.endDate;
          final horizon = _recurringHorizon(now, endDate);
          final occurrences = RecurrenceService.occurrencesBetween(
            rule,
            now.subtract(RuntimeReminderService.defaultGraceWindow),
            horizon,
          );
          for (final occurrence in occurrences) {
            // A recurring task completed before the app was reopened should
            // not replay its already-finished occurrence. Keep future
            // occurrences scheduled as usual.
            if (todo.isCompleted && !occurrence.scheduledTime.isAfter(now)) {
              continue;
            }
            for (final advance in advances) {
              final trigger = occurrence.scheduledTime.subtract(
                Duration(minutes: advance),
              );
              if (trigger.isBefore(
                now.subtract(RuntimeReminderService.defaultGraceWindow),
              )) {
                continue;
              }
              final key = _key(rule.id, occurrence.originalTime, advance);
              final displayTime = occurrence.scheduledTime;
              desired.add(
                _DesiredNotification(
                  key: key,
                  id: stableNotificationId(key),
                  title: todo.title,
                  body:
                      '$advance 分钟后开始 · '
                      '${displayTime.month.toString().padLeft(2, '0')}-'
                      '${displayTime.day.toString().padLeft(2, '0')} '
                      '${displayTime.hour.toString().padLeft(2, '0')}:'
                      '${displayTime.minute.toString().padLeft(2, '0')}',
                  triggerAt: trigger,
                  showImmediately: !trigger.isAfter(now),
                  payload: _payloadForOccurrence(key, displayTime),
                ),
              );
            }
          }
          continue;
        }
        // Deadline reminders follow the due date; user-created execution
        // reminders follow the planned work time. An execution reminder has
        // no valid trigger while a task is unscheduled; it must not silently
        // turn into a second deadline reminder.
        final isExecutionReminder = rule.note == '事项提醒';
        final anchor = isExecutionReminder
            ? todo.scheduledAt
            : (rule.anchorTime ?? todo.deadline);
        // A short look-back makes a reminder useful when the student reopens
        // the app just after the planned start/deadline. Older one-off
        // reminders are intentionally ignored instead of replaying stale
        // notifications indefinitely.
        if (anchor == null ||
            anchor.isBefore(
              now.subtract(RuntimeReminderService.defaultGraceWindow),
            )) {
          continue;
        }
        final advances = rule.advanceMinutes.isEmpty
            ? const [60]
            : rule.advanceMinutes;
        for (final advance in advances) {
          final trigger = anchor.subtract(Duration(minutes: advance));
          if (trigger.isBefore(
            now.subtract(RuntimeReminderService.defaultGraceWindow),
          )) {
            continue;
          }
          final key = _key(rule.id, anchor, advance);
          desired.add(
            _DesiredNotification(
              key: key,
              id: stableNotificationId(key),
              title: todo.title,
              body: isExecutionReminder
                  ? (advance == 0 ? '计划现在开始' : '计划将在 $advance 分钟后开始')
                  : (advance == 0 ? '作业现在截止' : '作业将在 $advance 分钟后截止'),
              triggerAt: trigger,
              showImmediately: !trigger.isAfter(now),
              // Keep one-off todo/deadline notifications actionable: clicking
              // the toast can recover both the source rule and its occurrence
              // date instead of merely opening the Today page.
              payload: _payloadForOccurrence(key, anchor),
            ),
          );
        }
        continue;
      }

      final event = rule.targetType == 'event'
          ? eventById[rule.targetId]
          : null;
      // Archiving an event removes it from the execution surface. Keep the
      // rule itself intact so restoring the event can restore its reminder.
      // A dangling event rule is not actionable either (for example after a
      // hand-edited backup). Do not emit a notification for an item the
      // student can no longer open.
      if (rule.targetType == 'event' &&
          rule.targetId != null &&
          (event == null || event.isArchived)) {
        continue;
      }
      // A completed one-off event no longer needs a future cue. Recurring
      // events keep their source entry as the template for future
      // occurrences; completion of one recurring instance is represented by
      // its RecurrenceOverride instead.
      if (event != null &&
          event.isCompleted &&
          !_isRecurringSchedule(rule.scheduleType)) {
        continue;
      }

      final advances = rule.advanceMinutes.isEmpty
          ? const [10]
          : rule.advanceMinutes;
      final endDate = rule.endDate;
      final horizon = _isRecurringSchedule(rule.scheduleType)
          ? _recurringHorizon(now, endDate)
          : endDate == null
          ? now.add(const Duration(days: 365))
          : DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
      // A one-off event reminder follows the event's current start time. The
      // entity is the source of truth when a drag/edit happened before the
      // next notification reconciliation; recurring rules remain anchored to
      // their recurrence definition and occurrence overrides.
      final eventScheduleRule = event != null && rule.scheduleType == 'once'
          ? (event.eventTime == null
                ? rule.copyWith(clearAnchorTime: true)
                : rule.copyWith(anchorTime: event.eventTime))
          : rule;
      // Include a short look-back so opening the app shortly after a missed
      // reminder can still surface it once instead of silently losing it.
      final occurrences = RecurrenceService.occurrencesBetween(
        eventScheduleRule,
        now.subtract(RuntimeReminderService.defaultGraceWindow),
        horizon,
      );
      for (final occurrence in occurrences) {
        for (final advance in advances) {
          final trigger = occurrence.scheduledTime.subtract(
            Duration(minutes: advance),
          );
          if (trigger.isBefore(
            now.subtract(RuntimeReminderService.defaultGraceWindow),
          )) {
            continue;
          }
          final key = _key(rule.id, occurrence.originalTime, advance);
          final displayTime = occurrence.scheduledTime;
          desired.add(
            _DesiredNotification(
              key: key,
              id: stableNotificationId(key),
              title: occurrence.override?.newContent ?? rule.title,
              body:
                  '$advance 分钟后开始 · '
                  '${displayTime.month.toString().padLeft(2, '0')}-'
                  '${displayTime.day.toString().padLeft(2, '0')} '
                  '${displayTime.hour.toString().padLeft(2, '0')}:'
                  '${displayTime.minute.toString().padLeft(2, '0')}',
              triggerAt: trigger,
              showImmediately: !trigger.isAfter(now),
              payload: _payloadForOccurrence(key, displayTime),
            ),
          );
        }
      }
    }
    return desired;
  }

  static DateTime _recurringHorizon(DateTime now, DateTime? endDate) {
    final rolling = now.add(
      const Duration(days: _recurringNotificationHorizonDays),
    );
    if (endDate == null) return rolling;
    final explicit = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      23,
      59,
      59,
    );
    return explicit.isBefore(rolling) ? explicit : rolling;
  }

  static Map<String, String> _readRegistry(SharedPreferences prefs) {
    final raw = prefs.getString(_registryKey);
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (_) {
      return const {};
    }
  }

  /// Portable Windows builds do not have an MSIX package identity, so a
  /// Windows scheduled toast cannot be relied on after the app is hidden.
  /// While the process remains in the tray, this fallback checks due rules and
  /// emits one immediate notification per occurrence.
  static Future<int> runPortableRuntimeFallback({
    required List<ReminderRule> rules,
    List<ReminderRule>? allRules,
    required List<TodoTask> todos,
    required List<DiaryEntry> events,
    DateTime? now,
  }) async {
    if (!isPortableWindows) return 0;
    if (!_initialized) await setup();
    final current = now ?? DateTime.now();
    // `rules` is normally the active subset used for actual notifications.
    // Fallback events must also respect disabled/paused/archived rules;
    // otherwise opting out would silently create a synthetic 10-minute cue.
    final knownEventRuleIds = (allRules ?? rules)
        .where((rule) => rule.targetType == 'event' && rule.targetId != null)
        .map((rule) => rule.targetId!)
        .toSet();
    final archivedEventIds = events
        .where((event) => event.isArchived)
        .map((event) => event.id)
        .toSet();
    final completedOneOffEventIds = events
        .where((event) => event.isCompleted)
        .map((event) => event.id)
        .toSet();
    final effectiveRules = rules
        .where(
          (rule) =>
              !(rule.targetType == 'event' &&
                  rule.targetId != null &&
                  (archivedEventIds.contains(rule.targetId) ||
                      (completedOneOffEventIds.contains(rule.targetId) &&
                          !_isRecurringSchedule(rule.scheduleType)))),
        )
        .toList();
    final fallbackRules = RuntimeReminderService.timelineFallbackRules(
      events,
      ignoredEntryIds: knownEventRuleIds,
    );
    final todoScheduledAt = <String, DateTime?>{
      for (final todo in todos) todo.id: todo.scheduledAt,
    };
    final eventTimes = <String, DateTime?>{
      for (final event in events) event.id: event.eventTime,
    };
    final hits = RuntimeReminderService.dueReminders(
      [...effectiveRules, ...fallbackRules],
      current,
      completedTodoIds: todos
          .where(
            (todo) =>
                todo.isCompleted ||
                todo.isArchived ||
                todo.validationMessage != null,
          )
          .map((todo) => todo.id)
          .toSet(),
      todoScheduledAt: todoScheduledAt,
      eventTimes: eventTimes,
    );
    final prefs = await SharedPreferences.getInstance();
    final snoozes = _readPortableSnoozeRegistry(prefs);
    var shown = 0;

    // Portable Windows cannot ask the OS to persist a future toast, but the
    // tray process is already our local scheduler. Consume temporary snoozes
    // here so “稍后 15 分钟” behaves the same in portable and packaged builds.
    final snoozeCutoff = current.subtract(const Duration(days: 7));
    snoozes.removeWhere((_, value) {
      final triggerAt = DateTime.tryParse(value['triggerAt'] ?? '');
      return triggerAt == null || triggerAt.isBefore(snoozeCutoff);
    });
    final dueSnoozes = <String, Map<String, String>>{};
    for (final entry in snoozes.entries) {
      final triggerAt = DateTime.tryParse(entry.value['triggerAt'] ?? '');
      if (triggerAt == null || triggerAt.isAfter(current)) continue;
      dueSnoozes[entry.key] = entry.value;
    }
    for (final entry in dueSnoozes.entries) {
      final snooze = entry.value;
      await _adapter.show(
        id: stableNotificationId('portable-snooze|${entry.key}'),
        title: snooze['title'] ?? appName,
        body: snooze['body'] ?? '稍后再次提醒',
        payload: snooze['payload'],
      );
      snoozes.remove(entry.key);
      shown++;
    }
    // Drop malformed or very old entries so a corrupted portable profile
    // cannot grow forever. A valid snooze remains eligible until consumed.
    await _writePortableSnoozeRegistry(prefs, snoozes);

    final fired = _readRuntimeFiredRegistry(prefs);
    final cutoff = current.subtract(const Duration(days: 7));
    fired.removeWhere((_, value) {
      final timestamp = DateTime.tryParse(value);
      return timestamp == null || timestamp.isBefore(cutoff);
    });

    if (hits.isEmpty) return shown;

    final todoById = {for (final todo in todos) todo.id: todo};
    for (final hit in hits) {
      if (fired.containsKey(hit.key)) continue;
      final todo = hit.rule.targetType == 'todo'
          ? todoById[hit.rule.targetId]
          : null;
      final title = todo?.title ?? hit.rule.title;
      final isTodoExecution =
          hit.rule.targetType == 'todo' && hit.rule.note == '事项提醒';
      final isTodoDeadline = hit.rule.targetType == 'todo' && !isTodoExecution;
      final body = hit.advanceMinutes == 0
          ? isTodoExecution
                ? '计划现在开始'
                : isTodoDeadline
                ? '作业现在截止'
                : '现在开始'
          : isTodoExecution
          ? '计划将在 ${hit.advanceMinutes} 分钟后开始'
          : isTodoDeadline
          ? '作业将在 ${hit.advanceMinutes} 分钟后截止'
          : '${hit.advanceMinutes} 分钟后开始';
      await _adapter.show(
        id: stableNotificationId('runtime|${hit.key}'),
        title: title,
        body: body,
        payload: hit.key,
      );
      fired[hit.key] = current.toIso8601String();
      shown++;
    }
    await prefs.setString(_runtimeFiredRegistryKey, jsonEncode(fired));
    return shown;
  }

  static Map<String, String> _readRuntimeFiredRegistry(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getString(_runtimeFiredRegistryKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (_) {
      return {};
    }
  }

  static Map<String, Map<String, String>> _readPortableSnoozeRegistry(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getString(_portableSnoozeRegistryKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, Map<String, String>>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        result[entry.key.toString()] = value.map(
          (key, item) => MapEntry(key.toString(), item.toString()),
        );
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writePortableSnoozeRegistry(
    SharedPreferences prefs,
    Map<String, Map<String, String>> registry,
  ) async {
    await prefs.setString(_portableSnoozeRegistryKey, jsonEncode(registry));
  }

  static String _key(String ruleId, DateTime occurrence, int advance) =>
      '$ruleId|${occurrence.toIso8601String()}|$advance';

  static String _payloadForOccurrence(String key, DateTime occurrence) =>
      '$key|occurrence=${occurrence.toIso8601String()}';

  static bool _isRecurringSchedule(String scheduleType) =>
      scheduleType == 'daily' ||
      scheduleType == 'weekly' ||
      scheduleType == 'every_n_days' ||
      scheduleType == 'monthly';

  @visibleForTesting
  static int stableNotificationId(String key) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(key)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static bool get isPortableWindows =>
      _portableWindowsOverride ??
      (Platform.isWindows &&
          !_windowsHasPackageIdentity &&
          _adapter is _PluginSchedulingAdapter);

  @visibleForTesting
  static void debugUseSchedulingAdapter(NotificationSchedulingAdapter adapter) {
    _adapter = adapter;
    _portableWindowsOverride = false;
    _initialized = true;
    _lastError = null;
    _pendingLaunchPayload = null;
    _launchDetailsConsumed = true;
    _reconcileChain = Future<void>.value();
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(_timeZoneName));
  }

  @visibleForTesting
  static void debugSetPortableWindows(bool value) {
    _portableWindowsOverride = value;
  }

  static bool get _windowsHasPackageIdentity =>
      !Platform.isWindows ||
      Platform.environment.containsKey('APPX_PACKAGE_FAMILY_NAME');

  static Future<void> showRegistrationNotification({
    NotificationClickCallback? onClick,
  }) async {
    _onClick = onClick ?? _onClick;
    await showReminderNotification(
      title: 'ZenDiary 通知已启用',
      body: '可以在系统设置中管理 ZenDiary 通知。',
      onClick: onClick,
    );
  }

  static Future<void> showReminderNotification({
    required String title,
    required String body,
    NotificationClickCallback? onClick,
  }) async {
    if (!_initialized) await setup(onClick: onClick);
    _onClick = onClick ?? _onClick;
    await _adapter.show(
      id: stableNotificationId('immediate|${DateTime.now().toIso8601String()}'),
      title: title,
      body: body,
    );
  }

  static Future<void> showTestNotification() async {
    await showReminderNotification(title: 'ZenDiary 测试提醒', body: '系统通知工作正常。');
  }

  /// Schedules a one-off follow-up notification after the student chooses
  /// “稍后处理” from a notification detail. This is intentionally separate
  /// from the recurring rule registry: snoozing is a temporary nudge and must
  /// not rewrite a class or assignment's real reminder schedule.
  static Future<bool> snooze({
    required String title,
    required String payload,
    Duration delay = const Duration(minutes: 15),
  }) async {
    final safeDelay = delay <= Duration.zero
        ? const Duration(minutes: 1)
        : delay;
    final triggerAt = DateTime.now().add(safeDelay);
    final key = 'snooze|$payload|${triggerAt.toIso8601String()}';
    if (isPortableWindows) {
      if (!_initialized) await setup();
      final prefs = await SharedPreferences.getInstance();
      final registry = _readPortableSnoozeRegistry(prefs);
      registry[key] = {
        'title': title,
        'body': '${safeDelay.inMinutes} 分钟后再次提醒',
        'payload': payload,
        'triggerAt': triggerAt.toIso8601String(),
      };
      await _writePortableSnoozeRegistry(prefs, registry);
      return true;
    }
    if (!_initialized) await setup();
    await _adapter.schedule(
      id: stableNotificationId(key),
      title: title,
      body: '${safeDelay.inMinutes} 分钟后再次提醒',
      triggerAt: triggerAt,
      payload: payload,
    );
    return true;
  }

  static String occurrencePayload(String ruleId, DateTime occurrence) =>
      _payloadForOccurrence(_key(ruleId, occurrence, 0), occurrence);

  static bool get supportsFutureScheduling => !isPortableWindows;

  /// Both packaged builds and a running portable tray can deliver a
  /// temporary snooze. Only long-lived OS scheduling is unavailable in the
  /// portable case.
  static bool get supportsSnooze =>
      supportsFutureScheduling || isPortableWindows;

  /// Extracts the occurrence timestamp embedded in a scheduled or runtime
  /// notification payload. Payloads use either `|` or `:` separators, while
  /// the ISO timestamp itself contains colons.
  static DateTime? notificationDateFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final explicit = RegExp(
      r'occurrence=(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?)',
    ).firstMatch(payload);
    if (explicit != null) {
      return DateTime.tryParse(explicit.group(1)!);
    }
    final matches = RegExp(
      r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?',
    ).allMatches(payload).toList();
    if (matches.isEmpty) return null;
    // Legacy payloads contain one timestamp; for any future payload that
    // carries more than one, the final timestamp is the displayed occurrence.
    return DateTime.tryParse(matches.last.group(0)!);
  }

  /// Returns whether [payload] came from the synthetic reminder generated for
  /// a bare timeline event. Keep this format check in one place because the
  /// portable fallback and the notification detail drawer both need to
  /// recognise the same payload.
  static bool isTimelineFallbackPayload(String? payload, String entryId) {
    if (payload == null || payload.isEmpty || entryId.isEmpty) return false;
    return payload.startsWith('timeline:$entryId|') ||
        payload.startsWith('timeline:$entryId:');
  }
}
