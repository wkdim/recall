import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/ai/flashcard_generator.dart';

void main() {
  group('parseGeneratedCards', () {
    test('parses a clean JSON array', () {
      final cards = parseGeneratedCards(
        '[{"front": "Capital of France?", "back": "Paris"}, {"front": "2+2", "back": "4"}]',
      );
      expect(cards.length, 2);
      expect(cards[0].front, 'Capital of France?');
      expect(cards[0].back, 'Paris');
      expect(cards[1].back, '4');
    });

    test('tolerates markdown code fences and preamble text', () {
      final cards = parseGeneratedCards('''
Here are your flashcards:
```json
[{"front": "Q", "back": "A"}]
```
Let me know if you need more!
''');
      expect(cards.length, 1);
      expect(cards.single.front, 'Q');
    });

    test('trims whitespace from front/back', () {
      final cards = parseGeneratedCards('[{"front": "  Q  ", "back": "  A  "}]');
      expect(cards.single.front, 'Q');
      expect(cards.single.back, 'A');
    });

    test('skips entries missing front or back', () {
      final cards = parseGeneratedCards(
        '[{"front": "Q1", "back": "A1"}, {"front": "Q2"}, {"back": "A3"}]',
      );
      expect(cards.length, 1);
      expect(cards.single.front, 'Q1');
    });

    test('skips entries with empty front or back', () {
      final cards = parseGeneratedCards(
        '[{"front": "Q1", "back": "A1"}, {"front": "", "back": "A2"}]',
      );
      expect(cards.length, 1);
    });

    test('throws when there is no bracketed list at all', () {
      expect(
        () => parseGeneratedCards('Sorry, I cannot help with that.'),
        throwsA(isA<FlashcardGenerationException>()),
      );
    });

    test('throws on malformed JSON inside the brackets', () {
      expect(
        () => parseGeneratedCards('[{"front": "Q", "back": }]'),
        throwsA(isA<FlashcardGenerationException>()),
      );
    });

    test('throws when every entry is unusable', () {
      expect(
        () => parseGeneratedCards('[{"front": ""}, {"back": ""}]'),
        throwsA(isA<FlashcardGenerationException>()),
      );
    });
  });

  group('parseImprovedCard', () {
    test('parses a clean JSON object', () {
      final card = parseImprovedCard('{"front": "Better Q?", "back": "Better A"}');
      expect(card.front, 'Better Q?');
      expect(card.back, 'Better A');
    });

    test('tolerates markdown code fences and preamble text', () {
      final card = parseImprovedCard('''
Here's a tighter version:
```json
{"front": "Q", "back": "A"}
```
''');
      expect(card.front, 'Q');
      expect(card.back, 'A');
    });

    test('trims whitespace from front/back', () {
      final card = parseImprovedCard('{"front": "  Q  ", "back": "  A  "}');
      expect(card.front, 'Q');
      expect(card.back, 'A');
    });

    test('throws when there is no braced object at all', () {
      expect(
        () => parseImprovedCard('I cannot help with that.'),
        throwsA(isA<FlashcardGenerationException>()),
      );
    });

    test('throws on malformed JSON inside the braces', () {
      expect(
        () => parseImprovedCard('{"front": "Q", "back": }'),
        throwsA(isA<FlashcardGenerationException>()),
      );
    });

    test('throws when front or back is missing', () {
      expect(
        () => parseImprovedCard('{"front": "Q"}'),
        throwsA(isA<FlashcardGenerationException>()),
      );
    });

    test('throws when front or back is empty', () {
      expect(
        () => parseImprovedCard('{"front": "", "back": "A"}'),
        throwsA(isA<FlashcardGenerationException>()),
      );
    });
  });
}
