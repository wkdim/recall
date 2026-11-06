import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flashcard_app/ai/flashcard_generator.dart';
import 'package:flashcard_app/database/database.dart';
import 'package:flashcard_app/screens/generate_cards_screen.dart';

class _FakeGenerator implements FlashcardGenerator {
  final List<GeneratedCard>? cards;
  final Object? error;
  final int? progressToReport;

  /// When set, [generateFromText] suspends here after reporting progress -
  /// lets a test pump exactly once and observe the in-flight download-progress
  /// frame before letting generation "complete".
  final Completer<void>? gate;

  _FakeGenerator({this.cards, this.error, this.progressToReport, this.gate});

  @override
  Future<List<GeneratedCard>> generateFromText(
    String sourceText, {
    void Function(int percent)? onDownloadProgress,
  }) async {
    if (progressToReport != null) onDownloadProgress?.call(progressToReport!);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return cards ?? [];
  }

  @override
  Future<GeneratedCard> improveCard(
    String front,
    String back, {
    void Function(int percent)? onDownloadProgress,
  }) async =>
      throw UnimplementedError();
}

void main() {
  testWidgets('generating cards shows a reviewable, selectable list', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final deckId = await db.into(db.decks).insert(DecksCompanion.insert(name: 'Deck'));
    final fake = _FakeGenerator(cards: const [
      GeneratedCard(front: 'Q1', back: 'A1'),
      GeneratedCard(front: 'Q2', back: 'A2'),
    ]);

    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(home: GenerateCardsScreen(deckId: deckId, generator: fake)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Some source text about geography.');
    await tester.tap(find.text('Generate Cards'));
    await tester.pumpAndSettle();

    expect(find.text('Q1'), findsOneWidget);
    expect(find.text('Q2'), findsOneWidget);
    expect(find.text('Add 2 Cards'), findsOneWidget);

    // Deselect the first card.
    await tester.tap(find.text('Q1'));
    await tester.pumpAndSettle();
    expect(find.text('Add 1 Card'), findsOneWidget);

    await tester.tap(find.text('Add 1 Card'));
    await tester.pumpAndSettle();

    final cards = await db.select(db.cards).get();
    expect(cards.length, 1);
    expect(cards.single.front, 'Q2');

    await db.close();
  });

  testWidgets('a generation failure shows an error with a retry option', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final deckId = await db.into(db.decks).insert(DecksCompanion.insert(name: 'Deck'));
    final fake = _FakeGenerator(
      error: const FlashcardGenerationException('No usable cards came back.'),
    );

    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(home: GenerateCardsScreen(deckId: deckId, generator: fake)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Text.');
    await tester.tap(find.text('Generate Cards'));
    await tester.pumpAndSettle();

    expect(find.text('No usable cards came back.'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);

    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(find.text('Generate Cards'), findsOneWidget);

    await db.close();
  });

  testWidgets('shows download progress before the generated list appears', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final deckId = await db.into(db.decks).insert(DecksCompanion.insert(name: 'Deck'));
    final gate = Completer<void>();
    final fake = _FakeGenerator(
      cards: const [GeneratedCard(front: 'Q', back: 'A')],
      progressToReport: 42,
      gate: gate,
    );

    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(home: GenerateCardsScreen(deckId: deckId, generator: fake)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Text.');
    await tester.tap(find.text('Generate Cards'));
    // One pump (not settle) to observe the in-flight download-progress frame
    // - generateFromText is suspended on the gate, so this is stable rather
    // than racing whatever's left of a real async chain.
    await tester.pump();

    expect(find.textContaining('Downloading on-device model: 42%'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Q'), findsOneWidget);

    await db.close();
  });
}
