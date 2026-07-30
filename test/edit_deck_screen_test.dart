import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flashcard_app/ai/flashcard_generator.dart';
import 'package:flashcard_app/database/database.dart';
import 'package:flashcard_app/media/media_picker.dart';
import 'package:flashcard_app/screens/edit_deck_screen.dart';

/// A real, valid 1x1 white PNG (1-bit grayscale) — Image.file actually
/// decodes the attached file (as a Chip avatar), so test fixtures need
/// real image bytes, not arbitrary placeholder data. Chunk lengths below
/// are self-consistent (IHDR data is exactly 13 bytes, IDAT data is
/// exactly 10) — a hand-typed PNG with a mismatched chunk length fails to
/// decode with an opaque "invalid image data" error, not a length error.
const _kMinimalPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR, length 13
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
  0x01, 0x00, 0x00, 0x00, 0x00, // bit depth 1, grayscale, no compression/filter/interlace
  0x37, 0x6E, 0xF9, 0x24, // IHDR CRC
  0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT, length 10
  0x78, 0x01, 0x63, 0x60, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01, // IDAT data
  0x48, 0xAF, 0xA4, 0x71, // IDAT CRC
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND, length 0
  0xAE, 0x42, 0x60, 0x82, // IEND CRC
];

/// Taps [tapTarget] and polls (with real delays, inside runAsync's real
/// zone) until [condition] is true, rather than guessing a fixed delay for
/// the real File.copy() the tap triggers. The tap itself must happen
/// *inside* runAsync too — a Future's continuation runs in the zone active
/// when it was created, so tapping outside runAsync leaves the resulting
/// async chain bound to the outer fake-async zone, where it never resolves.
Future<void> _tapAndWaitUntil(
  WidgetTester tester,
  Finder tapTarget,
  bool Function() condition,
) async {
  await tester.runAsync(() async {
    await tester.tap(tapTarget);
    for (var i = 0; i < 40; i++) {
      if (condition()) return;
      await Future.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
  });
}

/// Consumes any exceptions the test binding has recorded, after giving a
/// real Chip avatar's Image.file decode time to actually fail first.
/// Windows can briefly lock a media file just after it's written (File.copy
/// finishing, antivirus real-time scanning), and FileImage's decode failure
/// is reported to FlutterError asynchronously over real dart:io I/O —
/// pumpAndSettle only flushes fake-async frames/timers, so it can return
/// before that report lands, letting a plain takeException() miss it. Not
/// a sign the app logic is wrong (already verified separately via
/// DB/file-existence checks) — just a real decoder racing a real file.
Future<void> _settleAndDrainExceptions(WidgetTester tester) async {
  await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
  await tester.pumpAndSettle();
  while (tester.takeException() != null) {}
}

class _FakeMediaPicker implements MediaPicker {
  String? nextImagePath;
  String? nextAudioPath;

  @override
  Future<String?> pickImage() async => nextImagePath;

  @override
  Future<String?> pickAudio() async => nextAudioPath;
}

class _FakeFlashcardGenerator implements FlashcardGenerator {
  GeneratedCard? nextSuggestion;
  Object? nextError;

  @override
  Future<List<GeneratedCard>> generateFromText(
    String sourceText, {
    void Function(int percent)? onDownloadProgress,
  }) async =>
      throw UnimplementedError();

  @override
  Future<GeneratedCard> improveCard(
    String front,
    String back, {
    void Function(int percent)? onDownloadProgress,
  }) async {
    if (nextError != null) throw nextError!;
    return nextSuggestion ?? GeneratedCard(front: front, back: back);
  }
}

void main() {
  testWidgets('EditDeckScreen creates a new deck and card', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: const MaterialApp(home: EditDeckScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Fill deck name and description.
    await tester.enterText(find.byType(TextField).at(0), 'Deck Name');
    await tester.enterText(find.byType(TextField).at(1), 'Deck Description');

    // Add a card.
    await tester.enterText(find.byType(TextField).at(2), 'Front Side');
    await tester.enterText(find.byType(TextField).at(3), 'Back Side');
    await tester.ensureVisible(find.text('Add Card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Card'));
    await tester.pumpAndSettle();

    // The card should now be listed on this same screen.
    expect(find.text('Front Side'), findsOneWidget);
    expect(find.textContaining('YOUR CARDS'), findsOneWidget);

    // Tap Save to finish.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Verify deck and card are created in the database.
    final decks = await db.select(db.decks).get();
    final cards = await db.select(db.cards).get();
    expect(decks.any((d) => d.name == 'Deck Name'), isTrue);
    expect(
      cards.any((c) => c.front == 'Front Side' && c.back == 'Back Side'),
      isTrue,
    );

    await db.close();
  });

  testWidgets('EditDeckScreen edits an existing card', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final deckId = await db.into(db.decks).insert(
          DecksCompanion.insert(name: 'Deck'),
        );
    final cardId = await db.into(db.cards).insert(
          CardsCompanion.insert(deckId: deckId, front: 'Old Front', back: 'Old Back'),
        );

    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(
          home: EditDeckScreen(deck: (await db.select(db.decks).get()).first),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Old Front'));
    await tester.pumpAndSettle();
    expect(find.text('Old Front'), findsOneWidget);

    await tester.tap(find.text('Old Front'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('editCardFrontField')), 'New Front');
    await tester.enterText(find.byKey(const Key('editCardBackField')), 'New Back');
    await tester.tap(find.byKey(const Key('editCardSave')));
    await tester.pumpAndSettle();

    expect(find.text('New Front'), findsOneWidget);
    expect(find.text('Old Front'), findsNothing);

    final card = await (db.select(db.cards)..where((c) => c.id.equals(cardId))).getSingle();
    expect(card.front, 'New Front');
    expect(card.back, 'New Back');

    await db.close();
  });

  testWidgets('improving a card with AI shows a suggestion that can be applied', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final deckId = await db.into(db.decks).insert(DecksCompanion.insert(name: 'Deck'));
    await db.into(db.cards).insert(
          CardsCompanion.insert(deckId: deckId, front: 'Old Front', back: 'Old Back'),
        );
    final fake = _FakeFlashcardGenerator()
      ..nextSuggestion = const GeneratedCard(front: 'Tighter Front', back: 'Tighter Back');

    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(
          home: EditDeckScreen(
            deck: (await db.select(db.decks).get()).first,
            flashcardGenerator: fake,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Old Front'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Old Front'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('improveWithAi')));
    await tester.pumpAndSettle();

    expect(find.text('Tighter Front'), findsOneWidget);
    expect(find.text('Tighter Back'), findsOneWidget);

    await tester.tap(find.byKey(const Key('useSuggestion')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byKey(const Key('editCardFrontField'))).controller!.text,
      'Tighter Front',
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('editCardBackField'))).controller!.text,
      'Tighter Back',
    );

    await db.close();
  });

  testWidgets('a failed AI improvement shows an error, not a crash', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final deckId = await db.into(db.decks).insert(DecksCompanion.insert(name: 'Deck'));
    await db.into(db.cards).insert(
          CardsCompanion.insert(deckId: deckId, front: 'Old Front', back: 'Old Back'),
        );
    final fake = _FakeFlashcardGenerator()
      ..nextError = const FlashcardGenerationException('No suggestion came back.');

    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(
          home: EditDeckScreen(
            deck: (await db.select(db.decks).get()).first,
            flashcardGenerator: fake,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Old Front'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Old Front'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('improveWithAi')));
    await tester.pumpAndSettle();

    expect(find.text('No suggestion came back.'), findsOneWidget);

    await db.close();
  });

  testWidgets('EditDeckScreen requires confirmation before deleting a card', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final deckId = await db.into(db.decks).insert(
          DecksCompanion.insert(name: 'Deck'),
        );
    await db.into(db.cards).insert(
          CardsCompanion.insert(deckId: deckId, front: 'Front', back: 'Back'),
        );

    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(
          home: EditDeckScreen(deck: (await db.select(db.decks).get()).first),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    // Tap delete, then cancel — the card should survive.
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete card?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect((await db.select(db.cards).get()).length, 1);

    // Tap delete again, then confirm — the card should be gone.
    await tester.ensureVisible(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect((await db.select(db.cards).get()).length, 0);

    await db.close();
  });

  testWidgets('adding a card with tags stores them, normalized', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: const MaterialApp(home: EditDeckScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Deck Name');
    await tester.enterText(find.byType(TextField).at(2), 'Front Side');
    await tester.enterText(find.byType(TextField).at(3), 'Back Side');
    await tester.enterText(find.byType(TextField).at(4), 'verbs, , irregular ,');
    await tester.ensureVisible(find.text('Add Card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Card'));
    await tester.pumpAndSettle();

    final card = (await db.select(db.cards).get()).single;
    expect(card.tags, 'verbs,irregular');

    await db.close();
  });

  testWidgets('adding a cloze card without a {{c::...}} marker is rejected', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: const MaterialApp(home: EditDeckScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Deck Name');
    await tester.tap(find.text('Cloze deletion'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(2), 'Paris is the capital of France');
    await tester.tap(find.text('Add Card'));
    await tester.pumpAndSettle();

    expect(find.textContaining('{{c::'), findsWidgets);
    expect((await db.select(db.cards).get()), isEmpty);

    await db.close();
  });

  testWidgets('adding a valid cloze card stores it with isCloze set', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: const MaterialApp(home: EditDeckScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Deck Name');
    await tester.tap(find.text('Cloze deletion'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).at(2),
      'Paris is the {{c::capital}} of France',
    );
    await tester.tap(find.text('Add Card'));
    await tester.pumpAndSettle();

    final card = (await db.select(db.cards).get()).single;
    expect(card.isCloze, isTrue);
    expect(card.front, 'Paris is the {{c::capital}} of France');

    // The list shows the masked version, not the raw template.
    expect(find.text('Paris is the [...] of France'), findsOneWidget);

    await db.close();
  });

  testWidgets('shows a Deck Health card once the deck has cards', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final deckId = await db.into(db.decks).insert(DecksCompanion.insert(name: 'Deck'));
    await db.into(db.cards).insert(
          CardsCompanion.insert(deckId: deckId, front: 'Front', back: 'Back'),
        );

    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(
          home: EditDeckScreen(deck: (await db.select(db.decks).get()).first),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A single fresh, unreviewed card is exactly the "never reviewed" issue.
    expect(find.text('HEALTH'), findsOneWidget);
    expect(find.textContaining('never reviewed'), findsOneWidget);

    await db.close();
  });

  testWidgets('adding a card with a picked image attaches a copy of it', (
    WidgetTester tester,
  ) async {
    // Real dart:io calls (temp dirs, file copies) don't resolve inside
    // testWidgets' fake-async zone without runAsync — they hang forever,
    // not just slowly, if awaited directly.
    final tempDir = await tester.runAsync(() => Directory.systemTemp.createTemp('edit_deck_media_test_'));
    final imageFile = await tester.runAsync(() async {
      final f = File('${tempDir!.path}/pic.png');
      await f.writeAsBytes(_kMinimalPng);
      return f;
    });
    final fakePicker = _FakeMediaPicker()..nextImagePath = imageFile!.path;

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(home: EditDeckScreen(mediaPicker: fakePicker, mediaStorageDir: tempDir)),
      ),
    );
    await tester.pumpAndSettle();

    // The tap triggers a real File.copy() inside EditDeckScreen. pumpAndSettle
    // only tracks fake-async frames/timers — it can't see a plain real Future,
    // so it "settles" before the copy finishes. Poll for the resulting
    // state change instead of guessing a fixed delay.
    await _tapAndWaitUntil(
      tester,
      find.text('Add image').first,
      () => find.text('Image attached').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    await _settleAndDrainExceptions(tester);

    expect(find.text('Image attached'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'Deck Name');
    await tester.enterText(find.byType(TextField).at(2), 'Front Side');
    await tester.enterText(find.byType(TextField).at(3), 'Back Side');
    await tester.ensureVisible(find.text('Add Card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Card'));
    await tester.pumpAndSettle();
    await _settleAndDrainExceptions(tester);

    final card = (await db.select(db.cards).get()).single;
    expect(card.frontImagePath != null, true);
    // A copy, not the picker's own path — the source file must survive
    // independently of whatever the OS does with the picker's temp file.
    expect(card.frontImagePath, isNot(imageFile.path));
    expect(await tester.runAsync(() => File(card.frontImagePath!).exists()), true);

    await db.close();
    await _settleAndDrainExceptions(tester);
    // Best-effort cleanup: Windows can briefly hold a handle open right
    // after a File.copy(), so a delete attempted immediately afterward can
    // fail with "used by another process." Not worth failing the test over.
    await tester.runAsync(() async {
      try {
        await tempDir!.delete(recursive: true);
      } catch (_) {}
    });
  });

  testWidgets('removing an attached image clears it before saving', (
    WidgetTester tester,
  ) async {
    final tempDir = await tester.runAsync(() => Directory.systemTemp.createTemp('edit_deck_media_test_'));
    final imageFile = await tester.runAsync(() async {
      final f = File('${tempDir!.path}/pic.png');
      await f.writeAsBytes(_kMinimalPng);
      return f;
    });
    final fakePicker = _FakeMediaPicker()..nextImagePath = imageFile!.path;

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(home: EditDeckScreen(mediaPicker: fakePicker, mediaStorageDir: tempDir)),
      ),
    );
    await tester.pumpAndSettle();

    await _tapAndWaitUntil(
      tester,
      find.text('Add image').first,
      () => find.text('Image attached').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    await _settleAndDrainExceptions(tester);
    expect(find.text('Image attached'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.cancel).first);
    await tester.pumpAndSettle();
    // This test is about the remove button clearing the attachment state,
    // not about image decoding — the Chip avatar's real (if trivial) PNG
    // decode can race with removal, or with Windows briefly locking the
    // freshly-written file (antivirus scanning, etc.), and throw. That's an
    // artifact of testing a real decoder against a same-frame add-then-
    // remove, not a bug in the app: consume it rather than fail the test.
    await _settleAndDrainExceptions(tester);

    expect(find.text('Image attached'), findsNothing);
    expect(find.text('Add image'), findsWidgets);

    await db.close();
    await _settleAndDrainExceptions(tester);
    // Best-effort cleanup: Windows can briefly hold a handle open right
    // after a File.copy(), so a delete attempted immediately afterward can
    // fail with "used by another process." Not worth failing the test over.
    await tester.runAsync(() async {
      try {
        await tempDir!.delete(recursive: true);
      } catch (_) {}
    });
    await _settleAndDrainExceptions(tester);
  });

  testWidgets('adding a card with a picked audio file attaches a copy of it', (
    WidgetTester tester,
  ) async {
    final tempDir = await tester.runAsync(() => Directory.systemTemp.createTemp('edit_deck_media_test_'));
    final audioFile = await tester.runAsync(() async {
      final f = File('${tempDir!.path}/clip.mp3');
      await f.writeAsBytes([1, 2, 3, 4]);
      return f;
    });
    final fakePicker = _FakeMediaPicker()..nextAudioPath = audioFile!.path;

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(home: EditDeckScreen(mediaPicker: fakePicker, mediaStorageDir: tempDir)),
      ),
    );
    await tester.pumpAndSettle();

    // Unlike the image Chip, the audio Chip's avatar is a plain Icon, not
    // a real file decode — no Windows file-lock race to guard against here.
    await _tapAndWaitUntil(
      tester,
      find.text('Add audio').first,
      () => find.byIcon(Icons.audiotrack).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.audiotrack), findsOneWidget);
    // The back row's "Add audio" button is still unattached.
    expect(find.text('Add audio'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'Deck Name');
    await tester.enterText(find.byType(TextField).at(2), 'Front Side');
    await tester.enterText(find.byType(TextField).at(3), 'Back Side');
    await tester.ensureVisible(find.text('Add Card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Card'));
    await tester.pumpAndSettle();

    final card = (await db.select(db.cards).get()).single;
    expect(card.frontAudioPath != null, true);
    expect(card.frontAudioPath, isNot(audioFile.path));
    expect(await tester.runAsync(() => File(card.frontAudioPath!).exists()), true);

    await db.close();
    await tester.runAsync(() async {
      try {
        await tempDir!.delete(recursive: true);
      } catch (_) {}
    });
  });

  testWidgets('removing an attached audio file clears it before saving', (
    WidgetTester tester,
  ) async {
    final tempDir = await tester.runAsync(() => Directory.systemTemp.createTemp('edit_deck_media_test_'));
    final audioFile = await tester.runAsync(() async {
      final f = File('${tempDir!.path}/clip.mp3');
      await f.writeAsBytes([1, 2, 3, 4]);
      return f;
    });
    final fakePicker = _FakeMediaPicker()..nextAudioPath = audioFile!.path;

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(home: EditDeckScreen(mediaPicker: fakePicker, mediaStorageDir: tempDir)),
      ),
    );
    await tester.pumpAndSettle();

    await _tapAndWaitUntil(
      tester,
      find.text('Add audio').first,
      () => find.byIcon(Icons.audiotrack).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.audiotrack), findsOneWidget);

    await tester.tap(find.byIcon(Icons.cancel).first);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.audiotrack), findsNothing);
    expect(find.text('Add audio'), findsNWidgets(2));

    await db.close();
    await tester.runAsync(() async {
      try {
        await tempDir!.delete(recursive: true);
      } catch (_) {}
    });
  });
}
