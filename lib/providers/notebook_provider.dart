import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/database/db_service.dart';
import '../models/notebook_entry.dart';

final notebookListProvider =
    NotifierProvider<NotebookListNotifier, List<NotebookEntry>>(
      NotebookListNotifier.new,
    );

class NotebookListNotifier extends Notifier<List<NotebookEntry>> {
  @override
  List<NotebookEntry> build() {
    final box = Hive.box(DBService.noteBoxName);
    final List<NotebookEntry> entries = [];
    for (var value in box.values) {
      if (value is Map) {
        entries.add(NotebookEntry.fromJson(value));
      }
    }
    // 按修改时间倒序排列
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries;
  }

  void addNote(NotebookEntry entry) {
    state = [entry, ...state];
    Hive.box(DBService.noteBoxName).put(entry.id, entry.toJson());
  }

  void updateNote(NotebookEntry entry) {
    final idx = state.indexWhere((e) => e.id == entry.id);
    if (idx == -1) return;
    state = [...state.sublist(0, idx), entry, ...state.sublist(idx + 1)]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    Hive.box(DBService.noteBoxName).put(entry.id, entry.toJson());
  }

  void archiveNote(String id, {bool archived = true}) {
    final note = state.cast<NotebookEntry?>().firstWhere(
      (item) => item?.id == id,
      orElse: () => null,
    );
    if (note == null) return;
    updateNote(note.copyWith(isArchived: archived));
  }

  void deleteNote(String id) {
    state = state.where((e) => e.id != id).toList();
    Hive.box(DBService.noteBoxName).delete(id);
  }
}
