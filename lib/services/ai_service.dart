import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../core/database/db_service.dart';
import '../models/ai_settings.dart';
import '../models/ai_parsed_intent.dart';
import '../models/diary_entry.dart';
import '../models/todo_task.dart';

class _LocalRecurrenceCue {
  final String scheduleType;
  final int scheduleInterval;
  final int? scheduleDay;
  final List<int>? byDay;
  final DateTime anchorTime;

  const _LocalRecurrenceCue({
    required this.scheduleType,
    required this.scheduleInterval,
    required this.scheduleDay,
    required this.byDay,
    required this.anchorTime,
  });
}

class AIService {
  static const String _settingsKey = 'ai_settings';
  static final RegExp _localClockPattern = RegExp(
    r'(早上|上午|中午|下午|晚上|今晚)?\s*'
    r'(\d{1,2}|[零〇一二两三四五六七八九十]{1,3})\s*'
    r'(?:点|时|[:：])\s*'
    r'(\d{1,2}|[零〇一二两三四五六七八九十]{1,3}|半)?',
  );
  static final RegExp _localClockRangePattern = RegExp(
    r'(?:早上|上午|中午|下午|晚上|今晚)?\s*'
    r'(?:\d{1,2}|[零〇一二两三四五六七八九十]{1,3})\s*'
    r'(?:点|时|[:：])\s*'
    r'(?:\d{1,2}|[零〇一二两三四五六七八九十]{1,3}|半)?\s*'
    r'(?:[-–—~至到])\s*'
    r'(?:早上|上午|中午|下午|晚上|今晚)?\s*'
    r'(?:\d{1,2}|[零〇一二两三四五六七八九十]{1,3})\s*'
    r'(?:点|时|[:：])\s*'
    r'(?:\d{1,2}|[零〇一二两三四五六七八九十]{1,3}|半)?',
  );

  static Uri? _chatCompletionsUri(AISettings settings) {
    if (settings.endpointError != null) return null;
    final base = Uri.tryParse(settings.baseUrl.trim());
    if (base == null) return null;
    final basePath = base.path.replaceFirst(RegExp(r'/+$'), '');
    return base.replace(path: '$basePath/chat/completions');
  }

  /// Sends one provider request without following redirects. The request
  /// carries an API key, so an endpoint must not be able to redirect it to a
  /// different host or to an insecure URL.
  static Future<http.Response> _postJson(
    Uri endpoint, {
    required Map<String, String> headers,
    required Map<String, dynamic> body,
    required Duration timeout,
  }) async {
    final request = http.Request('POST', endpoint)
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers.addAll(headers)
      ..body = jsonEncode(body);
    final client = http.Client();
    try {
      final streamed = await client.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } finally {
      client.close();
    }
  }

  static AISettings loadSettings() {
    final box = Hive.box(DBService.settingsBoxName);
    final raw = box.get(_settingsKey);
    if (raw is! Map) return const AISettings();
    return AISettings.fromJson(raw);
  }

  static Future<void> saveSettings(AISettings settings) async {
    final box = Hive.box(DBService.settingsBoxName);
    await box.put(_settingsKey, settings.toJson());
  }

