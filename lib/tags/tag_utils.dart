/// Tags are stored as a single comma-separated string on each card - simple
/// by design, since a join table is overkill until decks routinely need
/// far more tags than a hobby deck ever will.
List<String> parseTags(String? raw) {
  if (raw == null || raw.trim().isEmpty) return [];
  return raw
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();
}

String encodeTags(List<String> tags) {
  return tags.map((t) => t.trim()).where((t) => t.isNotEmpty).join(',');
}

/// Whether a card matches a free-text search query - checked against front,
/// back, and tags, case-insensitively. Empty queries match everything.
bool cardMatchesQuery({
  required String front,
  required String back,
  String? tags,
  required String query,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (front.toLowerCase().contains(q)) return true;
  if (back.toLowerCase().contains(q)) return true;
  return parseTags(tags).any((t) => t.toLowerCase().contains(q));
}
