import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/importexport/deck_transfer.dart';

void main() {
  group('JSON export/import', () {
    test('round-trips a deck with full SM-2 fields', () {
      final nextReview = DateTime.utc(2026, 8, 1, 9, 30);
      final deck = DeckExport(
        name: 'Spanish Verbs',
        description: 'Irregular verbs',
        cards: [
          CardRecord(
            front: 'hablar',
            back: 'to speak',
            easeFactor: 2.3,
            interval: 14,
            repetitions: 3,
            nextReview: nextReview,
          ),
        ],
      );

      final json = encodeDeckToJson(deck);
      final decoded = decodeDeckFromJson(json);

      expect(decoded.name, 'Spanish Verbs');
      expect(decoded.description, 'Irregular verbs');
      expect(decoded.cards, hasLength(1));
      final card = decoded.cards.first;
      expect(card.front, 'hablar');
      expect(card.back, 'to speak');
      expect(card.easeFactor, 2.3);
      expect(card.interval, 14);
      expect(card.repetitions, 3);
      expect(card.nextReview, nextReview);
    });

    test('description is optional and round-trips as null', () {
      final json = encodeDeckToJson(DeckExport(
        name: 'Deck',
        cards: [CardRecord(front: 'a', back: 'b', nextReview: DateTime.now())],
      ));
      final decoded = decodeDeckFromJson(json);
      expect(decoded.description, isNull);
    });

    test('rejects malformed JSON', () {
      expect(() => decodeDeckFromJson('not json'), throwsA(isA<InvalidDeckFileException>()));
    });

    test('rejects JSON missing a deck name', () {
      expect(() => decodeDeckFromJson('{"cards": []}'), throwsA(isA<InvalidDeckFileException>()));
    });

    test('rejects JSON missing the cards array', () {
      expect(() => decodeDeckFromJson('{"name": "Deck"}'), throwsA(isA<InvalidDeckFileException>()));
    });

    test('rejects a card missing front/back', () {
      expect(
        () => decodeDeckFromJson('{"name": "Deck", "cards": [{"front": "only"}]}'),
        throwsA(isA<InvalidDeckFileException>()),
      );
    });

    test('missing SM-2 fields on a card default to a fresh card', () {
      final decoded = decodeDeckFromJson(
        '{"name": "Deck", "cards": [{"front": "a", "back": "b"}]}',
      );
      final card = decoded.cards.single;
      expect(card.easeFactor, 2.5);
      expect(card.interval, 1);
      expect(card.repetitions, 0);
    });
  });

  group('CSV export/import', () {
    test('round-trips simple front/back pairs', () {
      final csv = encodeCardsToCsv([
        CardRecord(front: 'cat', back: 'gato', nextReview: DateTime.now()),
        CardRecord(front: 'dog', back: 'perro', nextReview: DateTime.now()),
      ]);
      final decoded = decodeCardsFromCsv(csv);

      expect(decoded, hasLength(2));
      expect(decoded[0].front, 'cat');
      expect(decoded[0].back, 'gato');
      expect(decoded[1].front, 'dog');
      expect(decoded[1].back, 'perro');
    });

    test('imported cards start fresh regardless of source', () {
      final decoded = decodeCardsFromCsv('front,back\nhello,hola');
      expect(decoded.single.easeFactor, 2.5);
      expect(decoded.single.interval, 1);
      expect(decoded.single.repetitions, 0);
    });

    test('handles a header row case-insensitively', () {
      final decoded = decodeCardsFromCsv('Front,Back\nhello,hola');
      expect(decoded, hasLength(1));
      expect(decoded.single.front, 'hello');
    });

    test('handles a file with no header row', () {
      final decoded = decodeCardsFromCsv('hello,hola\nbye,adios');
      expect(decoded, hasLength(2));
      expect(decoded[0].front, 'hello');
      expect(decoded[1].front, 'bye');
    });

    test('fields containing commas are quoted and round-trip correctly', () {
      final csv = encodeCardsToCsv([
        CardRecord(front: 'What is 2, 3, and 4?', back: 'Numbers, obviously', nextReview: DateTime.now()),
      ]);
      final decoded = decodeCardsFromCsv(csv);
      expect(decoded.single.front, 'What is 2, 3, and 4?');
      expect(decoded.single.back, 'Numbers, obviously');
    });

    test('fields containing quotes round-trip correctly', () {
      final csv = encodeCardsToCsv([
        CardRecord(front: 'Say "hello"', back: 'The word "hola"', nextReview: DateTime.now()),
      ]);
      final decoded = decodeCardsFromCsv(csv);
      expect(decoded.single.front, 'Say "hello"');
      expect(decoded.single.back, 'The word "hola"');
    });

    test('blank lines and rows missing a back value are skipped', () {
      final decoded = decodeCardsFromCsv('front,back\nhello,hola\n\nincomplete');
      expect(decoded, hasLength(1));
      expect(decoded.single.front, 'hello');
    });

    test('empty input decodes to an empty list', () {
      expect(decodeCardsFromCsv(''), isEmpty);
    });
  });
}
