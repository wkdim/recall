import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flashcard_app/database/database.dart';
import 'package:flashcard_app/main.dart';

void main() {
  testWidgets('App boots to the deck list screen', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    await tester.pumpWidget(
      Provider<AppDatabase>(
        create: (_) => db,
        dispose: (_, db) => db.close(),
        child: const FlashcardApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('My Decks'), findsOneWidget);
    expect(find.text('No decks yet'), findsOneWidget);

    await db.close();
  });
}
