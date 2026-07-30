import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashcard_app/database/database.dart';
import 'package:flashcard_app/screens/deck_list_screen.dart';
import 'package:flashcard_app/theme/app_theme.dart';

void main() {
  // DeckListScreen reads the study streak from SharedPreferences; reset it
  // between tests so streak state can't leak across them. Onboarding is
  // marked seen so its first-launch sheet doesn't block these tests, which
  // aren't testing onboarding — see onboarding_test.dart for that.
  setUp(() => SharedPreferences.setMockInitialValues({'has_seen_onboarding': true}));

  testWidgets('DeckListScreen shows empty state and adds a deck', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(theme: buildLightTheme(), home: const DeckListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Empty state.
    expect(find.text('No decks yet'), findsOneWidget);
    expect(find.text('New Deck'), findsOneWidget);

    // Tap the FAB to open EditDeckScreen.
    await tester.tap(find.text('New Deck'));
    await tester.pumpAndSettle();
    expect(find.text('New Deck'), findsWidgets); // AppBar title + FAB label

    // Fill deck name and description.
    await tester.enterText(find.byType(TextField).at(0), 'Test Deck');
    await tester.enterText(find.byType(TextField).at(1), 'A deck for testing');

    // Add a card.
    await tester.enterText(find.byType(TextField).at(2), 'Front');
    await tester.enterText(find.byType(TextField).at(3), 'Back');
    await tester.tap(find.text('Add Card'));
    await tester.pumpAndSettle();

    // Tap Save to go back.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Deck should appear in the list.
    expect(find.text('Test Deck'), findsOneWidget);
    expect(find.text('A deck for testing'), findsOneWidget);

    await db.close();
  });

  testWidgets('Focus Mode shows the total due count and starts a cross-deck session', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final deckAId = await db.into(db.decks).insert(DecksCompanion.insert(name: 'Deck A'));
    final deckBId = await db.into(db.decks).insert(DecksCompanion.insert(name: 'Deck B'));
    await db.into(db.cards).insert(
          CardsCompanion.insert(deckId: deckAId, front: 'Question A', back: 'Answer A'),
        );
    await db.into(db.cards).insert(
          CardsCompanion.insert(
            deckId: deckBId,
            front: 'Question B',
            back: 'Answer B',
            nextReview: Value(DateTime.now().add(const Duration(days: 30))),
          ),
        );

    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(theme: buildLightTheme(), home: const DeckListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Only the card from Deck A is due today.
    expect(find.text('1 card due'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    // Cross-deck study screen: titled "Today", shows the one due card.
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Question A'), findsOneWidget);

    await db.close();
  });

  testWidgets('completing a study session shows a 1-day streak back on the deck list', (
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
        child: MaterialApp(theme: buildLightTheme(), home: const DeckListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // No streak yet — nothing has been studied. Check the streak's exact
    // "N day(s)" text rather than the bare substring "day" — the daily-goal
    // progress text ("N / 20 today's goal") also contains "day" and is
    // present regardless of streak state.
    expect(find.text('1 day'), findsNothing);

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('flip-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to Decks'));
    await tester.pumpAndSettle();

    expect(find.text('1 day'), findsOneWidget);
    // Rating one card awards XP (still level 1) and counts once toward the
    // default 20-card daily goal.
    expect(find.text('Lv. 1'), findsOneWidget);
    expect(find.text('1 / 20 today\'s goal'), findsOneWidget);

    await db.close();
  });

  testWidgets('shows level and daily goal progress before any studying', (
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
        child: MaterialApp(theme: buildLightTheme(), home: const DeckListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lv. 1'), findsOneWidget);
    expect(find.text('0 / 20 today\'s goal'), findsOneWidget);

    await db.close();
  });

  testWidgets('renders under dark theme without error', (
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
        child: MaterialApp(theme: buildDarkTheme(), home: const DeckListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), null);
    expect(find.text('Deck'), findsOneWidget);

    await db.close();
  });

  testWidgets('Smart Collections chip starts a filtered, due-date-ignoring session', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final deckId = await db.into(db.decks).insert(DecksCompanion.insert(name: 'Deck'));
    // A mature card, not due for a long time — only reachable via the collection.
    await db.into(db.cards).insert(
          CardsCompanion.insert(
            deckId: deckId,
            front: 'Mature Card',
            back: 'Back',
            interval: const Value(30),
            repetitions: const Value(4),
            nextReview: Value(DateTime.now().add(const Duration(days: 30))),
          ),
        );

    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(theme: buildLightTheme(), home: const DeckListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mature Cards (1)'), findsOneWidget);

    await tester.tap(find.text('Mature Cards (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Mature Cards'), findsOneWidget);
    expect(find.text('Mature Card'), findsOneWidget);

    await db.close();
  });
}
