import 'package:uuid/uuid.dart';

class NotebookEntry {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> tags;
  final String folder;
  final bool isArchived;

  NotebookEntry({
    String? id,
    this.title = '',
    this.content = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.tags = const [],
    this.folder = '全部笔记',
    this.isArchived = false,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  static DateTime? _tryParseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static List<String> _stringList(dynamic value) {
    final values = value is List
        ? value.map((e) => e.toString())
        : value is String
        ? value.split(RegExp(r'[\s,，、]+'))
        : const <String>[];
    return List<String>.from(
      values.map((e) => e.trim()).where((e) => e.isNotEmpty),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'tags': tags,
    'folder': folder,
    'isArchived': isArchived,
  };

  factory NotebookEntry.fromJson(Map<dynamic, dynamic> json) {
    return NotebookEntry(
      id: json['id']?.toString(),
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      createdAt: _tryParseDate(json['createdAt']),
      updatedAt: _tryParseDate(json['updatedAt']),
      tags: _stringList(json['tags']),
      folder: json['folder']?.toString() ?? '全部笔记',
      isArchived: json['isArchived'] == true,
    );
  }

  NotebookEntry copyWith({
    String? title,
    String? content,
    List<String>? tags,
    String? folder,
    bool? isArchived,
  }) {
    return NotebookEntry(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      tags: tags ?? this.tags,
      folder: folder ?? this.folder,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}
