import '../database/database.dart';

enum SmartCollectionType { dueToday, forgotten, difficult, recentlyAdded, mature }

String collectionLabel(SmartCollectionType type) {
  switch (type) {
    case SmartCollectionType.dueToday:
      return 'Due Today';
    case SmartCollectionType.forgotten:
      return 'Forgotten Cards';
    case SmartCollectionType.difficult:
      return 'Difficult Cards';
    case SmartCollectionType.recentlyAdded:
      return 'Recently Added';
    case SmartCollectionType.mature:
      return 'Mature Cards';
  }
}

/// Filters a full card list down to one Smart Collection. All heuristics
/// work only from fields already on [Card] — no extra schema needed.
///
/// - Due Today: due for review right now, same rule the study screen uses.
/// - Forgotten: has lapsed at least once (ease pulled below the pristine
///   2.5 default) and reset to zero repetitions — distinct from a card
///   that's simply never been studied, which stays at the 2.5 default.
/// - Difficult: has been reviewed and its ease factor is well below
///   default, meaning it keeps getting rated Again/Hard.
/// - Recently Added: newest by insertion order (autoincrement id), not by
///   review state — there's no separate "created at" timestamp.
/// - Mature: interval of 21+ days with at least 2 successful reviews —
///   the same "mature" threshold Anki uses.
List<Card> filterCollection(
  SmartCollectionType type,
  List<Card> cards, {
  DateTime? now,
  int recentlyAddedLimit = 20,
}) {
  switch (type) {
    case SmartCollectionType.dueToday:
      final today = now ?? DateTime.now();
      return cards.where((c) => !c.nextReview.isAfter(today)).toList();
    case SmartCollectionType.forgotten:
      return cards.where((c) => c.repetitions == 0 && c.easeFactor < 2.5).toList();
    case SmartCollectionType.difficult:
      return cards.where((c) => c.repetitions > 0 && c.easeFactor < 2.0).toList();
    case SmartCollectionType.recentlyAdded:
      final sorted = [...cards]..sort((a, b) => b.id.compareTo(a.id));
      return sorted.take(recentlyAddedLimit).toList();
    case SmartCollectionType.mature:
      return cards.where((c) => c.interval >= 21 && c.repetitions >= 2).toList();
  }
}
