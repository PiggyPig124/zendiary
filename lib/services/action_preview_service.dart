import '../models/ai_parsed_intent.dart';
import '../models/diary_entry.dart';
import '../models/pending_action_preview.dart';
import '../models/reminder_rule.dart';
import '../models/todo_task.dart';

class ActionPreviewService {
  static PendingActionPreview? buildPreview({
    required AiParsedIntent intent,
    required String sourceText,
    required DateTime now,
    required List<TodoTask> todos,
    required List<DiaryEntry> events,
    required List<ReminderRule> rules,
  }) {
    if (intent.isLowLoadCommand) {
      return buildLowLoadPreview(
        sourceText: sourceText,
        now: now,
        days: intent.commandDays ?? _daysFromText(sourceText),
        targetText: intent.commandTarget ?? sourceText,
        todos: todos,
        events: events,
        rules: rules,
      );
    }
    if (intent.isDisableFutureCommand) {
      return buildDisableFuturePreview(
        sourceText: sourceText,
        now: now,
        targetText: intent.commandTarget ?? sourceText,
        todos: todos,
        events: events,
        rules: rules,
      );
    }
    return null;
  }

  static PendingActionPreview buildLowLoadPreview({
    required String sourceText,
    required DateTime now,
    required int days,
    required String targetText,
    required List<TodoTask> todos,
    required List<DiaryEntry> events,
    required List<ReminderRule> rules,
  }) {
    final rangeStart = DateTime(now.year, now.month, now.day);
    final rangeEnd = rangeStart.add(Duration(days: days));
    final affectedEvents = events
        .where((entry) => !entry.isArchived)
        .where((entry) => _isInRange(entry.sortTime, rangeStart, rangeEnd))
        .where((entry) => _matchesLowLoadTarget(entry.content, targetText))
        .where((entry) => !_isProtectedText(entry.content))
        .toList();
    final affectedTodos = todos
        .where((todo) => !todo.isCompleted && !todo.isArchived)
        .where((todo) {
          // A planned study block is part of the student's near-term load
          // even when it has no formal deadline. Prefer the execution plan,
          // then the deadline, and only fall back to capture time for a
          // genuinely floating task.
          final time = todo.scheduledAt ?? todo.deadline ?? todo.createdAt;
          return _isInRange(time, rangeStart, rangeEnd);
        })
        .where((todo) => _matchesLowLoadTarget(_todoText(todo), targetText))
        .where((todo) => !_isProtectedText(_todoText(todo)))
        .toList();
    final affectedIds = {
      ...affectedEvents.map((entry) => entry.id),
      ...affectedTodos.map((todo) => todo.id),
    };
    final affectedRules = rules
        .where((rule) => rule.isActive)
        .where(
          (rule) =>
              (rule.targetId != null && affectedIds.contains(rule.targetId)) ||
              (_isInRange(rule.anchorTime, rangeStart, rangeEnd) &&
                  _matchesLowLoadTarget(_ruleText(rule), targetText) &&
                  !_isProtectedText(_ruleText(rule))),
        )
        .toList();
    final protectedItems = [
      ...events
          .where((entry) => !entry.isArchived)
          .where((entry) => _isInRange(entry.sortTime, rangeStart, rangeEnd))
          .where((entry) => _isProtectedText(entry.content))
          .map((entry) => entry.aiSummary ?? entry.content),
      ...todos
          .where((todo) => !todo.isCompleted && !todo.isArchived)
          .where((todo) => _isProtectedText(_todoText(todo)))
          .map((todo) => todo.title),
    ];
    return PendingActionPreview(
      type: PendingActionType.lowLoad,
      title: '低负荷安排预览',
      reason: sourceText,
      createdAt: now,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      todos: affectedTodos,
      events: affectedEvents,
      rules: affectedRules,
      protectedItems: protectedItems.toSet().toList(),
    );
  }

  static PendingActionPreview buildDisableFuturePreview({
    required String sourceText,
    required DateTime now,
    required String targetText,
    required List<TodoTask> todos,
    required List<DiaryEntry> events,
    required List<ReminderRule> rules,
  }) {
    final affectedEvents = events
        .where((entry) => !entry.isArchived && !entry.sortTime.isBefore(now))
        .where((entry) => _matchesFutureTarget(entry.content, targetText))
        .toList();
    final affectedTodos = todos
        .where((todo) => !todo.isCompleted && !todo.isArchived)
        .where((todo) => _matchesFutureTarget(_todoText(todo), targetText))
        .toList();
    final affectedIds = {
      ...affectedEvents.map((entry) => entry.id),
      ...affectedTodos.map((todo) => todo.id),
    };
    final affectedRules = rules
        .where((rule) => rule.isActive)
        .where(
          (rule) =>
              (rule.targetId != null && affectedIds.contains(rule.targetId)) ||
              _matchesFutureTarget(_ruleText(rule), targetText),
        )
        .toList();
    return PendingActionPreview(
      type: PendingActionType.disableFuture,
      title: '停用未来事项预览',
      reason: sourceText,
      createdAt: now,
      todos: affectedTodos,
      events: affectedEvents,
      rules: affectedRules,
    );
  }

  static bool _isInRange(DateTime? time, DateTime start, DateTime end) {
    if (time == null) return false;
    return !time.isBefore(start) && time.isBefore(end);
  }

  static bool _matchesLowLoadTarget(String text, String targetText) {
    final haystack = '$text $targetText'.toLowerCase();
    return _containsAny(haystack, const [
      '工作',
      '上班',
      '项目',
      '会议',
      '开会',
      '课',
      '课程',
      '上课',
      'class',
      'work',
      'meeting',
    ]);
  }

  static bool _matchesFutureTarget(String text, String targetText) {
    final normalizedText = text.toLowerCase();
    final terms = _targetTerms(targetText);
    if (terms.any(normalizedText.contains)) return true;
    return _containsAny('$normalizedText ${targetText.toLowerCase()}', const [
      '课',
      '课程',
      '任务',
      '提醒',
      'todo',
      'class',
    ]);
  }

  static List<String> _targetTerms(String text) {
    final cleaned = text
        .replaceAll(RegExp(r'[以后之后未来不要再都不做了不上了停掉提醒我]'), ' ')
        .split(RegExp(r'\s+'))
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.length >= 2)
        .toList();
    return cleaned.take(6).toList();
  }

  static bool _isProtectedText(String text) {
    final normalized = text.toLowerCase();
    return _containsAny(normalized, const [
      '考试',
      '考研',
      '期末',
      '面试',
      '截止',
      'ddl',
      'deadline',
      '预约',
      '医院',
      '签证',
    ]);
  }

  static bool _containsAny(String text, List<String> needles) {
    return needles.any(text.contains);
  }

  static String _todoText(TodoTask todo) {
    return '${todo.title} ${todo.category} ${todo.priority}';
  }

  static String _ruleText(ReminderRule rule) {
    return '${rule.title} ${rule.category} ${rule.note ?? ''}';
  }

  static int _daysFromText(String text) {
    final match = RegExp(r'(\d+)\s*天').firstMatch(text);
    final days = int.tryParse(match?.group(1) ?? '');
    if (days != null && days > 0) return days;
    if (text.contains('近') || text.contains('几天')) return 3;
    return 1;
  }
}
