import 'diary_entry.dart';
import 'todo_task.dart';

class AiReminderCandidate {
  final bool enabled;
  final String scheduleType;
  final int scheduleInterval;
  final int? scheduleDay;
  final List<int> advanceMinutes;
  final bool requiresConfirmation;
  final List<int>? byDay;

  const AiReminderCandidate({
    this.enabled = false,
    this.scheduleType = 'once',
    this.scheduleInterval = 1,
    this.scheduleDay,
    this.advanceMinutes = const [],
    this.requiresConfirmation = false,
    this.byDay,
  });

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

  static List<int> _intList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => int.tryParse(item.toString()))
        .whereType<int>()
        .where((item) => item >= 0)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
  }

  static List<int>? _intListNullable(dynamic value) {
    if (value is! List || value.isEmpty) return null;
    final result =
        value
            .map((item) => int.tryParse(item.toString()))
            .whereType<int>()
            .where((item) => item >= 1 && item <= 7)
            .toSet()
            .toList()
          ..sort();
    return result.isEmpty ? null : result;
  }

  factory AiReminderCandidate.fromJson(dynamic value) {
    if (value is! Map) return const AiReminderCandidate();
    return AiReminderCandidate(
      enabled: value['enabled'] == true,
      scheduleType: _normalizeScheduleType(value['schedule_type']),
      scheduleInterval:
          int.tryParse(value['schedule_interval']?.toString() ?? '') ?? 1,
      scheduleDay: int.tryParse(value['schedule_day']?.toString() ?? ''),
      advanceMinutes: _intList(value['advance_minutes']),
      requiresConfirmation: value['requires_confirmation'] == true,
      byDay: _intListNullable(value['by_day']),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'schedule_type': scheduleType,
    'schedule_interval': scheduleInterval,
    'schedule_day': scheduleDay,
    'advance_minutes': advanceMinutes,
    'requires_confirmation': requiresConfirmation,
    'by_day': byDay,
  };

  AiReminderCandidate copyWith({
    bool? enabled,
    String? scheduleType,
    int? scheduleInterval,
    int? scheduleDay,
    bool clearScheduleDay = false,
    List<int>? advanceMinutes,
    bool? requiresConfirmation,
    List<int>? byDay,
    bool clearByDay = false,
  }) {
    return AiReminderCandidate(
      enabled: enabled ?? this.enabled,
      scheduleType: scheduleType ?? this.scheduleType,
      scheduleInterval: scheduleInterval ?? this.scheduleInterval,
      scheduleDay: clearScheduleDay ? null : scheduleDay ?? this.scheduleDay,
      advanceMinutes: advanceMinutes ?? this.advanceMinutes,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
      byDay: clearByDay ? null : byDay ?? this.byDay,
    );
  }
}

class AiParsedIntent {
  final String category;
  final DateTime? eventTime;
  final DateTime? eventEndTime;
  final int? durationMinutes;
  final String? location;
  final String? aiSummary;
  final String? sentimentReply;
  final List<String> todos;
  final List<String> tags;
  final String importance;
  final String disturbanceLevel;
  final AiReminderCandidate reminder;
  final List<String> missingInfo;
  final String commandType;
  final String? commandTarget;
  final int? commandDays;
  final DateTime? todoDeadline;
  final DateTime? scheduledAt;
  final TaskKind taskKind;
  final DateTime? attentionDate;
  final DateTime? todoOpensAt;

  const AiParsedIntent({
    this.category = 'draft',
    this.eventTime,
    this.eventEndTime,
    this.durationMinutes,
    this.location,
    this.aiSummary,
    this.sentimentReply,
    this.todos = const [],
    this.tags = const [],
    this.importance = 'normal',
    this.disturbanceLevel = 'normal',
    this.reminder = const AiReminderCandidate(),
    this.missingInfo = const [],
    this.commandType = 'none',
    this.commandTarget,
    this.commandDays,
    this.todoDeadline,
    this.scheduledAt,
    this.taskKind = TaskKind.ordinary,
    this.attentionDate,
    this.todoOpensAt,
  });

  bool get isLowLoadCommand => commandType == 'low_load';
  bool get isDisableFutureCommand => commandType == 'disable_future';

  bool get requiresReminderConfirmation {
    return reminder.enabled &&
        (reminder.requiresConfirmation ||
            importance == 'important' ||
            disturbanceLevel == 'strong' ||
            reminder.advanceMinutes.length > 1 ||
            reminder.scheduleType != 'once');
  }

  Map<String, dynamic> get legacyMap => {
    'category': category,
    'event_time': eventTime?.toIso8601String(),
    'event_end_time': eventEndTime?.toIso8601String(),
    'duration_minutes': durationMinutes,
    'location': location,
    'ai_summary': aiSummary,
    'sentiment_reply': sentimentReply,
    'todos': todos,
    'tags': tags,
    'todo_deadline': todoDeadline?.toIso8601String(),
    'scheduled_at': scheduledAt?.toIso8601String(),
    'task_kind': taskKind.name,
    'attention_date': attentionDate?.toIso8601String(),
    'opens_at': todoOpensAt?.toIso8601String(),
  };

