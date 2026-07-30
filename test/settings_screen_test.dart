import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashcard_app/gamification/daily_goal.dart';
import 'package:flashcard_app/notifications/reminder_prefs.dart';
import 'package:flashcard_app/notifications/reminder_service.dart';
import 'package:flashcard_app/screens/settings_screen.dart';

class _FakeReminderScheduler implements ReminderScheduler {
  bool permissionGranted;
  bool scheduled = false;
  bool cancelled = false;
  int? lastHour;
  int? lastMinute;

  _FakeReminderScheduler({this.permissionGranted = true});

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> scheduleDaily({required int hour, required int minute}) async {
    scheduled = true;
    cancelled = false;
    lastHour = hour;
    lastMinute = minute;
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
    scheduled = false;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('reminder is off by default and the time row is hidden', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(reminderScheduler: _FakeReminderScheduler())));
    await tester.pumpAndSettle();

    final toggle = tester.widget<SwitchListTile>(find.byKey(const ValueKey('reminder-toggle')));
    expect(toggle.value, false);
    expect(find.byKey(const ValueKey('reminder-time')), findsNothing);
  });

  testWidgets('enabling the reminder schedules it and persists the choice', (
    WidgetTester tester,
  ) async {
    final fake = _FakeReminderScheduler();
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(reminderScheduler: fake)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('reminder-toggle')));
    await tester.pumpAndSettle();

    expect(fake.scheduled, true);
    expect(fake.lastHour, 9); // default time
    expect(find.byKey(const ValueKey('reminder-time')), findsOneWidget);
    expect((await ReminderPrefs().load()).enabled, true);
  });

  testWidgets('a declined permission keeps the reminder off', (
    WidgetTester tester,
  ) async {
    final fake = _FakeReminderScheduler(permissionGranted: false);
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(reminderScheduler: fake)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('reminder-toggle')));
    await tester.pumpAndSettle();

    expect(fake.scheduled, false);
    expect(find.textContaining('declined'), findsOneWidget);
    expect((await ReminderPrefs().load()).enabled, false);
  });

  testWidgets('disabling an active reminder cancels it', (
    WidgetTester tester,
  ) async {
    final fake = _FakeReminderScheduler();
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(reminderScheduler: fake)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('reminder-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reminder-toggle')));
    await tester.pumpAndSettle();

    expect(fake.cancelled, true);
    expect((await ReminderPrefs().load()).enabled, false);
  });

  testWidgets('the daily goal defaults to 20 and can be adjusted with the steppers', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(reminderScheduler: _FakeReminderScheduler())));
    await tester.pumpAndSettle();

    expect(find.text('20'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('dailyGoalIncrease')));
    await tester.pumpAndSettle();

    expect(find.text('25'), findsOneWidget);
    expect(await DailyGoalTracker().getGoal(), 25);

    await tester.tap(find.byKey(const ValueKey('dailyGoalDecrease')));
    await tester.pumpAndSettle();

    expect(find.text('20'), findsOneWidget);
    expect(await DailyGoalTracker().getGoal(), 20);
  });

  testWidgets('the daily goal cannot go below the minimum', (
    WidgetTester tester,
  ) async {
    await DailyGoalTracker().setGoal(5);
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(reminderScheduler: _FakeReminderScheduler())));
    await tester.pumpAndSettle();

    expect(find.text('5'), findsOneWidget);
    final decreaseButton = tester.widget<IconButton>(find.byKey(const ValueKey('dailyGoalDecrease')));
    expect(decreaseButton.onPressed, isNull);
  });
}
