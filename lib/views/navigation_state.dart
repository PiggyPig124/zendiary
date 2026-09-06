import 'package:flutter_riverpod/flutter_riverpod.dart';

const int navIndexToday = 0;
const int navIndexPlan = 1;
const int navIndexInbox = 2;
const int navIndexNotes = 3;
const int navIndexSettings = 4;

final navIndexProvider = NotifierProvider<NavIndexNotifier, int>(
  NavIndexNotifier.new,
);

/// A one-shot hand-off used when a result from global search or a unified
/// detail drawer should open a specific note in the Notes workspace.
///
/// The value is intentionally kept outside [NotebookView] so the request can
/// survive the navigation change on both desktop and mobile.
final selectedNoteIdProvider =
    NotifierProvider<SelectedNoteIdNotifier, String?>(
      SelectedNoteIdNotifier.new,
    );

class SelectedNoteIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String id) => state = id;

  void clear() => state = null;
}

class NavIndexNotifier extends Notifier<int> {
  @override
  int build() => navIndexToday;

  void setIndex(int index) =>
      state = index.clamp(navIndexToday, navIndexSettings).toInt();
}
