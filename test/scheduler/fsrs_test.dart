import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/scheduler/fsrs.dart';

void main() {
  group('first review (no prior stability/difficulty)', () {
    test('Good on a first review gives the published initial stability', () {
      final r = fsrsSchedule(quality: 3);
      expect(r.stability, 2.4);
    });

    test('Easy starts with higher initial stability than Good', () {
      final good = fsrsSchedule(quality: 3);
      final easy = fsrsSchedule(quality: 4);
      expect(easy.stability, greaterThan(good.stability));
    });

    test('Again starts with the lowest initial stability', () {
      final again = fsrsSchedule(quality: 0);
      final hard = fsrsSchedule(quality: 2);
      expect(again.stability, lessThan(hard.stability));
    });

    test('a harder first rating produces a higher starting difficulty', () {
      final again = fsrsSchedule(quality: 0);
      final easy = fsrsSchedule(quality: 4);
      expect(again.difficulty, greaterThan(easy.difficulty));
    });
  });

  group('interval from stability (forgetting-curve formula)', () {
    test('at the default 90% retention target, interval roughly equals stability', () {
      final r = fsrsSchedule(stability: 10, difficulty: 5, quality: 3);
      // Passing Good multiplies stability, so check the *formula* directly
      // via a lapse-free round trip: schedule once, then verify the next
      // interval is in the same order of magnitude as the new stability.
      expect(r.interval, closeTo(r.stability, r.stability * 0.5 + 1));
    });

    test('a higher stability produces a longer interval', () {
      final low = fsrsSchedule(stability: 2, difficulty: 5, quality: 3);
      final high = fsrsSchedule(stability: 20, difficulty: 5, quality: 3);
      expect(high.interval, greaterThan(low.interval));
    });

    test('a lower request retention target produces a longer interval', () {
      final strict = fsrsSchedule(stability: 10, difficulty: 5, quality: 3, requestRetention: 0.95);
      final relaxed = fsrsSchedule(stability: 10, difficulty: 5, quality: 3, requestRetention: 0.8);
      expect(relaxed.interval, greaterThan(strict.interval));
    });

    test('interval is never less than 1 day', () {
      final r = fsrsSchedule(stability: 0.01, difficulty: 5, quality: 0);
      expect(r.interval, greaterThanOrEqualTo(1));
    });
  });

  group('lapses vs. passes - the key difference from this app\'s SM-2 path', () {
    test('Again (quality 0) is a lapse: stability drops', () {
      final r = fsrsSchedule(stability: 10, difficulty: 5, quality: 0);
      expect(r.stability, lessThan(10));
    });

    test('Hard (quality 2) is a pass, not a lapse: stability still grows', () {
      final r = fsrsSchedule(stability: 10, difficulty: 5, quality: 2);
      expect(r.stability, greaterThan(10));
    });

    test('Hard grows stability less than Good, and Good less than Easy', () {
      final hard = fsrsSchedule(stability: 10, difficulty: 5, quality: 2);
      final good = fsrsSchedule(stability: 10, difficulty: 5, quality: 3);
      final easy = fsrsSchedule(stability: 10, difficulty: 5, quality: 4);
      expect(hard.stability, lessThan(good.stability));
      expect(good.stability, lessThan(easy.stability));
    });
  });

  group('difficulty evolution', () {
    test('a lapse increases difficulty', () {
      final r = fsrsSchedule(stability: 10, difficulty: 5, quality: 0);
      expect(r.difficulty, greaterThan(5));
    });

    test('an Easy rating decreases difficulty', () {
      final r = fsrsSchedule(stability: 10, difficulty: 5, quality: 4);
      expect(r.difficulty, lessThan(5));
    });

    test('difficulty never exceeds the 1-10 scale', () {
      var difficulty = 9.5;
      for (var i = 0; i < 5; i++) {
        final r = fsrsSchedule(stability: 10, difficulty: difficulty, quality: 0);
        difficulty = r.difficulty;
      }
      expect(difficulty, lessThanOrEqualTo(10));
    });

    test('difficulty never drops below 1', () {
      var difficulty = 1.5;
      for (var i = 0; i < 5; i++) {
        final r = fsrsSchedule(stability: 10, difficulty: difficulty, quality: 4);
        difficulty = r.difficulty;
      }
      expect(difficulty, greaterThanOrEqualTo(1));
    });
  });
}
