import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashcard_app/gamification/xp_tracker.dart';

void main() {
  group('xpForRating (pure logic)', () {
    test('Again earns the least, but still something', () {
      expect(xpForRating(0), greaterThan(0));
    });

    test('harder-earned ratings award more XP than easier ones', () {
      expect(xpForRating(2), greaterThan(xpForRating(0)));
      expect(xpForRating(3), greaterThan(xpForRating(2)));
      expect(xpForRating(4), greaterThan(xpForRating(3)));
    });

    test('an unrecognized quality value earns nothing', () {
      expect(xpForRating(99), 0);
    });
  });

  group('leveling (pure logic)', () {
    test('starts at level 1 with 0 XP', () {
      expect(levelForXp(0), 1);
    });

    test('does not level up until a full level is earned', () {
      expect(levelForXp(kXpPerLevel - 1), 1);
      expect(levelForXp(kXpPerLevel), 2);
    });

    test('xpIntoCurrentLevel resets at each level boundary', () {
      expect(xpIntoCurrentLevel(kXpPerLevel - 1), kXpPerLevel - 1);
      expect(xpIntoCurrentLevel(kXpPerLevel), 0);
      expect(xpIntoCurrentLevel(kXpPerLevel + 30), 30);
    });

    test('xpToNextLevel is the complement of xpIntoCurrentLevel', () {
      expect(xpToNextLevel(kXpPerLevel + 30), kXpPerLevel - 30);
      expect(xpToNextLevel(0), kXpPerLevel);
    });
  });

  group('XpTracker (persisted)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('starts at 0 XP before any is earned', () async {
      expect(await XpTracker().totalXp(), 0);
    });

    test('addXp accumulates across separate calls', () async {
      final tracker = XpTracker();
      await tracker.addXp(10);
      final total = await tracker.addXp(5);
      expect(total, 15);
      expect(await tracker.totalXp(), 15);
    });
  });
}
