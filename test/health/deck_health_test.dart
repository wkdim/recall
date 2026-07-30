import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/database/database.dart';
import 'package:flashcard_app/health/deck_health.dart';

Card _card({
  required int id,
  String front = 'front',
  String back = 'back',
  double easeFactor = 2.5,
  int repetitions = 0,
  DateTime? nextReview,
}) {
  return Card(
    id: id,
    deckId: 1,
    front: front,
    back: back,
    easeFactor: easeFactor,
    interval: 1,
    repetitions: repetitions,
    nextReview: nextReview ?? DateTime.now(),
    isCloze: false,
  );
}

void main() {
  test('an empty deck scores 100 with no issues', () {
    final report = computeDeckHealth([]);
    expect(report.score, 100);
    expect(report.hasIssues, isFalse);
  });

  test('a deck with no problems scores 100', () {
    final clean = [
      _card(id: 1, front: 'a', repetitions: 3, easeFactor: 2.6),
      _card(id: 2, front: 'b', repetitions: 1, easeFactor: 2.4),
    ];
    final report = computeDeckHealth(clean);
    expect(report.score, 100);
    expect(report.hasIssues, isFalse);
  });

  group('duplicates', () {
    test('counts every copy beyond the first as one duplicate', () {
      final cards = [
        _card(id: 1, front: 'Capital of France'),
        _card(id: 2, front: 'capital of france'), // same, different case
        _card(id: 3, front: '  Capital of France  '), // same, extra whitespace
        _card(id: 4, front: 'Something else'),
      ];
      final report = computeDeckHealth(cards);
      expect(report.duplicateCount, 2);
    });

    test('no duplicates when every front is distinct', () {
      final cards = [_card(id: 1, front: 'a'), _card(id: 2, front: 'b')];
      expect(computeDeckHealth(cards).duplicateCount, 0);
    });
  });

  group('too long', () {
    test('flags a card whose front exceeds the length threshold', () {
      final cards = [_card(id: 1, front: 'x' * 250)];
      expect(computeDeckHealth(cards, maxLength: 200).tooLongCount, 1);
    });

    test('flags a card whose back exceeds the length threshold', () {
      final cards = [_card(id: 1, back: 'x' * 250)];
      expect(computeDeckHealth(cards, maxLength: 200).tooLongCount, 1);
    });

    test('does not flag a card within the threshold', () {
      final cards = [_card(id: 1, front: 'short', back: 'also short')];
      expect(computeDeckHealth(cards, maxLength: 200).tooLongCount, 0);
    });
  });

  group('never reviewed', () {
    test('flags a card still at the pristine ease/repetitions defaults', () {
      final cards = [_card(id: 1, easeFactor: 2.5, repetitions: 0)];
      expect(computeDeckHealth(cards).neverReviewedCount, 1);
    });

    test('does not flag a card that has been reviewed', () {
      final cards = [_card(id: 1, easeFactor: 2.5, repetitions: 3)];
      expect(computeDeckHealth(cards).neverReviewedCount, 0);
    });
  });

  group('overdue', () {
    test('flags a card overdue by more than the threshold', () {
      final now = DateTime(2026, 7, 27);
      final cards = [_card(id: 1, nextReview: DateTime(2026, 7, 1))];
      expect(computeDeckHealth(cards, now: now, overdueDays: 7).overdueCount, 1);
    });

    test('does not flag a card that is merely due today', () {
      final now = DateTime(2026, 7, 27);
      final cards = [_card(id: 1, nextReview: DateTime(2026, 7, 26))];
      expect(computeDeckHealth(cards, now: now, overdueDays: 7).overdueCount, 0);
    });
  });

  group('score', () {
    test('drops proportionally to the fraction of cards with issues', () {
      final now = DateTime(2026, 7, 27);
      final cards = [
        _card(id: 1, front: 'ok', repetitions: 3, nextReview: now), // healthy, reviewed
        _card(id: 2, front: 'ok2', repetitions: 3, nextReview: DateTime(2026, 1, 1)), // overdue only
      ];
      final report = computeDeckHealth(cards, now: now, overdueDays: 7);
      expect(report.score, 50);
    });

    test('never drops below 0 even with many overlapping issues', () {
      final cards = [
        _card(id: 1, front: 'dup', nextReview: DateTime(2020, 1, 1)),
        _card(id: 2, front: 'dup', nextReview: DateTime(2020, 1, 1)),
      ];
      final report = computeDeckHealth(cards, now: DateTime(2026, 7, 27), overdueDays: 7);
      expect(report.score, greaterThanOrEqualTo(0));
    });
  });
}
