import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:provider/provider.dart';
import '../cloze/cloze_parser.dart';
import '../database/database.dart';
import '../gamification/daily_goal.dart';
import '../gamification/xp_tracker.dart';
import '../scheduler/fsrs.dart';
import '../scheduler/sm2.dart';
import '../streak/streak_tracker.dart';
import '../theme/app_theme.dart';
import 'edit_deck_screen.dart';

/// Minimum fling velocity (px/s) along the dominant axis before a swipe
/// counts as a rating gesture, rather than an accidental drag.
const _kSwipeVelocityThreshold = 250.0;

/// Everything needed to put a card back exactly how it was before its most
/// recent rating — a single-level undo, not a full history stack.
class _LastRating {
  final int cardId;
  final double easeFactor;
  final int interval;
  final int repetitions;
  final DateTime nextReview;
  final double? stability;
  final double? difficulty;
  final int quality;
  final int reviewLogId;

  const _LastRating({
    required this.cardId,
    required this.easeFactor,
    required this.interval,
    required this.repetitions,
    required this.nextReview,
    this.stability,
    this.difficulty,
    required this.quality,
    required this.reviewLogId,
  });
}

class StudyScreen extends StatefulWidget {
  /// The deck to study. Null means "study every due card across every
  /// deck" — the cross-deck Focus Mode queue from the deck list's home screen.
  final Deck? deck;

  /// Studying a specific set of cards (a Smart Collection) instead of a
  /// deck. Takes priority over [deck] when both are somehow set.
  final List<int>? cardIds;

  /// Overrides the AppBar title — used by Smart Collections, since there's
  /// no deck name to fall back on.
  final String? title;

  /// Smart Collections other than "Due Today" deliberately study cards
  /// regardless of whether they're due yet — that's the point of e.g.
  /// practicing "Difficult Cards" ahead of schedule.
  final bool ignoreDueDate;

