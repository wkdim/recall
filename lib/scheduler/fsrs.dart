import 'dart:math' as math;

/// A simplified FSRS-style scheduler - an alternative to [sm2Schedule] that
/// tracks memory **stability** and **difficulty** separately instead of a
/// single ease factor, which is the core idea FSRS improves on SM-2 with.
///
/// Honesty note: the interval-from-stability formula below is the real
/// FSRS v4 forgetting-curve formula (fixed DECAY/FACTOR constants published
/// by the fsrs4anki project). The stability/difficulty *update* rules after
/// each rating are a deliberately simplified approximation, not a byte-exact
/// port of FSRS-4.5's 17 trained weights - those are calibrated against a
/// huge review dataset this app has no way to reproduce or verify against.
/// What's preserved is the actual mechanic that matters: difficulty and
/// stability evolve as two independent numbers, and only a true failure
/// (quality 0, "Again") counts as a lapse - unlike this app's SM-2 path,
/// where quality 2 ("Hard") also resets progress. That difference is real
/// and intentional, not a simplification.
class FsrsResult {
  final double stability;
  final double difficulty;
  final int interval;

  const FsrsResult({
    required this.stability,
    required this.difficulty,
    required this.interval,
  });
}

const _kDecay = -0.5;
const _kFactor = 19 / 81;

/// FSRS-4.5's published default initial-stability weights for a first
/// review, indexed by rating (Again/Hard/Good/Easy).
const _kInitialStability = [0.4, 0.6, 2.4, 5.8];

int _ratingFromQuality(int quality) {
  if (quality == 0) return 1; // Again
  if (quality == 2) return 2; // Hard
  if (quality == 3) return 3; // Good
  return 4; // Easy
}

/// Days until retrievability decays to [requestRetention], given current
/// stability - the real FSRS v4 forgetting-curve formula.
int _intervalFromStability(double stability, double requestRetention) {
  final days = stability * (1 / _kFactor) * (math.pow(requestRetention, 1 / _kDecay) - 1);
  return days.round().clamp(1, 36500);
}

FsrsResult fsrsSchedule({
  double? stability,
  double? difficulty,
  required int quality,
  double requestRetention = 0.9,
}) {
  final rating = _ratingFromQuality(quality);

  double newStability;
  double newDifficulty;

  if (stability == null || difficulty == null) {
    // First review of this card under FSRS.
    newStability = _kInitialStability[rating - 1];
    newDifficulty = (5 - (rating - 3) * 1.5).clamp(1.0, 10.0);
  } else if (rating == 1) {
    // A lapse: stability drops sharply, difficulty climbs.
    newStability = math.max(0.1, stability * 0.5);
    newDifficulty = (difficulty + 2).clamp(1.0, 10.0);
  } else {
    // A pass (Hard/Good/Easy) - harder ratings grow stability less, and
    // lower difficulty compounds future growth, mirroring FSRS's intent
    // without its exact weights.
    const growthByRating = {2: 1.0, 3: 1.3, 4: 1.8};
    final difficultyFactor = 1 + (10 - difficulty) / 20;
    newStability = stability * growthByRating[rating]! * difficultyFactor;
    newDifficulty = (difficulty - (rating - 3) * 0.6).clamp(1.0, 10.0);
  }

  return FsrsResult(
    stability: newStability,
    difficulty: newDifficulty,
    interval: _intervalFromStability(newStability, requestRetention),
  );
}