  /// Full, stable payload used when an AI result must survive an app restart.
  /// [legacyMap] intentionally stays small because it is passed to the
  /// DiaryEntry mapper; this method is for persistence only.
  Map<String, dynamic> toJson() => {
    ...legacyMap,
    'importance': importance,
    'disturbance_level': disturbanceLevel,
    'reminder': reminder.toJson(),
    'missing_info': missingInfo,
    'command_type': commandType,
    'command_target': commandTarget,
    'command_days': commandDays,
  };

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

  static String _normalizeCommandType(dynamic value) {
    final text = value?.toString() ?? 'none';
    return switch (text) {
      'low_load' || 'disable_future' || 'none' => text,
      _ => 'none',
    };
  }

  static List<String> _stringList(dynamic value) {
    final values = value is List
        ? value.map((item) => item.toString())
        : value is String
        ? value.split(RegExp(r'[\s,，、]+'))
        : const <String>[];
    return values
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  factory AiParsedIntent.fromJson(Map<String, dynamic> json) {
    final category = DiaryEntry.normalizeCategory(json['category']);
    final eventTime = category == 'event'
        ? DateTime.tryParse(json['event_time']?.toString() ?? '')
        : null;
    final eventEndTime = category == 'event'
        ? DateTime.tryParse(json['event_end_time']?.toString() ?? '')
        : null;
    final commandDays = int.tryParse(json['command_days']?.toString() ?? '');
    return AiParsedIntent(
      category: category,
      eventTime: eventTime,
      eventEndTime: eventEndTime,
      durationMinutes: _normalizeDuration(json['duration_minutes']),
      location: json['location']?.toString(),
      aiSummary: json['ai_summary']?.toString(),
      sentimentReply: json['sentiment_reply']?.toString(),
      todos: _stringList(json['todos']),
      tags: _stringList(json['tags']),
      importance: _normalizeImportance(json['importance']),
      disturbanceLevel: _normalizeDisturbanceLevel(json['disturbance_level']),
      reminder: AiReminderCandidate.fromJson(json['reminder']),
      missingInfo: _stringList(json['missing_info']),
      commandType: _normalizeCommandType(json['command_type']),
      commandTarget: json['command_target']?.toString(),
      commandDays: commandDays == null || commandDays < 1 ? null : commandDays,
      todoDeadline: DateTime.tryParse(json['todo_deadline']?.toString() ?? ''),
      scheduledAt: DateTime.tryParse(json['scheduled_at']?.toString() ?? ''),
      taskKind: TaskKind.parse(json['task_kind']),
      attentionDate: DateTime.tryParse(
        json['attention_date']?.toString() ?? '',
      ),
      todoOpensAt: DateTime.tryParse(json['opens_at']?.toString() ?? ''),
    );
  }

  AiParsedIntent copyWith({
    String? category,
    DateTime? eventTime,
    DateTime? eventEndTime,
    int? durationMinutes,
    String? location,
    String? aiSummary,
    String? sentimentReply,
    List<String>? todos,
    List<String>? tags,
    String? importance,
    String? disturbanceLevel,
    AiReminderCandidate? reminder,
    List<String>? missingInfo,
    String? commandType,
    String? commandTarget,
    int? commandDays,
    DateTime? todoDeadline,
    bool clearTodoDeadline = false,
    TaskKind? taskKind,
    DateTime? attentionDate,
    DateTime? todoOpensAt,
    DateTime? scheduledAt,
    bool clearScheduledAt = false,
  }) {
    return AiParsedIntent(
      category: category ?? this.category,
      eventTime: eventTime ?? this.eventTime,
      eventEndTime: eventEndTime ?? this.eventEndTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      location: location ?? this.location,
      aiSummary: aiSummary ?? this.aiSummary,
      sentimentReply: sentimentReply ?? this.sentimentReply,
      todos: todos ?? this.todos,
      tags: tags ?? this.tags,
      importance: importance ?? this.importance,
      disturbanceLevel: disturbanceLevel ?? this.disturbanceLevel,
      reminder: reminder ?? this.reminder,
      missingInfo: missingInfo ?? this.missingInfo,
      commandType: commandType ?? this.commandType,
      commandTarget: commandTarget ?? this.commandTarget,
      commandDays: commandDays ?? this.commandDays,
      todoDeadline: clearTodoDeadline
          ? null
          : todoDeadline ?? this.todoDeadline,
      scheduledAt: clearScheduledAt ? null : scheduledAt ?? this.scheduledAt,
      taskKind: taskKind ?? this.taskKind,
      attentionDate: attentionDate ?? this.attentionDate,
      todoOpensAt: todoOpensAt ?? this.todoOpensAt,
    );
  }

  static int? _normalizeDuration(dynamic value) {
    final minutes = int.tryParse(value?.toString() ?? '');
    return minutes != null && minutes > 0 && minutes <= 1440 ? minutes : null;
  }
}
