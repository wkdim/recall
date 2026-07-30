import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashcard_app/database/database.dart';
import 'package:flashcard_app/screens/deck_list_screen.dart';
import 'package:flashcard_app/theme/app_theme.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the onboarding sheet on first launch and only once', (
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

    expect(find.text('Welcome to Recall'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Recall'), findsNothing);

    await db.close();
  });

  testWidgets('does not show the onboarding sheet once already seen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'has_seen_onboarding': true});
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: MaterialApp(theme: buildLightTheme(), home: const DeckListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Recall'), findsNothing);
    expect(find.text('My Decks'), findsOneWidget);

    await db.close();
  });
}
