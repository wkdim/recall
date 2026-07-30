import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

part 'database.g.dart';

class Decks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
}

class Cards extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get deckId => integer().references(Decks, #id)();
  TextColumn get front => text()();
  TextColumn get back => text()();
  RealColumn get easeFactor => real().withDefault(const Constant(2.5))();
  IntColumn get interval => integer().withDefault(const Constant(1))();
  IntColumn get repetitions => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextReview => dateTime().withDefault(currentDate)();
  /// Comma-separated tags (e.g. "verbs,irregular") — simple by design;
  /// a join table would be overkill until decks routinely need >100 tags.
  TextColumn get tags => text().nullable()();
  /// When true, `front` holds a cloze template (e.g. "Paris is the
  /// {{c::capital}} of France") instead of a plain question.
  BoolColumn get isCloze => boolean().withDefault(const Constant(false))();
  /// FSRS-specific memory state — null until a card has been reviewed at
  /// least once under the FSRS scheduler; SM-2 fields above are untouched.
  RealColumn get stability => real().nullable()();
  RealColumn get difficulty => real().nullable()();
  /// Absolute paths into this app's own documents directory — never the
  /// picker's original (often cache/temp) path, which the OS can reclaim.
  /// Not included in CSV/JSON export: a local file path is meaningless on
  /// another device, and bundling the actual bytes is a separate feature.
  TextColumn get frontImagePath => text().nullable()();
  TextColumn get backImagePath => text().nullable()();
  TextColumn get frontAudioPath => text().nullable()();
  TextColumn get backAudioPath => text().nullable()();
}

/// One row per rating, kept even after a card is deleted (no FK constraint)
/// so the Stats screen's history stays intact regardless of later edits.
class ReviewLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get cardId => integer()();
  IntColumn get quality => integer()();
  DateTimeColumn get reviewedAt => dateTime()();
}

@DriftDatabase(tables: [Decks, Cards, ReviewLogs])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // Lets tests use an in-memory executor instead of the real on-disk file.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(reviewLogs);
          }
          if (from < 3) {
            await m.addColumn(cards, cards.tags);
            await m.addColumn(cards, cards.isCloze);
            await m.addColumn(cards, cards.stability);
            await m.addColumn(cards, cards.difficulty);
          }
          if (from < 4) {
            await m.addColumn(cards, cards.frontImagePath);
            await m.addColumn(cards, cards.backImagePath);
            await m.addColumn(cards, cards.frontAudioPath);
            await m.addColumn(cards, cards.backAudioPath);
          }
        },
      );

  Future<void> deleteDeckWithCards(int deckId) async {
    final deckCards = await (select(cards)..where((c) => c.deckId.equals(deckId))).get();
    for (final card in deckCards) {
      await _deleteCardMedia(card);
    }
    await (delete(cards)..where((c) => c.deckId.equals(deckId))).go();
    await (delete(decks)..where((d) => d.id.equals(deckId))).go();
  }

  Future<void> deleteCard(int cardId) async {
    final card = await (select(cards)..where((c) => c.id.equals(cardId))).getSingleOrNull();
    if (card != null) await _deleteCardMedia(card);
    await (delete(cards)..where((c) => c.id.equals(cardId))).go();
  }

  Future<void> _deleteCardMedia(Card card) async {
    for (final path in [
      card.frontImagePath,
      card.backImagePath,
      card.frontAudioPath,
      card.backAudioPath,
    ]) {
      if (path == null) continue;
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> updateCard(
    int cardId,
    String front,
    String back, {
    String? tags,
  }) async {
    await (update(cards)..where((c) => c.id.equals(cardId))).write(
      CardsCompanion(
        front: Value(front),
        back: Value(back),
        tags: Value(tags),
      ),
    );
  }

  Future<int> logReview(int cardId, int quality, DateTime reviewedAt) async {
    return into(reviewLogs).insert(
      ReviewLogsCompanion.insert(cardId: cardId, quality: quality, reviewedAt: reviewedAt),
    );
  }

  Future<void> deleteReviewLog(int id) async {
    await (delete(reviewLogs)..where((r) => r.id.equals(id))).go();
  }

  Future<void> updateDeck(int id, String name, String? description) async {
    await (update(decks)..where((d) => d.id.equals(id))).write(
      DecksCompanion(
        name: Value(name),
        description: Value(description),
      ),
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'flashcards.db'));
    return NativeDatabase(file);
  });
}