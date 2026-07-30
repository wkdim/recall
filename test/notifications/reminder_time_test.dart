import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/notifications/reminder_time.dart';

void main() {
  test('schedules for today when the time has not passed yet', () {
    final now = DateTime(2026, 7, 27, 8, 0);
    final result = nextOccurrence(hour: 9, minute: 0, now: now);
    expect(result, DateTime(2026, 7, 27, 9, 0));
  });

  test('schedules for tomorrow when the time has already passed', () {
    final now = DateTime(2026, 7, 27, 10, 0);
    final result = nextOccurrence(hour: 9, minute: 0, now: now);
    expect(result, DateTime(2026, 7, 28, 9, 0));
  });

  test('schedules for tomorrow when the time is exactly now', () {
    final now = DateTime(2026, 7, 27, 9, 0);
    final result = nextOccurrence(hour: 9, minute: 0, now: now);
    expect(result, DateTime(2026, 7, 28, 9, 0));
  });

  test('crosses a month boundary correctly', () {
    final now = DateTime(2026, 7, 31, 10, 0);
    final result = nextOccurrence(hour: 9, minute: 0, now: now);
    expect(result, DateTime(2026, 8, 1, 9, 0));
  });
}
