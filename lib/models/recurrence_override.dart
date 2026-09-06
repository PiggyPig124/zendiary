class RecurrenceOverride {
  /// 被覆盖的原始投影日期（年月日，忽略时分）。
  final DateTime originalDate;

  /// 覆盖后的内容，null = 不覆盖。
  final String? newContent;

  /// 覆盖后的时间（时+分），null = 不覆盖。
  final DateTime? newTime;

  /// 覆盖后的时长（分钟），null = 不覆盖。
  final int? newDurationMinutes;

  /// 明确清空来源事件时长。nullable 值本身无法区分“不覆盖”和“清空”。
  final bool clearDurationMinutes;

  /// 覆盖后的地点，null = 不覆盖。
  final String? newLocation;

  /// 明确清空来源事件地点。
  final bool clearLocation;

  /// 本次实例独立的完成状态。
  final bool isCompleted;

  /// 完成的时间戳。
  final DateTime? completedAt;

  /// 备注。
  final String? note;

  const RecurrenceOverride({
    required this.originalDate,
    this.newContent,
    this.newTime,
    this.newDurationMinutes,
    this.clearDurationMinutes = false,
    this.newLocation,
    this.clearLocation = false,
    this.isCompleted = false,
    this.completedAt,
    this.note,
  });

  static DateTime? _tryParseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  Map<String, dynamic> toJson() => {
    'originalDate': originalDate.toIso8601String().split('T').first,
    'newContent': newContent,
    'newTime': newTime?.toIso8601String(),
    'newDurationMinutes': newDurationMinutes,
    'clearDurationMinutes': clearDurationMinutes,
    'newLocation': newLocation,
    'clearLocation': clearLocation,
    'isCompleted': isCompleted,
    'completedAt': completedAt?.toIso8601String(),
    'note': note,
  };

  factory RecurrenceOverride.fromJson(Map<dynamic, dynamic> json) {
    final dateStr = json['originalDate']?.toString() ?? '';
    final originalDate = DateTime.tryParse(dateStr) ?? DateTime(1970);
    return RecurrenceOverride(
      originalDate: originalDate,
      newContent: json['newContent']?.toString(),
      newTime: _tryParseDate(json['newTime']),
      newDurationMinutes: _normalizeDuration(json['newDurationMinutes']),
      clearDurationMinutes: json['clearDurationMinutes'] == true,
      newLocation: json['newLocation']?.toString(),
      clearLocation: json['clearLocation'] == true,
      isCompleted: json['isCompleted'] == true,
      completedAt: _tryParseDate(json['completedAt']),
      note: json['note']?.toString(),
    );
  }

  RecurrenceOverride copyWith({
    DateTime? originalDate,
    String? newContent,
    bool clearNewContent = false,
    DateTime? newTime,
    bool clearNewTime = false,
    int? newDurationMinutes,
    bool clearNewDurationMinutes = false,
    bool? clearDurationMinutes,
    String? newLocation,
    bool clearNewLocation = false,
    bool? clearLocation,
    bool? isCompleted,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    String? note,
    bool clearNote = false,
  }) {
    return RecurrenceOverride(
      originalDate: originalDate ?? this.originalDate,
      newContent: clearNewContent ? null : newContent ?? this.newContent,
      newTime: clearNewTime ? null : newTime ?? this.newTime,
      newDurationMinutes: clearNewDurationMinutes
          ? null
          : newDurationMinutes ?? this.newDurationMinutes,
      clearDurationMinutes:
          clearDurationMinutes ?? this.clearDurationMinutes,
      newLocation: clearNewLocation ? null : newLocation ?? this.newLocation,
      clearLocation: clearLocation ?? this.clearLocation,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      note: clearNote ? null : note ?? this.note,
    );
  }

  static int? _normalizeDuration(dynamic value) {
    final minutes = int.tryParse(value?.toString() ?? '');
    return minutes != null && minutes > 0 && minutes <= 1440 ? minutes : null;
  }
}
