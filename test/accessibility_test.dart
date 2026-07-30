import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashcard_app/database/database.dart';
import 'package:flashcard_app/screens/deck_list_screen.dart';
import 'package:flashcard_app/screens/study_screen.dart';
import 'package:flashcard_app/theme/app_theme.dart';

void main() {
  // Onboarding marked seen so its first-launch sheet doesn't interfere —
  // these tests aren't testing onboarding.
  setUp(() => SharedPreferences.setMockInitialValues({'has_seen_onboarding': true}));

  testWidgets('DeckListScreen renders without error at 2x text scale', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final deckId = await db.into(db.decks).insert(
          DecksCompanion.insert(name: 'Deck', description: const Value('A description')),
        );
    await db.into(db.cards).insert(
          CardsCompanion.insert(deckId: deckId, front: 'Front', back: 'Back'),
        );

    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(
          theme: buildLightTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: const DeckListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), null);
    expect(find.text('Deck'), findsOneWidget);

    await db.close();
  });

  testWidgets('the flip card exposes a semantic label describing its state', (
    WidgetTester tester,
  ) async {
    final handle = tester.ensureSemantics();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final deckId = await db.into(db.decks).insert(DecksCompanion.insert(name: 'Deck'));
    await db.into(db.cards).insert(
          CardsCompanion.insert(deckId: deckId, front: 'Front', back: 'Back'),
        );
    final deck = (await db.select(db.decks).get()).first;

    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(theme: buildLightTheme(), home: StudyScreen(deck: deck)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(RegExp('Flashcard question: Front')),
      findsOneWidget,
    );

    handle.dispose();
    await db.close();
  });

  testWidgets('reduced-motion setting still flips the card, just without animating', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final deckId = await db.into(db.decks).insert(DecksCompanion.insert(name: 'Deck'));
    await db.into(db.cards).insert(
          CardsCompanion.insert(deckId: deckId, front: 'Front', back: 'Back'),
        );
    final deck = (await db.select(db.decks).get()).first;

    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(
          theme: buildLightTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: StudyScreen(deck: deck),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Front'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('flip-card')));
    // pumpAndSettle, not a bare pump: tap() leaves a short gesture-recognizer
    // timer pending regardless of animation settings. Skipping the settle
    // here left db.close() below waiting on it forever.
    await tester.pumpAndSettle();

    expect(find.text('Back'), findsOneWidget);

    await db.close();
  });
}
