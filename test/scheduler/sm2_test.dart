import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/scheduler/sm2.dart';

void main() {
  group('sm2Schedule - first-time reviews (repetitions == 0)', () {
    test('quality 3 (Good) sets interval to 1 and repetitions to 1', () {
      final r = sm2Schedule(
          easeFactor: 2.5, interval: 1, repetitions: 0, quality: 3);
      expect(r.interval, 1);
      expect(r.repetitions, 1);
    });

    test('quality 4 (Easy) also sets interval to 1 on the first pass', () {
      final r = sm2Schedule(
          easeFactor: 2.5, interval: 1, repetitions: 0, quality: 4);
      expect(r.interval, 1);
      expect(r.repetitions, 1);
    });
  });

  group('sm2Schedule - second review (repetitions == 1)', () {
    test('a pass sets interval to 6 regardless of ease factor', () {
      final r = sm2Schedule(
          easeFactor: 1.8, interval: 1, repetitions: 1, quality: 3);
      expect(r.interval, 6);
      expect(r.repetitions, 2);
    });
  });

  group('sm2Schedule - later reviews (repetitions >= 2)', () {
    test('a pass multiplies interval by the ease factor and rounds', () {
      final r = sm2Schedule(
          easeFactor: 2.5, interval: 6, repetitions: 2, quality: 4);
      expect(r.interval, (6 * 2.5).round());
      expect(r.repetitions, 3);
    });

    test('rounding: interval * ease rounds to nearest int, not truncates',
        () {
      // 10 * 1.35 = 13.5 -> rounds to 14, not 13.
      final r = sm2Schedule(
          easeFactor: 1.35, interval: 10, repetitions: 2, quality: 3);
      expect(r.interval, 14);
    });

    test('repeated passes compound the interval across calls', () {
      var ease = 2.5;
      var interval = 1;
      var reps = 0;
      for (final quality in [3, 3, 4, 4]) {
        final r = sm2Schedule(
            easeFactor: ease, interval: interval, repetitions: reps,
            quality: quality);
        ease = r.easeFactor;
        interval = r.interval;
        reps = r.repetitions;
      }
      expect(reps, 4);
      expect(interval, greaterThan(6));
    });
  });

  group('sm2Schedule - lapses (quality < 3)', () {
    test('quality 0 (Again) resets repetitions and interval to 1', () {
      final r = sm2Schedule(
          easeFactor: 2.5, interval: 30, repetitions: 5, quality: 0);
      expect(r.repetitions, 0);
      expect(r.interval, 1);
    });

    test('quality 2 (Hard) is still a lapse under standard SM-2 (q < 3)', () {
      final r = sm2Schedule(
          easeFactor: 2.5, interval: 30, repetitions: 5, quality: 2);
      expect(r.repetitions, 0);
      expect(r.interval, 1);
    });

    test('a lapse still updates the ease factor down, not just interval',
        () {
      final r = sm2Schedule(
          easeFactor: 2.5, interval: 30, repetitions: 5, quality: 0);
      expect(r.easeFactor, lessThan(2.5));
    });
  });

  group('sm2Schedule - ease factor floor', () {
    test('ease factor never drops below 1.3 even after repeated failures',
        () {
      var ease = 1.3;
      for (var i = 0; i < 20; i++) {
        final r = sm2Schedule(
            easeFactor: ease, interval: 1, repetitions: 0, quality: 0);
        ease = r.easeFactor;
        expect(ease, greaterThanOrEqualTo(1.3));
      }
      expect(ease, 1.3);
    });

    test('starting already below the floor still clamps up to 1.3', () {
      final r = sm2Schedule(
          easeFactor: 1.1, interval: 1, repetitions: 0, quality: 0);
      expect(r.easeFactor, 1.3);
    });

    test('quality 5 raises the ease factor above the default 2.5', () {
      final r = sm2Schedule(
          easeFactor: 2.5, interval: 6, repetitions: 2, quality: 5);
      expect(r.easeFactor, greaterThan(2.5));
    });
  });

  group('sm2Schedule - no interval cap in this implementation', () {
    test('a high ease factor with a large interval keeps growing unbounded',
        () {
      final r = sm2Schedule(
          easeFactor: 3.0, interval: 3000, repetitions: 10, quality: 4);
      expect(r.interval, 9000);
    });
  });

  group('sm2Schedule - same-day re-review after a lapse', () {
    test('failing immediately after failing keeps interval at 1 day', () {
      var r = sm2Schedule(
          easeFactor: 2.5, interval: 15, repetitions: 4, quality: 0);
      expect(r.interval, 1);
      r = sm2Schedule(
          easeFactor: r.easeFactor,
          interval: r.interval,
          repetitions: r.repetitions,
          quality: 0);
      expect(r.interval, 1);
      expect(r.repetitions, 0);
    });
  });
}
