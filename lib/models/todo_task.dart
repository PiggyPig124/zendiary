enum TaskKind {
  ordinary('普通待办'),
  timed('限时任务 / Quiz'),
  preparation('准备型作业');

  final String label;
  const TaskKind(this.label);

  static TaskKind parse(dynamic value) => TaskKind.values.firstWhere(
    (kind) => kind.name == value,
    orElse: () => TaskKind.ordinary,
  );
}

DateTime calendarDate(DateTime value) =>
    DateTime(value.year, value.month, value.day);

class TodoTask {
  final String id;
  final String title;
  final DateTime createdAt;
  bool isCompleted;
  final List<String> subNotes;
  String priority;
  String category;
  int inheritCount;
  final String? sourceEntryId;
  final DateTime? opensAt;
  final TaskKind taskKind;
  final DateTime? attentionDate;
  final bool attentionConfirmed;

  /// When the user intends to work on the task; independent from its due date.
  DateTime? scheduledAt;

  /// Expected focused work time in minutes. Null keeps the planner's
  /// backwards-compatible 30-minute estimate.
  final int? estimatedMinutes;
  final DateTime? deadline;
  List<String> tags;
  bool monthVisibility;
  final bool isArchived;

  TodoTask({
    required this.id,
    required this.title,
    required this.createdAt,
    this.isCompleted = false,
    this.subNotes = const [],
    this.priority = 'B',
    this.category = 'general',
    this.inheritCount = 0,
    this.sourceEntryId,
    this.opensAt,
    this.taskKind = TaskKind.ordinary,
    DateTime? attentionDate,
    this.attentionConfirmed = true,
    this.scheduledAt,
    int? estimatedMinutes,
    this.deadline,
    this.tags = const [],
    this.monthVisibility = true,
    this.isArchived = false,
  }) : attentionDate = attentionDate == null
           ? null
           : calendarDate(attentionDate),
       estimatedMinutes = _normalizeEstimatedMinutes(estimatedMinutes);

  /// Shared by capture, forms and Today. Invalid captures remain recoverable.
  String? get validationMessage {
    if (title.trim().isEmpty) return '请填写待办内容';
    if (taskKind == TaskKind.preparation) {
      if (attentionDate == null) return '请选择开始关注日';
      if (!attentionConfirmed) return '请确认开始关注日';
    }
    if (taskKind == TaskKind.timed && (opensAt == null || deadline == null)) {
      return '请补充开放时间和截止时间';
    }
    if (opensAt != null && deadline != null && !opensAt!.isBefore(deadline!)) {
      return '开放时间必须早于截止时间';
    }
    if (attentionDate != null &&
        deadline != null &&
        attentionDate!.isAfter(calendarDate(deadline!))) {
      return '开始关注日不能晚于截止日期';
    }
    return null;
  }