  const StudyScreen({
    super.key,
    this.deck,
    this.cardIds,
    this.title,
    this.ignoreDueDate = false,
  });

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  final _streakTracker = StreakTracker();
  final _xpTracker = XpTracker();
  final _dailyGoalTracker = DailyGoalTracker();
  final _audioPlayer = AudioPlayer();
  bool isFront = true;
  int _studiedCount = 0;
  final Map<int, int> _ratingCounts = {0: 0, 2: 0, 3: 0, 4: 0};
  _LastRating? _lastRating;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        duration: const Duration(milliseconds: 500), vsync: this);
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playAudio(String path) async {
    await _audioPlayer.play(DeviceFileSource(path));
  }

  void _flip() {
    if (_controller.isAnimating) return;
    HapticFeedback.selectionClick();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (isFront) {
      reduceMotion ? _controller.value = 1 : _controller.forward();
    } else {
      reduceMotion ? _controller.value = 0 : _controller.reverse();
    }
    setState(() => isFront = !isFront);
  }

  /// Swipe-to-rate: only active once the answer is showing, so a swipe on
  /// the question side can't be mistaken for a rating. Buttons stay as the
  /// accessible, always-visible fallback for the same actions.
  void _handleSwipe(DragEndDetails details, Card card) {
    if (isFront) return;
    final velocity = details.velocity.pixelsPerSecond;
    if (velocity.dx.abs() > velocity.dy.abs()) {
      if (velocity.dx > _kSwipeVelocityThreshold) {
        _rateCard(card, 3); // right = Good
      } else if (velocity.dx < -_kSwipeVelocityThreshold) {
        _rateCard(card, 0); // left = Again
      }
    } else {
      if (velocity.dy < -_kSwipeVelocityThreshold) {
        _rateCard(card, 4); // up = Easy
      } else if (velocity.dy > _kSwipeVelocityThreshold) {
        _rateCard(card, 2); // down = Hard
      }
    }
  }

  Future<void> _rateCard(Card card, int quality) async {
    if (quality >= 3) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.mediumImpact();
    }

    // Record today's streak once per session, on the first card rated.
    // Awaited (not fire-and-forget) so the write can't race a screen
    // transition back to a caller that immediately reads the streak.
    if (_studiedCount == 0) {
      await _streakTracker.recordStudySession();
    }

    final db = Provider.of<AppDatabase>(context, listen: false);

    // SM-2 bookkeeping (easeFactor/repetitions) always runs alongside FSRS —
    // Smart Collections and Deck Health key off those fields, not off the
    // scheduling interval, so they need it regardless of which algorithm
    // is authoritative for the actual next-review date.
    final sm2Result = sm2Schedule(
      easeFactor: card.easeFactor,
      interval: card.interval,
      repetitions: card.repetitions,
      quality: quality,
    );

    final fsrsResult = fsrsSchedule(
      stability: card.stability,
      difficulty: card.difficulty,
      quality: quality,
    );

    await (db.update(db.cards)..where((c) => c.id.equals(card.id))).write(
      CardsCompanion(
        easeFactor: drift.Value(sm2Result.easeFactor),
        interval: drift.Value(fsrsResult.interval),
        repetitions: drift.Value(sm2Result.repetitions),
        nextReview: drift.Value(DateTime.now().add(Duration(days: fsrsResult.interval))),
        stability: drift.Value(fsrsResult.stability),
        difficulty: drift.Value(fsrsResult.difficulty),
      ),
    );
    final reviewLogId = await db.logReview(card.id, quality, DateTime.now());

    // XP/daily-goal deliberately aren't reverted by undo (below) — undo
    // exists to fix a scheduling mistake, not to erase that the user engaged
    // with the card, and there's no competitive stakes here that would make
    // "gaming" a rate-then-undo loop worth guarding against.
    final xpBefore = await _xpTracker.totalXp();
    final xpAfter = await _xpTracker.addXp(xpForRating(quality));
    await _dailyGoalTracker.recordReview();
    if (mounted && levelForXp(xpBefore) != levelForXp(xpAfter)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Level up! You reached level ${levelForXp(xpAfter)}.')),
      );
    }

    if (!mounted) return;
    setState(() {
      _lastRating = _LastRating(
        cardId: card.id,
        easeFactor: card.easeFactor,
        interval: card.interval,
        repetitions: card.repetitions,
        nextReview: card.nextReview,
        stability: card.stability,
        difficulty: card.difficulty,
        quality: quality,
        reviewLogId: reviewLogId,
      );
      _studiedCount++;
      _ratingCounts[quality] = (_ratingCounts[quality] ?? 0) + 1;
      isFront = true;
      _controller.reset();
    });
  }

  /// Puts the most recently rated card back exactly how it was — a single
  /// step, not a full undo history. Rating another card replaces this.
  Future<void> _undoLastRating() async {
    final last = _lastRating;
    if (last == null) return;

    final db = Provider.of<AppDatabase>(context, listen: false);
    await (db.update(db.cards)..where((c) => c.id.equals(last.cardId))).write(
      CardsCompanion(
        easeFactor: drift.Value(last.easeFactor),
        interval: drift.Value(last.interval),
        repetitions: drift.Value(last.repetitions),
        nextReview: drift.Value(last.nextReview),
        stability: drift.Value(last.stability),
        difficulty: drift.Value(last.difficulty),
      ),
    );
    await db.deleteReviewLog(last.reviewLogId);

    setState(() {
      _studiedCount--;
      _ratingCounts[last.quality] = (_ratingCounts[last.quality] ?? 0) - 1;
      _lastRating = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<AppDatabase>(context);
    final colorScheme = Theme.of(context).colorScheme;

    final deck = widget.deck;
    final cardIds = widget.cardIds;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? deck?.name ?? 'Today'),
        actions: [
          if (_lastRating != null)
            IconButton(
              key: const ValueKey('undo-rating'),
              icon: const Icon(Icons.undo),
              tooltip: 'Undo last rating',
              onPressed: _undoLastRating,
            ),
          if (deck != null && cardIds == null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Deck',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => EditDeckScreen(deck: deck)),
              ),
            ),
        ],
      ),
      body: StreamBuilder<List<Card>>(
        stream: (cardIds != null
                ? (db.select(db.cards)..where((c) => c.id.isIn(cardIds)))
                : deck != null
                    ? (db.select(db.cards)..where((c) => c.deckId.equals(deck.id)))
                    : db.select(db.cards))
            .watch(),
        builder: (context, snapshot) {
          final allCards = snapshot.data ?? [];
          final now = DateTime.now();
          final dueCards = widget.ignoreDueDate
              ? allCards
              : allCards.where((c) => !c.nextReview.isAfter(now)).toList();

          if (_studiedCount > 0 && dueCards.isEmpty) {
            return _buildSummary();
          }
          if (dueCards.isEmpty) {
            return _buildNoDueCards(allCards.length);
          }

          final card = dueCards.first;
          final remaining = dueCards.length;
          final total = _studiedCount + remaining;
          final progressValue = total == 0 ? 0.0 : _studiedCount / total;
          final questionText = card.isCloze ? maskCloze(card.front) : card.front;
          final answerText = card.isCloze ? revealCloze(card.front) : card.back;

          return Column(
            children: [
              // Thin session progress bar
              LinearProgressIndicator(
                value: progressValue,
                minHeight: 4,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: colorScheme.primary,
              ),
              // Counter row
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_studiedCount + 1} / $total',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '$remaining to go',
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Flip card
              Expanded(
                child: Semantics(
                  label: isFront
                      ? 'Flashcard question: $questionText. Tap or swipe up to flip.'
                      : 'Flashcard answer: $answerText. Swipe to rate, or use the buttons below.',
                  button: true,
                  child: GestureDetector(
                    key: const ValueKey('flip-card'),
                    onTap: _flip,
                    onPanEnd: (details) => _handleSwipe(details, card),
                    child: AnimatedBuilder(
                      animation: _animation,
                      builder: (context, child) {
                        final angle = _animation.value * 3.14159;
                        final showBack = angle >= 1.5708;
                        return Transform(
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(angle),
                          alignment: Alignment.center,
                          child: showBack && !isFront
                              ? Transform(
                                  transform: Matrix4.rotationY(3.14159),
                                  alignment: Alignment.center,
                                  child: _buildCardFace(
                                    text: answerText,
                                    isAnswer: true,
                                    label: 'ANSWER',
                                    imagePath: card.backImagePath,
                                    audioPath: card.backAudioPath,
                                  ),
                                )
                              : _buildCardFace(
                                  text: questionText,
                                  isAnswer: false,
                                  label: card.isCloze ? 'CLOZE' : 'QUESTION',
                                  imagePath: card.frontImagePath,
                                  audioPath: card.frontAudioPath,
                                ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              // Rating buttons or flip hint
              if (!isFront)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Row(
                    children: [
                      _rateButton('Again', card, 0, context.appColors.ratingAgain,
                          Icons.replay),
                      const SizedBox(width: 8),
                      _rateButton('Hard', card, 2, context.appColors.ratingHard,
                          Icons.trending_flat),
                      const SizedBox(width: 8),
                      _rateButton('Good', card, 3, context.appColors.ratingGood,
                          Icons.check),
                      const SizedBox(width: 8),
                      _rateButton('Easy', card, 4, context.appColors.ratingEasy,
                          Icons.bolt),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.touch_app_outlined,
                          size: 16, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        'Tap card to flip',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCardFace({
    required String text,
    required bool isAnswer,
    required String label,
    String? imagePath,
    String? audioPath,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = isAnswer ? colorScheme.primary : colorScheme.surface;
    final textColor = isAnswer ? colorScheme.onPrimary : colorScheme.onSurface;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(24),
        border: isAnswer ? null : Border.all(color: colorScheme.outlineVariant, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: isAnswer
                ? colorScheme.primary.withValues(alpha: 0.35)
                : colorScheme.shadow.withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: textColor.withValues(alpha: 0.4),
              letterSpacing: 1.8,
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (imagePath != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(imagePath), height: 120, fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (audioPath != null) ...[
                    const SizedBox(height: 12),
                    IconButton(
                      icon: Icon(Icons.play_circle_fill, size: 36, color: textColor),
                      tooltip: 'Play audio',
                      onPressed: () => _playAudio(audioPath),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rateButton(
      String label, Card card, int quality, Color color, IconData icon) {
    return Expanded(
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        onPressed: () => _rateCard(card, quality),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _buildNoDueCards(int totalCards) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;

    if (totalCards == 0) {
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
              child: Icon(Icons.add_card_outlined,
                  size: 44, color: colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Text('No cards yet',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                )),
            const SizedBox(height: 8),
            Text('Add some using the edit button above',
                style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: appColors.successBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_circle_outline,
                size: 44, color: appColors.successForeground),
          ),
          const SizedBox(height: 20),
          Text('All caught up!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              )),
          const SizedBox(height: 8),
          Text(
            '$totalCards card${totalCards == 1 ? '' : 's'} · no reviews due',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text('Come back tomorrow',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;
    final remembered =
        (_ratingCounts[3] ?? 0) + (_ratingCounts[4] ?? 0);
    final ratio =
        _studiedCount == 0 ? 0.0 : remembered / _studiedCount;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 110,
                  height: 110,
                  child: CircularProgressIndicator(
                    value: ratio,
                    strokeWidth: 10,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    color: colorScheme.primary,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  children: [
                    Text(
                      '${(ratio * 100).round()}%',
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w800, color: colorScheme.onSurface),
                    ),
                    Text(
                      'recalled',
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Session Complete!',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                )),
            const SizedBox(height: 6),
            Text(
              'You reviewed $_studiedCount card${_studiedCount == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _summaryChip('Again', _ratingCounts[0] ?? 0, appColors.ratingAgain),
                _summaryChip('Hard', _ratingCounts[2] ?? 0, appColors.ratingHard),
                _summaryChip('Good', _ratingCounts[3] ?? 0, appColors.ratingGood),
                _summaryChip('Easy', _ratingCounts[4] ?? 0, appColors.ratingEasy),
              ],
            ),
            const SizedBox(height: 36),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back to Decks'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryChip(String label, int count, Color color) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$count',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: color),
          ),
        ),
        const SizedBox(height: 5),
        Text(label, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
