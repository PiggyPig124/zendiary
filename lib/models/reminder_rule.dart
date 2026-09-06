import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'recurrence_override.dart';

class ReminderRule {
  final String id;
  final String title;
  final String targetType;
  final String? targetId;
  final String category;
  final String importance;
  final String disturbanceLevel;
  final String scheduleType;
  final int scheduleInterval;
  final int? scheduleDay;
  final DateTime? anchorTime;
  final List<int> advanceMinutes;
  final String status;
  final String displayMode; // 'punctual' | 'spanning' | 'customSpan'
  final int? customSpanDays; // displayMode == 'customSpan' 时的窗口天数
  final DateTime? startDate; // 重复起始日期
  final DateTime? endDate; // 重复截止日期
  /// 总出现次数（含锚点日）。设为 1 可阻止所有投影。
  final int? endCount;
  final List<int>? byDay; // 周几：1=周一..7=周日，如 [1,3,5]=周一三五
  final List<int>? byMonthDay; // 月内日期，如 [15, 30]
  final List<DateTime> skipDates; // 跳过的投影日期（仅比较年月日）
  final List<RecurrenceOverride> overrides; // 逐次覆盖列表
  final bool generatedByAi;
  final bool requiresConfirmation;
  /// True only when completion temporarily archived an otherwise active rule.
  /// This lets undo restore the rule without resurrecting a reminder the
  /// student had already paused or disabled by choice.
  final bool archivedByCompletion;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? note;

