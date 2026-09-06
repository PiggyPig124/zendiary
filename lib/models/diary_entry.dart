class DiaryEntry {
  final String id;
  final String content;
  final DateTime timestamp;
  final String category;
  final DateTime? eventTime;

  /// Optional duration in minutes. Null keeps a punctual event marker.
  final int? durationMinutes;
  final String? location;
  final String? aiSummary;
  final String? sentimentReply;
  final List<String> tags;
  final bool isCompleted;
  final bool isArchived;

  DiaryEntry({
    required this.id,
    required this.content,
    required this.timestamp,
    this.category = 'draft',
    this.eventTime,
    int? durationMinutes,
    this.location,
    this.aiSummary,
    this.sentimentReply,
    this.tags = const [],
    this.isCompleted = false,
    this.isArchived = false,
  }) : durationMinutes = _normalizeDuration(durationMinutes);

  DateTime get sortTime => eventTime ?? timestamp;
  bool get isTimelineVisible =>
      category == 'event' && eventTime != null && !isArchived;
  DateTime? get endTime =>
      eventTime == null ||
          durationMinutes == null ||
          durationMinutes! <= 0 ||
          durationMinutes! > 1440
      ? null
      : eventTime!.add(Duration(minutes: durationMinutes!));

  static String normalizeCategory(dynamic value) {
    final category = value?.toString() ?? 'draft';
    if (category == 'thought') return 'draft';
    if (category == 'draft' ||
        category == 'event' ||
        category == 'todo' ||
        category == 'note') {
      return category;
    }
    return 'draft';
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
    // Early exports represented tags as one whitespace/comma-delimited
    // string. Preserve those tags when a v1 backup is opened in v2.
    if (value is String) {
      return value
          .split(RegExp(r'[\s,，、]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'category': normalizeCategory(category),
    'eventTime': eventTime?.toIso8601String(),
    'durationMinutes': durationMinutes,
    'location': location,
    'aiSummary': aiSummary,
    'sentimentReply': sentimentReply,
    'tags': tags,
    'isCompleted': isCompleted,
    'isArchived': isArchived,
  };

  factory DiaryEntry.fromJson(Map<dynamic, dynamic> json) {
    final timestamp = _tryParseDate(json['timestamp']) ?? DateTime.now();
    return DiaryEntry(
      id: json['id']?.toString() ?? timestamp.microsecondsSinceEpoch.toString(),
      content: json['content']?.toString() ?? '',
      timestamp: timestamp,
      category: normalizeCategory(json['category']),
      eventTime: _tryParseDate(json['eventTime']),
      durationMinutes: _normalizeDuration(json['durationMinutes']),
      location: json['location']?.toString(),
      aiSummary: json['aiSummary']?.toString(),
      sentimentReply: json['sentimentReply']?.toString(),
      tags: _stringList(json['tags']),
      isCompleted: json['isCompleted'] == true,
      isArchived: json['isArchived'] == true,
    );
  }

  DiaryEntry copyWith({
    String? content,
    String? category,
    DateTime? eventTime,
    bool clearEventTime = false,
    int? durationMinutes,
    bool clearDurationMinutes = false,
    String? location,
    bool clearLocation = false,
    String? aiSummary,
    bool clearAiSummary = false,
    String? sentimentReply,
    bool clearSentimentReply = false,
    List<String>? tags,
    bool? isCompleted,
    bool? isArchived,
  }) {
    return DiaryEntry(
      id: id,
      content: content ?? this.content,
      timestamp: timestamp,
      category: category != null ? normalizeCategory(category) : this.category,
      eventTime: clearEventTime ? null : eventTime ?? this.eventTime,
      durationMinutes: clearDurationMinutes
          ? null
          : durationMinutes ?? this.durationMinutes,
      location: clearLocation ? null : location ?? this.location,
      aiSummary: clearAiSummary ? null : aiSummary ?? this.aiSummary,
      sentimentReply: clearSentimentReply
          ? null
          : sentimentReply ?? this.sentimentReply,
      tags: tags ?? this.tags,
      isCompleted: isCompleted ?? this.isCompleted,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  static int? _normalizeDuration(dynamic value) {
    final minutes = int.tryParse(value?.toString() ?? '');
    return minutes != null && minutes > 0 && minutes <= 1440 ? minutes : null;
  }
}
