DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Buckets a list of review timestamps into per-day counts, keyed by the
/// date (time-of-day stripped). Independent of any database row type so
/// it can be tested without Drift or a real clock.
Map<DateTime, int> bucketReviewsByDay(List<DateTime> reviewedAt) {
  final buckets = <DateTime, int>{};
  for (final t in reviewedAt) {
    final day = dateOnly(t);
    buckets[day] = (buckets[day] ?? 0) + 1;
  }
  return buckets;
}

/// The last [count] calendar days ending on (and including) [today], oldest
/// first — the x-axis of the study-calendar heatmap.
List<DateTime> lastNDays(int count, DateTime today) {
  final end = dateOnly(today);
  return List.generate(count, (i) => end.subtract(Duration(days: count - 1 - i)));
}

/// Fraction (0.0–1.0) of reviews rated Good or Easy (quality >= 3) — the
/// simplest honest measure of "how much of what I studied did I actually
/// remember," used for the Stats screen's retention figure.
double retentionRate(List<int> qualities) {
  if (qualities.isEmpty) return 0.0;
  final remembered = qualities.where((q) => q >= 3).length;
  return remembered / qualities.length;
}
