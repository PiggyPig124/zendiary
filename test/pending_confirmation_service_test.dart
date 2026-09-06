import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:zendiary/core/database/db_service.dart';
import 'package:zendiary/models/ai_parsed_intent.dart';
import 'package:zendiary/models/diary_entry.dart';
import 'package:zendiary/services/pending_confirmation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zendiary-pending-');
    Hive.init(directory.path);
    await Hive.openBox(DBService.settingsBoxName);
  });

  tearDown(() async {
    await Hive.close();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test('pending reminder survives a reload and can be cleared', () async {
    final entry = DiaryEntry(
      id: 'event-1',
      content: '周五考试',
      timestamp: DateTime(2026, 9, 2),
      category: 'event',
      eventTime: DateTime(2026, 9, 4, 9),
    );
    const intent = AiParsedIntent(
      category: 'event',
      reminder: AiReminderCandidate(
        enabled: true,
        advanceMinutes: [30],
        requiresConfirmation: true,
      ),
    );

    await PendingConfirmationService.save(entry: entry, intent: intent);
    final restored = PendingConfirmationService.load();

    expect(restored?.entry.id, 'event-1');
    expect(restored?.entry.eventTime, DateTime(2026, 9, 4, 9));
    expect(restored?.intent.reminder.enabled, isTrue);
    expect(restored?.intent.reminder.advanceMinutes, [30]);

    PendingConfirmationService.clear();
    expect(PendingConfirmationService.load(), isNull);
  });

  test('pending reminder queue keeps captures independent', () async {
    const intent = AiParsedIntent(
      category: 'event',
      reminder: AiReminderCandidate(
        enabled: true,
        advanceMinutes: [10],
        requiresConfirmation: true,
      ),
    );
    final first = DiaryEntry(
      id: 'event-1',
      content: '周五考试',
      timestamp: DateTime(2026, 9, 2),
      category: 'event',
      eventTime: DateTime(2026, 9, 4, 9),
    );
    final second = DiaryEntry(
      id: 'event-2',
      content: '周六交作业',
      timestamp: DateTime(2026, 9, 2),
      category: 'event',
      eventTime: DateTime(2026, 9, 5, 18),
    );

    await PendingConfirmationService.save(entry: first, intent: intent);
    await PendingConfirmationService.save(entry: second, intent: intent);

    expect(PendingConfirmationService.loadAll().map((item) => item.entry.id), [
      'event-1',
      'event-2',
    ]);
    PendingConfirmationService.clear('event-1');
    expect(PendingConfirmationService.loadAll().map((item) => item.entry.id), [
      'event-2',
    ]);
  });
}
