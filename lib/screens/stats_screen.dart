import 'package:flutter/material.dart' hide Card;
import 'package:provider/provider.dart';
import '../database/database.dart';
import '../stats/stats_calculations.dart';
import '../streak/streak_tracker.dart';
import '../theme/app_theme.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<AppDatabase>(context, listen: false);
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
      body: FutureBuilder<List<ReviewLog>>(
        future: db.select(db.reviewLogs).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          final logs = snapshot.data!;

          if (logs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.query_stats, size: 44, color: colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'No reviews yet',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Study a few cards and your stats will show up here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }

          final retention = retentionRate(logs.map((l) => l.quality).toList());
          final byDay = bucketReviewsByDay(logs.map((l) => l.reviewedAt).toList());
          final days = lastNDays(35, DateTime.now());

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(
                        label: 'Total reviews',
                        value: '${logs.length}',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FutureBuilder<int>(
                        future: StreakTracker().currentStreak(),
                        builder: (context, streakSnap) => _StatTile(
                          label: 'Day streak',
                          value: '${streakSnap.data ?? 0}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatTile(
                        label: 'Retention',
                        value: '${(retention * 100).round()}%',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  'Last 5 weeks',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _StudyCalendar(days: days, byDay: byDay, appColors: appColors, colorScheme: colorScheme),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _StudyCalendar extends StatelessWidget {
  final List<DateTime> days;
  final Map<DateTime, int> byDay;
  final AppColors appColors;
  final ColorScheme colorScheme;

  const _StudyCalendar({
    required this.days,
    required this.byDay,
    required this.appColors,
    required this.colorScheme,
  });

  Color _cellColor(int count) {
    if (count <= 0) return colorScheme.surfaceContainerHighest;
    if (count <= 2) return colorScheme.primary.withValues(alpha: 0.35);
    if (count <= 5) return colorScheme.primary.withValues(alpha: 0.65);
    return colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Study calendar, last ${days.length} days',
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: days.length,
        itemBuilder: (context, i) {
          final day = days[i];
          final count = byDay[day] ?? 0;
          return Tooltip(
            message: '${day.year}-${day.month}-${day.day}: $count review${count == 1 ? '' : 's'}',
            child: AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _cellColor(count),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
