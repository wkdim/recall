import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/tags/tag_utils.dart';

void main() {
  group('parseTags', () {
    test('splits and trims a comma-separated string', () {
      expect(parseTags('verbs, irregular ,common'), ['verbs', 'irregular', 'common']);
    });

    test('drops empty segments from stray commas', () {
      expect(parseTags('verbs,,irregular,'), ['verbs', 'irregular']);
    });

    test('null and empty input produce an empty list', () {
      expect(parseTags(null), isEmpty);
      expect(parseTags(''), isEmpty);
      expect(parseTags('   '), isEmpty);
    });
  });

  group('encodeTags', () {
    test('joins tags with commas, trimming and dropping empties', () {
      expect(encodeTags([' verbs ', 'irregular', '']), 'verbs,irregular');
    });

    test('empty list encodes to an empty string', () {
      expect(encodeTags([]), '');
    });

    test('round-trips through parseTags', () {
      final original = ['verbs', 'irregular', 'common'];
      expect(parseTags(encodeTags(original)), original);
    });
  });

  group('cardMatchesQuery', () {
    test('empty query matches everything', () {
      expect(cardMatchesQuery(front: 'hablar', back: 'to speak', query: ''), isTrue);
    });

    test('matches on front text, case-insensitively', () {
      expect(cardMatchesQuery(front: 'Hablar', back: 'to speak', query: 'HABLAR'), isTrue);
    });

    test('matches on back text', () {
      expect(cardMatchesQuery(front: 'hablar', back: 'to speak', query: 'speak'), isTrue);
    });

    test('matches on tags', () {
      expect(
        cardMatchesQuery(front: 'hablar', back: 'to speak', tags: 'verbs,irregular', query: 'irregular'),
        isTrue,
      );
    });

    test('does not match unrelated text', () {
      expect(cardMatchesQuery(front: 'hablar', back: 'to speak', query: 'xyz'), isFalse);
    });
  });
}
