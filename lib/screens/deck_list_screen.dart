import 'package:flutter/material.dart' hide Card;
import 'package:provider/provider.dart';
import '../collections/smart_collections.dart';
import '../database/database.dart';
import '../gamification/daily_goal.dart';
import '../gamification/xp_tracker.dart';
import '../health/deck_health.dart';
import '../onboarding/onboarding_prefs.dart';
import '../streak/streak_tracker.dart';
import '../theme/app_theme.dart';
import 'edit_deck_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'study_screen.dart';

/// "Due Today" is deliberately left out here - the Focus Mode card above
/// already covers it, and repeating it as a collection chip would be
/// redundant rather than useful.
const _kCollectionTypes = [
  SmartCollectionType.forgotten,
  SmartCollectionType.difficult,
  SmartCollectionType.recentlyAdded,
  SmartCollectionType.mature,
];

class DeckListScreen extends StatefulWidget {
  const DeckListScreen({super.key});

  @override
  State<DeckListScreen> createState() => _DeckListScreenState();
}

class _DeckListScreenState extends State<DeckListScreen> {
  final _onboardingPrefs = OnboardingPrefs();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowOnboarding());
  }

  Future<void> _maybeShowOnboarding() async {
    if (await _onboardingPrefs.hasSeenOnboarding()) return;
    if (!mounted) return;
    await _onboardingPrefs.markSeen();
    if (!mounted) return;

    final colorScheme = Theme.of(context).colorScheme;
    await showModalBottomSheet(
      context: context,
      isDismissible: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome to Recall',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              _OnboardingTip(
                icon: Icons.bolt,
                text: 'Tap Start on the home card to review everything due, across every deck.',
              ),
              const SizedBox(height: 12),
              _OnboardingTip(
                icon: Icons.touch_app_outlined,
                text: 'Tap a deck to study just that one.',
              ),
              const SizedBox(height: 12),
              _OnboardingTip(
                icon: Icons.more_horiz,
                text: 'Long-press a deck to edit or delete it.',
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<(int, int)> _loadDailyGoalProgress() async {
    final tracker = DailyGoalTracker();
    final goal = await tracker.getGoal();
    final count = await tracker.todayCount();
    return (goal, count);
  }

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<AppDatabase>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Decks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.query_stats),
            tooltip: 'Stats',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StatsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Focus Mode: one glanceable card, one button, no deck to pick first.
          StreamBuilder<List<Card>>(
            stream: db.select(db.cards).watch(),
            builder: (context, allCardSnap) {
              final allCards = allCardSnap.data ?? [];
              if (allCards.isEmpty) return const SizedBox.shrink();
              final due = allCards
                  .where((c) => !c.nextReview.isAfter(DateTime.now()))
                  .length;
              final isDone = due == 0;
              final minutes = (due * 15 / 60).ceil().clamp(1, 999);

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  decoration: BoxDecoration(
                    color: isDone ? appColors.successBackground : colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _greeting(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDone ? appColors.successForeground : colorScheme.primary,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FutureBuilder<int>(
                                future: XpTracker().totalXp(),
                                builder: (context, xpSnap) {
                                  final level = levelForXp(xpSnap.data ?? 0);
                                  return Semantics(
                                    label: 'Level $level',
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Lv. $level',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: colorScheme.onPrimary,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              FutureBuilder<int>(
                                future: StreakTracker().currentStreak(),
                                builder: (context, streakSnap) {
                                  final streak = streakSnap.data ?? 0;
                                  if (streak <= 0) return const SizedBox.shrink();
                                  return Semantics(
                                    label: '$streak day study streak',
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.local_fire_department,
                                            size: 15, color: appColors.streakFlame),
                                        const SizedBox(width: 3),
                                        Text(
                                          '$streak day${streak == 1 ? '' : 's'}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: appColors.streakFlame,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isDone ? 'All caught up' : '$due card${due == 1 ? '' : 's'} due',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (!isDone) ...[
                        const SizedBox(height: 4),
                        Text(
                          '~$minutes minute${minutes == 1 ? '' : 's'} session',
                          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 10),
                      FutureBuilder<(int, int)>(
                        future: _loadDailyGoalProgress(),
                        builder: (context, goalSnap) {
                          final (goal, count) = goalSnap.data ?? (kDefaultDailyGoal, 0);
                          final fraction = goal == 0 ? 0.0 : (count / goal).clamp(0.0, 1.0);
                          return Semantics(
                            label: '$count of $goal cards toward today\'s goal',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: fraction,
                                    minHeight: 5,
                                    backgroundColor: colorScheme.surface.withValues(alpha: 0.5),
                                    color: colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$count / $goal today\'s goal',
                                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      if (!isDone)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const StudyScreen()),
                            ),
                            child: const Text('Start'),
                          ),
                        )
                      else
                        Text(
                          'Come back tomorrow for more',
                          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),

          _buildSmartCollections(context, db, colorScheme),

          // Deck grid
          Expanded(
            child: StreamBuilder<List<Deck>>(
              stream: db.select(db.decks).watch(),
              builder: (context, snapshot) {
                final decks = snapshot.data ?? [];

                if (decks.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.style_outlined,
                            size: 44,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'No decks yet',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap + to create your first deck',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 1.05,
                  ),
                  itemCount: decks.length,
                  itemBuilder: (context, index) {
                    final deck = decks[index];
                    final gradient = appColors.deckGradients[index % appColors.deckGradients.length];
                    final accent = appColors.deckAccents[index % appColors.deckAccents.length];

                    return StreamBuilder<List<Card>>(
                      stream: (db.select(db.cards)
                            ..where((c) => c.deckId.equals(deck.id)))
                          .watch(),
                      builder: (context, cardSnap) {
                        final cards = cardSnap.data ?? [];
                        final total = cards.length;
                        final now = DateTime.now();
                        final due =
                            cards.where((c) => !c.nextReview.isAfter(now)).length;
                        final progress =
                            total == 0 ? 0.0 : (total - due) / total;
                        final health = computeDeckHealth(cards);

                        return Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [gradient[0], gradient[1]],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: gradient[1].withValues(alpha: 0.7),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => StudyScreen(deck: deck)),
                              ),
                              onLongPress: () =>
                                  _showDeckMenu(context, db, deck),
                              child: Semantics(
                                button: true,
                                label:
                                    '${deck.name}, $total card${total == 1 ? '' : 's'}, $due due. Double tap to study, long-press for more options.',
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 32,
                                            height: 32,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: accent.withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              deck.name.isNotEmpty
                                                  ? deck.name[0].toUpperCase()
                                                  : '?',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: accent,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              deck.name,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                                color: appColors.tileForeground,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (health.score < 70)
                                            Tooltip(
                                              message: 'Deck health: ${health.score}/100. Open the deck to see why.',
                                              child: Icon(
                                                Icons.health_and_safety_outlined,
                                                size: 16,
                                                color: appColors.tileForegroundMuted,
                                              ),
                                            ),
                                        ],
                                      ),
                                      if (deck.description != null &&
                                          deck.description!.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          deck.description!,
                                          style: TextStyle(
                                            color: appColors.tileForegroundMuted,
                                            fontSize: 11,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                      const Spacer(),
                                      Text(
                                        due == 0
                                            ? '$total card${total == 1 ? '' : 's'}'
                                            : '$due/$total due',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: due > 0 ? accent : appColors.tileForegroundMuted,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: progress,
                                          backgroundColor: appColors.tileTrackBackground,
                                          color: accent,
                                          minHeight: 5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EditDeckScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New Deck'),
      ),
    );
  }

  Widget _buildSmartCollections(BuildContext context, AppDatabase db, ColorScheme colorScheme) {
    return StreamBuilder<List<Card>>(
      stream: db.select(db.cards).watch(),
      builder: (context, snapshot) {
        final allCards = snapshot.data ?? [];
        if (allCards.isEmpty) return const SizedBox.shrink();

        final nonEmpty = _kCollectionTypes
            .map((type) => (type: type, cards: filterCollection(type, allCards)))
            .where((entry) => entry.cards.isNotEmpty)
            .toList();
        if (nonEmpty.isEmpty) return const SizedBox.shrink();

        return SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            itemCount: nonEmpty.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final entry = nonEmpty[index];
              return ActionChip(
                label: Text('${collectionLabel(entry.type)} (${entry.cards.length})'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudyScreen(
                      cardIds: entry.cards.map((c) => c.id).toList(),
                      title: collectionLabel(entry.type),
                      ignoreDueDate: true,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  void _showDeckMenu(BuildContext context, AppDatabase db, Deck deck) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text(
                deck.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.edit_outlined, size: 18, color: colorScheme.primary),
              ),
              title: const Text('Edit Deck'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => EditDeckScreen(deck: deck)),
                );
              },
            ),
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.delete_outline, size: 18, color: colorScheme.error),
              ),
              title: Text('Delete Deck', style: TextStyle(color: colorScheme.error)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, db, deck);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppDatabase db, Deck deck) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete deck?'),
        content: Text('Permanently delete "${deck.name}" and all its cards?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            onPressed: () async {
              await db.deleteDeckWithCards(deck.id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _OnboardingTip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _OnboardingTip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
          ),
        ),
      ],
    );
  }
}
