import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/cloze/cloze_parser.dart';

void main() {
  group('hasClozeMarker', () {
    test('detects a single cloze marker', () {
      expect(hasClozeMarker('Paris is the {{c::capital}} of France'), isTrue);
    });

    test('returns false for plain text', () {
      expect(hasClozeMarker('What is the capital of France?'), isFalse);
    });
  });

  group('maskCloze', () {
    test('replaces a single cloze span with a blank', () {
      expect(
        maskCloze('Paris is the {{c::capital}} of France'),
        'Paris is the [...] of France',
      );
    });

    test('replaces multiple cloze spans, each with its own blank', () {
      expect(
        maskCloze('{{c::Paris}} is the capital of {{c::France}}'),
        '[...] is the capital of [...]',
      );
    });

    test('leaves text with no cloze markers unchanged', () {
      expect(maskCloze('plain text'), 'plain text');
    });
  });

  group('revealCloze', () {
    test('replaces a single cloze span with its answer', () {
      expect(
        revealCloze('Paris is the {{c::capital}} of France'),
        'Paris is the capital of France',
      );
    });

    test('replaces multiple cloze spans with their answers', () {
      expect(
        revealCloze('{{c::Paris}} is the capital of {{c::France}}'),
        'Paris is the capital of France',
      );
    });
  });
}
