import '../models/recurrence_override.dart';
import '../models/reminder_rule.dart';

class RecurrenceOccurrence {
  final DateTime originalTime;
  final DateTime scheduledTime;
  final RecurrenceOverride? override;

  const RecurrenceOccurrence({
    required this.originalTime,
    required this.scheduledTime,
    this.override,
  });

  DateTime get originalDate =>
      DateTime(originalTime.year, originalTime.month, originalTime.day);
}

/// 课程时间轴、早报和系统通知共同使用的唯一周期计算器。
class RecurrenceService {
  const RecurrenceService._();

  static List<RecurrenceOccurrence> occurrencesBetween(
    ReminderRule rule,
    DateTime from,
    DateTime to,
  ) {
    final anchor = rule.anchorTime;
    if (!rule.isActive || anchor == null || to.isBefore(from)) return const [];

    final effectiveStart = _laterDate(rule.startDate ?? anchor, anchor);
    final startDay = _dateOnly(effectiveStart);
    // Never scan past the caller's requested window. The previous code used
    // the later of `endDate` and `to`, so a recurring class ending in 2030
    // could make a Today/Week query walk years of calendar days.
    final requestedEndDay = _dateOnly(to);
    final ruleEndDay = rule.endDate == null
        ? requestedEndDay
        : _dateOnly(rule.endDate!);
    final scanEnd = ruleEndDay.isBefore(requestedEndDay)
        ? ruleEndDay
        : requestedEndDay;
    final occurrences = <RecurrenceOccurrence>[];
    var occurrenceOrdinal = 0;

    for (
      var day = startDay;
      !day.isAfter(scanEnd);
      day = day.add(const Duration(days: 1))
    ) {
      if (!_matches(rule, day, anchor)) continue;
      if (rule.endCount != null && occurrenceOrdinal >= rule.endCount!) break;
      occurrenceOrdinal++;

      if (rule.skipDates.any((value) => isSameDate(value, day))) continue;
      final original = DateTime(
        day.year,
        day.month,
        day.day,
        anchor.hour,
        anchor.minute,
        anchor.second,
      );
      final recurrenceOverride = _overrideFor(rule, day);
      if (recurrenceOverride?.isCompleted == true) continue;
      final scheduled = _applyTimeOverride(original, recurrenceOverride);
      if (!scheduled.isBefore(from) && !scheduled.isAfter(to)) {
        occurrences.add(
          RecurrenceOccurrence(
            originalTime: original,
            scheduledTime: scheduled,
            override: recurrenceOverride,
          ),
        );
      }
    }

    // 单次改期可能把原发生时间移出扫描窗口，因此单独补入窗口内的覆盖。
    for (final recurrenceOverride in rule.overrides) {
      if (recurrenceOverride.isCompleted ||
          recurrenceOverride.newTime == null) {
        continue;
      }
      final originalDay = _dateOnly(recurrenceOverride.originalDate);
      // originalDay 可能在当前窗口外，但 newTime 被改到了窗口内；这类
      // 跨日单次改期仍然应该出现在新日期。
      final recurrenceStartDay = _dateOnly(
        _laterDate(rule.startDate ?? anchor, anchor),
      );
      if (originalDay.isBefore(recurrenceStartDay)) continue;
      if (rule.endDate != null &&
          originalDay.isAfter(_dateOnly(rule.endDate!))) {
        continue;
      }
      if (!_matches(rule, originalDay, anchor)) continue;
      if (rule.skipDates.any((value) => isSameDate(value, originalDay))) {
        continue;
      }
      if (rule.endCount != null &&
          occurrenceIndex(rule, originalDay) >= rule.endCount!) {
        continue;
      }
      final original = DateTime(
        originalDay.year,
        originalDay.month,
        originalDay.day,
        anchor.hour,
        anchor.minute,
      );
      final scheduled = _applyTimeOverride(original, recurrenceOverride);
      if (!scheduled.isBefore(from) &&
          !scheduled.isAfter(to) &&
          !occurrences.any(
            (item) => isSameDate(item.originalTime, originalDay),
          )) {
        occurrences.add(
          RecurrenceOccurrence(
            originalTime: original,
            scheduledTime: scheduled,
            override: recurrenceOverride,
          ),
        );
      }
    }

    occurrences.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    return occurrences;
  }

