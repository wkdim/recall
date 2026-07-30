import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/stats/stats_calculations.dart';

void main() {
  group('bucketReviewsByDay', () {
    test('groups multiple reviews on the same day into one bucket', () {
      final buckets = bucketReviewsByDay([
        DateTime(2026, 7, 26, 8, 0),
        DateTime(2026, 7, 26, 20, 30),
        DateTime(2026, 7, 25, 9, 0),
      ]);

      expect(buckets[DateTime(2026, 7, 26)], 2);
      expect(buckets[DateTime(2026, 7, 25)], 1);
      expect(buckets.length, 2);
    });

    test('empty input produces empty buckets', () {
      expect(bucketReviewsByDay([]), isEmpty);
    });

    test('time of day is stripped when bucketing', () {
      final buckets = bucketReviewsByDay([
        DateTime(2026, 7, 26, 0, 1),
        DateTime(2026, 7, 26, 23, 59),
      ]);
      expect(buckets.length, 1);
      expect(buckets[DateTime(2026, 7, 26)], 2);
    });
  });

  group('lastNDays', () {
    test('returns the requested number of days, oldest first, ending on today', () {
      final days = lastNDays(5, DateTime(2026, 7, 26));
      expect(days, [
        DateTime(2026, 7, 22),
        DateTime(2026, 7, 23),
        DateTime(2026, 7, 24),
        DateTime(2026, 7, 25),
        DateTime(2026, 7, 26),
      ]);
    });

    test('strips time of day from "today"', () {
      final days = lastNDays(1, DateTime(2026, 7, 26, 23, 59));
      expect(days, [DateTime(2026, 7, 26)]);
    });

    test('crosses a month boundary correctly', () {
      final days = lastNDays(3, DateTime(2026, 8, 1));
      expect(days, [
        DateTime(2026, 7, 30),
        DateTime(2026, 7, 31),
        DateTime(2026, 8, 1),
      ]);
    });
  });

  group('retentionRate', () {
    test('is 0 for no reviews', () {
      expect(retentionRate([]), 0.0);
    });

    test('counts Good (3) and Easy (4) as remembered', () {
      expect(retentionRate([3, 4]), 1.0);
    });

    test('counts Again (0) and Hard (2) as not remembered', () {
      expect(retentionRate([0, 2]), 0.0);
    });

    test('computes a mixed fraction correctly', () {
      expect(retentionRate([0, 2, 3, 4]), 0.5);
    });
  });
}