  ReminderRule({
    String? id,
    required this.title,
    this.targetType = 'standalone',
    this.targetId,
    this.category = 'general',
    this.importance = 'normal',
    this.disturbanceLevel = 'normal',
    this.scheduleType = 'once',
    this.scheduleInterval = 1,
    this.scheduleDay,
    this.anchorTime,
    this.advanceMinutes = const [],
    this.status = 'active',
    this.generatedByAi = false,
    this.requiresConfirmation = false,
    this.archivedByCompletion = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.note,
    this.displayMode = 'punctual',
    this.customSpanDays,
    this.startDate,
    this.endDate,
    this.endCount,
    this.byDay,
    this.byMonthDay,
    this.skipDates = const [],
    this.overrides = const [],
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  bool get isActive => status == 'active';
  bool get isStrong => disturbanceLevel == 'strong';

  static DateTime? _tryParseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static String _normalizeTargetType(dynamic value) {
    final text = value?.toString() ?? 'standalone';
    return switch (text) {
      'todo' || 'event' || 'standalone' || 'rule' => text,
      _ => 'standalone',
    };
  }

  static String _normalizeImportance(dynamic value) {
    final text = value?.toString() ?? 'normal';
    return switch (text) {
      'important' || 'normal' || 'minor' => text,
      _ => 'normal',
    };
  }

  static String _normalizeDisturbanceLevel(dynamic value) {
    final text = value?.toString() ?? 'normal';
    return switch (text) {
      'strong' || 'normal' || 'silent' => text,
      _ => 'normal',
    };
  }

  static String _normalizeScheduleType(dynamic value) {
    final text = value?.toString() ?? 'once';
    return switch (text) {
      'once' ||
      'daily' ||
      'weekly' ||
      'every_n_days' ||
      'monthly' ||
      'custom' => text,
      _ => 'once',
    };
  }

  static String _normalizeStatus(dynamic value) {
    final text = value?.toString() ?? 'active';
    return switch (text) {
      'active' || 'paused' || 'disabled' || 'archived' => text,
      _ => 'active',
    };
  }

  static String _normalizeDisplayMode(dynamic value) {
    final text = value?.toString() ?? 'punctual';
    return switch (text) {
      'punctual' || 'spanning' || 'customSpan' => text,
      _ => 'punctual',
    };
  }

  /// Accept both the current JSON arrays and the space-delimited values used
  /// by older exports (for example, `"30 5"` for two advance points).
  static List<dynamic> _listValues(dynamic value) {
    if (value is List) return List<dynamic>.from(value);
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) return const [];
      return text
          .split(RegExp(r'[\s,，、;；]+'))
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static List<int>? _normalizeWeekdays(dynamic value) {
    final values = _listValues(value);
    if (values.isEmpty) return null;
    final days =
        values
            .map((e) => int.tryParse(e.toString()))
            .whereType<int>()
            .where((d) => d >= 1 && d <= 7)
            .toSet()
            .toList()
          ..sort();
    return days.isEmpty ? null : days;
  }

  static List<int>? _normalizeMonthDays(dynamic value) {
    final values = _listValues(value);
    if (values.isEmpty) return null;
    final days =
        values
            .map((e) => int.tryParse(e.toString()))
            .whereType<int>()
            .where((d) => d >= 1 && d <= 31)
            .toSet()
            .toList()
          ..sort();
    return days.isEmpty ? null : days;
  }

  static List<DateTime> _parseDateList(dynamic value) {
    final values = _listValues(value);
    if (values.isEmpty) return const [];
    return values
        .map((e) {
          final parsed = DateTime.tryParse(e.toString());
          if (parsed == null) return null;
          return DateTime(parsed.year, parsed.month, parsed.day);
        })
        .whereType<DateTime>()
        .toList();
  }

  static List<RecurrenceOverride> _parseOverrides(dynamic value) {
    dynamic source = value;
    if (value is String && value.trim().isNotEmpty) {
      try {
        source = jsonDecode(value);
      } on FormatException {
        return const [];
      }
    }
    if (source is! List || source.isEmpty) return const [];
    return source
        .whereType<Map>()
        .map((e) => RecurrenceOverride.fromJson(e))
        .toList();
  }

  static List<int> _intList(dynamic value) {
    return _listValues(value)
        .map((item) => int.tryParse(item.toString()))
        .whereType<int>()
        .where((item) => item >= 0)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'targetType': _normalizeTargetType(targetType),
    'targetId': targetId,
    'category': category,
    'importance': _normalizeImportance(importance),
    'disturbanceLevel': _normalizeDisturbanceLevel(disturbanceLevel),
    'scheduleType': _normalizeScheduleType(scheduleType),
    'scheduleInterval': scheduleInterval,
    'scheduleDay': scheduleDay,
    'anchorTime': anchorTime?.toIso8601String(),
    'advanceMinutes': advanceMinutes,
    'status': _normalizeStatus(status),
    'generatedByAi': generatedByAi,
    'requiresConfirmation': requiresConfirmation,
    'archivedByCompletion': archivedByCompletion,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'note': note,
    'displayMode': displayMode,
    'customSpanDays': customSpanDays,
    'startDate': startDate?.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'endCount': endCount,
    'byDay': byDay,
    'byMonthDay': byMonthDay,
    'skipDates': skipDates
        .map((d) => d.toIso8601String().split('T').first)
        .toList(),
    'overrides': overrides.map((o) => o.toJson()).toList(),
  };

  factory ReminderRule.fromJson(Map<dynamic, dynamic> json) {
    final createdAt = _tryParseDate(json['createdAt']) ?? DateTime.now();
    return ReminderRule(
      id: json['id']?.toString(),
      title: json['title']?.toString() ?? '',
      targetType: _normalizeTargetType(json['targetType']),
      targetId: json['targetId']?.toString(),
      category: json['category']?.toString() ?? 'general',
      importance: _normalizeImportance(json['importance']),
      disturbanceLevel: _normalizeDisturbanceLevel(json['disturbanceLevel']),
      scheduleType: _normalizeScheduleType(json['scheduleType']),
      scheduleInterval:
          int.tryParse(json['scheduleInterval']?.toString() ?? '') ?? 1,
      scheduleDay: int.tryParse(json['scheduleDay']?.toString() ?? ''),
      anchorTime: _tryParseDate(json['anchorTime']),
      advanceMinutes: _intList(json['advanceMinutes']),
      status: _normalizeStatus(json['status']),
      generatedByAi: json['generatedByAi'] == true,
      requiresConfirmation: json['requiresConfirmation'] == true,
      archivedByCompletion: json['archivedByCompletion'] == true,
      createdAt: createdAt,
      updatedAt: _tryParseDate(json['updatedAt']) ?? createdAt,
      note: json['note']?.toString(),
      displayMode: _normalizeDisplayMode(json['displayMode']),
      customSpanDays: int.tryParse(json['customSpanDays']?.toString() ?? ''),
      startDate: _tryParseDate(json['startDate']),
      endDate: _tryParseDate(json['endDate']),
      endCount: int.tryParse(json['endCount']?.toString() ?? ''),
      byDay: _normalizeWeekdays(json['byDay']),
      byMonthDay: _normalizeMonthDays(json['byMonthDay']),
      skipDates: _parseDateList(json['skipDates']),
      overrides: _parseOverrides(json['overrides']),
    );
  }

  ReminderRule copyWith({
    String? title,
    String? targetType,
    String? targetId,
    bool clearTargetId = false,
    String? category,
    String? importance,
    String? disturbanceLevel,
    String? scheduleType,
    int? scheduleInterval,
    int? scheduleDay,
    bool clearScheduleDay = false,
    DateTime? anchorTime,
    bool clearAnchorTime = false,
    List<int>? advanceMinutes,
    String? status,
    bool? generatedByAi,
    bool? requiresConfirmation,
    bool? archivedByCompletion,
    String? displayMode,
    int? customSpanDays,
    bool clearCustomSpanDays = false,
    DateTime? startDate,
    bool clearStartDate = false,
    DateTime? endDate,
    bool clearEndDate = false,
    int? endCount,
    bool clearEndCount = false,
    List<int>? byDay,
    bool clearByDay = false,
    List<int>? byMonthDay,
    bool clearByMonthDay = false,
    List<DateTime>? skipDates,
    bool clearSkipDates = false,
    List<RecurrenceOverride>? overrides,
    bool clearOverrides = false,
    String? note,
    bool clearNote = false,
  }) {
    return ReminderRule(
      id: id,
      title: title ?? this.title,
      targetType: targetType ?? this.targetType,
      targetId: clearTargetId ? null : targetId ?? this.targetId,
      category: category ?? this.category,
      importance: importance ?? this.importance,
      disturbanceLevel: disturbanceLevel ?? this.disturbanceLevel,
      scheduleType: scheduleType ?? this.scheduleType,
      scheduleInterval: scheduleInterval ?? this.scheduleInterval,
      scheduleDay: clearScheduleDay ? null : scheduleDay ?? this.scheduleDay,
      anchorTime: clearAnchorTime ? null : anchorTime ?? this.anchorTime,
      advanceMinutes: advanceMinutes ?? this.advanceMinutes,
      status: status ?? this.status,
      generatedByAi: generatedByAi ?? this.generatedByAi,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
      archivedByCompletion:
          archivedByCompletion ?? this.archivedByCompletion,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      note: clearNote ? null : note ?? this.note,
      displayMode: displayMode ?? this.displayMode,
      customSpanDays: clearCustomSpanDays
          ? null
          : customSpanDays ?? this.customSpanDays,
      startDate: clearStartDate ? null : startDate ?? this.startDate,
      endDate: clearEndDate ? null : endDate ?? this.endDate,
      endCount: clearEndCount ? null : endCount ?? this.endCount,
      byDay: clearByDay ? null : byDay ?? this.byDay,
      byMonthDay: clearByMonthDay ? null : byMonthDay ?? this.byMonthDay,
      skipDates: clearSkipDates ? const [] : skipDates ?? this.skipDates,
      overrides: clearOverrides ? const [] : overrides ?? this.overrides,
    );
  }
}
