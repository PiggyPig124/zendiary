import 'package:hive_flutter/hive_flutter.dart';

import '../core/database/db_service.dart';
import '../models/pending_action_preview.dart';

/// Persists high-impact AI operation previews until the student explicitly
/// confirms or dismisses each one.
class PendingActionService {
  static const _key = 'pending_action_previews_v1';

  static List<PendingActionPreview> loadAll() {
    final raw = Hive.box(DBService.settingsBoxName).get(_key);
    if (raw is! List) return <PendingActionPreview>[];
    return raw
        .whereType<Map>()
        .map(PendingActionPreview.fromJson)
        .where((preview) => !preview.isEmpty)
        .toList();
  }

  static Future<void> save(PendingActionPreview preview) async {
    if (preview.isEmpty) return;
    final pending = loadAll();
    final existingIndex = pending.indexWhere(_samePreviewMatcher(preview));
    if (existingIndex == -1) {
      pending.add(preview);
    } else {
      pending[existingIndex] = preview;
    }
    await Hive.box(
      DBService.settingsBoxName,
    ).put(_key, pending.map((item) => item.toJson()).toList());
  }

  static void clear(PendingActionPreview preview) {
    final box = Hive.box(DBService.settingsBoxName);
    final remaining = loadAll().where((item) {
      return !_samePreviewMatcher(preview)(item);
    }).toList();
    if (remaining.isEmpty) {
      box.delete(_key);
    } else {
      box.put(_key, remaining.map((item) => item.toJson()).toList());
    }
  }

  static Future<void> clearAll() async {
    await Hive.box(DBService.settingsBoxName).delete(_key);
  }

  static bool Function(PendingActionPreview) _samePreviewMatcher(
    PendingActionPreview expected,
  ) {
    return (actual) =>
        actual.type == expected.type &&
        actual.createdAt == expected.createdAt &&
        actual.reason == expected.reason;
  }
}
