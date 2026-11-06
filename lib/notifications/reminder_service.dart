import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const _kNotificationId = 1;

/// Abstraction over the real plugin calls so [SettingsScreen] can be tested
/// with a fake - actual notification delivery can't be verified by an
/// automated test regardless, only by checking a real device.
abstract class ReminderScheduler {
  Future<bool> requestPermission();
  Future<void> scheduleDaily({required int hour, required int minute});
  Future<void> cancel();
}

class ReminderService implements ReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // Falls back to whatever `timezone` defaults to (UTC) - a reminder
      // that fires at the wrong local hour is still better than one that
      // silently never gets scheduled at all.
    }
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    await _ensureInitialized();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    return true; // Desktop/web: no permission model to request.
  }

  @override
  Future<void> scheduleDaily({required int hour, required int minute}) async {
    await _ensureInitialized();
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      _kNotificationId,
      'Time to review',
      'Your flashcards are waiting for you.',
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails('daily_reminder', 'Daily study reminder'),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> cancel() async {
    await _ensureInitialized();
    await _plugin.cancel(_kNotificationId);
  }
}
