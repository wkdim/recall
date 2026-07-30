import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashcard_app/database/database.dart';
import 'package:flashcard_app/gamification/daily_goal.dart';
import 'package:flashcard_app/gamification/xp_tracker.dart';
import 'package:flashcard_app/screens/study_screen.dart';
import 'package:flashcard_app/theme/app_theme.dart';

void main() {
  // StudyScreen records a study streak via SharedPreferences on each rating;
  // reset it between tests so streak state can't leak across them.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('StudyScreen shows a due card, flips it, and rates it', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final deckId = await db.into(db.decks).insert(
          DecksCompanion.insert(name: 'Test Deck', description: const Value('desc')),
        );
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

    // Card front should be visible.
    expect(find.text('Front'), findsOneWidget);
    expect(find.text('Back'), findsNothing);

    // Tap to flip the card.
    await tester.tap(find.byKey(const ValueKey('flip-card')));
    await tester.pumpAndSettle();
    expect(find.text('Back'), findsOneWidget);

    // Rate the card as Good.
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();

    // A single due card means the session summary shows right away.
    expect(find.text('Session Complete!'), findsOneWidget);
    expect(find.textContaining('You reviewed 1 card'), findsOneWidget);

    await db.close();
  });

  testWidgets('swiping right on the answer rates the card and advances the session', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final deckId = await db.into(db.decks).insert(DecksCompanion.insert(name: 'Deck'));
    await db.into(db.cards).insert(
          CardsCompanion.insert(deckId: deckId, front: 'First', back: 'FirstBack'),
        );
    await db.into(db.cards).insert(
          CardsCompanion.insert(deckId: deckId, front: 'Second', back: 'SecondBack'),
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
    expect(find.text('First'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('flip-card')));
    await tester.pumpAndSettle();
    expect(find.text('FirstBack'), findsOneWidget);

    // Swipe right (fling with a strong rightward velocity) to rate as Good.
    await tester.fling(find.byKey(const ValueKey('flip-card')), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();

    // Session advanced to the second card, front-side up again.
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('SecondBack'), findsNothing);

    await db.close();
  });

  testWidgets('swiping while the question is showing does not rate the card', (
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
        child: MaterialApp(theme: buildLightTheme(), home: StudyScreen(deck: deck)),
      ),
    );
    await tester.pumpAndSettle();

    // Swiping before flipping should do nothing — still on the question side.
    await tester.fling(find.byKey(const ValueKey('flip-card')), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Front'), findsOneWidget);
    expect(find.text('Session Complete!'), findsNothing);

    await db.close();
  });

  testWidgets('undo button is absent until a card has been rated', (
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
        child: MaterialApp(theme: buildLightTheme(), home: StudyScreen(deck: deck)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('undo-rating')), findsNothing);

    await db.close();
  });

  testWidgets('undo reverts the card, the review log, and the session tally', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final deckId = await db.into(db.decks).insert(DecksCompanion.insert(name: 'Deck'));
    final cardId = await db.into(db.cards).insert(
          CardsCompanion.insert(deckId: deckId, front: 'Front', back: 'Back'),
        );
    final originalCard = (await db.select(db.cards).get()).first;
    final deck = (await db.select(db.decks).get()).first;

    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(theme: buildLightTheme(), home: StudyScreen(deck: deck)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('flip-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();

    // Rating the only due card ends the session...
    expect(find.text('Session Complete!'), findsOneWidget);
    expect((await db.select(db.reviewLogs).get()).length, 1);

    await tester.tap(find.byKey(const ValueKey('undo-rating')));
    await tester.pumpAndSettle();

    // ...undo puts it right back, as if it was never rated.
    expect(find.text('Session Complete!'), findsNothing);
    expect(find.text('Front'), findsOneWidget);
    expect(find.byKey(const ValueKey('undo-rating')), findsNothing);
    expect((await db.select(db.reviewLogs).get()).length, 0);

    final revertedCard = (await (db.select(db.cards)..where((c) => c.id.equals(cardId))).getSingle());
    expect(revertedCard.easeFactor, originalCard.easeFactor);
    expect(revertedCard.interval, originalCard.interval);
    expect(revertedCard.repetitions, originalCard.repetitions);
    expect(revertedCard.nextReview, originalCard.nextReview);

    await db.close();
  });

  testWidgets('a cloze card shows the masked template first, then the revealed sentence', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final deckId = await db.into(db.decks).insert(DecksCompanion.insert(name: 'Deck'));
    await db.into(db.cards).insert(
          CardsCompanion.insert(
            deckId: deckId,
            front: 'Paris is the {{c::capital}} of France',
            back: '',
            isCloze: const Value(true),
          ),
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

    expect(find.text('Paris is the [...] of France'), findsOneWidget);
    expect(find.text('CLOZE'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('flip-card')));
    await tester.pumpAndSettle();

    expect(find.text('Paris is the capital of France'), findsOneWidget);

    await db.close();
  });

  testWidgets('rating a card under the FSRS scheduler sets stability and difficulty', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'scheduler_type': 'fsrs'});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final deckId = await db.into(db.decks).insert(DecksCompanion.insert(name: 'Deck'));
    final cardId = await db.into(db.cards).insert(
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

    await tester.tap(find.byKey(const ValueKey('flip-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();

    final card = await (db.select(db.cards)..where((c) => c.id.equals(cardId))).getSingle();
    expect(card.stability != null, true);
    expect(card.difficulty != null, true);
    expect(card.stability, 2.4); // FSRS's published initial stability for "Good"
    // SM-2 bookkeeping still advances underneath, for Smart Collections/Deck Health.
    expect(card.repetitions, 1);

    await db.close();
  });

  testWidgets('rating a card awards XP and counts toward the daily goal', (
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
        child: MaterialApp(theme: buildLightTheme(), home: StudyScreen(deck: deck)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('flip-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();

    expect(await XpTracker().totalXp(), xpForRating(3));
    expect(await DailyGoalTracker().todayCount(), 1);

    await db.close();
  });

  testWidgets('crossing a level boundary shows a level-up notification', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'total_xp': kXpPerLevel - xpForRating(4)});
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

    await tester.tap(find.byKey(const ValueKey('flip-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Easy'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Level up! You reached level 2'), findsOneWidget);

    await db.close();
  });

  testWidgets('staying within the same level shows no level-up notification', (
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
        child: MaterialApp(theme: buildLightTheme(), home: StudyScreen(deck: deck)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('flip-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Level up!'), findsNothing);

    await db.close();
  });
}
