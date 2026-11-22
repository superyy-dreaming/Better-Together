import 'package:better_together/domain/rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);
  test('calendar offsets do not repeat or skip a date across DST', () {
    // New York 00:30 after spring-forward: subtracting 24 hours skips a date.
    final spring = DateTime.utc(2026, 3, 9, 4, 30);
    expect(calendarDateOffset(spring, 'America/New_York', -1), '2026-03-08');
    // New York 23:30 on fall-back day: subtracting 24 hours repeats the day.
    final fall = DateTime.utc(2026, 11, 2, 4, 30);
    expect(calendarDateOffset(fall, 'America/New_York', -1), '2026-10-31');
  });
}
