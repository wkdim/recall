import 'package:shared_preferences/shared_preferences.dart';

const _kXpKey = 'total_xp';

/// Flat XP-per-level curve, deliberately simple for v1 — every level costs
/// the same, no escalating grind. Can be revisited once there's real usage
/// data on whether leveling feels too fast/slow.
const kXpPerLevel = 100;

/// XP awarded per review, by rating quality (0=Again, 2=Hard, 3=Good,
/// 4=Easy). Every rating earns *something* — even "Again" — so the reward
/// tracks honest engagement with the material, not just how the answer felt;
/// otherwise the incentive would be to rate generously just to see numbers
/// go up, which undermines the SM-2/FSRS scheduling both rely on accurate
/// ratings to work well.
int xpForRating(int quality) => switch (quality) {
      0 => 2,
      2 => 5,
      3 => 10,
      4 => 15,
      _ => 0,
    };

/// Levels start at 1 (0 XP). Pure function of total XP so the UI never needs
/// its own copy of the leveling curve.
int levelForXp(int totalXp) => 1 + (totalXp ~/ kXpPerLevel);

/// XP earned within the current level (0..kXpPerLevel-1) — the "progress bar
/// fill" value.
int xpIntoCurrentLevel(int totalXp) => totalXp % kXpPerLevel;

/// XP still needed to reach the next level.
int xpToNextLevel(int totalXp) => kXpPerLevel - xpIntoCurrentLevel(totalXp);

/// Persists total XP locally via [SharedPreferences].
class XpTracker {
  Future<int> totalXp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kXpKey) ?? 0;
  }

  /// Adds [amount] XP and returns the new total. Callers that want to detect
  /// a level-up should compare `levelForXp` before/after — this method only
  /// tracks the raw total, not level-change events, to keep it a plain
  /// read-modify-write with nothing else to get out of sync.
  Future<int> addXp(int amount) async {
    final prefs = await SharedPreferences.getInstance();
    final newTotal = (prefs.getInt(_kXpKey) ?? 0) + amount;
    await prefs.setInt(_kXpKey, newTotal);
    return newTotal;
  }
}
