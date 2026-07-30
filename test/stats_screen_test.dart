import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flashcard_app/database/database.dart';
import 'package:flashcard_app/screens/stats_screen.dart';
import 'package:flashcard_app/theme/app_theme.dart';

void main() {
  testWidgets('shows an empty state before any review is logged', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(theme: buildLightTheme(), home: const StatsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No reviews yet'), findsOneWidget);

    await db.close();
  });

  testWidgets('shows totals and the study calendar once reviews are logged', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final deckId = await db.into(db.decks).insert(DecksCompanion.insert(name: 'Deck'));
    final cardId = await db.into(db.cards).insert(
          CardsCompanion.insert(deckId: deckId, front: 'Front', back: 'Back'),
        );
    await db.logReview(cardId, 3, DateTime.now());
    await db.logReview(cardId, 0, DateTime.now());
    await db.logReview(cardId, 4, DateTime.now().subtract(const Duration(days: 1)));

    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(theme: buildLightTheme(), home: const StatsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget); // total reviews
    expect(find.text('67%'), findsOneWidget); // 2 of 3 remembered
    expect(find.text('Last 5 weeks'), findsOneWidget);
    expect(tester.takeException(), null);

    await db.close();
  });
}
