import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashcard_app/notifications/reminder_prefs.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to disabled at 9:00 when nothing has been set', () async {
    final settings = await ReminderPrefs().load();
    expect(settings.enabled, false);
    expect(settings.hour, 9);
    expect(settings.minute, 0);
  });

  test('persists a saved choice across loads', () async {
    final prefs = ReminderPrefs();
    await prefs.save(const ReminderSettings(enabled: true, hour: 20, minute: 30));
    final loaded = await prefs.load();
    expect(loaded.enabled, true);
    expect(loaded.hour, 20);
    expect(loaded.minute, 30);
  });
}
