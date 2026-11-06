import 'package:shared_preferences/shared_preferences.dart';

const _kStreakKey = 'streak_current';
const _kLastStudyDateKey = 'streak_last_study_date';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Pure streak-update rule, independent of storage: given the streak going
/// into today and the last date a session was recorded, what's the streak
/// after recording a session today?
///
/// - No prior session: starts a streak of 1.
/// - Already recorded today: unchanged (studying more today doesn't count twice).
/// - Last session was yesterday: extends the streak by 1.
/// - Any bigger gap: the streak broke, so it restarts at 1.
int computeNewStreak({
  required int currentStreak,
  required DateTime? lastStudyDate,
  required DateTime today,
}) {
  final todayDate = _dateOnly(today);

  if (lastStudyDate == null) return 1;

  final lastDate = _dateOnly(lastStudyDate);
  final dayGap = todayDate.difference(lastDate).inDays;

  if (dayGap == 0) return currentStreak < 1 ? 1 : currentStreak;
  if (dayGap == 1) return currentStreak + 1;
  return 1;
}

/// Persists the daily study streak locally via [SharedPreferences].
class StreakTracker {
  /// Records that a study session happened today, updating and persisting
  /// the streak. Safe to call more than once in the same day - the streak
  /// only advances on the first call of a new calendar day.
  Future<int> recordStudySession({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final currentStreak = prefs.getInt(_kStreakKey) ?? 0;
    final lastStudyMillis = prefs.getInt(_kLastStudyDateKey);
    final lastStudyDate = lastStudyMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(lastStudyMillis)
        : null;

    final today = now ?? DateTime.now();
    final newStreak = computeNewStreak(
      currentStreak: currentStreak,
      lastStudyDate: lastStudyDate,
      today: today,
    );

    await prefs.setInt(_kStreakKey, newStreak);
    await prefs.setInt(_kLastStudyDateKey, _dateOnly(today).millisecondsSinceEpoch);
    return newStreak;
  }

  /// The current streak without recording a new session - for display only.
  Future<int> currentStreak({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final streak = prefs.getInt(_kStreakKey) ?? 0;
    if (streak == 0) return 0;

    // A streak that's gone stale (more than a day without a session) reads
    // as 0 until the user studies again, rather than showing a stale count.
    final lastStudyMillis = prefs.getInt(_kLastStudyDateKey);
    if (lastStudyMillis == null) return 0;
    final lastStudyDate = DateTime.fromMillisecondsSinceEpoch(lastStudyMillis);
    final dayGap = _dateOnly(now ?? DateTime.now()).difference(_dateOnly(lastStudyDate)).inDays;
    return dayGap <= 1 ? streak : 0;
  }
}
