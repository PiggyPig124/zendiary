import 'package:flutter_test/flutter_test.dart';
import 'package:zendiary/models/diary_entry.dart';
import 'package:zendiary/models/ai_parsed_intent.dart';
import 'package:zendiary/models/todo_task.dart';
import 'package:zendiary/models/notebook_entry.dart';
import 'package:zendiary/services/planner_service.dart';
import 'package:zendiary/services/ai_service.dart';
import 'package:zendiary/services/data_migration_service.dart';
import 'package:zendiary/services/unified_item_service.dart';
import 'package:zendiary/services/recurrence_service.dart';
import 'package:zendiary/views/timeline/timeline_data.dart';
import 'package:zendiary/models/reminder_rule.dart';
import 'package:zendiary/models/recurrence_override.dart';
import 'package:zendiary/models/unified_item.dart';

void main() {
  group('planner service', () {
    test('note is a first-class capture category', () {
      expect(DiaryEntry.normalizeCategory('note'), 'note');
    });

    test('weekly plan keeps a deliberately scheduled low-priority todo', () {
      final weekStart = DateTime(2026, 9, 7);
      final lowPriority = TodoTask(
        id: 'scheduled-c-todo',
        title: '整理下载文件',
        createdAt: weekStart,
        priority: 'C',
        scheduledAt: weekStart.add(const Duration(days: 2, hours: 10)),
      );

      final summary = buildWeekTimelineSummary(
        weekStart: weekStart,
        events: const [],
        todos: [lowPriority],
        actionPriorityFilter: null,
        rules: const [],
      );

      expect(summary.todoCount, 1);
      expect(summary.days[2].actionTodos.single.title, '整理下载文件');
    });

    test('multiple captured todos keep an explicit time without stacking', () {
      final anchor = DateTime(2026, 9, 8, 19);
      expect(staggerCapturedTodoSchedule(anchor, 0), anchor);
      expect(
        staggerCapturedTodoSchedule(anchor, 1),
        DateTime(2026, 9, 8, 19, 30),
      );
      expect(
        staggerCapturedTodoSchedule(anchor, 2, spacingMinutes: 45),
        DateTime(2026, 9, 8, 20, 30),
      );
      expect(staggerCapturedTodoSchedule(null, 1), isNull);
    });

    test('event duration JSON is backward compatible', () {
      final event = DiaryEntry(
        id: 'event',
        content: '演示',
        timestamp: DateTime(2026, 9, 2),
        category: 'event',
        eventTime: DateTime(2026, 9, 2, 14),
        durationMinutes: 90,
      );
      expect(DiaryEntry.fromJson(event.toJson()).durationMinutes, 90);
      expect(
        DiaryEntry.fromJson(
          {...event.toJson()}..remove('durationMinutes'),
        ).durationMinutes,
        isNull,
      );
    });

    test('event duration can be explicitly cleared during editing', () {
      final event = DiaryEntry(
        id: 'clear-duration',
        content: '课程',
        timestamp: DateTime(2026, 9, 2),
        category: 'event',
        eventTime: DateTime(2026, 9, 2, 14),
        durationMinutes: 90,
      );

      final edited = event.copyWith(
        durationMinutes: null,
        clearDurationMinutes: true,
      );

      expect(edited.durationMinutes, isNull);
      expect(edited.endTime, isNull);
    });

    test(
      'todo estimate round-trips and missing estimates keep the 30-minute fallback',
      () {
        final todo = TodoTask(
          id: 'estimated-todo',
          title: '复习整章',
          createdAt: DateTime(2026, 9, 2),
          estimatedMinutes: 90,
        );
        expect(TodoTask.fromJson(todo.toJson()).estimatedMinutes, 90);
        expect(
          TodoTask.fromJson(
            {...todo.toJson()}..remove('estimatedMinutes'),
          ).estimatedMinutes,
          isNull,
        );
        expect(todoPlanningMinutes(todo), 90);
        expect(
          todoPlanningMinutes(
            TodoTask(id: 'legacy', title: '旧待办', createdAt: todo.createdAt),
          ),
          30,
        );
      },
    );

    test(
      'day load uses each todo estimate instead of counting every task as 30 minutes',
      () {
        final day = DateTime(2026, 9, 4, 8);
        final tasks = [
          TodoTask(
            id: 'short',
            title: '发邮件',
            createdAt: day,
            scheduledAt: DateTime(2026, 9, 4, 9),
            estimatedMinutes: 15,
          ),
          TodoTask(
            id: 'long',
            title: '复习整章',
            createdAt: day,
            scheduledAt: DateTime(2026, 9, 4, 10),
            estimatedMinutes: 90,
          ),
        ];
        expect(
          buildDayLoad(day: day, events: const [], todos: tasks).todoMinutes,
          105,
        );
      },
    );

    test(
      'legacy string lists keep imported tags and reminder schedule fields',
      () {
        final event = DiaryEntry.fromJson({
          'id': 'legacy-event',
          'content': 'CS2115 Lecture',
          'timestamp': '2026-09-01T12:00:00',
          'category': 'event',
          'eventTime': '2026-09-01T12:00:00',
          'tags': '课程 CS2115 Lecture',
        });
        expect(event.tags, ['课程', 'CS2115', 'Lecture']);

        final todo = TodoTask.fromJson({
          'id': 'legacy-todo',
          'title': '复习',
          'createdAt': '2026-09-01T12:00:00',
          'tags': '课程 离散数学',
        });
        expect(todo.tags, ['课程', '离散数学']);

        final rule = ReminderRule.fromJson({
          'id': 'legacy-rule',
          'title': '课程提醒',
          'targetType': 'event',
          'scheduleType': 'weekly',
          'anchorTime': '2026-09-01T12:00:00',
          'advanceMinutes': '30 5',
          'byDay': '1 3',
          'skipDates': '2026-10-19 2026-10-26',
        });
        expect(rule.advanceMinutes, [30, 5]);
        expect(rule.byDay, [1, 3]);
        expect(rule.skipDates, hasLength(2));
      },
    );

    test(
      'imports explicit clock ranges as event durations without guessing',
      () {
        expect(
          DataMigrationService.inferDurationMinutes(
            'CS2115 Lecture（周一 12:00–15:00）',
          ),
          180,
        );
        expect(
          DataMigrationService.inferDurationMinutes('没有结束时间的事件 12:00'),
          isNull,
        );
        expect(
          DataMigrationService.inferDurationMinutes('坏范围 15:00–12:00'),
          isNull,
        );
      },
    );

    test(
      'AI duration prefers valid end time and falls back from invalid end',
      () {
        final base = DiaryEntry(
          id: 'ai-event',
          content: '课',
          timestamp: DateTime(2026, 9, 2),
          category: 'draft',
        );
        final preferred = AIService.applyAIResult(base, {
          'category': 'event',
          'event_time': '2026-09-02T10:00:00',
          'event_end_time': '2026-09-02T11:30:00',
          'duration_minutes': 30,
        });
        expect(preferred.durationMinutes, 90);

        final fallback = AIService.applyAIResult(base, {
          'category': 'event',
          'event_time': '2026-09-02T10:00:00',
          'event_end_time': '2026-09-02T09:00:00',
          'duration_minutes': 45,
        });
        expect(fallback.durationMinutes, 45);
      },
    );

    test('student deadline phrases with a clock become todo deadlines', () {
      final normalized = AIService.normalizeStudentIntent(
        AiParsedIntent(
          category: 'event',
          eventTime: DateTime(2026, 9, 5, 17),
          aiSummary: '交报告',
        ),
        sourceText: '周五17:00前交报告',
      );

      expect(normalized.category, 'todo');
      expect(normalized.eventTime, isNull);
      expect(normalized.eventEndTime, isNull);
      expect(normalized.todoDeadline, DateTime(2026, 9, 5, 17));

      final written = AIService.normalizeStudentIntent(
        AiParsedIntent(
          category: 'event',
          eventTime: DateTime(2026, 9, 5, 17),
          aiSummary: '写完报告',
        ),
        sourceText: '周五17:00前写完报告',
      );
      expect(written.category, 'todo');
      expect(written.todoDeadline, DateTime(2026, 9, 5, 17));
    });

    test('ordinary timed events stay events during student normalization', () {
      final normalized = AIService.normalizeStudentIntent(
        AiParsedIntent(
          category: 'event',
          eventTime: DateTime(2026, 9, 5, 17),
          aiSummary: '参加社团活动',
        ),
        sourceText: '周五17:00参加社团活动',
      );

      expect(normalized.category, 'event');
      expect(normalized.eventTime, DateTime(2026, 9, 5, 17));
    });

    test(
      'date-only study wording becomes an attention date without an execution time',
      () {
        final now = DateTime(2026, 9, 4, 14);
        final normalized = AIService.normalizeStudentIntent(
          AiParsedIntent(
            category: 'todo',
            todos: const ['复习高数'],
            // Models trained on the older prompt sometimes put every date-only
            // phrase into todo_deadline. The capture normalizer should repair
            // that when the source has no due-date wording.
            todoDeadline: DateTime(2026, 9, 5, 23, 59),
          ),
          sourceText: '明天复习高数',
          now: now,
        );

        expect(normalized.category, 'todo');
        expect(normalized.attentionDate, DateTime(2026, 9, 5));
        expect(normalized.todoDeadline, isNull);
      },
    );

    test('date-only delivery wording remains a deadline', () {
      final normalized = AIService.normalizeStudentIntent(
        AiParsedIntent(
          category: 'todo',
          todos: const ['提交报告'],
          todoDeadline: DateTime(2026, 9, 5, 23, 59),
        ),
        sourceText: '明天前提交报告',
        now: DateTime(2026, 9, 4, 14),
      );

      expect(normalized.scheduledAt, isNull);
      expect(normalized.todoDeadline, DateTime(2026, 9, 5, 23, 59));
    });

    test('offline capture parser turns a date-only delivery into a todo', () {
      final intent = AIService.parseLocalIntent(
        '明天交报告',
        DateTime(2026, 9, 4, 8),
      );

      expect(intent?.category, 'todo');
      expect(intent?.todos, ['交报告']);
      expect(intent?.todoDeadline, DateTime(2026, 9, 5, 23, 59));
      expect(intent?.scheduledAt, isNull);
    });

    test(
      'offline capture parser turns an upcoming timed plan into an event',
      () {
        final intent = AIService.parseLocalIntent(
          '周三 19:00 复习高数',
          DateTime(2026, 9, 4, 8),
        );

        expect(intent?.category, 'event');
        expect(intent?.eventTime, DateTime(2026, 9, 9, 19));
        expect(intent?.aiSummary, '复习高数');
        expect(intent?.reminder.enabled, isFalse);
      },
    );

    test('offline capture parser understands 星期 and 礼拜 date phrases', () {
      final nextMonday = AIService.parseLocalIntent(
        '下星期一复习高数',
        DateTime(2026, 9, 4, 8),
      );
      expect(nextMonday?.category, 'todo');
      expect(nextMonday?.todos, ['复习高数']);
      expect(nextMonday?.attentionDate, DateTime(2026, 9, 7));

      final thisFriday = AIService.parseLocalIntent(
        '礼拜五整理课堂资料',
        DateTime(2026, 9, 2, 8),
      );
      expect(thisFriday?.todos, ['整理课堂资料']);
      expect(thisFriday?.attentionDate, DateTime(2026, 9, 4));

      final bareMonday = AIService.parseLocalIntent(
        '星期一复习错题',
        DateTime(2026, 9, 4, 8),
      );
      expect(bareMonday?.attentionDate, DateTime(2026, 9, 7));
    });

    test('offline capture parser rejects an impossible numeric date', () {
      expect(
        AIService.parseLocalIntent('13月40日复习高数', DateTime(2026, 9, 4, 8)),
        isNull,
      );
    });

    test(
      'offline capture parser asks before creating an explicit reminder',
      () {
        final intent = AIService.parseLocalIntent(
          '明天 8 点提醒我复习',
          DateTime(2026, 9, 4, 8),
        );

        expect(intent?.category, 'event');
        expect(intent?.eventTime, DateTime(2026, 9, 5, 8));
        expect(intent?.reminder.enabled, isTrue);
        expect(intent?.requiresReminderConfirmation, isTrue);
      },
    );

    test('offline capture parser understands Chinese numeral clock times', () {
      final morning = AIService.parseLocalIntent(
        '明天八点上课',
        DateTime(2026, 9, 4, 8),
      );
      expect(morning?.category, 'event');
      expect(morning?.eventTime, DateTime(2026, 9, 5, 8));
      expect(morning?.aiSummary, '上课');

      final evening = AIService.parseLocalIntent(
        '今晚五点半复习',
        DateTime(2026, 9, 4, 8),
      );
      expect(evening?.category, 'event');
      expect(evening?.eventTime, DateTime(2026, 9, 4, 17, 30));
      expect(evening?.aiSummary, '复习');
    });

    test('offline capture parser keeps an explicit event location', () {
      final intent = AIService.parseLocalIntent(
        '明天 15:00 在图书馆复习高数',
        DateTime(2026, 9, 4, 8),
      );

      expect(intent?.category, 'event');
      expect(intent?.location, '图书馆');
      expect(intent?.aiSummary, '复习高数');
    });

    test('offline capture parser preserves an explicit class time range', () {
      final intent = AIService.parseLocalIntent(
        '周一 12:00–15:00 CS2115 Lecture',
        DateTime(2026, 9, 4, 8),
      );

      expect(intent?.category, 'event');
      expect(intent?.eventTime, DateTime(2026, 9, 7, 12));
      expect(intent?.eventEndTime, DateTime(2026, 9, 7, 15));
      expect(intent?.durationMinutes, 180);
      expect(intent?.aiSummary, 'CS2115 Lecture');
    });

    test(
      'offline capture parser keeps mood prose as an unclassified draft',
      () {
        expect(
          AIService.parseLocalIntent('我今天很累', DateTime(2026, 9, 4, 8)),
          isNull,
        );
      },
    );

    test('offline capture parser keeps vague periods unscheduled', () {
      final tonight = AIService.parseLocalIntent(
        '今天晚上复习高数',
        DateTime(2026, 9, 4, 8),
      );
      expect(tonight?.category, 'todo');
      expect(tonight?.todos, ['复习高数']);
      expect(tonight?.scheduledAt, isNull);

      final later = AIService.parseLocalIntent(
        '一会儿倒垃圾',
        DateTime(2026, 9, 4, 8),
      );
      expect(later?.category, 'todo');
      expect(later?.todos, ['倒垃圾']);
      expect(later?.scheduledAt, isNull);
    });

    test(
      'offline capture parser preserves a reminder request without a clock',
      () {
        final intent = AIService.parseLocalIntent(
          '提醒我做实验报告',
          DateTime(2026, 9, 4, 8),
        );

        expect(intent?.category, 'todo');
        expect(intent?.todos, ['做实验报告']);
        expect(intent?.scheduledAt, isNull);
        expect(intent?.reminder.enabled, isTrue);
        expect(intent?.requiresReminderConfirmation, isTrue);
      },
    );

    test(
      'offline capture parser keeps explicit reminder timing out of title',
      () {
        final intent = AIService.parseLocalIntent(
          '8点提前15分钟提醒我上课',
          DateTime(2026, 9, 4, 8),
        );

        expect(intent, isNotNull);
        expect(intent!.category, 'event');
        expect(intent.aiSummary, '上课');
        expect(intent.reminder.enabled, isTrue);
        expect(intent.reminder.advanceMinutes, [15]);
      },
    );

    test(
      'offline capture parser turns recurring study phrases into a rule',
      () {
        final daily = AIService.parseLocalIntent(
          '每天做游戏日常',
          DateTime(2026, 9, 4, 8),
        );
        expect(daily?.category, 'todo');
        expect(daily?.todos, ['做游戏日常']);
        expect(daily?.scheduledAt, DateTime(2026, 9, 4, 9));
        expect(daily?.reminder.enabled, isTrue);
        expect(daily?.reminder.scheduleType, 'daily');
        expect(daily?.requiresReminderConfirmation, isTrue);

        final weekly = AIService.parseLocalIntent(
          '每周一三五复习高数',
          DateTime(2026, 9, 4, 8),
        );
        expect(weekly?.todos, ['复习高数']);
        expect(weekly?.reminder.scheduleType, 'weekly');
        expect(weekly?.reminder.byDay, [1, 3, 5]);

        final monthly = AIService.parseLocalIntent(
          '每月15号缴费',
          DateTime(2026, 9, 4, 8),
        );
        expect(monthly?.todos, ['缴费']);
        expect(monthly?.reminder.scheduleType, 'monthly');
        expect(monthly?.reminder.scheduleDay, 15);
      },
    );

    test(
      'offline capture parser handles an imprecise future date as backlog',
      () {
        final intent = AIService.parseLocalIntent(
          '下周准备考试',
          DateTime(2026, 9, 4, 8),
        );
        expect(intent?.category, 'todo');
        expect(intent?.todos, ['准备考试']);
        expect(intent?.scheduledAt, isNull);
        expect(intent?.todoDeadline, isNull);
      },
    );

    test('archived items round-trip and leave execution views', () {
      final event = DiaryEntry(
        id: 'archived-event',
        content: '旧课程',
        timestamp: DateTime(2026, 9, 2),
        category: 'event',
        eventTime: DateTime(2026, 9, 2, 14),
        durationMinutes: 60,
        isArchived: true,
      );
      final todo = TodoTask(
        id: 'archived-todo',
        title: '旧作业',
        createdAt: DateTime(2026, 9, 2),
        isArchived: true,
      );

      expect(DiaryEntry.fromJson(event.toJson()).isArchived, isTrue);
      expect(event.isTimelineVisible, isFalse);
      expect(unifiedEventItem(event).isArchived, isTrue);
      expect(TodoTask.fromJson(todo.toJson()).isArchived, isTrue);
      expect(unifiedTodoItem(todo, DateTime(2026, 9, 2)).isArchived, isTrue);
    });

    test(
      'AI reminder confirmation payload round-trips all scheduling fields',
      () {
        const original = AiParsedIntent(
          category: 'event',
          eventTime: null,
          importance: 'important',
          disturbanceLevel: 'strong',
          reminder: AiReminderCandidate(
            enabled: true,
            scheduleType: 'weekly',
            scheduleInterval: 1,
            advanceMinutes: [60, 15],
            requiresConfirmation: true,
            byDay: [1, 3],
          ),
          missingInfo: ['地点'],
        );
        final restored = AiParsedIntent.fromJson(original.toJson());

        expect(restored.category, 'event');
        expect(restored.importance, 'important');
        expect(restored.reminder.enabled, isTrue);
        expect(restored.reminder.scheduleType, 'weekly');
        expect(restored.reminder.advanceMinutes, [60, 15]);
        expect(restored.reminder.byDay, [1, 3]);
        expect(restored.missingInfo, ['地点']);
      },
    );

    test('snaps a time to the nearest quarter hour', () {
      expect(
        snapToQuarterHour(DateTime(2026, 9, 2, 10, 07)),
        DateTime(2026, 9, 2, 10, 00),
      );
      expect(
        snapToQuarterHour(DateTime(2026, 9, 2, 10, 53)),
        DateTime(2026, 9, 2, 11, 00),
      );
    });

    test('finds only overlapping events with duration', () {
      final first = DiaryEntry(
        id: 'a',
        content: 'A',
        timestamp: DateTime(2026, 9, 2),
        category: 'event',
        eventTime: DateTime(2026, 9, 2, 10),
        durationMinutes: 60,
      );
      final second = DiaryEntry(
        id: 'b',
        content: 'B',
        timestamp: DateTime(2026, 9, 2),
        category: 'event',
        eventTime: DateTime(2026, 9, 2, 10, 30),
        durationMinutes: 30,
      );
      final punctual = DiaryEntry(
        id: 'c',
        content: 'C',
        timestamp: DateTime(2026, 9, 2),
        category: 'event',
        eventTime: DateTime(2026, 9, 2, 11),
      );
      expect(findEventConflicts([first, second, punctual]), hasLength(1));
    });

    test('timeline keeps same-title events from different sources', () {
      final first = DiaryEntry(
        id: 'same-title-a',
        content: '课堂',
        timestamp: DateTime(2026, 9, 2),
        category: 'event',
        eventTime: DateTime(2026, 9, 2, 10),
        durationMinutes: 60,
      );
      final second = DiaryEntry(
        id: 'same-title-b',
        content: '课堂',
        timestamp: DateTime(2026, 9, 2),
        category: 'event',
        eventTime: DateTime(2026, 9, 2, 10),
        durationMinutes: 60,
      );

      final summary = buildTimelineDaySummary(
        day: DateTime(2026, 9, 2),
        events: [first, second],
        todos: const [],
        rules: const [],
      );

      expect(summary.events.map((event) => event.id), [
        'same-title-a',
        'same-title-b',
      ]);
      expect(findEventConflicts(summary.events), hasLength(1));
    });

    test('conflicts ignore archived and non-event entries', () {
      final archived = DiaryEntry(
        id: 'archived',
        content: '旧事件',
        timestamp: DateTime(2026, 9, 2),
        category: 'event',
        eventTime: DateTime(2026, 9, 2, 10),
        durationMinutes: 60,
        isArchived: true,
      );
      final note = DiaryEntry(
        id: 'note',
        content: '笔记',
        timestamp: DateTime(2026, 9, 2),
        category: 'note',
        eventTime: DateTime(2026, 9, 2, 10, 30),
        durationMinutes: 60,
      );

      expect(findEventConflicts([archived, note]), isEmpty);
    });

    test('suggests the opening day without mutating todo', () {
      final todo = TodoTask(
        id: 'report',
        title: '准备报告',
        createdAt: DateTime(2026, 9, 1),
        opensAt: DateTime(2026, 9, 13),
        deadline: DateTime(2026, 9, 19, 23, 59),
      );
      final suggestion = suggestTodoSchedule(todo, DateTime(2026, 9, 2));

      expect(suggestion?.scheduledAt, DateTime(2026, 9, 13, 9));
      expect(suggestion?.reason, '开放后开始');
      expect(todo.scheduledAt, isNull);
    });

    test('suggests the opening day when it is still in the future', () {
      final todo = TodoTask(
        id: 'coursework',
        title: '课程作业',
        createdAt: DateTime(2026, 9, 1),
        opensAt: DateTime(2026, 10, 1),
        deadline: DateTime(2026, 10, 25),
      );
      final suggestion = suggestTodoSchedule(todo, DateTime(2026, 9, 2));

      expect(suggestion?.scheduledAt, DateTime(2026, 10, 1, 9));
      expect(suggestion?.reason, '开放后开始');
    });

    test('today recommendations keep an undated backlog out of focus', () {
      final now = DateTime(2026, 9, 2, 14);
      expect(
        shouldRecommendTodoToday(
          TodoTask(id: 'normal', title: '整理资料', createdAt: now),
          now,
        ),
        isFalse,
      );
      expect(
        shouldRecommendTodoToday(
          TodoTask(
            id: 'important',
            title: '准备考试',
            createdAt: now,
            priority: 'A',
          ),
          now,
        ),
        isTrue,
      );
    });

    test('today recommendations follow deadline urgency and opening date', () {
      final now = DateTime(2026, 9, 2, 14);
      expect(
        shouldRecommendTodoToday(
          TodoTask(
            id: 'soon',
            title: '周四交作业',
            createdAt: now,
            deadline: DateTime(2026, 9, 4, 23, 59),
          ),
          now,
        ),
        isTrue,
      );
      expect(
        shouldRecommendTodoToday(
          TodoTask(
            id: 'later',
            title: '月底报告',
            createdAt: now,
            deadline: DateTime(2026, 9, 30, 23, 59),
          ),
          now,
        ),
        isFalse,
      );
      expect(
        shouldRecommendTodoToday(
          TodoTask(
            id: 'locked',
            title: '尚未开放的题目',
            createdAt: now,
            opensAt: DateTime(2026, 9, 3, 9),
            deadline: DateTime(2026, 9, 4, 23, 59),
          ),
          now,
        ),
        isFalse,
      );
    });

    test('late planning only promotes tasks with an immediate reason', () {
      final now = DateTime(2026, 9, 2, 21);
      expect(
        isMustPlanToday(
          TodoTask(
            id: 'tomorrow',
            title: '明天截止',
            createdAt: now,
            deadline: DateTime(2026, 9, 3, 23, 59),
          ),
          now,
        ),
        isTrue,
      );
      expect(
        isMustPlanToday(
          TodoTask(
            id: 'important-backlog',
            title: '重要但没有截止日期',
            createdAt: now,
            priority: 'A',
          ),
          now,
        ),
        isFalse,
      );
      expect(
        isMustPlanToday(
          TodoTask(
            id: 'later',
            title: '下周截止',
            createdAt: now,
            deadline: DateTime(2026, 9, 8, 23, 59),
          ),
          now,
        ),
        isFalse,
      );
    });

    test('today planning prompt names the right planning moment', () {
      expect(
        todayPlanningMoment(DateTime(2026, 9, 2, 9)),
        TodayPlanningMoment.startOfDay,
      );
      expect(
        todayPlanningMoment(DateTime(2026, 9, 2, 15)),
        TodayPlanningMoment.betweenPlans,
      );
      expect(
        todayPlanningMoment(DateTime(2026, 9, 2, 21)),
        TodayPlanningMoment.evening,
      );
      expect(todayPlanningActionLabel(DateTime(2026, 9, 2, 9)), '安排下一项');
      expect(
        todayPlanningMessage(DateTime(2026, 9, 2, 21), candidateCount: 2),
        contains('必须今天'),
      );
      expect(
        todayPlanningMessage(DateTime(2026, 9, 2, 15), candidateCount: 0),
        contains('需要时再手动安排'),
      );
    });

    test('today planning batch limit follows the time of day', () {
      expect(todayPlanningBatchLimit(DateTime(2026, 9, 2, 9)), 1);
      expect(todayPlanningBatchLimit(DateTime(2026, 9, 2, 15)), 1);
      expect(todayPlanningBatchLimit(DateTime(2026, 9, 2, 21)), 1);
      expect(
        todayPlanningMessage(DateTime(2026, 9, 2, 15), candidateCount: 2),
        contains('下一项'),
      );
    });

    test('scheduled work warns when its estimate misses the deadline', () {
      final todo = TodoTask(
        id: 'late-plan',
        title: '赶在截止前完成',
        createdAt: DateTime(2026, 9, 2),
        scheduledAt: DateTime(2026, 9, 2, 15),
        estimatedMinutes: 90,
        deadline: DateTime(2026, 9, 2, 16),
      );
      expect(todoScheduleDeadlineWarning(todo), '预计完成会晚于截止');
      expect(
        todoScheduleDeadlineWarning(todo.copyWith(estimatedMinutes: 60)),
        isNull,
      );
      expect(
        todoScheduleDeadlineWarning(
          todo.copyWith(scheduledAt: DateTime(2026, 9, 2, 17)),
        ),
        '计划晚于截止',
      );
    });

    test('day load counts only placed work and clips overnight events', () {
      final day = DateTime(2026, 9, 2);
      final overnight = DiaryEntry(
        id: 'overnight-load',
        content: '夜间自习',
        timestamp: day,
        category: 'event',
        eventTime: DateTime(2026, 9, 1, 23, 30),
        durationMinutes: 120,
      );
      final placed = TodoTask(
        id: 'placed-load',
        title: '复习',
        createdAt: day,
        scheduledAt: DateTime(2026, 9, 2, 10),
      );
      final floating = TodoTask(
        id: 'floating-load',
        title: '以后再做',
        createdAt: day,
      );
      final load = buildDayLoad(
        day: day,
        events: [overnight],
        todos: [placed, floating],
      );

      expect(load.eventMinutes, 90);
      expect(load.todoMinutes, 30);
      expect(load.totalMinutes, 120);
      expect(load.level, DayLoadLevel.light);
      expect(load.label, '2 小时');
    });

    test('day load can exclude routine tasks from execution pressure', () {
      final day = DateTime(2026, 9, 2);
      final routine = TodoTask(
        id: 'routine-load',
        title: '每日背单词',
        createdAt: day,
        scheduledAt: DateTime(2026, 9, 2, 8),
      );
      final focused = TodoTask(
        id: 'focused-load',
        title: '完成实验报告',
        createdAt: day,
        scheduledAt: DateTime(2026, 9, 2, 10),
      );

      final load = buildDayLoad(
        day: day,
        events: const [],
        todos: [routine, focused],
        excludedTodoIds: {'routine-load'},
      );

      expect(load.todoMinutes, 30);
      expect(load.totalMinutes, 30);
    });

    test('安排今天 uses the next future quarter-hour', () {
      final now = DateTime(2026, 9, 2, 14, 10);
      expect(suggestedTodoScheduleTime(now), DateTime(2026, 9, 2, 14, 30));
      expect(
        suggestTodoSchedule(
          TodoTask(id: 'today', title: '复习', createdAt: now),
          now,
        )?.scheduledAt,
        DateTime(2026, 9, 2, 14, 30),
      );
    });

    test('安排今天 before the study day starts stays at 09:00', () {
      expect(
        suggestedTodoScheduleTime(DateTime(2026, 9, 2, 8, 20)),
        DateTime(2026, 9, 2, 9),
      );
    });

    test('安排今天 respects a task opening later today', () {
      final now = DateTime(2026, 9, 2, 14, 10);
      expect(
        suggestedTodoScheduleTime(now, notBefore: DateTime(2026, 9, 2, 18, 5)),
        DateTime(2026, 9, 2, 18, 5),
      );
    });

    test('next free slot never schedules before a future opening day', () {
      final now = DateTime(2026, 9, 2, 14, 10);
      final todo = TodoTask(
        id: 'locked-slot',
        title: '开放后才能做的作业',
        createdAt: now,
        opensAt: DateTime(2026, 9, 5, 10, 30),
      );

      expect(suggestTodoScheduleSlot(todo, now), DateTime(2026, 9, 5, 10, 30));
    });

    test('安排今天 chooses the next free slot around timed events', () {
      final now = DateTime(2026, 9, 2, 14, 10);
      final event = DiaryEntry(
        id: 'class',
        content: '上课',
        timestamp: now,
        category: 'event',
        eventTime: DateTime(2026, 9, 2, 14, 30),
        durationMinutes: 60,
      );
      final todo = TodoTask(
        id: 'todo',
        title: '复习',
        createdAt: now,
        deadline: DateTime(2026, 9, 2, 18),
      );

      expect(
        suggestTodoScheduleSlot(todo, now, events: [event]),
        DateTime(2026, 9, 2, 15, 30),
      );
    });

    test('安排今天 skips an existing scheduled todo block', () {
      final now = DateTime(2026, 9, 2, 14, 10);
      final existing = TodoTask(
        id: 'existing',
        title: '已经安排的任务',
        createdAt: now,
        scheduledAt: DateTime(2026, 9, 2, 14, 30),
      );
      final todo = TodoTask(id: 'todo', title: '复习', createdAt: now);

      expect(
        suggestTodoScheduleSlot(todo, now, scheduledTodos: [existing]),
        DateTime(2026, 9, 2, 15),
      );
    });

    test(
      'batch planning uses estimates instead of a fixed 30-minute offset',
      () {
        final now = DateTime(2026, 9, 2, 8);
        final day = DateTime(2026, 9, 5);
        final first = TodoTask(
          id: 'batch-first',
          title: '写报告',
          createdAt: now,
          estimatedMinutes: 90,
        );
        final second = TodoTask(
          id: 'batch-second',
          title: '复习',
          createdAt: now,
          estimatedMinutes: 60,
        );

        final slots = suggestTodoBatchSlots([first, second], day, now);

        expect(slots['batch-first'], DateTime(2026, 9, 5, 9));
        expect(slots['batch-second'], DateTime(2026, 9, 5, 10, 30));
      },
    );

    test(
      'batch planning skips a class and respects each task opening time',
      () {
        final now = DateTime(2026, 9, 2, 8);
        final day = DateTime(2026, 9, 5);
        final classEvent = DiaryEntry(
          id: 'batch-class',
          content: '课程',
          timestamp: now,
          category: 'event',
          eventTime: DateTime(2026, 9, 5, 9),
          durationMinutes: 90,
        );
        final first = TodoTask(
          id: 'batch-open',
          title: '开放后写报告',
          createdAt: now,
          opensAt: DateTime(2026, 9, 5, 11),
          estimatedMinutes: 60,
        );
        final second = TodoTask(
          id: 'batch-after',
          title: '整理资料',
          createdAt: now,
          estimatedMinutes: 30,
        );

        final slots = suggestTodoBatchSlots(
          [first, second],
          day,
          now,
          events: [classEvent],
        );

        expect(slots['batch-open'], DateTime(2026, 9, 5, 11));
        expect(slots['batch-after'], DateTime(2026, 9, 5, 12));
      },
    );

    test('punctual events do not block the suggested todo slot', () {
      final now = DateTime(2026, 9, 2, 14, 10);
      final event = DiaryEntry(
        id: 'marker',
        content: '签到',
        timestamp: now,
        category: 'event',
        eventTime: DateTime(2026, 9, 2, 14, 30),
      );
      final todo = TodoTask(id: 'todo', title: '复习', createdAt: now);

      expect(
        suggestTodoScheduleSlot(todo, now, events: [event]),
        DateTime(2026, 9, 2, 14, 30),
      );
    });

    test('todo availability follows its opening time', () {
      final todo = TodoTask(
        id: 'opens-later',
        title: '晚间作业',
        createdAt: DateTime(2026, 9, 2),
        opensAt: DateTime(2026, 9, 2, 18),
      );
      expect(isTodoOpenAt(todo, DateTime(2026, 9, 2, 17, 59)), isFalse);
      expect(isTodoOpenAt(todo, DateTime(2026, 9, 2, 18)), isTrue);
    });

    test('manual planning never places a todo before its opening time', () {
      final todo = TodoTask(
        id: 'opens-tomorrow',
        title: '明天开放的作业',
        createdAt: DateTime(2026, 9, 2),
        opensAt: DateTime(2026, 9, 3, 10),
        deadline: DateTime(2026, 9, 5, 23, 59),
      );
      expect(
        respectTodoOpening(todo, DateTime(2026, 9, 2, 16)),
        DateTime(2026, 9, 3, 10),
      );
      expect(
        respectTodoOpening(todo, DateTime(2026, 9, 3, 11)),
        DateTime(2026, 9, 3, 11),
      );
    });

    test('安排今天 late at night never rolls into tomorrow', () {
      final now = DateTime(2026, 9, 2, 23, 55);
      final value = suggestedTodoScheduleTime(now);
      expect(value.year, now.year);
      expect(value.month, now.month);
      expect(value.day, now.day);
      expect(value.isAfter(now), isTrue);
    });

    test(
      'slot availability reports deadline and calendar pressure honestly',
      () {
        final now = DateTime(2026, 9, 2, 14);
        final todo = TodoTask(
          id: 'tight-deadline',
          title: '提交作业',
          createdAt: now,
          deadline: DateTime(2026, 9, 2, 14, 20),
        );
        expect(
          isTodoScheduleSlotAvailable(todo, now, DateTime(2026, 9, 2, 14)),
          isFalse,
        );

        final openTodo = TodoTask(id: 'open-slot', title: '复习', createdAt: now);
        final classEvent = DiaryEntry(
          id: 'slot-class',
          content: '上课',
          timestamp: now,
          category: 'event',
          eventTime: DateTime(2026, 9, 2, 15),
          durationMinutes: 60,
        );
        expect(
          isTodoScheduleSlotAvailable(
            openTodo,
            now,
            DateTime(2026, 9, 2, 15),
            events: [classEvent],
          ),
          isFalse,
        );
        expect(
          isTodoScheduleSlotAvailable(
            openTodo,
            now,
            DateTime(2026, 9, 2, 16),
            events: [classEvent],
          ),
          isTrue,
        );
      },
    );

    test('treats invalid and touching durations as non-conflicting', () {
      final invalid = DiaryEntry(
        id: 'invalid',
        content: 'invalid',
        timestamp: DateTime(2026, 9, 2),
        category: 'event',
        eventTime: DateTime(2026, 9, 2, 8),
        durationMinutes: 2000,
      );
      final first = DiaryEntry(
        id: 'first',
        content: 'first',
        timestamp: DateTime(2026, 9, 2),
        category: 'event',
        eventTime: DateTime(2026, 9, 2, 10),
        durationMinutes: 30,
      );
      final touching = DiaryEntry(
        id: 'touching',
        content: 'touching',
        timestamp: DateTime(2026, 9, 2),
        category: 'event',
        eventTime: DateTime(2026, 9, 2, 10, 30),
        durationMinutes: 30,
      );
      expect(invalid.endTime, isNull);
      expect(findEventConflicts([invalid, first, touching]), isEmpty);
    });

    test('detects overlaps that cross midnight', () {
      final late = DiaryEntry(
        id: 'late',
        content: '晚间',
        timestamp: DateTime(2026, 9, 2),
        category: 'event',
        eventTime: DateTime(2026, 9, 2, 23, 30),
        durationMinutes: 120,
      );
      final early = DiaryEntry(
        id: 'early',
        content: '凌晨',
        timestamp: DateTime(2026, 9, 3),
        category: 'event',
        eventTime: DateTime(2026, 9, 3, 0, 30),
        durationMinutes: 30,
      );
      expect(findEventConflicts([late, early]), hasLength(1));
    });

    test('period filter keeps an event that began before the visible day', () {
      final overnight = DiaryEntry(
        id: 'overnight',
        content: '夜间自习',
        timestamp: DateTime(2026, 9, 2),
        category: 'event',
        eventTime: DateTime(2026, 9, 2, 23, 30),
        durationMinutes: 120,
      );
      final nextDayStart = DateTime(2026, 9, 3);
      final nextDayEnd = nextDayStart.add(const Duration(days: 1));

      expect(
        eventsOverlappingPeriod([overnight], nextDayStart, nextDayEnd),
        contains(overnight),
      );
    });
  });

  test('unified items keep a todo schedule separate from its deadline', () {
    final scheduled = DateTime(2026, 9, 3, 9);
    final due = DateTime(2026, 9, 5, 23, 59);
    final todo = TodoTask(
      id: 'todo',
      title: '准备报告',
      createdAt: DateTime(2026, 9, 1),
      scheduledAt: scheduled,
      deadline: due,
    );
    final items = buildUnifiedItems(
      entries: const [],
      todos: [todo],
      rules: const <ReminderRule>[],
    );
    expect(items.single.source, UnifiedItemSource.todo);
    expect(items.single.scheduledAt, scheduled);
    expect(items.single.deadline, due);
  });

  test('unified event prefers the concise AI summary over capture prose', () {
    final event = DiaryEntry(
      id: 'summary-event',
      content: '记得明天下午三点到图书馆参加学习小组，别迟到',
      timestamp: DateTime(2026, 9, 3, 8),
      category: 'event',
      eventTime: DateTime(2026, 9, 4, 15),
      aiSummary: '学习小组 · 图书馆',
    );

    expect(unifiedEventItem(event).title, '学习小组 · 图书馆');
  });

  test(
    'imported timetable event keeps its course title instead of schedule summary',
    () {
      final event = DiaryEntry(
        id: 'aims-course',
        content: '[CS2115-C01] Computer Organization · Lecture',
        timestamp: DateTime(2026, 9, 6),
        category: 'event',
        eventTime: DateTime(2026, 9, 7, 12),
        location: 'BOC R4057',
        aiSummary: '每周一 12:00–14:50',
        tags: const ['CS2115', 'AIMS', 'Lecture'],
      );

      final item = unifiedEventItem(event);
      expect(item.title, '[CS2115-C01] Computer Organization · Lecture');
      expect(item.location, 'BOC R4057');
    },
  );

  test('unified todo can display a specific recurring occurrence', () {
    final sourceSchedule = DateTime(2026, 9, 3, 9);
    final occurrence = DateTime(2026, 9, 4, 9);
    final todo = TodoTask(
      id: 'daily-review',
      title: '背单词',
      createdAt: DateTime(2026, 9, 1),
      scheduledAt: sourceSchedule,
      deadline: DateTime(2026, 9, 30, 23, 59),
    );

    final item = unifiedTodoItem(
      todo,
      DateTime(2026, 9, 3, 8),
      scheduledAtOverride: occurrence,
    );

    expect(item.scheduledAt, occurrence);
    expect(item.deadline, todo.deadline);
  });

  test('unified aggregation deduplicates source IDs before sorting', () {
    final later = DiaryEntry(
      id: 'later-event',
      content: '稍后事件',
      timestamp: DateTime(2026, 9, 1),
      category: 'event',
      eventTime: DateTime(2026, 9, 5, 9),
    );
    final duplicate = DiaryEntry(
      id: 'same-event',
      content: '同一事件（导入副本）',
      timestamp: DateTime(2026, 9, 1),
      category: 'event',
      eventTime: DateTime(2026, 9, 4, 15),
    );
    final original = duplicate.copyWith(content: '同一事件（重复行）');

    final items = buildUnifiedItems(
      entries: [later, duplicate, original],
      todos: const [],
      rules: const <ReminderRule>[],
    );

    expect(items.map((item) => item.id), ['same-event', 'later-event']);
    expect(items.first.title, '同一事件（导入副本）');
  });

  test('unified aggregation deduplicates a diary note and notebook copy', () {
    final capturedAt = DateTime(2026, 9, 2, 8);
    final diaryNote = DiaryEntry(
      id: 'shared-note',
      content: '从随手捕捉整理出的复习笔记',
      timestamp: capturedAt,
      category: 'note',
    );
    final notebookCopy = NotebookEntry(
      id: diaryNote.id,
      title: '复习笔记',
      content: diaryNote.content,
      createdAt: capturedAt,
      updatedAt: capturedAt,
    );

    final items = buildUnifiedItems(
      entries: [diaryNote],
      todos: const [],
      rules: const <ReminderRule>[],
      notes: [notebookCopy],
    );

    expect(items, hasLength(1));
    expect(items.single.source, UnifiedItemSource.note);
    expect(items.single.id, diaryNote.id);
  });

  test('unified aggregation keeps separate reminders with a shared target', () {
    final first = ReminderRule(
      id: 'standalone-reminder-a',
      title: '喝水',
      targetType: 'standalone',
      targetId: 'shared-label',
      anchorTime: DateTime(2026, 9, 4, 10),
    );
    final second = ReminderRule(
      id: 'standalone-reminder-b',
      title: '拉伸',
      targetType: 'standalone',
      targetId: 'shared-label',
      anchorTime: DateTime(2026, 9, 4, 16),
    );

    final items = buildUnifiedItems(
      entries: const [],
      todos: const [],
      rules: [first, second],
    );

    expect(items.map((item) => item.id), [first.id, second.id]);
  });

  test(
    'standalone reminders project into Today without duplicating the rule',
    () {
      final reminder = ReminderRule(
        id: 'daily-water-reminder',
        title: '喝水',
        scheduleType: 'daily',
        anchorTime: DateTime(2026, 9, 1, 10),
        skipDates: [DateTime(2026, 9, 4)],
      );

      final skipped = buildStandaloneReminderItemsForDay(
        rules: [reminder],
        day: DateTime(2026, 9, 4),
      );
      expect(skipped, isEmpty);

      final nextDay = buildStandaloneReminderItemsForDay(
        rules: [reminder],
        day: DateTime(2026, 9, 5),
      );
      expect(nextDay, hasLength(1));
      expect(nextDay.single.source, UnifiedItemSource.reminder);
      expect(nextDay.single.sourceId, reminder.id);
      expect(nextDay.single.id, contains(reminder.id));
      expect(nextDay.single.startAt, DateTime(2026, 9, 5, 10));
    },
  );

  test(
    'unified aggregation keeps archived drafts and notes in their source type',
    () {
      final archivedDraft = DiaryEntry(
        id: 'archived-draft',
        content: '归档随笔',
        timestamp: DateTime(2026, 9, 2, 8),
        category: 'draft',
        isArchived: true,
      );
      final archivedNote = DiaryEntry(
        id: 'archived-note',
        content: '归档笔记',
        timestamp: DateTime(2026, 9, 2, 9),
        category: 'note',
        isArchived: true,
      );

      final items = buildUnifiedItems(
        entries: [archivedDraft, archivedNote],
        todos: const [],
        rules: const <ReminderRule>[],
      );

      expect(items.map((item) => item.source).toSet(), {
        UnifiedItemSource.draft,
        UnifiedItemSource.note,
      });
      expect(items.map((item) => item.id).toSet(), {
        'archived-draft',
        'archived-note',
      });
    },
  );

  test('recent captures map AI todo sources to actionable todo ids', () {
    final source = DiaryEntry(
      id: 'capture',
      content: '周五交报告',
      timestamp: DateTime(2026, 9, 2),
      category: 'todo',
    );
    final todo = TodoTask(
      id: 'real-todo',
      title: '交报告',
      createdAt: DateTime(2026, 9, 2),
      sourceEntryId: source.id,
      deadline: DateTime(2026, 9, 5, 23, 59),
    );

    final items = buildRecentCaptureItems(
      entries: [source],
      todos: [todo],
      now: DateTime(2026, 9, 2),
    );

    expect(items.single.source, UnifiedItemSource.todo);
    expect(items.single.id, todo.id);
  });

  test('recent captures include promoted notes and sort by capture time', () {
    final oldDraft = DiaryEntry(
      id: 'old-draft',
      content: '旧想法',
      timestamp: DateTime(2026, 9, 1, 8),
      category: 'draft',
    );
    final recentDraft = DiaryEntry(
      id: 'recent-draft',
      content: '刚刚想到的事',
      timestamp: DateTime(2026, 9, 3, 9),
      category: 'draft',
    );
    final promotedNote = NotebookEntry(
      id: 'promoted-note',
      title: '复习提纲',
      content: '整理离散数学复习提纲',
      createdAt: DateTime(2026, 9, 3, 10),
      updatedAt: DateTime(2026, 9, 3, 10),
    );

    final items = buildRecentCaptureItems(
      entries: [oldDraft, recentDraft],
      todos: const [],
      notes: [promotedNote],
      now: DateTime(2026, 9, 3, 10),
    );

    expect(items.map((item) => item.id), [
      'promoted-note',
      'recent-draft',
      'old-draft',
    ]);
    expect(items.first.source, UnifiedItemSource.note);
  });

  test('missed scheduled work remains visible on today until rescheduled', () {
    // Keep this scenario relative to the real calendar day; the behavior is
    // specifically about resurfacing a task on *today*, not on a fixed date.
    final clock = DateTime.now();
    final now = DateTime(clock.year, clock.month, clock.day, 10);
    final missed = TodoTask(
      id: 'missed-plan',
      title: '补完实验报告',
      createdAt: now.subtract(const Duration(days: 2)),
      scheduledAt: now.subtract(const Duration(days: 1, hours: 2)),
      deadline: now.add(const Duration(days: 2, hours: 13, minutes: 59)),
    );

    final summary = buildTimelineDaySummary(
      day: now,
      events: const [],
      todos: [missed],
      floatingTodoPolicy: TimelineFloatingTodoPolicy.exclude,
      rules: const [],
    );

    expect(summary.actionTodos.map((todo) => todo.id), ['missed-plan']);
    expect(summary.deadlineTodos, isEmpty);
    expect(shouldSurfaceMissedScheduledTodo(missed, now), isTrue);
  });

  test('a same-day plan that already passed is surfaced as missed', () {
    final now = DateTime(2026, 9, 2, 14);
    final todo = TodoTask(
      id: 'missed-this-morning',
      title: '上午计划的复习',
      createdAt: now.subtract(const Duration(hours: 3)),
      scheduledAt: DateTime(2026, 9, 2, 10),
      deadline: DateTime(2026, 9, 4, 23, 59),
    );
    expect(shouldSurfaceMissedScheduledTodo(todo, now), isTrue);
    expect(
      shouldSurfaceMissedScheduledTodo(
        todo.copyWith(scheduledAt: DateTime(2026, 9, 2, 15)),
        now,
      ),
      isFalse,
    );
  });

  test('missed plan due today stays in the deadline lane only', () {
    final now = DateTime(2026, 9, 3, 10);
    final missed = TodoTask(
      id: 'missed-deadline',
      title: '今天交实验报告',
      createdAt: DateTime(2026, 9, 1),
      scheduledAt: DateTime(2026, 9, 2, 14),
      deadline: DateTime(2026, 9, 3, 23, 59),
    );

    final summary = buildTimelineDaySummary(
      day: now,
      events: const [],
      todos: [missed],
      floatingTodoPolicy: TimelineFloatingTodoPolicy.exclude,
      rules: const [],
    );

    expect(summary.deadlineTodos.map((todo) => todo.id), ['missed-deadline']);
    expect(summary.actionTodos, isEmpty);
    expect(shouldSurfaceMissedScheduledTodo(missed, now), isFalse);
  });

  test(
    'recurrence override duration round-trips and rejects invalid values',
    () {
      final override = RecurrenceOverride(
        originalDate: DateTime(2026, 9, 2),
        newDurationMinutes: 45,
      );
      final restored = RecurrenceOverride.fromJson(override.toJson());
      expect(restored.newDurationMinutes, 45);
      final cleared = RecurrenceOverride.fromJson(
        RecurrenceOverride(
          originalDate: DateTime(2026, 9, 2),
          clearDurationMinutes: true,
          clearLocation: true,
        ).toJson(),
      );
      expect(cleared.clearDurationMinutes, isTrue);
      expect(cleared.clearLocation, isTrue);
      expect(
        RecurrenceOverride.fromJson({
          'originalDate': '2026-09-02',
          'newDurationMinutes': 2000,
        }).newDurationMinutes,
        isNull,
      );
    },
  );

  test(
    'recurrence override can explicitly clear source duration and location',
    () {
      final anchor = DateTime(2026, 7, 1, 9);
      final event = DiaryEntry(
        id: 'clear-recurring-fields',
        content: '周课',
        timestamp: anchor,
        category: 'event',
        eventTime: anchor,
        durationMinutes: 90,
        location: 'B203',
      );
      final rule = ReminderRule(
        id: 'clear-recurring-fields-rule',
        title: '周课',
        targetType: 'event',
        targetId: event.id,
        scheduleType: 'weekly',
        byDay: const [3],
        anchorTime: anchor,
        overrides: [
          RecurrenceOverride(
            originalDate: DateTime(2026, 7, 8),
            clearDurationMinutes: true,
            clearLocation: true,
          ),
        ],
      );

      final projected = projectRecurringEvents(
        day: DateTime(2026, 7, 8),
        events: [event],
        rules: [rule],
      );

      expect(projected, hasLength(1));
      expect(projected.single.durationMinutes, isNull);
      expect(projected.single.location, isNull);
    },
  );

  test(
    'moved recurrence resolves its source date before native destination occurrence',
    () {
      final anchor = DateTime(2026, 7, 1, 9);
      final rule = ReminderRule(
        id: 'weekly-overlap',
        title: '周课',
        targetType: 'event',
        targetId: 'weekly-overlap-event',
        scheduleType: 'weekly',
        anchorTime: anchor,
        overrides: [
          RecurrenceOverride(
            originalDate: anchor,
            newTime: DateTime(2026, 7, 8, 14),
          ),
        ],
      );

      expect(
        RecurrenceService.originalDateForOccurrence(
          rule,
          DateTime(2026, 7, 8, 14),
        ),
        DateTime(2026, 7, 1),
      );
    },
  );

  test(
    'moved recurrence remains visible beside a native destination occurrence',
    () {
      final anchor = DateTime(2026, 7, 1, 9); // Wednesday
      final event = DiaryEntry(
        id: 'weekly-overlap-event',
        content: '周课',
        timestamp: anchor,
        category: 'event',
        eventTime: anchor,
      );
      final rule = ReminderRule(
        id: 'weekly-overlap-rule',
        title: '周课',
        targetType: 'event',
        targetId: event.id,
        scheduleType: 'weekly',
        byDay: const [3, 4],
        anchorTime: anchor,
        overrides: [
          RecurrenceOverride(
            originalDate: anchor,
            newTime: DateTime(2026, 7, 2, 14),
          ),
        ],
      );
      final projected = projectRecurringEvents(
        day: DateTime(2026, 7, 2),
        events: [event],
        rules: [rule],
      );

      expect(projected.map((item) => item.sortTime).toList(), [
        DateTime(2026, 7, 2, 9),
        DateTime(2026, 7, 2, 14),
      ]);
    },
  );

  test('recurring projected classes participate in conflict detection', () {
    final first = DiaryEntry(
      id: 'recurring-first',
      content: '周课 A',
      timestamp: DateTime(2026, 7, 1),
      category: 'event',
      eventTime: DateTime(2026, 7, 1, 9),
      durationMinutes: 60,
    );
    final second = DiaryEntry(
      id: 'recurring-second',
      content: '周课 B',
      timestamp: DateTime(2026, 7, 1),
      category: 'event',
      eventTime: DateTime(2026, 7, 1, 9, 30),
      durationMinutes: 60,
    );
    final rules = [
      ReminderRule(
        id: 'recurring-first-rule',
        title: first.content,
        targetType: 'event',
        targetId: first.id,
        scheduleType: 'weekly',
        byDay: const [3],
        anchorTime: first.eventTime,
      ),
      ReminderRule(
        id: 'recurring-second-rule',
        title: second.content,
        targetType: 'event',
        targetId: second.id,
        scheduleType: 'weekly',
        byDay: const [3],
        anchorTime: second.eventTime,
      ),
    ];
    final projected = [
      ...projectRecurringEvents(
        day: DateTime(2026, 7, 8),
        events: [first, second],
        rules: rules,
      ),
    ];

    expect(projected, hasLength(2));
    expect(findEventConflicts(projected), hasLength(1));
  });
}
