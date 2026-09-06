import 'package:hive_flutter/hive_flutter.dart';

import '../core/database/db_service.dart';
import '../models/ai_parsed_intent.dart';
import '../models/diary_entry.dart';

class PendingReminderRecord {
  final DiaryEntry entry;
  final AiParsedIntent intent;

  const PendingReminderRecord({required this.entry, required this.intent});
}

/// Keeps reminder confirmations that are waiting for a user decision.
/// Pending confirmations are deliberately separate from the event itself:
/// closing the app does not lose the original capture or the user's choice.
class PendingConfirmationService {
  static const _key = 'pending_reminder_confirmation_v2';

  /// Loads all pending reminders. Older builds stored a single map; accepting
  /// that shape here makes the queue upgrade without losing the old card.
  static List<PendingReminderRecord> loadAll() {
    final raw = Hive.box(DBService.settingsBoxName).get(_key);
    if (raw is List) {
      return raw.map(_fromRaw).whereType<PendingReminderRecord>().toList();
    }
    final single = _fromRaw(raw);
    return single == null ? <PendingReminderRecord>[] : [single];
  }

  static PendingReminderRecord? load() {
    final pending = loadAll();
    return pending.isEmpty ? null : pending.first;
  }

  static Future<void> save({
    required DiaryEntry entry,
    required AiParsedIntent intent,
  }) async {
    final pending = loadAll();
    final record = PendingReminderRecord(entry: entry, intent: intent);
    final existingIndex = pending.indexWhere(
      (item) => item.entry.id == entry.id,
    );
    if (existingIndex == -1) {
      pending.add(record);
    } else {
      pending[existingIndex] = record;
    }
    await Hive.box(
      DBService.settingsBoxName,
    ).put(_key, pending.map(_toRaw).toList());
  }

  /// Clears one entry, or the whole queue when [entryId] is omitted.
  static void clear([String? entryId]) {
    final box = Hive.box(DBService.settingsBoxName);
    if (entryId == null) {
      box.delete(_key);
      return;
    }
    final remaining = loadAll()
        .where((item) => item.entry.id != entryId)
        .toList();
    if (remaining.isEmpty) {
      box.delete(_key);
    } else {
      box.put(_key, remaining.map(_toRaw).toList());
    }
  }

  static Future<void> clearAll() async {
    await Hive.box(DBService.settingsBoxName).delete(_key);
  }

  static Map<String, dynamic> _toRaw(PendingReminderRecord record) => {
    'entry': record.entry.toJson(),
    'intent': record.intent.toJson(),
  };

  static PendingReminderRecord? _fromRaw(dynamic raw) {
    if (raw is! Map) return null;
    final entryRaw = raw['entry'];
    final intentRaw = raw['intent'];
    if (entryRaw is! Map || intentRaw is! Map) return null;
    try {
      return PendingReminderRecord(
        entry: DiaryEntry.fromJson(entryRaw),
        intent: AiParsedIntent.fromJson(Map<String, dynamic>.from(intentRaw)),
      );
    } catch (_) {
      return null;
    }
  }
}
