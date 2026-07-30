import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/collections/smart_collections.dart';
import 'package:flashcard_app/database/database.dart';

Card _card({
  required int id,
  double easeFactor = 2.5,
  int interval = 1,
  int repetitions = 0,
  DateTime? nextReview,
}) {
  return Card(
    id: id,
    deckId: 1,
    front: 'front $id',
    back: 'back $id',
    easeFactor: easeFactor,
    interval: interval,
    repetitions: repetitions,
    nextReview: nextReview ?? DateTime.now(),
    isCloze: false,
  );
}

void main() {
  group('Due Today', () {
    test('includes cards due now or overdue, excludes future cards', () {
      final now = DateTime(2026, 7, 27);
      final due = _card(id: 1, nextReview: DateTime(2026, 7, 26));
      final future = _card(id: 2, nextReview: DateTime(2026, 8, 1));
      final result = filterCollection(SmartCollectionType.dueToday, [due, future], now: now);
      expect(result, [due]);
    });
  });

  group('Forgotten Cards', () {
    test('includes a lapsed card (reps reset, ease below default)', () {
      final lapsed = _card(id: 1, repetitions: 0, easeFactor: 1.8);
      final result = filterCollection(SmartCollectionType.forgotten, [lapsed]);
      expect(result, [lapsed]);
    });

    test('excludes a brand-new, never-reviewed card', () {
      final fresh = _card(id: 1, repetitions: 0, easeFactor: 2.5);
      final result = filterCollection(SmartCollectionType.forgotten, [fresh]);
      expect(result, isEmpty);
    });

    test('excludes a card currently in good standing', () {
      final healthy = _card(id: 1, repetitions: 5, easeFactor: 2.6);
      final result = filterCollection(SmartCollectionType.forgotten, [healthy]);
      expect(result, isEmpty);
    });
  });

  group('Difficult Cards', () {
    test('includes a reviewed card with a low ease factor', () {
      final hard = _card(id: 1, repetitions: 3, easeFactor: 1.5);
      final result = filterCollection(SmartCollectionType.difficult, [hard]);
      expect(result, [hard]);
    });

    test('excludes a never-reviewed card even with low ease', () {
      final unreviewed = _card(id: 1, repetitions: 0, easeFactor: 1.5);
      final result = filterCollection(SmartCollectionType.difficult, [unreviewed]);
      expect(result, isEmpty);
    });

    test('excludes a card with a comfortable ease factor', () {
      final easy = _card(id: 1, repetitions: 3, easeFactor: 2.8);
      final result = filterCollection(SmartCollectionType.difficult, [easy]);
      expect(result, isEmpty);
    });
  });

  group('Recently Added', () {
    test('returns cards ordered by id descending', () {
      final cards = [_card(id: 1), _card(id: 3), _card(id: 2)];
      final result = filterCollection(SmartCollectionType.recentlyAdded, cards);
      expect(result.map((c) => c.id).toList(), [3, 2, 1]);
    });

    test('respects the limit', () {
      final cards = List.generate(30, (i) => _card(id: i));
      final result = filterCollection(SmartCollectionType.recentlyAdded, cards, recentlyAddedLimit: 5);
      expect(result, hasLength(5));
      expect(result.first.id, 29);
    });
  });

  group('Mature Cards', () {
    test('includes a card with a long interval and multiple successful reviews', () {
      final mature = _card(id: 1, interval: 30, repetitions: 4);
      final result = filterCollection(SmartCollectionType.mature, [mature]);
      expect(result, [mature]);
    });

    test('excludes a card with a long interval but too few repetitions', () {
      final card = _card(id: 1, interval: 30, repetitions: 1);
      final result = filterCollection(SmartCollectionType.mature, [card]);
      expect(result, isEmpty);
    });

    test('excludes a card with enough repetitions but a short interval', () {
      final card = _card(id: 1, interval: 5, repetitions: 4);
      final result = filterCollection(SmartCollectionType.mature, [card]);
      expect(result, isEmpty);
    });
  });

  test('collectionLabel returns a distinct label for every type', () {
    final labels = SmartCollectionType.values.map(collectionLabel).toSet();
    expect(labels, hasLength(SmartCollectionType.values.length));
  });
}
