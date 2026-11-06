import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashcard_app/streak/streak_tracker.dart';

void main() {
  group('computeNewStreak (pure logic)', () {
    test('no prior session starts a streak of 1', () {
      final streak = computeNewStreak(
        currentStreak: 0,
        lastStudyDate: null,
        today: DateTime(2026, 7, 26),
      );
      expect(streak, 1);
    });

    test('studying again the same day does not double-count', () {
      final streak = computeNewStreak(
        currentStreak: 5,
        lastStudyDate: DateTime(2026, 7, 26, 8, 0),
        today: DateTime(2026, 7, 26, 21, 0),
      );
      expect(streak, 5);
    });

    test('studying the day after extends the streak by one', () {
      final streak = computeNewStreak(
        currentStreak: 5,
        lastStudyDate: DateTime(2026, 7, 25),
        today: DateTime(2026, 7, 26),
      );
      expect(streak, 6);
    });

    test('a gap of two or more days resets the streak to 1', () {
      final streak = computeNewStreak(
        currentStreak: 30,
        lastStudyDate: DateTime(2026, 7, 20),
        today: DateTime(2026, 7, 26),
      );
      expect(streak, 1);
    });

    test('extends correctly across a month boundary', () {
      final streak = computeNewStreak(
        currentStreak: 10,
        lastStudyDate: DateTime(2026, 7, 31),
        today: DateTime(2026, 8, 1),
      );
      expect(streak, 11);
    });

    test('only the calendar date matters, not time of day', () {
      final streak = computeNewStreak(
        currentStreak: 3,
        lastStudyDate: DateTime(2026, 7, 25, 23, 59),
        today: DateTime(2026, 7, 26, 0, 1),
      );
      expect(streak, 4);
    });
  });

  group('StreakTracker (persisted)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('first session ever records a streak of 1', () async {
      final tracker = StreakTracker();
      final streak = await tracker.recordStudySession(now: DateTime(2026, 7, 26));
      expect(streak, 1);
      // Same fixed date as above - currentStreak() defaults to the real
      // clock, and comparing a 2026-07-26 fixture against a much later real
      // "today" would incorrectly read the streak as stale.
      expect(await tracker.currentStreak(now: DateTime(2026, 7, 26)), 1);
    });

    test('consecutive days accumulate across separate calls', () async {
      final tracker = StreakTracker();
      await tracker.recordStudySession(now: DateTime(2026, 7, 24));
      await tracker.recordStudySession(now: DateTime(2026, 7, 25));
      final streak = await tracker.recordStudySession(now: DateTime(2026, 7, 26));
      expect(streak, 3);
    });

    test('recording twice in the same day keeps the streak stable', () async {
      final tracker = StreakTracker();
      await tracker.recordStudySession(now: DateTime(2026, 7, 26, 8));
      final streak = await tracker.recordStudySession(now: DateTime(2026, 7, 26, 20));
      expect(streak, 1);
    });

    test('currentStreak reports 0 before any session is recorded', () async {
      expect(await StreakTracker().currentStreak(), 0);
    });

    test('currentStreak reads back as 0 once the streak has gone stale', () async {
      SharedPreferences.setMockInitialValues({
        'streak_current': 12,
        'streak_last_study_date': DateTime(2026, 7, 1).millisecondsSinceEpoch,
      });
      expect(await StreakTracker().currentStreak(now: DateTime(2026, 7, 26)), 0);
    });
  });
}
