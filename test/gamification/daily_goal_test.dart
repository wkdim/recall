import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashcard_app/gamification/daily_goal.dart';

void main() {
  group('computeDailyCount (pure logic)', () {
    test('no prior record starts the count at 1', () {
      final count = computeDailyCount(
        currentCount: 0,
        lastRecordedDate: null,
        today: DateTime(2026, 7, 26),
      );
      expect(count, 1);
    });

    test('recording again the same day increments the count', () {
      final count = computeDailyCount(
        currentCount: 5,
        lastRecordedDate: DateTime(2026, 7, 26, 8),
        today: DateTime(2026, 7, 26, 21),
      );
      expect(count, 6);
    });

    test('a new calendar day resets the count to 1', () {
      final count = computeDailyCount(
        currentCount: 12,
        lastRecordedDate: DateTime(2026, 7, 25),
        today: DateTime(2026, 7, 26),
      );
      expect(count, 1);
    });

    test('only the calendar date matters, not time of day', () {
      final count = computeDailyCount(
        currentCount: 3,
        lastRecordedDate: DateTime(2026, 7, 26, 23, 59),
        today: DateTime(2026, 7, 26, 0, 1),
      );
      expect(count, 4);
    });
  });

  group('DailyGoalTracker (persisted)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to kDefaultDailyGoal before the user picks their own', () async {
      expect(await DailyGoalTracker().getGoal(), kDefaultDailyGoal);
    });

    test('setGoal persists a custom target', () async {
      final tracker = DailyGoalTracker();
      await tracker.setGoal(50);
      expect(await tracker.getGoal(), 50);
    });

    test('todayCount reports 0 before any review is recorded', () async {
      expect(await DailyGoalTracker().todayCount(), 0);
    });

    test('recordReview accumulates across the same day', () async {
      final tracker = DailyGoalTracker();
      final now = DateTime(2026, 7, 26, 10);
      await tracker.recordReview(now: now);
      final count = await tracker.recordReview(now: now);
      expect(count, 2);
      expect(await tracker.todayCount(now: now), 2);
    });

    test('todayCount reads back as 0 once the count is from a prior day', () async {
      SharedPreferences.setMockInitialValues({
        'daily_goal_count': 8,
        'daily_goal_date': DateTime(2026, 7, 1).millisecondsSinceEpoch,
      });
      expect(await DailyGoalTracker().todayCount(now: DateTime(2026, 7, 26)), 0);
    });
  });
}
