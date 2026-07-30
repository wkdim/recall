import 'package:flutter/material.dart';
import '../gamification/daily_goal.dart';
import '../notifications/reminder_prefs.dart';
import '../notifications/reminder_service.dart';

const _kDailyGoalStep = 5;
const _kMinDailyGoal = 5;
const _kMaxDailyGoal = 100;

class SettingsScreen extends StatefulWidget {
  /// Injectable so tests can exercise the toggle without hitting the real
  /// notification plugin, which needs a platform this test host doesn't have.
  final ReminderScheduler? reminderScheduler;

  const SettingsScreen({super.key, this.reminderScheduler});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _reminderPrefs = ReminderPrefs();
  final _dailyGoalPrefs = DailyGoalTracker();
  late final ReminderScheduler _reminderScheduler = widget.reminderScheduler ?? ReminderService();

  ReminderSettings? _reminder;
  int? _dailyGoal;

  @override
  void initState() {
    super.initState();
    _reminderPrefs.load().then((value) {
      if (mounted) setState(() => _reminder = value);
    });
    _dailyGoalPrefs.getGoal().then((value) {
      if (mounted) setState(() => _dailyGoal = value);
    });
  }

  Future<void> _setDailyGoal(int delta) async {
    final current = _dailyGoal;
    if (current == null) return;
    final updated = (current + delta).clamp(_kMinDailyGoal, _kMaxDailyGoal);
    await _dailyGoalPrefs.setGoal(updated);
    if (mounted) setState(() => _dailyGoal = updated);
  }

  Future<void> _toggleReminder(bool enabled) async {
    final current = _reminder!;
    if (enabled) {
      final granted = await _reminderScheduler.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notification permission was declined')),
          );
        }
        return;
      }
      await _reminderScheduler.scheduleDaily(hour: current.hour, minute: current.minute);
    } else {
      await _reminderScheduler.cancel();
    }
    final updated = ReminderSettings(enabled: enabled, hour: current.hour, minute: current.minute);
    await _reminderPrefs.save(updated);
    if (mounted) setState(() => _reminder = updated);
  }

  Future<void> _pickTime() async {
    final current = _reminder!;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) return;

    final updated = ReminderSettings(enabled: current.enabled, hour: picked.hour, minute: picked.minute);
    if (updated.enabled) {
      await _reminderScheduler.scheduleDaily(hour: updated.hour, minute: updated.minute);
    }
    await _reminderPrefs.save(updated);
    if (mounted) setState(() => _reminder = updated);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'DAILY REMINDER',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (_reminder == null)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else ...[
            SwitchListTile(
              key: const ValueKey('reminder-toggle'),
              contentPadding: EdgeInsets.zero,
              value: _reminder!.enabled,
              onChanged: _toggleReminder,
              title: const Text('Remind me to study'),
              subtitle: const Text('A single daily notification — nothing fancier, no due-count details.'),
            ),
            if (_reminder!.enabled)
              ListTile(
                key: const ValueKey('reminder-time'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('Time'),
                trailing: Text(
                  TimeOfDay(hour: _reminder!.hour, minute: _reminder!.minute).format(context),
                  style: TextStyle(fontWeight: FontWeight.w700, color: colorScheme.primary),
                ),
                onTap: _pickTime,
              ),
          ],
          const SizedBox(height: 28),
          Text(
            'DAILY GOAL',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (_dailyGoal == null)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Cards per day'),
              subtitle: const Text("Shown as a progress bar on today's home card."),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const ValueKey('dailyGoalDecrease'),
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _dailyGoal! <= _kMinDailyGoal ? null : () => _setDailyGoal(-_kDailyGoalStep),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '$_dailyGoal',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700, color: colorScheme.primary),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('dailyGoalIncrease'),
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _dailyGoal! >= _kMaxDailyGoal ? null : () => _setDailyGoal(_kDailyGoalStep),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
