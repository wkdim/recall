/// Result of scheduling a single SM-2 review.
class Sm2Result {
  final double easeFactor;
  final int interval;
  final int repetitions;

  const Sm2Result({
    required this.easeFactor,
    required this.interval,
    required this.repetitions,
  });
}

/// Applies the SM-2 spaced-repetition algorithm to a single card review.
///
/// [quality] is graded 0-5 (this app uses 0=Again, 2=Hard, 3=Good, 4=Easy).
/// A quality below 3 is a lapse: repetitions and interval reset.
Sm2Result sm2Schedule({
  required double easeFactor,
  required int interval,
  required int repetitions,
  required int quality,
}) {
  assert(quality >= 0 && quality <= 5, 'quality must be between 0 and 5');

  double ease = easeFactor;
  int nextInterval = interval;
  int nextReps = repetitions;

  if (quality >= 3) {
    if (nextReps == 0) {
      nextInterval = 1;
    } else if (nextReps == 1) {
      nextInterval = 6;
    } else {
      nextInterval = (nextInterval * ease).round();
    }
    nextReps++;
  } else {
    nextReps = 0;
    nextInterval = 1;
  }

  ease = ease + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
  if (ease < 1.3) ease = 1.3;

  return Sm2Result(
    easeFactor: ease,
    interval: nextInterval,
    repetitions: nextReps,
  );
}
