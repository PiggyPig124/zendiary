import 'diary_entry.dart';
import 'reminder_rule.dart';
import 'todo_task.dart';

enum PendingActionType { lowLoad, disableFuture }

class PendingActionPreview {
  final PendingActionType type;
  final String title;
  final String reason;
  final DateTime createdAt;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final List<TodoTask> todos;
  final List<DiaryEntry> events;
  final List<ReminderRule> rules;
  final List<String> protectedItems;

  const PendingActionPreview({
    required this.type,
    required this.title,
    required this.reason,
    required this.createdAt,
    this.rangeStart,
    this.rangeEnd,
    this.todos = const [],
    this.events = const [],
    this.rules = const [],
    this.protectedItems = const [],
  });

  bool get isEmpty => todos.isEmpty && events.isEmpty && rules.isEmpty;

  int get affectedCount => todos.length + events.length + rules.length;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'title': title,
    'reason': reason,
    'createdAt': createdAt.toIso8601String(),
    'rangeStart': rangeStart?.toIso8601String(),
    'rangeEnd': rangeEnd?.toIso8601String(),
    'todos': todos.map((todo) => todo.toJson()).toList(),
    'events': events.map((entry) => entry.toJson()).toList(),
    'rules': rules.map((rule) => rule.toJson()).toList(),
    'protectedItems': protectedItems,
  };

  factory PendingActionPreview.fromJson(Map<dynamic, dynamic> json) {
    final type = PendingActionType.values.firstWhere(
      (value) => value.name == json['type']?.toString(),
      orElse: () => PendingActionType.lowLoad,
    );
    final createdAt =
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now();
    List<TodoTask> parseTodos(dynamic value) => value is List
        ? value.whereType<Map>().map(TodoTask.fromJson).toList()
        : const [];
    List<DiaryEntry> parseEvents(dynamic value) => value is List
        ? value.whereType<Map>().map(DiaryEntry.fromJson).toList()
        : const [];
    List<ReminderRule> parseRules(dynamic value) => value is List
        ? value.whereType<Map>().map(ReminderRule.fromJson).toList()
        : const [];
    final protected = json['protectedItems'] is List
        ? List<String>.from(
            (json['protectedItems'] as List).map((item) => item.toString()),
          )
        : const <String>[];
    return PendingActionPreview(
      type: type,
      title: json['title']?.toString() ?? '待确认操作',
      reason: json['reason']?.toString() ?? '',
      createdAt: createdAt,
      rangeStart: DateTime.tryParse(json['rangeStart']?.toString() ?? ''),
      rangeEnd: DateTime.tryParse(json['rangeEnd']?.toString() ?? ''),
      todos: parseTodos(json['todos']),
      events: parseEvents(json['events']),
      rules: parseRules(json['rules']),
      protectedItems: protected,
    );
  }
}

class LowLoadStatus {
  final bool active;
  final String reason;
  final DateTime startedAt;
  final DateTime? until;
  final int affectedCount;

  const LowLoadStatus({
    required this.active,
    required this.reason,
    required this.startedAt,
    this.until,
    this.affectedCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'active': active,
    'reason': reason,
    'startedAt': startedAt.toIso8601String(),
    'until': until?.toIso8601String(),
    'affectedCount': affectedCount,
  };

  factory LowLoadStatus.fromJson(Map<dynamic, dynamic> json) {
    final startedAt =
        DateTime.tryParse(json['startedAt']?.toString() ?? '') ??
        DateTime.now();
    return LowLoadStatus(
      active: json['active'] == true,
      reason: json['reason']?.toString() ?? '低负荷安排',
      startedAt: startedAt,
      until: DateTime.tryParse(json['until']?.toString() ?? ''),
      affectedCount: int.tryParse(json['affectedCount']?.toString() ?? '') ?? 0,
    );
  }
}