  static RecurrenceOccurrence? occurrenceOn(ReminderRule rule, DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));
    final values = occurrencesBetween(rule, start, end);
    return values.isEmpty ? null : values.first;
  }

  /// Finds the original recurrence date for an item currently displayed at
  /// [scheduledTime]. This is important after a one-off occurrence is moved
  /// across days: the UI must continue writing the override against its
  /// original date instead of creating a second override for the new date.
  static DateTime? originalDateForOccurrence(
    ReminderRule rule,
    DateTime scheduledTime,
  ) {
    // A moved occurrence can land on a day that already has another regular
    // occurrence. Resolve an exact override timestamp first; otherwise
    // occurrenceOn() would incorrectly return the destination day's native
    // occurrence and subsequent edits would write to the wrong date.
    for (final override in rule.overrides) {
      final changed = override.newTime;
      if (changed != null && changed.isAtSameMomentAs(scheduledTime)) {
        return _dateOnly(override.originalDate);
      }
    }
    final occurrence = occurrenceOn(rule, scheduledTime);
    if (occurrence != null) return occurrence.originalDate;

    // Keep a defensive fallback for legacy data whose override has an
    // incomplete timestamp but still identifies the moved calendar day.
    for (final override in rule.overrides) {
      final changed = override.newTime;
      if (changed != null && isSameDate(changed, scheduledTime)) {
        return _dateOnly(override.originalDate);
      }
    }
    return null;
  }

  /// 返回不晚于 [day] 的最近一个原始投影日（不应用停课与改单次时间）。
  static DateTime? lastProjectionDay(ReminderRule rule, DateTime day) {
    final anchor = rule.anchorTime;
    if (anchor == null) return null;
    final start = _dateOnly(_laterDate(rule.startDate ?? anchor, anchor));
    final target = _dateOnly(day);
    if (target.isBefore(start)) return null;
    DateTime? last;
    var count = 0;
    for (
      var cursor = start;
      !cursor.isAfter(target);
      cursor = cursor.add(const Duration(days: 1))
    ) {
      if (!_matches(rule, cursor, anchor)) continue;
      if (rule.endCount != null && count >= rule.endCount!) break;
      last = cursor;
      count++;
    }
    return last;
  }

  static DateTime nextProjectionDay(ReminderRule rule, DateTime after) {
    final anchor = rule.anchorTime ?? after;
    for (var offset = 1; offset <= 3660; offset++) {
      final candidate = _dateOnly(after).add(Duration(days: offset));
      if (_matches(rule, candidate, anchor)) return candidate;
    }
    return _dateOnly(after).add(const Duration(days: 1));
  }

  static int occurrenceIndex(ReminderRule rule, DateTime projectionDay) {
    final anchor = rule.anchorTime;
    if (anchor == null) return -1;
    final start = _dateOnly(_laterDate(rule.startDate ?? anchor, anchor));
    final target = _dateOnly(projectionDay);
    var index = -1;
    for (
      var cursor = start;
      !cursor.isAfter(target);
      cursor = cursor.add(const Duration(days: 1))
    ) {
      if (_matches(rule, cursor, anchor)) index++;
    }
    return index;
  }

  static bool isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime _laterDate(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

  static RecurrenceOverride? _overrideFor(ReminderRule rule, DateTime day) {
    for (final value in rule.overrides) {
      if (isSameDate(value.originalDate, day)) return value;
    }
    return null;
  }

  static DateTime _applyTimeOverride(
    DateTime original,
    RecurrenceOverride? recurrenceOverride,
  ) {
    final changed = recurrenceOverride?.newTime;
    if (changed == null) return original;
    final changesDate = !isSameDate(changed, recurrenceOverride!.originalDate);
    return DateTime(
      changesDate ? changed.year : original.year,
      changesDate ? changed.month : original.month,
      changesDate ? changed.day : original.day,
      changed.hour,
      changed.minute,
      changed.second,
    );
  }

  static bool _matches(ReminderRule rule, DateTime day, DateTime anchor) {
    final anchorDay = _dateOnly(anchor);
    if (day.isBefore(anchorDay)) return false;
    final difference = day.difference(anchorDay).inDays;
    return switch (rule.scheduleType) {
      'once' => isSameDate(day, anchorDay),
      'daily' => true,
      'weekly' => (rule.byDay ?? [anchor.weekday]).contains(day.weekday),
      'every_n_days' =>
        rule.scheduleInterval > 0 && difference % rule.scheduleInterval == 0,
      'monthly' => _matchesMonthly(rule, day, anchorDay),
      _ => false,
    };
  }

  static bool _matchesMonthly(
    ReminderRule rule,
    DateTime day,
    DateTime anchor,
  ) {
    // scheduleDay is the compact v2 representation used by captures and the
    // manual routine editor. Keep supporting the richer byMonthDay list when
    // it exists, while allowing older rules to honor scheduleDay directly.
    final monthDays = rule.byMonthDay ??
        (rule.scheduleDay == null ? [anchor.day] : [rule.scheduleDay!]);
    final lastDay = DateTime(day.year, day.month + 1, 0).day;
    return monthDays.map((value) => value.clamp(1, lastDay)).contains(day.day);
  }
}
