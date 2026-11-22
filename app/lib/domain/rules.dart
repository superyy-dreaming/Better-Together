import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

const maxPhotosPerCheckin = 9;
const maxChallengesPerDay = 2;
const monthlyMakeupAllowance = 2;

String localDate(DateTime instant, String timezone) {
  final date = tz.TZDateTime.from(instant, tz.getLocation(timezone));
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// Calendar offsets, not elapsed 24-hour intervals, across daylight-saving days.
String calendarDateOffset(DateTime instant, String timezone, int days) {
  final location = tz.getLocation(timezone);
  final day = tz.TZDateTime.from(instant, location);
  return localDate(
    tz.TZDateTime(location, day.year, day.month, day.day + days),
    timezone,
  );
}

bool planIsDue(Plan plan, DateTime instant, String timezone) {
  if (!plan.isActive ||
      plan.scheduleKind == 'weekly_target' ||
      plan.scheduleKind == 'period_target') {
    return false;
  }
  final date = localDate(instant, timezone);
  if (plan.anchorDate != null && date.compareTo(plan.anchorDate!) < 0) {
    return false;
  }
  final d = DateTime.parse('${date}T00:00:00Z');
  if (plan.scheduleKind == 'interval') {
    final anchor = DateTime.parse('${plan.anchorDate ?? date}T00:00:00Z');
    return d.difference(anchor).inDays % plan.intervalDays == 0;
  }
  return plan.weekdays.contains(d.weekday);
}

int challengeThreshold(int memberCount) => memberCount ~/ 2 + 1;
bool challengeTriggersRedo(int votes, int memberCount) =>
    votes >= challengeThreshold(memberCount);

DateTime overdueSyncAt(DateTime day, String deadline, String timezone) {
  final location = tz.getLocation(timezone);
  final date = tz.TZDateTime.from(day, location);
  final parts = deadline.split(':');
  final hour = int.parse(parts[0]);
  final minute = int.parse(parts[1]);
  final cutoff = tz.TZDateTime(
    location,
    date.year,
    date.month,
    date.day,
    23,
    30,
  );
  final scheduled = tz.TZDateTime(
    location,
    date.year,
    date.month,
    date.day,
    hour,
    minute,
  ).add(const Duration(minutes: 30));
  return scheduled.isAfter(cutoff) ? cutoff : scheduled;
}

DateTime redoDeadline(DateTime originalDay, String timezone) {
  final location = tz.getLocation(timezone);
  final date = tz.TZDateTime.from(originalDay, location);
  return tz.TZDateTime(location, date.year, date.month, date.day + 1, 12);
}

bool canMakeup({
  required DateTime now,
  required DateTime targetDay,
  required String timezone,
  required int remaining,
}) {
  if (remaining <= 0) return false;
  final location = tz.getLocation(timezone);
  final current = tz.TZDateTime.from(now, location);
  final target = tz.TZDateTime.from(targetDay, location);
  final yesterday = tz.TZDateTime(
    location,
    current.year,
    current.month,
    current.day - 1,
  );
  return target.year == yesterday.year &&
      target.month == yesterday.month &&
      target.day == yesterday.day &&
      now.isBefore(redoDeadline(targetDay, timezone));
}

/// Aggregate only completed scheduled days. Makeup and pending redo freeze the
/// count; missing scheduled days reset it. Rest days never reset a streak.
int streakForPlan(
  Plan plan,
  List<Checkin> checkins,
  String userId,
  DateTime now,
  String timezone,
) {
  final location = tz.getLocation(timezone);
  final today = tz.TZDateTime.from(now, location);
  var streak = 0;
  for (var offset = 0; offset < 3660; offset++) {
    final day = tz.TZDateTime(
      location,
      today.year,
      today.month,
      today.day - offset,
    );
    if (!planIsDue(plan, day, timezone)) continue;
    final entries = checkins.where(
      (c) =>
          c.userId == userId &&
          c.planId == plan.id &&
          c.localDate == localDate(day, timezone),
    );
    if (entries.any((c) => c.status == 'stamped' && !c.isLate)) {
      streak++;
    } else if (entries.any(
      (c) => c.status == 'makeup' || c.status == 'redo_required',
    )) {
      continue;
    } else if (offset == 0) {
      continue;
    } else {
      break;
    }
  }
  return streak;
}

String? validateMemoFields(List<MemoField> fields, String category) {
  for (final field in fields) {
    if (field.value == null) continue;
    if (category == 'food' &&
        (field.key.contains('calor') || field.key.contains('kcal'))) {
      final range = jsonObject(field.value);
      if (range['min'] is! num ||
          range['max'] is! num ||
          !boolValue(range['estimated'])) {
        return '热量请填写区间，并标注估算';
      }
      if ((range['min'] as num) > (range['max'] as num)) return '热量区间下限不能大于上限';
    }
    if (category == 'exercise' &&
        [
          'duration',
          'duration_seconds',
          'distance',
          'calories',
          'energy',
        ].contains(field.key) &&
        !['screenshot', 'timer', 'health', 'manual'].contains(field.source)) {
      return '运动数据需要截图、计时或手填来源';
    }
  }
  return null;
}