  static Future<String?> testConnection(AISettings settings) async {
    if (settings.apiKey.trim().isEmpty || settings.modelName.trim().isEmpty) {
      return '请先填写 API Key、模型名称和 Base URL';
    }
    final endpointError = settings.endpointError;
    if (endpointError != null) return endpointError;
    final endpoint = _chatCompletionsUri(settings);
    if (endpoint == null) return 'Base URL 无法使用';
    try {
      final response = await _postJson(
        endpoint,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${settings.apiKey}',
        },
        body: {
          'model': settings.modelName,
          'messages': [
            {'role': 'user', 'content': '请只回复 OK 两个字。'},
          ],
          'max_tokens': 10,
        },
        timeout: const Duration(seconds: 15),
      );

      if (response.statusCode == 200) return null;

      return '服务返回 HTTP ${response.statusCode}';
    } on Exception {
      return '连接失败，请检查网络、证书与 Base URL';
    }
  }

  /// A deliberately conservative offline parser for the capture inbox.
  ///
  /// It only promotes input when there is a recognizable clock/date plus an
  /// action phrase (or a clear imperative without a date). Anything unclear
  /// remains a draft, so losing network access never causes a destructive or
  /// surprising classification. The parser is also used as a fallback when
  /// an configured AI endpoint times out.
  static AiParsedIntent? parseLocalIntent(String sourceText, DateTime now) {
    final raw = _parseLocalIntentRaw(sourceText, now);
    if (raw != null) {
      return normalizeStudentIntent(raw, sourceText: sourceText, now: now);
    }
    if (RegExp(
      r'quiz|测验|大作业|课程论文|毕业论文|项目报告',
      caseSensitive: false,
    ).hasMatch(sourceText)) {
      return _dailyMetadata(
        AiParsedIntent(category: 'todo', todos: [sourceText.trim()]),
        sourceText,
        now,
      );
    }
    return null;
  }

  static AiParsedIntent? _parseLocalIntentRaw(String sourceText, DateTime now) {
    final text = sourceText.trim();
    if (text.isEmpty) return null;
    final clock = _parseLocalClock(text, now);
    final recurrence = _parseLocalRecurrence(text, now);
    final hasDate = _hasDateOnlyCue(text);
    final hasAction = _hasLocalActionCue(text);
    final hasReminderCue = RegExp(r'提醒|别忘|记得').hasMatch(text);

    if (clock != null) {
      final location = _parseLocalLocation(text);
      final title = _localCaptureTitle(text, location: location);
      final durationMinutes = _parseLocalDuration(text);
      if (title.isEmpty ||
          (!hasAction &&
              !hasReminderCue &&
              recurrence == null &&
              durationMinutes == null)) {
        return null;
      }
      final advances = _explicitAdvanceMinutes(text);
      final reminder = hasReminderCue || recurrence != null
          ? AiReminderCandidate(
              enabled: true,
              advanceMinutes: advances.isEmpty ? const [0] : advances,
              requiresConfirmation: hasReminderCue || recurrence != null,
              scheduleType: recurrence?.scheduleType ?? 'once',
              scheduleInterval: recurrence?.scheduleInterval ?? 1,
              scheduleDay: recurrence?.scheduleDay,
              byDay: recurrence?.byDay,
            )
          : const AiReminderCandidate();
      return AiParsedIntent(
        category: 'event',
        eventTime: clock,
        eventEndTime: durationMinutes == null
            ? null
            : clock.add(Duration(minutes: durationMinutes)),
        durationMinutes: durationMinutes,
        location: location,
        aiSummary: title,
        importance: _localImportance(text),
        disturbanceLevel: hasReminderCue ? 'strong' : 'normal',
        reminder: reminder,
      );
    }

    // A recurring habit often has no exact clock. Preserve its first
    // occurrence as a planning anchor and keep the repeat rule in the
    // confirmation card, instead of turning “每天背单词” into a plain,
    // forgettable backlog task.
    if (recurrence != null && (hasAction || hasReminderCue)) {
      final title = _localCaptureTitle(text);
      if (title.isNotEmpty) {
        return AiParsedIntent(
          category: 'todo',
          aiSummary: title,
          todos: [title],
          importance: _localImportance(text),
          scheduledAt: recurrence.anchorTime,
          reminder: AiReminderCandidate(
            enabled: true,
            scheduleType: recurrence.scheduleType,
            scheduleInterval: recurrence.scheduleInterval,
            scheduleDay: recurrence.scheduleDay,
            byDay: recurrence.byDay,
            advanceMinutes: _explicitAdvanceMinutes(text).isEmpty
                ? const [0]
                : _explicitAdvanceMinutes(text),
            requiresConfirmation: true,
          ),
        );
      }
    }

    if (hasDate && hasAction) {
      final day = _parseDateOnlyCue(text, now);
      if (day != null) {
        final title = _localCaptureTitle(text);
        if (title.isEmpty) return null;
        final deadline = _hasDeadlineCue(text)
            ? DateTime(day.year, day.month, day.day, 23, 59)
            : null;
        // “晚上/稍后/一会儿” tells us the day but not a trustworthy clock.
        // Keep the task on that day without inventing a 09:00 appointment;
        // the student can choose a concrete slot from Plan or Today.
        final hasVagueTime = _hasVagueTimeCue(text);
        return AiParsedIntent(
          category: 'todo',
          aiSummary: title,
          todos: [title],
          importance: _localImportance(text),
          todoDeadline: deadline,
          scheduledAt: deadline == null && !hasVagueTime
              ? DateTime(day.year, day.month, day.day, 9)
              : null,
        );
      }
    }

    // Without a date, require an imperative-shaped beginning. This keeps
    // ordinary mood/journal sentences in the inbox instead of turning them
    // into accidental tasks.
    if (_hasStandaloneImperative(text)) {
      final title = _localCaptureTitle(text);
      if (title.isEmpty) return null;
      // “提醒我/记得/别忘了” without a clock is still a reminder intent.
      // Keep the task unscheduled and ask for a plan time in Inbox instead of
      // silently dropping the notification request.
      final reminder = hasReminderCue
          ? const AiReminderCandidate(
              enabled: true,
              advanceMinutes: [0],
              requiresConfirmation: true,
            )
          : const AiReminderCandidate();
      return AiParsedIntent(
        category: 'todo',
        aiSummary: title,
        todos: [title],
        importance: _localImportance(text),
        disturbanceLevel: hasReminderCue ? 'strong' : 'normal',
        reminder: reminder,
      );
    }
    return null;
  }

  static DateTime? _parseLocalClock(String text, DateTime now) {
    final match = _localClockPattern.firstMatch(text);
    if (match == null) return null;
    final totalMinutes = _localClockMinutes(match);
    if (totalMinutes == null) return null;
    final day = _hasDateOnlyCue(text)
        ? _parseDateOnlyCue(text, now)
        : DateTime(now.year, now.month, now.day);
    if (day == null) return null;
    return DateTime(
      day.year,
      day.month,
      day.day,
      totalMinutes ~/ 60,
      totalMinutes % 60,
    );
  }

  static int? _localClockMinutes(Match match, {String? fallbackPeriod}) {
    var hour = _parseLocalNumber(match.group(2) ?? '');
    if (hour == null) return null;
    final minuteText = match.group(3);
    final minute = minuteText == '半'
        ? 30
        : _parseLocalNumber(minuteText ?? '0') ?? 0;
    if (minute < 0 || minute > 59) return null;
    final period = match.group(1) ?? fallbackPeriod;
    if (period == '下午' || period == '晚上' || period == '今晚') {
      if (hour < 12) hour += 12;
    } else if (period == '中午' && hour < 11) {
      hour += 12;
    }
    if (hour > 23) return null;
    return hour * 60 + minute;
  }

  /// Returns a duration only when two clock tokens are explicitly joined by
  /// a range separator. A negative or zero range is intentionally rejected;
  /// an overnight class must be entered with an explicit next-day event.
  static int? _parseLocalDuration(String text) {
    final matches = _localClockPattern.allMatches(text).toList();
    for (var index = 0; index + 1 < matches.length; index++) {
      final first = matches[index];
      final second = matches[index + 1];
      final separator = text.substring(first.end, second.start);
      if (!RegExp(r'^\s*[-–—~至到]\s*$').hasMatch(separator)) continue;
      final start = _localClockMinutes(first);
      final end = _localClockMinutes(second, fallbackPeriod: first.group(1));
      if (start == null || end == null) continue;
      final duration = end - start;
      if (duration > 0 && duration <= 1440) return duration;
    }
    return null;
  }

  static _LocalRecurrenceCue? _parseLocalRecurrence(String text, DateTime now) {
    final everyDays = RegExp(r'每隔\s*(\d{1,3})\s*天').firstMatch(text);
    if (everyDays != null) {
      final interval = int.tryParse(everyDays.group(1) ?? '');
      if (interval != null && interval >= 1 && interval <= 365) {
        return _LocalRecurrenceCue(
          scheduleType: 'every_n_days',
          scheduleInterval: interval,
          scheduleDay: null,
          byDay: null,
          anchorTime: _nextLocalRecurringAnchor(now),
        );
      }
    }

    final monthly = RegExp(r'每月(?:\s*(\d{1,2})\s*(?:号|日)?)?').firstMatch(text);
    if (monthly != null) {
      final requestedDay = int.tryParse(monthly.group(1) ?? '') ?? now.day;
      if (requestedDay >= 1 && requestedDay <= 31) {
        return _LocalRecurrenceCue(
          scheduleType: 'monthly',
          scheduleInterval: 1,
          scheduleDay: requestedDay,
          byDay: null,
          anchorTime: _nextMonthlyAnchor(now, requestedDay),
        );
      }
    }

    final hasWeeklyCue = RegExp(r'每(?:周|星期|礼拜)|工作日|周末').hasMatch(text);
    if (hasWeeklyCue) {
      final days = _localWeeklyDays(text);
      return _LocalRecurrenceCue(
        scheduleType: 'weekly',
        scheduleInterval: 1,
        scheduleDay: null,
        byDay: days,
        anchorTime: _nextWeeklyAnchor(now, days),
      );
    }

    if (RegExp(r'每(?:天|日)').hasMatch(text)) {
      return _LocalRecurrenceCue(
        scheduleType: 'daily',
        scheduleInterval: 1,
        scheduleDay: null,
        byDay: null,
        anchorTime: _nextLocalRecurringAnchor(now),
      );
    }
    return null;
  }

  static List<int>? _localWeeklyDays(String text) {
    if (text.contains('工作日')) return const [1, 2, 3, 4, 5];
    if (text.contains('周末')) return const [6, 7];

    final range = RegExp(
      r'(?:每周|每星期|每礼拜)\s*([一二三四五六日])\s*(?:到|至|-)\s*(?:周)?([一二三四五六日])',
    ).firstMatch(text);
    if (range != null) {
      final start = _weekdayFromChinese(range.group(1)!);
      final end = _weekdayFromChinese(range.group(2)!);
      if (start != null && end != null) {
        if (start <= end) {
          return [for (var day = start; day <= end; day++) day];
        }
        return [
          for (var day = start; day <= 7; day++) day,
          for (var day = 1; day <= end; day++) day,
        ];
      }
    }

    final compact = RegExp(
      r'(?:每周|每星期|每礼拜)\s*([一二三四五六日]{1,7})',
    ).firstMatch(text);
    if (compact != null) {
      final days =
          compact
              .group(1)!
              .split('')
              .map(_weekdayFromChinese)
              .whereType<int>()
              .toSet()
              .toList()
            ..sort();
      if (days.isNotEmpty) return days;
    }
    return null;
  }

  static int? _weekdayFromChinese(String value) {
    final index = '一二三四五六日'.indexOf(value);
    return index == -1 ? null : index + 1;
  }

  static DateTime _nextLocalRecurringAnchor(DateTime now) {
    var anchor = DateTime(now.year, now.month, now.day, 9);
    if (!anchor.isAfter(now)) anchor = anchor.add(const Duration(days: 1));
    return anchor;
  }

  static DateTime _nextWeeklyAnchor(DateTime now, List<int>? days) {
    final candidates = days ?? [now.weekday];
    for (var offset = 0; offset <= 7; offset++) {
      final date = DateTime(now.year, now.month, now.day + offset, 9);
      if (candidates.contains(date.weekday) && date.isAfter(now)) {
        return date;
      }
    }
    return DateTime(now.year, now.month, now.day + 7, 9);
  }

  static DateTime _nextMonthlyAnchor(DateTime now, int requestedDay) {
    DateTime candidateFor(int year, int month) {
      final daysInMonth = DateTime(year, month + 1, 0).day;
      return DateTime(year, month, requestedDay.clamp(1, daysInMonth), 9);
    }

    var candidate = candidateFor(now.year, now.month);
    if (!candidate.isAfter(now)) {
      candidate = candidateFor(now.year, now.month + 1);
    }
    return candidate;
  }

  static int? _parseLocalNumber(String value) {
    final arabic = int.tryParse(value);
    if (arabic != null) return arabic;
    if (value.isEmpty) return null;
    const digits = {
      '零': 0,
      '〇': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    final direct = digits[value];
    if (direct != null) return direct;
    if (value == '十') return 10;
    final tenIndex = value.indexOf('十');
    if (tenIndex == -1 || value.length > 3) return null;
    final tens = tenIndex == 0 ? 1 : digits[value.substring(0, tenIndex)];
    if (tens == null) return null;
    final ones = tenIndex == value.length - 1
        ? 0
        : digits[value.substring(tenIndex + 1)];
    if (ones == null) return null;
    return tens * 10 + ones;
  }

  static bool _hasLocalActionCue(String text) {
    return RegExp(
      r'(复习|学习|完成|提交|交|上传|写|整理|阅读|读|背|做|买|预约|上课|考试|开会|出发|缴费|报名|打卡|练习|联系|发送|归还|清理|收拾|倒|洗|取|办|准备)',
    ).hasMatch(text);
  }

  static bool _hasStandaloneImperative(String text) {
    final normalized = _stripLocalTimeCue(text);
    return RegExp(
      r'^(?:请|记得|提醒我|帮我|需要|要|得|去|把|完成|提交|交|上传|写|复习|学习|整理|阅读|读|背|做|买|预约|上课|考试|开会|出发|缴费|报名|打卡|练习|联系|发送|归还|清理|收拾|倒|洗|取|办|准备)',
    ).hasMatch(normalized);
  }

  static bool _hasVagueTimeCue(String text) {
    return RegExp(r'(早上|今早|上午|中午|下午|晚上|今晚|今夜|一会儿|一会|稍后|待会|等会)').hasMatch(text);
  }

  static String _stripLocalTimeCue(String text) {
    var value = text.trim();
    // Remove at most one date cue and one vague period. Exact clock phrases
    // have already taken the event branch, so this only handles fuzzy input.
    value = value.replaceFirst(
      RegExp(
        r'^(?:今天|明天|后天|大后天|(?:下|本|这)?(?:周|星期|礼拜)[一二三四五六日]?|'
        r'下星期|本星期|这星期|下礼拜|本礼拜|这礼拜)\s*',
      ),
      '',
    );
    value = value.replaceFirst(
      RegExp(r'^(?:早上|今早|上午|中午|下午|晚上|今晚|今夜|一会儿|一会|稍后|待会|等会)\s*'),
      '',
    );
    return value.trim();
  }

  /// Extract a location only for the conservative offline event branch.
  ///
  /// We require the explicit Chinese prepositions “在/于” and either a known
  /// action after the place or punctuation/end-of-input after it. This avoids
  /// mistaking “在晚上” or “在截止前” for a location when network AI is not
  /// available.
  static String? _parseLocalLocation(String text) {
    const actionPattern =
        r'(?:复习|学习|完成|提交|交|上传|写|整理|阅读|读|背|做|买|预约|上课|考试|开会|出发|缴费|报名|打卡|练习|联系|发送|归还|清理|收拾|倒|洗|取|办|准备)';
    final beforeAction = RegExp(
      '(?:在|于)\\s*([^，。；,.;\\s]{1,20}?)\\s*(?=$actionPattern)',
    ).firstMatch(text);
    final candidate =
        beforeAction?.group(1) ??
        RegExp(
          r'(?:在|于)\s*([^，。；,.;\s]{1,20})\s*(?:[，。；,.;]|$)',
        ).firstMatch(text)?.group(1);
    if (candidate == null) return null;
    final value = candidate.trim();
    if (value.isEmpty ||
        RegExp(r'^(?:早上|今早|上午|中午|下午|晚上|今晚|今夜|截止|最晚|之前|以前)$').hasMatch(value)) {
      return null;
    }
    return value;
  }

  static String _localCaptureTitle(String text, {String? location}) {
    var title = text;
    title = title.replaceAll(_localClockRangePattern, ' ');
    title = title.replaceAll(_localClockPattern, ' ');
    title = title.replaceAll(
      RegExp(
        r'(每隔\s*\d{1,3}\s*天|每(?:天|日)|'
        r'(?:每周|每星期|每礼拜)\s*[一二三四五六日]{0,7}(?:\s*(?:到|至|-)\s*(?:周)?[一二三四五六日])?|'
        r'工作日|周末|每月\s*\d{0,2}\s*(?:号|日)?)',
      ),
      ' ',
    );
    title = title.replaceAll(
      RegExp(
        r'(今天|明天|后天|大后天|(?:下|本|这)?(?:周|星期|礼拜)[一二三四五六日]?|'
        r'\d{1,2}\s*[月/.-]\s*\d{1,2})',
      ),
      ' ',
    );
    title = title.replaceAll(
      RegExp(r'(早上|今早|上午|中午|下午|晚上|今晚|今夜|一会儿|一会|稍后|待会|等会)'),
      ' ',
    );
    // Keep reminder intent in structured fields, not in the visible title.
    // This covers natural phrasing such as “8点提前15分钟提醒我上课”.
    title = title.replaceAll(
      RegExp(r'提前\s*(?:\d+|[一二两三四五六七八九十]+)\s*(?:个)?\s*(?:小时|分钟|分)'),
      ' ',
    );
    title = title.replaceAll(RegExp(r'(?:提醒我|别忘了|提醒)\s*'), ' ');
    if (location != null) {
      title = title.replaceAll(
        RegExp('(?:在|于)\\s*${RegExp.escape(location)}'),
        ' ',
      );
    }
    title = title.replaceAll(RegExp(r'^(?:请|记得|提醒我|提醒|别忘了|帮我|安排|在)\s*'), '');
    title = title.replaceAll(RegExp(r'(?:截止|最晚|之前|以前)\s*'), ' ');
    title = title.replaceAll(RegExp(r'[，。！？!?,:：；;]+'), ' ');
    return title.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _localImportance(String text) {
    return RegExp(r'考试|上课|预约|截止|最晚|提交|交|上传|缴费|报名').hasMatch(text)
        ? 'important'
        : 'normal';
  }

  static const String _systemPrompt = '''
你是一个智能日记助手。用户会给你一段话，可能是随想、情绪、待办事项或带时间的事件。
请只返回合法 JSON，不要返回 Markdown 或额外解释。

返回格式：
{
  "category": "draft" | "event" | "todo" | "note",
  "event_time": "2026-06-28T14:30:00" | null,
  "event_end_time": "2026-06-28T16:00:00" | null,
  "duration_minutes": 90 | null,
  "location": "地点" | null,
  "ai_summary": "事件摘要",
  "sentiment_reply": "15字以内温暖回应，仅 draft 需要",
  "todos": ["任务1", "任务2"],
  "tags": ["tag1", "tag2"],
  "importance": "important" | "normal" | "minor",
  "disturbance_level": "strong" | "normal" | "silent",
  "reminder": {
    "enabled": true | false,
    "schedule_type": "once" | "daily" | "weekly" | "every_n_days" | "monthly",
    "schedule_interval": 1 | 2 | 3 | null,
    "schedule_day": 15 | 1 | null,
    "advance_minutes": [60, 15, 5],
    "requires_confirmation": true | false,
    "by_day": [1, 2, 3, 4, 5] | null
  },
  "missing_info": ["缺少具体时间"],
  "command_type": "none" | "low_load" | "disable_future",
  "command_target": "工作/课程/高数课/背单词" | null,
  "command_days": 1 | 3 | null,
  "todo_deadline": "2026-07-10T23:59:00" | null,
  "scheduled_at": "2026-07-10T09:00:00" | null,
  "task_kind": "ordinary" | "timed" | "preparation",
  "attention_date": "2026-07-10" | null,
  "opens_at": "2026-07-10T08:00:00" | null
}

═══════ 分类规则 — 严格按以下顺序判断，匹配即停止 ═══════

第 1 步：检查精确时间点（最高优先级）
────────────────────────────────
精确时间点的定义：输入中出现了具体钟点。
包括：5点、5:50、五点五十、下午3点、3点半、中午12点、早上8点 等。

判定规则：
✅ 有精确钟点 → category = "event"
❌ 只有日期没有钟点（"下周一""周四""明天"）→ 不是 event，继续往下判断
❌ 模糊时段没有钟点（"晚上""上午""一会儿""稍后""这周"）→ 不是 event，继续往下判断

常见错误警告（务必遵守）：
⚠️ "5点50提醒我下班" → event，不是 todo。有钟点 = event，动词是什么不重要。
⚠️ "记得下午3点开会" → event，不是 todo。"记得"只表示要加 reminder，不改变 category。
⚠️ "7点写作业" → event，不是 todo。不要把"几点+动作"误判为 todo。
⚠️ 判断 category 的唯一标准是"有没有精确钟点"，不是"动作像不像待办"。
⚠️ 只要用户输入中出现任何一个精确钟点，就必须输出 category="event"，不管后面的动词是什么。

示例（全部 → event）：
  "下午3点开会"       → event，event_time 取最近的下午3点
  "5点下班"           → event
  "5点50提醒我下班"   → event + reminder.enabled=true
  "两点去吃饭"        → event
  "记得下午3点开会"   → event + reminder.enabled=true
  "7点写作业"        → event
  "12点半午休"       → event
  "早上8点出发"       → event

第 2 步：检查是否为命令
────────────────────────
仅在第 1 步不匹配时检查。用户试图管理提醒/负荷 → category="draft"：
  "推掉今天的工作和课"        → command_type="low_load"
  "近3天课程先别提醒我"       → command_type="low_load", command_days=3
  "以后不要再提醒我做xx"      → command_type="disable_future"
  "以后的xx课都不上了"        → command_type="disable_future"

第 3 步：检查日期意图（有日期无钟点）
────────────────────────────────────
明确截止语义（"截止"、"最晚"、"前"，或交/提交/上传等交付动作）
→ category="todo" + todo_deadline：
  "周四前交表"       → todo + todo_deadline="本周四 23:59:00"
  "下周一前交报告"   → todo + todo_deadline="下周一 23:59:00"
只有关注日期、没有明确钟点 → category="todo" + attention_date，不填写 scheduled_at：
  "明天复习高数"     → todo + attention_date="明天日期"
  "周五整理笔记"     → todo + attention_date="周五日期"

第 4 步：无任何时间信息
──────────────────────
category="todo"。去掉模糊时间词（"晚上""一会儿""稍后""这周"等），只保留动作核心：
  "记得买菜"     → todo, todos=["买菜"]
  "倒垃圾"       → todo, todos=["倒垃圾"]
  "把文档写完"   → todo, todos=["把文档写完"]
  "一会儿倒垃圾" → todo, todos=["倒垃圾"]
  "晚上收拾"     → todo, todos=["收拾"]
  "每天做游戏日常" → todo, reminder.schedule_type="daily", importance="minor"

第 5 步：以上都不匹配
─────────────────────
长期资料、知识整理或需要日后查阅的内容 → category="note"；
单次心情、随想、灵感 → category="draft"，返回 sentiment_reply。

═══════ 摘要规则 ═══════
- ai_summary 从用户输入中提取核心行为，去掉"我""记得提醒我""了"等冗余词。
- 保留有意义的人物、地点、对象。例如"我5点和xxx吃饭"→"和xxx吃饭"；"5点50下班，记得提醒我"→"下班"。
- 不要全句照抄原文，只保留关键信息。

═══════ 时间规则 ═══════
- 当前时间会在用户消息中给出，请以此解析"今天/明天/下周一"等相对时间。
- "5点50""5:50"等均指最近的对应时刻，默认指今天。
- 只有日期没有时间时，写入 attention_date；scheduled_at 仅用于明确钟点。只有明确截止语义时才写入
  todo_deadline。都没有时不要凭空添加日期。
- quiz/限时测验用 task_kind="timed"，开放时间写 opens_at，截止写 todo_deadline。
- 大作业/课程论文等需要提前准备的任务用 task_kind="preparation"。attention_date 只能来自用户明确的开始关注日或提前准备天数，缺失返回 null，不能默认截止前两天。
- 普通任务用 task_kind="ordinary"。任务的预计用时、拆分和空档安排不属于本次整理。
- 非 event 时 event_time 返回 null。

═══════ 提醒与命令规则 ═══════
- 考试、上课、预约、必须按时出发或完成的事项 importance=important。
- reminder.enabled=true 时 disturbance_level 通常为 strong，requires_confirmation=true。
- 如果用户只说"几点提醒我做某事"，没有说"提前"，advance_minutes 必须返回 [0]。
- 只有用户明确说"提前 15 分钟""提前 1 小时""提前多次提醒"时，advance_minutes 才返回对应提前点。
	- schedule_type 判断：
	  * 一次性事件 → "once"
	  * "每天""每日" → "daily"
	  * "每周X""每周" → "weekly"，需设置 by_day
	  * "每隔N天" → "every_n_days"，schedule_interval=N
	  * "每月X号""每月初" → "monthly"，schedule_day=X
	- by_day 判断（仅 schedule_type="weekly" 时需要）：
	  * "每周一到周五""工作日""周一到周五" → by_day=[1,2,3,4,5]
	  * "周末""周六日" → by_day=[6,7]
	  * "每周一三五" → by_day=[1,3,5]
	  * "每周二四六" → by_day=[2,4,6]
	  * "每周一" → by_day=[1]；"每周三" → by_day=[3]
	  * 单说"每周"不指定哪天 → by_day=null（默认按 anchorTime 的星期几）
	  * by_day 值为：1=周一 2=周二 3=周三 4=周四 5=周五 6=周六 7=周日
- "每天做游戏日常"等小事 importance=minor，disturbance_level=silent，reminder.schedule_type="daily"。
- 同时有 deadline 和 reminder 时，两者都返回。
- 命令类输入如不能直接生成普通事项，category 返回 draft。
- 不再使用 todo_time_window 字段——所有模糊时间词直接丢弃。
- 非 event 时不返回 event_time。
''';

  static Future<Map<String, dynamic>?> parseDiaryInput(
    String content,
    DateTime now,
  ) async {
    final settings = loadSettings();
    debugPrint(
      '[AI] 设置: enabled=${settings.enabled}, configured=${settings.isConfigured}',
    );
    if (!settings.isConfigured) {
      debugPrint(
        '[AI] ❌ 配置不完整或 Base URL 不安全',
      );
      return null;
    }
    if (!settings.enabled) {
      debugPrint('[AI] ❌ 未启用');
      return null;
    }

    final userMessage = '当前时间：${now.toIso8601String()}\n用户输入：$content';

    try {
      final endpoint = _chatCompletionsUri(settings);
      if (endpoint == null) {
        debugPrint('[AI] ❌ Base URL 不安全');
        return null;
      }
      debugPrint('[AI] → 发送请求');
      final response = await _postJson(
        endpoint,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${settings.apiKey}',
        },
        body: {
          'model': settings.modelName,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': userMessage},
          ],
          'temperature': 0.1,
          'max_tokens': 512,
          'response_format': {'type': 'json_object'},
        },
        timeout: const Duration(seconds: 20),
      );
      debugPrint('[AI] ← HTTP ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint('[AI] ❌ HTTP ${response.statusCode}');
        return null;
      }

      final data = _decodeJsonObject(response.body);
      if (data == null) {
        debugPrint('[AI] ❌ 响应非有效 JSON');
        return null;
      }

      final text = data['choices']?[0]?['message']?['content']?.toString();
      if (text == null || text.trim().isEmpty) {
        debugPrint('[AI] ❌ 缺少 choices[0].message.content');
        return null;
      }

      debugPrint('[AI] 收到模型响应');
      final parsed = _extractJsonObject(text);
      if (parsed == null) {
        debugPrint('[AI] ❌ 提取 JSON 失败');
      } else {
        debugPrint('[AI] ✅ 已提取结构化结果');
      }
      return parsed;
    } catch (_) {
      debugPrint('[AI] ❌ 请求或响应处理失败');
      return null;
    }
  }

  static Future<AiParsedIntent?> parseDiaryIntent(
    String content,
    DateTime now,
  ) async {
    final result = await parseDiaryInput(content, now);
    if (result == null) return null;
    final intent = AiParsedIntent.fromJson(result);
    debugPrint(
      '[AI] 解析结果: category=${intent.category}, eventTime=${intent.eventTime != null}, todos=${intent.todos.length}',
    );
    return normalizeStudentIntent(intent, sourceText: content, now: now);
  }

  /// Applies small, deterministic corrections for phrases that are easy for
  /// a general model to misclassify. In particular, a clock in a sentence
  /// ending with “前/截止” is a todo deadline, not an event to attend.
  ///
  /// Keeping this normalization local means the capture is still useful when
  /// the model returns a plausible but semantically wrong category, while all
  /// other fields (tags, importance and reminder intent) remain intact.
  static AiParsedIntent normalizeStudentIntent(
    AiParsedIntent intent, {
    required String sourceText,
    DateTime? now,
  }) {
    final instant = now ?? DateTime.now();
    return _dailyMetadata(
      _normalizeStudentLegacy(intent, sourceText: sourceText, now: instant),
      sourceText,
      instant,
    );
  }

  static AiParsedIntent _normalizeStudentLegacy(
    AiParsedIntent intent, {
    required String sourceText,
    DateTime? now,
  }) {
    final normalized = _normalizeReminderIntent(intent, sourceText: sourceText);
    final datedTodo = _normalizeDateOnlyTodo(
      normalized,
      sourceText: sourceText,
      now: now ?? DateTime.now(),
    );
    if (datedTodo.category != 'event' || datedTodo.eventTime == null) {
      return datedTodo;
    }

    final hasDeadlineCue = RegExp(
      r'(?:截止|最晚|之前|以前|前)\s*'
      r'(?:交|提交|上交|上传|完成|发|写|做|复习|准备|整理|阅读|看完|读完|背|填)|'
      r'(?:交|提交|上交|上传|完成|发|写|做|复习|准备|整理|阅读|看完|读完|背|填)'
      r'[^。！？\n]{0,12}(?:截止|之前|以前|前)',
    ).hasMatch(sourceText);
    if (!hasDeadlineCue) return datedTodo;

    return AiParsedIntent(
      category: 'todo',
      aiSummary: datedTodo.aiSummary,
      sentimentReply: datedTodo.sentimentReply,
      todos: datedTodo.todos,
      tags: datedTodo.tags,
      importance: datedTodo.importance,
      disturbanceLevel: datedTodo.disturbanceLevel,
      reminder: datedTodo.reminder,
      missingInfo: datedTodo.missingInfo,
      commandType: datedTodo.commandType,
      commandTarget: datedTodo.commandTarget,
      commandDays: datedTodo.commandDays,
      todoDeadline: datedTodo.todoDeadline ?? datedTodo.eventTime,
      scheduledAt: datedTodo.scheduledAt,
      taskKind: datedTodo.taskKind,
      attentionDate: datedTodo.attentionDate,
      todoOpensAt: datedTodo.todoOpensAt,
    );
  }

  /// Corrects the common date-only ambiguity at the capture boundary. A
  /// student saying “明天复习” is asking for an execution plan, while
  /// “明天前交报告” is asking for a deadline. The model is still the primary
  /// parser; this deterministic pass only fills or moves date fields when the
  /// source text makes the distinction clear.
  static AiParsedIntent _normalizeDateOnlyTodo(
    AiParsedIntent intent, {
    required String sourceText,
    required DateTime now,
  }) {
    if (intent.category != 'todo' || !_hasDateOnlyCue(sourceText)) {
      return intent;
    }
    if (_hasDeadlineCue(sourceText)) return intent;
    final day = _parseDateOnlyCue(sourceText, now);
    if (day == null) return intent;
    final currentScheduled = intent.scheduledAt;
    if (currentScheduled != null) return intent;
    final scheduled = DateTime(day.year, day.month, day.day, 9);
    // Some models follow the older prompt and put a date-only execution into
    // todo_deadline. Move that value to scheduledAt only when the wording has
    // no delivery/deadline cue, keeping explicit due dates untouched.
    return intent.copyWith(
      scheduledAt: scheduled,
      clearTodoDeadline: intent.todoDeadline != null,
    );
  }

  static AiParsedIntent _dailyMetadata(
    AiParsedIntent intent,
    String text,
    DateTime now,
  ) {
    var kind = intent.taskKind;
    if (RegExp(r'quiz|测验|限时任务', caseSensitive: false).hasMatch(text)) {
      kind = TaskKind.timed;
    } else if (RegExp(r'大作业|课程论文|毕业论文|项目报告').hasMatch(text)) {
      kind = TaskKind.preparation;
    }
    if (intent.category != 'todo' && kind == TaskKind.ordinary) return intent;
    var attention = intent.attentionDate;
    var opening = intent.todoOpensAt;
    var deadline = intent.todoDeadline;
    for (final segment in text.split(RegExp(r'[，,；;\n]'))) {
      final isOpening = RegExp(r'开放|开启').hasMatch(segment);
      final isAttention = RegExp(r'关注|开始准备|开始做|开始写').hasMatch(segment);
      final isDeadline = RegExp(r'截止|最晚|提交|上交').hasMatch(segment);
      // Several roles in one clause are ambiguous: keep them for confirmation.
      if ([isOpening, isAttention, isDeadline].where((v) => v).length != 1) {
        continue;
      }
      final date = _explicitTaskDate(segment, now, endOfDay: isDeadline);
      if (date == null) continue;
      if (isOpening) opening = date;
      if (isAttention) attention = calendarDate(date);
      if (isDeadline) deadline = date;
    }
    final advance = RegExp(r'提前\s*(\d+)\s*天').firstMatch(text);
    if (kind == TaskKind.preparation && advance != null && deadline != null) {
      attention ??= calendarDate(
        deadline,
      ).subtract(Duration(days: int.parse(advance.group(1)!)));
    }
    final explicitClock = _parseLocalClock(text, now) != null;
    final dateOnlySchedule =
        intent.scheduledAt != null &&
        !explicitClock &&
        intent.reminder.scheduleType == 'once';
    if (kind == TaskKind.ordinary && dateOnlySchedule) {
      attention ??= calendarDate(intent.scheduledAt!);
    }
    if (kind == TaskKind.ordinary &&
        attention == null &&
        !_hasDeadlineCue(text)) {
      attention = _parseDateOnlyCue(text, now);
    }
    return intent.copyWith(
      category: 'todo',
      taskKind: kind,
      attentionDate: attention,
      todoOpensAt: opening,
      todoDeadline: deadline,
      clearScheduledAt: dateOnlySchedule || kind != TaskKind.ordinary,
    );
  }

  static DateTime? _explicitTaskDate(
    String text,
    DateTime now, {
    bool endOfDay = false,
  }) {
    final iso = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
    DateTime? day;
    if (iso != null) {
      final y = int.parse(iso.group(1)!);
      final m = int.parse(iso.group(2)!);
      final d = int.parse(iso.group(3)!);
      final candidate = DateTime(y, m, d);
      if (candidate.year != y || candidate.month != m || candidate.day != d) {
        return null;
      }
      day = candidate;
    } else {
      day = _parseDateOnlyCue(text, now);
    }
    if (day == null) return null;
    final clock = _parseLocalClock(text, day);
    return DateTime(
      day.year,
      day.month,
      day.day,
      clock?.hour ?? (endOfDay ? 23 : 0),
      clock?.minute ?? (endOfDay ? 59 : 0),
    );
  }

  static bool _hasDateOnlyCue(String text) {
    return RegExp(
      r'(今天|明天|后天|大后天|(?:下|本|这)?(?:周|星期|礼拜)[一二三四五六日]|'
      r'(?:下|本|这)(?:周|星期|礼拜)|'
      r'\d{1,2}\s*[月/.-]\s*\d{1,2})',
    ).hasMatch(text);
  }

  static bool _hasDeadlineCue(String text) {
    return RegExp(
      r'(截止|最晚|deadline|交|提交|上交|上传|发送|发给|归还|缴费|报名|'
      r'完成|做完|写完|复习完|整理完|阅读完|看完|之前|以前|以内|前\s*(?=\S))',
      caseSensitive: false,
    ).hasMatch(text);
  }

  static DateTime? _parseDateOnlyCue(String text, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (text.contains('大后天')) return today.add(const Duration(days: 3));
    if (text.contains('后天')) return today.add(const Duration(days: 2));
    if (text.contains('明天')) return today.add(const Duration(days: 1));
    if (text.contains('今天')) return today;

    final numeric = RegExp(r'(\d{1,2})\s*[月/.-]\s*(\d{1,2})').firstMatch(text);
    if (numeric != null) {
      final month = int.tryParse(numeric.group(1)!);
      final day = int.tryParse(numeric.group(2)!);
      if (month != null && day != null && month >= 1 && month <= 12) {
        final daysInMonth = DateTime(now.year, month + 1, 0).day;
        if (day < 1 || day > daysInMonth) return null;
        final candidate = DateTime(now.year, month, day);
        return candidate.isBefore(today)
            ? DateTime(now.year + 1, month, day)
            : candidate;
      }
    }

    final weekdayMatch = RegExp(
      r'((?:下|本|这)?(?:周|星期|礼拜))([一二三四五六日])',
    ).firstMatch(text);
    if (weekdayMatch == null) return null;
    final prefix = weekdayMatch.group(1) ?? '';
    final weekday = '一二三四五六日'.indexOf(weekdayMatch.group(2)!) + 1;
    if (weekday < 1) return null;
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    var candidate = startOfWeek.add(Duration(days: weekday - 1));
    final isNextWeek = prefix.startsWith('下');
    final isBareWeekday = const {'周', '星期', '礼拜'}.contains(prefix);
    if (isNextWeek || (isBareWeekday && !candidate.isAfter(today))) {
      candidate = candidate.add(const Duration(days: 7));
    }
    return candidate;
  }

  static DiaryEntry applyAIResult(
    DiaryEntry entry,
    Map<String, dynamic> result,
  ) {
    final category = DiaryEntry.normalizeCategory(result['category']);
    final eventTime = category == 'event'
        ? DateTime.tryParse(result['event_time']?.toString() ?? '')
        : null;
    final eventEndTime = category == 'event'
        ? DateTime.tryParse(result['event_end_time']?.toString() ?? '')
        : null;
    final rawDuration = int.tryParse(
      result['duration_minutes']?.toString() ?? '',
    );
    final durationMinutes = _resolveEventDuration(
      eventTime: eventTime,
      eventEndTime: eventEndTime,
      rawDuration: rawDuration,
    );

    final tags = result['tags'] is List
        ? List<String>.from((result['tags'] as List).map((e) => e.toString()))
        : const <String>[];

    return entry.copyWith(
      category: category,
      eventTime: eventTime,
      clearEventTime: eventTime == null,
      durationMinutes: durationMinutes,
      clearDurationMinutes: durationMinutes == null,
      location: result['location']?.toString(),
      clearLocation: result['location'] == null,
      aiSummary: result['ai_summary']?.toString(),
      sentimentReply: result['sentiment_reply']?.toString(),
      tags: tags,
    );
  }

  static DiaryEntry applyAIIntent(DiaryEntry entry, AiParsedIntent intent) {
    return applyAIResult(entry, intent.legacyMap);
  }

  /// Keeps malformed AI classifications actionable instead of creating an
  /// invisible event with no time. The original capture remains a draft so
  /// the student can correct it from the Inbox.
  static DiaryEntry normalizeCapturedEntry(DiaryEntry entry) {
    if (entry.category == 'event' && entry.eventTime == null) {
      return entry.copyWith(
        category: 'draft',
        clearEventTime: true,
        clearDurationMinutes: true,
      );
    }
    return entry;
  }

  /// AI responses occasionally omit `todos` even though they classified the
  /// input as a todo. Preserve that capture by creating one conservative
  /// fallback task from the summary or original text.
  static List<String> todoTitlesForIntent(
    AiParsedIntent intent,
    String sourceText,
  ) {
    final titles = intent.todos
        .map((title) => title.trim())
        .where((title) => title.isNotEmpty)
        .toList();
    if (titles.isNotEmpty || intent.category != 'todo') return titles;

    final summary = intent.aiSummary?.trim();
    final fallback = summary?.isNotEmpty == true ? summary! : sourceText.trim();
    return fallback.isEmpty ? const [] : [fallback];
  }

  static AiParsedIntent _normalizeReminderIntent(
    AiParsedIntent intent, {
    required String sourceText,
  }) {
    final reminder = intent.reminder;
    if (!reminder.enabled) return intent;

    if (!_hasExplicitAdvanceRequest(sourceText)) {
      return intent.copyWith(
        reminder: reminder.copyWith(advanceMinutes: const [0]),
      );
    }

    final explicitAdvances = _explicitAdvanceMinutes(sourceText);
    if (explicitAdvances.isEmpty) return intent;
    return intent.copyWith(
      reminder: reminder.copyWith(advanceMinutes: explicitAdvances),
    );
  }

  static bool _hasExplicitAdvanceRequest(String text) {
    return RegExp(r'提前|前\s*\d+\s*(分钟|分|小时|个小时)').hasMatch(text);
  }

  static List<int> _explicitAdvanceMinutes(String text) {
    final values = <int>{};
    final numberPattern = RegExp(
      r'(\d+|一|二|两|三|四|五|六|七|八|九|十)\s*(个)?\s*(小时|分钟|分)',
    );
    for (final match in numberPattern.allMatches(text)) {
      final rawNumber = match.group(1) ?? '';
      final unit = match.group(3) ?? '';
      final number = _parseChineseOrArabicNumber(rawNumber);
      if (number == null) continue;
      values.add(unit == '小时' ? number * 60 : number);
    }
    return values.where((value) => value >= 0).toList()
      ..sort((a, b) => b.compareTo(a));
  }

  static int? _parseChineseOrArabicNumber(String value) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
    return switch (value) {
      '一' => 1,
      '二' || '两' => 2,
      '三' => 3,
      '四' => 4,
      '五' => 5,
      '六' => 6,
      '七' => 7,
      '八' => 8,
      '九' => 9,
      '十' => 10,
      _ => null,
    };
  }

  static Map<String, dynamic>? _extractJsonObject(String text) {
    final direct = _decodeJsonObject(text);
    if (direct != null) return direct;

    final match = RegExp(r'\{[\s\S]+\}').firstMatch(text);
    if (match == null) return null;
    return _decodeJsonObject(match.group(0)!);
  }

  static Map<String, dynamic>? _decodeJsonObject(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  /// Prefer a valid end time, but fall back to an independently valid
  /// duration when the model returned an impossible or overlong end time.
  static int? _resolveEventDuration({
    required DateTime? eventTime,
    required DateTime? eventEndTime,
    required int? rawDuration,
  }) {
    final fromEnd = eventTime == null || eventEndTime == null
        ? null
        : eventEndTime.difference(eventTime).inMinutes;
    final candidate = fromEnd != null && fromEnd > 0 && fromEnd <= 1440
        ? fromEnd
        : rawDuration;
    return candidate != null && candidate > 0 && candidate <= 1440
        ? candidate
        : null;
  }
}
