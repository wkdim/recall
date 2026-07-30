import '../database/database.dart';

class DeckHealthReport {
  final int score; // 0-100
  final int duplicateCount;
  final int tooLongCount;
  final int neverReviewedCount;
  final int overdueCount;

  const DeckHealthReport({
    required this.score,
    required this.duplicateCount,
    required this.tooLongCount,
    required this.neverReviewedCount,
    required this.overdueCount,
  });

  bool get hasIssues =>
      duplicateCount > 0 || tooLongCount > 0 || neverReviewedCount > 0 || overdueCount > 0;
}

/// Rule-based deck quality check — no AI needed. Every check works off
/// fields already on [Card].
///
/// - Duplicates: cards sharing the same front text (case/whitespace
///   insensitive) — every copy beyond the first counts as one duplicate.
/// - Too long: front or back text past [maxLength], which tends to test
///   recall of a paragraph instead of one fact.
/// - Never reviewed: still at the pristine ease/repetition defaults.
/// - Overdue: due more than [overdueDays] days ago — not just due today,
///   genuinely neglected.
DeckHealthReport computeDeckHealth(
  List<Card> cards, {
  DateTime? now,
  int maxLength = 200,
  int overdueDays = 7,
}) {
  if (cards.isEmpty) {
    return const DeckHealthReport(
      score: 100,
      duplicateCount: 0,
      tooLongCount: 0,
      neverReviewedCount: 0,
      overdueCount: 0,
    );
  }

  final today = now ?? DateTime.now();

  final normalizedFronts = <String, int>{};
  for (final c in cards) {
    final key = c.front.trim().toLowerCase();
    normalizedFronts[key] = (normalizedFronts[key] ?? 0) + 1;
  }
  final duplicateCount =
      normalizedFronts.values.where((count) => count > 1).fold(0, (sum, count) => sum + count - 1);

  final tooLongCount =
      cards.where((c) => c.front.length > maxLength || c.back.length > maxLength).length;

  final neverReviewedCount =
      cards.where((c) => c.repetitions == 0 && c.easeFactor == 2.5).length;

  final overdueCount =
      cards.where((c) => today.difference(c.nextReview).inDays > overdueDays).length;

  final issues = duplicateCount + tooLongCount + neverReviewedCount + overdueCount;
  final score = (100 - (issues / cards.length * 100)).clamp(0, 100).round();

  return DeckHealthReport(
    score: score,
    duplicateCount: duplicateCount,
    tooLongCount: tooLongCount,
    neverReviewedCount: neverReviewedCount,
    overdueCount: overdueCount,
  );
}
