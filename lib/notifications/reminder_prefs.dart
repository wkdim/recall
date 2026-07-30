import 'package:shared_preferences/shared_preferences.dart';

const _kEnabledKey = 'reminder_enabled';
const _kHourKey = 'reminder_hour';
const _kMinuteKey = 'reminder_minute';
const _kDefaultHour = 9;
const _kDefaultMinute = 0;

class ReminderSettings {
  final bool enabled;
  final int hour;
  final int minute;
  const ReminderSettings({required this.enabled, required this.hour, required this.minute});
}

class ReminderPrefs {
  Future<ReminderSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ReminderSettings(
      enabled: prefs.getBool(_kEnabledKey) ?? false,
      hour: prefs.getInt(_kHourKey) ?? _kDefaultHour,
      minute: prefs.getInt(_kMinuteKey) ?? _kDefaultMinute,
    );
  }

  Future<void> save(ReminderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, settings.enabled);
    await prefs.setInt(_kHourKey, settings.hour);
    await prefs.setInt(_kMinuteKey, settings.minute);
  }
}