  static DateTime? _tryParseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return List<String>.from(
        value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
      );
    }
    if (value is String) {
      return value
          .split(RegExp(r'[\s,，、]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static String _normalizePriority(dynamic value) {
    final priority = value?.toString() ?? 'B';
    return priority == 'A' || priority == 'B' || priority == 'C'
        ? priority
        : 'B';
  }

  static String _normalizeCategory(dynamic value) {
    final category = value?.toString().trim() ?? '';
    return category.isEmpty ? 'general' : category;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'isCompleted': isCompleted,
    'subNotes': subNotes,
    'priority': _normalizePriority(priority),
    'category': _normalizeCategory(category),
    'inheritCount': inheritCount,
    'sourceEntryId': sourceEntryId,
    'opensAt': opensAt?.toIso8601String(),
    'taskKind': taskKind.name,
    'attentionDate': attentionDate == null
        ? null
        : '${attentionDate!.year.toString().padLeft(4, '0')}-${attentionDate!.month.toString().padLeft(2, '0')}-${attentionDate!.day.toString().padLeft(2, '0')}',
    'attentionConfirmed': attentionConfirmed,
    'scheduledAt': scheduledAt?.toIso8601String(),
    'estimatedMinutes': estimatedMinutes,
    'deadline': deadline?.toIso8601String(),
    'tags': tags,
    'monthVisibility': monthVisibility,
    'isArchived': isArchived,
  };

  /// 是否设置了提醒时间（可直接用于时间线展示）。
  /// 已废弃：提醒现在由 ReminderRule 统一管理。

  factory TodoTask.fromJson(Map<dynamic, dynamic> json) {
    final createdAt = _tryParseDate(json['createdAt']) ?? DateTime.now();
    // [Migration] 旧字段 remindAt / timeWindow 已废弃，不再存储
    // [Migration] importance 字段已废弃，合并到 priority
    final priority = _migratePriority(json);
    return TodoTask(
      id: json['id']?.toString() ?? createdAt.microsecondsSinceEpoch.toString(),
      title: json['title']?.toString() ?? json['todo']?.toString() ?? '',
      createdAt: createdAt,
      isCompleted: json['isCompleted'] == true,
      subNotes: _stringList(json['subNotes']),
      priority: priority,
      category: _normalizeCategory(json['category']),
      inheritCount: json['inheritCount'] is int
          ? json['inheritCount'] as int
          : 0,
      sourceEntryId: json['sourceEntryId']?.toString(),
      opensAt: _tryParseDate(json['opensAt']),
      taskKind: TaskKind.parse(json['taskKind']),
      attentionDate: json.containsKey('taskKind')
          ? _tryParseDate(json['attentionDate'])
          : (_tryParseDate(json['opensAt']) ??
                _tryParseDate(json['scheduledAt'])),
      attentionConfirmed: json['attentionConfirmed'] != false,
      scheduledAt: _tryParseDate(json['scheduledAt']),
      estimatedMinutes: _normalizeEstimatedMinutes(json['estimatedMinutes']),
      deadline: _tryParseDate(json['deadline']),
      tags: _stringList(json['tags']),
      monthVisibility: json['monthVisibility'] != false,
      isArchived: json['isArchived'] == true,
    );
  }

  TodoTask copyWith({
    String? title,
    DateTime? createdAt,
    bool? isCompleted,
    List<String>? subNotes,
    String? priority,
    String? category,
    int? inheritCount,
    String? sourceEntryId,
    bool clearSourceEntryId = false,
    DateTime? opensAt,
    TaskKind? taskKind,
    DateTime? attentionDate,
    bool clearAttentionDate = false,
    bool? attentionConfirmed,
    bool clearOpensAt = false,
    DateTime? scheduledAt,
    bool clearScheduledAt = false,
    int? estimatedMinutes,
    bool clearEstimatedMinutes = false,
    DateTime? deadline,
    bool clearDeadline = false,
    List<String>? tags,
    bool? monthVisibility,
    bool? isArchived,
  }) {
    return TodoTask(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      isCompleted: isCompleted ?? this.isCompleted,
      subNotes: subNotes ?? this.subNotes,
      priority: priority ?? this.priority,
      category: category ?? this.category,
      inheritCount: inheritCount ?? this.inheritCount,
      sourceEntryId: clearSourceEntryId
          ? null
          : sourceEntryId ?? this.sourceEntryId,
      opensAt: clearOpensAt ? null : opensAt ?? this.opensAt,
      taskKind: taskKind ?? this.taskKind,
      attentionDate: clearAttentionDate
          ? null
          : attentionDate ?? this.attentionDate,
      attentionConfirmed: attentionConfirmed ?? this.attentionConfirmed,
      scheduledAt: clearScheduledAt ? null : scheduledAt ?? this.scheduledAt,
      estimatedMinutes: clearEstimatedMinutes
          ? null
          : estimatedMinutes ?? this.estimatedMinutes,
      deadline: clearDeadline ? null : deadline ?? this.deadline,
      tags: tags ?? this.tags,
      monthVisibility: monthVisibility ?? this.monthVisibility,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  /// 迁移旧 importance 到 priority。
  /// 如果已存储有效的 priority，保持不变；否则从旧 importance 推导。
  static String _migratePriority(Map<dynamic, dynamic> json) {
    final storedPriority = json['priority']?.toString() ?? '';
    if (storedPriority == 'A' ||
        storedPriority == 'B' ||
        storedPriority == 'C') {
      return storedPriority;
    }
    // 没有有效 priority，从旧 importance 推导
    final importance = json['importance']?.toString() ?? '';
    return switch (importance) {
      'important' => 'A',
      'minor' => 'C',
      _ => 'B',
    };
  }

  TodoLifecycle lifecycleAt(DateTime now) {
    if (isCompleted) return TodoLifecycle.completed;
    if (opensAt != null && now.isBefore(opensAt!)) {
      return TodoLifecycle.upcoming;
    }
    if (deadline != null && now.isAfter(deadline!)) {
      return TodoLifecycle.overdue;
    }
    return TodoLifecycle.active;
  }

  static int? _normalizeEstimatedMinutes(dynamic value) {
    final minutes = int.tryParse(value?.toString() ?? '');
    return minutes != null && minutes >= 5 && minutes <= 480 ? minutes : null;
  }
}

enum TodoLifecycle { upcoming, active, overdue, completed }
