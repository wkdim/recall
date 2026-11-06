import 'package:shared_preferences/shared_preferences.dart';

const _kGoalKey = 'daily_goal_target';
const _kCountKey = 'daily_goal_count';
const _kDateKey = 'daily_goal_date';

/// Shown until the user picks their own target in Settings.
const kDefaultDailyGoal = 20;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Pure daily-count-update rule, independent of storage: given the count
/// recorded so far today (or a prior day) and today's date, what's the count
/// after recording one more review?
///
/// - No prior record, or the last record was a different calendar day: this
///   review is the first one of a fresh day.
/// - Last record was today: increments the existing count.
int computeDailyCount({
  required int currentCount,
  required DateTime? lastRecordedDate,
  required DateTime today,
}) {
  if (lastRecordedDate == null) return 1;
  final dayGap = _dateOnly(today).difference(_dateOnly(lastRecordedDate)).inDays;
  return dayGap == 0 ? currentCount + 1 : 1;
}

/// Persists the user's daily card-review goal and today's progress toward it
/// locally via [SharedPreferences] - same thin-wrapper-over-a-pure-function
/// pattern as [StreakTracker].
class DailyGoalTracker {
  Future<int> getGoal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kGoalKey) ?? kDefaultDailyGoal;
  }

  Future<void> setGoal(int target) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kGoalKey, target);
  }

  /// Records that one card was reviewed just now, updating and persisting
  /// today's progress. Safe to call for every card in a session - unlike the
  /// streak (once per day), the daily goal count increments every time.
  Future<int> recordReview({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final currentCount = prefs.getInt(_kCountKey) ?? 0;
    final lastRecordedMillis = prefs.getInt(_kDateKey);
    final lastRecordedDate = lastRecordedMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(lastRecordedMillis)
        : null;

    final today = now ?? DateTime.now();
    final newCount = computeDailyCount(
      currentCount: currentCount,
      lastRecordedDate: lastRecordedDate,
      today: today,
    );

    await prefs.setInt(_kCountKey, newCount);
    await prefs.setInt(_kDateKey, _dateOnly(today).millisecondsSinceEpoch);
    return newCount;
  }

  /// Today's progress without recording a review - for display only. Reads
  /// as 0 once the stored count is from a prior day, rather than showing a
  /// stale number.
  Future<int> todayCount({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_kCountKey) ?? 0;
    if (count == 0) return 0;

    final lastRecordedMillis = prefs.getInt(_kDateKey);
    if (lastRecordedMillis == null) return 0;
    final lastRecordedDate = DateTime.fromMillisecondsSinceEpoch(lastRecordedMillis);
    final dayGap = _dateOnly(now ?? DateTime.now()).difference(_dateOnly(lastRecordedDate)).inDays;
    return dayGap == 0 ? count : 0;
  }
}
