import 'package:flutter_test/flutter_test.dart';
import 'package:zendiary/models/todo_task.dart';
import 'package:zendiary/models/reminder_rule.dart';
import 'package:zendiary/services/today_list_service.dart';
import 'package:zendiary/services/today_missed_service.dart';
import 'package:zendiary/services/ai_service.dart';
import 'package:zendiary/models/ai_parsed_intent.dart';

void main() {
  final now = DateTime(2026, 9, 5, 10);
  TodoTask task(
    String id, {
    TaskKind kind = TaskKind.ordinary,
    DateTime? attention,
    DateTime? opening,
    DateTime? due,
    String priority = 'B',
    DateTime? scheduled,
    int? estimatedMinutes,
  }) => TodoTask(
    id: id,
    title: id,
    createdAt: now,
    taskKind: kind,
    attentionDate: attention,
    opensAt: opening,
    deadline: due,
    priority: priority,
    scheduledAt: scheduled,
    estimatedMinutes: estimatedMinutes,
  );

  test(
    'quiz stays active from opening until completion, then becomes expired',
    () {
      final quiz = task(
        'quiz',
        kind: TaskKind.timed,
        opening: now,
        due: now.add(const Duration(days: 2)),
        scheduled: now.subtract(const Duration(days: 1)),
      );
      expect(
        TodayListService.build(
          todos: [quiz],
          now: now.subtract(const Duration(seconds: 1)),
        ).later,
        [quiz],
      );
      for (final time in [now, now.add(const Duration(days: 1))]) {
        expect(TodayListService.build(todos: [quiz], now: time).actionable, [
          quiz,
        ]);
      }
      expect(
        TodayListService.build(todos: [quiz], now: quiz.deadline!).expired,
        [quiz],
      );
      final done = quiz.copyWith(isCompleted: true);
      expect(TodayListService.build(todos: [done], now: now).completed, [done]);
    },
  );

  test('preparation requires an explicit confirmed attention date', () {
    final work = task(
      'report',
      kind: TaskKind.preparation,
      due: now.add(const Duration(days: 20)),
    );
    expect(work.validationMessage, '请选择开始关注日');
    expect(TodayListService.build(todos: [work], now: now).pending, [work]);
    final proposed = work.copyWith(
      attentionDate: now,
      attentionConfirmed: false,
    );
    expect(proposed.validationMessage, '请确认开始关注日');
    final confirmed = proposed.copyWith(attentionConfirmed: true);
    expect(TodayListService.build(todos: [confirmed], now: now).actionable, [
      confirmed,
    ]);
    expect(confirmed.estimatedMinutes, isNull);
    expect(confirmed.scheduledAt, isNull);
  });

  test(
    'attention begins on its calendar day and persists without rescheduling',
    () {
      final report = task(
        'report',
        kind: TaskKind.preparation,
        attention: now.add(const Duration(days: 1)),
      );
      expect(TodayListService.build(todos: [report], now: now).later, [report]);
      for (final day in [DateTime(2026, 9, 6), DateTime(2026, 10, 1)]) {
        expect(
          TodayListService.build(todos: [report, report], now: day).actionable,
          [report],
        );
        expect(report.scheduledAt, isNull);
      }
    },
  );

  test(
    'actual opening is a hard boundary regardless of attention and schedule',
    () {
      final locked = task(
        'locked',
        attention: now,
        scheduled: now,
        opening: now.add(const Duration(hours: 2)),
      );
      expect(TodayListService.build(todos: [locked], now: now).later, [locked]);
    },
  );

  test(
    'deadline order precedes manual priority and ties are deterministic',
    () {
      final early = task(
        'early',
        due: now.add(const Duration(hours: 1)),
        priority: 'C',
      );
      final late = task(
        'late',
        due: now.add(const Duration(days: 2)),
        priority: 'A',
      );
      final floating = task('floating', priority: 'A');
      final a = task('a');
      final b = task('b');
      expect(
        TodayListService.build(
          todos: [b, a, floating, late, early],
          now: now,
        ).actionable.map((t) => t.id),
        ['early', 'late', 'floating', 'a', 'b'],
      );
      expect(TodayListService.reason(early, now), contains('今天截止'));
      expect(early.priority, 'C');
    },
  );

  test('invalid ranges remain pending, not misleading actionable tasks', () {
    expect(task('quiz', kind: TaskKind.timed).validationMessage, isNotNull);
    expect(
      task(
        'quiz',
        kind: TaskKind.timed,
        opening: now,
        due: now,
      ).validationMessage,
      isNotNull,
    );
    expect(
      task(
        'report',
        kind: TaskKind.preparation,
        attention: now.add(const Duration(days: 2)),
        due: now,
      ).validationMessage,
      isNotNull,
    );
  });

  test('active quiz ignores a later attention date', () {
    final quiz = task(
      'quiz',
      kind: TaskKind.timed,
      opening: now,
      due: now.add(const Duration(days: 4)),
      attention: now.add(const Duration(days: 2)),
    );
    expect(TodayListService.build(todos: [quiz], now: now).actionable, [quiz]);
  });

  test('routine occurrence and skip rules govern today visibility', () {
    final todo = task('routine');
    final rule = ReminderRule(
      id: 'rule',
      title: 'routine',
      targetType: 'todo',
      targetId: todo.id,
      scheduleType: 'weekly',
      anchorTime: now,
      byDay: [now.weekday],
    );
    expect(
      TodayListService.build(todos: [todo], rules: [rule], now: now).actionable,
      [todo],
    );
    expect(
      TodayListService.build(
        todos: [todo],
        rules: [rule],
        now: now.add(const Duration(days: 1)),
      ).actionable,
      isEmpty,
    );
    final skipped = rule.copyWith(skipDates: [calendarDate(now)]);
    expect(
      TodayListService.build(
        todos: [todo],
        rules: [skipped],
        now: now,
      ).actionable,
      isEmpty,
    );
  });

  test(
    'missed uses the planned end, carries across dates, and keeps lifecycle filters',
    () {
      final endedAtBoundary = task(
        'ended-at-boundary',
        scheduled: now.subtract(const Duration(minutes: 30)),
      );
      final stillRunning = task(
        'still-running',
        scheduled: now.subtract(const Duration(minutes: 29)),
      );
      final overnight = task(
        'overnight',
        scheduled: now.subtract(const Duration(days: 1, hours: 2)),
        estimatedMinutes: 120,
        due: now.add(const Duration(days: 1)),
      );
      final futureOpening = task(
        'future-opening',
        scheduled: now.subtract(const Duration(hours: 2)),
        opening: now.add(const Duration(hours: 1)),
      );
      final futureAttention = task(
        'future-attention',
        kind: TaskKind.preparation,
        attention: now.add(const Duration(days: 1)),
        scheduled: now.subtract(const Duration(hours: 2)),
      );
      final completed = task(
        'completed',
        scheduled: now.subtract(const Duration(hours: 2)),
      ).copyWith(isCompleted: true);
      final archived = task(
        'archived',
        scheduled: now.subtract(const Duration(hours: 2)),
      ).copyWith(isArchived: true);
      final pending = task(
        'pending',
        kind: TaskKind.timed,
        scheduled: now.subtract(const Duration(hours: 2)),
      );
      final expired = task(
        'expired',
        scheduled: now.subtract(const Duration(hours: 2)),
        due: now,
      );

      final missed = TodayMissedService.build(
        todos: [
          endedAtBoundary,
          stillRunning,
          overnight,
          futureOpening,
          futureAttention,
          completed,
          archived,
          pending,
          expired,
        ],
        now: now,
      );

      expect(missed.map((todo) => todo.id), ['overnight', 'ended-at-boundary']);
      expect(TodayListService.build(todos: [expired], now: now).expired, [
        expired,
      ]);
    },
  );

  test(
    'legacy reading uses opening before schedule, and remains idempotent',
    () {
      final legacy =
          task(
              'old',
              opening: now,
              scheduled: now.add(const Duration(days: 3)),
            ).toJson()
            ..remove('taskKind')
            ..remove('attentionDate')
            ..remove('attentionConfirmed');
      final upgraded = TodoTask.fromJson(legacy);
      expect(upgraded.taskKind, TaskKind.ordinary);
      expect(upgraded.attentionDate, calendarDate(now));
      expect(upgraded.scheduledAt, now.add(const Duration(days: 3)));
      expect(TodoTask.fromJson(upgraded.toJson()).toJson(), upgraded.toJson());
      final modern = task(
        'modern',
        scheduled: now.add(const Duration(days: 5)),
      );
      expect(TodoTask.fromJson(modern.toJson()).attentionDate, isNull);
    },
  );

  test('date-only captures do not create a nine oclock execution block', () {
    final intent = AIService.parseLocalIntent('明天复习高数', now)!;
    expect(intent.attentionDate, DateTime(2026, 9, 6));
    expect(intent.scheduledAt, isNull);
  });

  test(
    'preparation captures keep missing date empty and preserve explicit dates',
    () {
      final missing = AIService.parseLocalIntent('大作业：课程论文', now)!;
      expect(missing.taskKind, TaskKind.preparation);
      expect(missing.attentionDate, isNull);
      final dated = AIService.parseLocalIntent(
        '大作业：课程论文，9月6日开始关注，9月26日截止',
        now,
      )!;
      expect(dated.attentionDate, DateTime(2026, 9, 6));
      expect(dated.todoDeadline, DateTime(2026, 9, 26, 23, 59));
      expect(dated.scheduledAt, isNull);
      final ai = AiParsedIntent.fromJson(dated.toJson());
      expect(ai.attentionDate, dated.attentionDate);
      expect(ai.taskKind, dated.taskKind);
    },
  );

  test('quiz captures keep actual opening and closing distinct', () {
    final intent = AIService.parseLocalIntent(
      'quiz，9月6日08:00开放，9月8日22:00截止',
      now,
    )!;
    expect(intent.taskKind, TaskKind.timed);
    expect(intent.todoOpensAt, DateTime(2026, 9, 6, 8));
    expect(intent.todoDeadline, DateTime(2026, 9, 8, 22));
    expect(intent.scheduledAt, isNull);
  });
}
