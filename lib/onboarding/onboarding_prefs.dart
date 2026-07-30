import 'package:shared_preferences/shared_preferences.dart';

const _kHasSeenOnboardingKey = 'has_seen_onboarding';

/// Tracks whether the first-launch onboarding hint has already been shown,
/// via the same lightweight local-prefs pattern as [StreakTracker].
class OnboardingPrefs {
  Future<bool> hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kHasSeenOnboardingKey) ?? false;
  }

  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHasSeenOnboardingKey, true);
  }
}
