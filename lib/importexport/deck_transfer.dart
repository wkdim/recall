import 'dart:convert';

import 'package:csv/csv.dart';

/// A single card's data, independent of the database row type, so this
/// module can be encoded/decoded/tested without a Drift database.
class CardRecord {
  final String front;
  final String back;
  final double easeFactor;
  final int interval;
  final int repetitions;
  final DateTime nextReview;

  const CardRecord({
    required this.front,
    required this.back,
    this.easeFactor = 2.5,
    this.interval = 1,
    this.repetitions = 0,
    required this.nextReview,
  });
}

/// A deck and its cards, the unit of a JSON export/import.
class DeckExport {
  final String name;
  final String? description;
  final List<CardRecord> cards;

  const DeckExport({
    required this.name,
    this.description,
    required this.cards,
  });
}

class InvalidDeckFileException implements Exception {
  final String message;
  const InvalidDeckFileException(this.message);

  @override
  String toString() => message;
}

/// Full-fidelity JSON export: deck metadata plus every SM-2 field, so a
/// re-import can restore review progress, not just card content.
String encodeDeckToJson(DeckExport deck) {
  final map = {
    'name': deck.name,
    'description': deck.description,
    'cards': deck.cards
        .map((c) => {
              'front': c.front,
              'back': c.back,
              'easeFactor': c.easeFactor,
              'interval': c.interval,
              'repetitions': c.repetitions,
              'nextReview': c.nextReview.toIso8601String(),
            })
        .toList(),
  };
  return const JsonEncoder.withIndent('  ').convert(map);
}

DeckExport decodeDeckFromJson(String jsonStr) {
  final Object? decoded;
  try {
    decoded = jsonDecode(jsonStr);
  } on FormatException {
    throw const InvalidDeckFileException('Not a valid JSON file.');
  }

  if (decoded is! Map<String, dynamic>) {
    throw const InvalidDeckFileException('Expected a JSON object at the top level.');
  }
  final name = decoded['name'];
  if (name is! String || name.trim().isEmpty) {
    throw const InvalidDeckFileException('Missing or empty deck "name".');
  }
  final rawCards = decoded['cards'];
  if (rawCards is! List) {
    throw const InvalidDeckFileException('Missing "cards" array.');
  }

  final cards = <CardRecord>[];
  for (final entry in rawCards) {
    if (entry is! Map<String, dynamic>) {
      throw const InvalidDeckFileException('Each card must be a JSON object.');
    }
    final front = entry['front'];
    final back = entry['back'];
    if (front is! String || back is! String) {
      throw const InvalidDeckFileException('Each card needs "front" and "back" strings.');
    }
    final nextReviewRaw = entry['nextReview'];
    final nextReview = nextReviewRaw is String
        ? DateTime.tryParse(nextReviewRaw) ?? DateTime.now()
        : DateTime.now();
    cards.add(CardRecord(
      front: front,
      back: back,
      easeFactor: (entry['easeFactor'] as num?)?.toDouble() ?? 2.5,
      interval: (entry['interval'] as num?)?.toInt() ?? 1,
      repetitions: (entry['repetitions'] as num?)?.toInt() ?? 0,
      nextReview: nextReview,
    ));
  }

  return DeckExport(
    name: name,
    description: decoded['description'] as String?,
    cards: cards,
  );
}

/// Simple front/back CSV - the common interchange format other flashcard
/// apps export/import, so a switcher doesn't have to retype their deck.
String encodeCardsToCsv(List<CardRecord> cards) {
  final rows = [
    ['front', 'back'],
    ...cards.map((c) => [c.front, c.back]),
  ];
  return const ListToCsvConverter().convert(rows);
}

/// Parses a front/back CSV. Cards created from CSV have no prior review
/// history, so they start fresh (default ease/interval/repetitions, due now).
List<CardRecord> decodeCardsFromCsv(String csvStr) {
  final rows = const CsvToListConverter(eol: '\n').convert(csvStr, shouldParseNumbers: false);
  if (rows.isEmpty) return [];

  var dataRows = rows;
  final firstRow = rows.first;
  final looksLikeHeader = firstRow.length >= 2 &&
      firstRow[0].toString().trim().toLowerCase() == 'front' &&
      firstRow[1].toString().trim().toLowerCase() == 'back';
  if (looksLikeHeader) {
    dataRows = rows.skip(1).toList();
  }

  final now = DateTime.now();
  final cards = <CardRecord>[];
  for (final row in dataRows) {
    if (row.isEmpty) continue;
    final front = row[0].toString().trim();
    final back = row.length > 1 ? row[1].toString().trim() : '';
    if (front.isEmpty || back.isEmpty) continue;
    cards.add(CardRecord(front: front, back: back, nextReview: now));
  }
  return cards;
}
