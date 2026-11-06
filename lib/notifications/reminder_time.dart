/// The next moment a daily reminder at [hour]:[minute] should fire, given
/// the current time - today if that time hasn't passed yet, tomorrow if it
/// has. Kept Flutter- and plugin-independent so it's trivially testable.
DateTime nextOccurrence({required int hour, required int minute, required DateTime now}) {
  var candidate = DateTime(now.year, now.month, now.day, hour, minute);
  if (!candidate.isAfter(now)) {
    candidate = candidate.add(const Duration(days: 1));
  }
  return candidate;
}
