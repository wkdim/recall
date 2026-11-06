import 'package:flutter/material.dart';

const _seedColor = Color(0xFF6750A4);

/// Semantic colors this app needs beyond what [ColorScheme] provides -
/// deck tile gradients/accents, the four SM-2 rating colors, the streak
/// flame, and the "all caught up" success state. Centralizing these here
/// (instead of hardcoding hex values per-screen) is what makes dark mode
/// possible without a second, hand-maintained copy of every color.
class AppColors extends ThemeExtension<AppColors> {
  final List<List<Color>> deckGradients;
  final List<Color> deckAccents;
  final Color ratingAgain;
  final Color ratingHard;
  final Color ratingGood;
  final Color ratingEasy;
  final Color streakFlame;
  final Color successBackground;
  final Color successForeground;

  /// Text drawn directly on a deck tile's gradient background - that
  /// background isn't tied to [ColorScheme], so its foreground can't be
  /// derived from onSurface/onSurfaceVariant the way normal content can.
  final Color tileForeground;
  final Color tileForegroundMuted;
  final Color tileTrackBackground;

  const AppColors({
    required this.deckGradients,
    required this.deckAccents,
    required this.ratingAgain,
    required this.ratingHard,
    required this.ratingGood,
    required this.ratingEasy,
    required this.streakFlame,
    required this.successBackground,
    required this.successForeground,
    required this.tileForeground,
    required this.tileForegroundMuted,
    required this.tileTrackBackground,
  });

  static const light = AppColors(
    deckGradients: [
      [Color(0xFFEDE0FF), Color(0xFFD8B4FE)],
      [Color(0xFFDBEAFE), Color(0xFFBFDBFE)],
      [Color(0xFFD1FAE5), Color(0xFFA7F3D0)],
      [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
      [Color(0xFFFFE4E6), Color(0xFFFECACA)],
      [Color(0xFFE0F2FE), Color(0xFFBAE6FD)],
    ],
    deckAccents: [
      Color(0xFF7C3AED),
      Color(0xFF2563EB),
      Color(0xFF059669),
      Color(0xFFD97706),
      Color(0xFFE11D48),
      Color(0xFF0284C7),
    ],
    ratingAgain: Color(0xFFEF5350),
    ratingHard: Color(0xFFFB8C00),
    ratingGood: Color(0xFF43A047),
    ratingEasy: Color(0xFF1E88E5),
    streakFlame: Color(0xFFD97706),
    successBackground: Color(0xFFDCFCE7),
    successForeground: Color(0xFF15803D),
    tileForeground: Color(0xFF1C1B1F),
    tileForegroundMuted: Colors.black45,
    tileTrackBackground: Colors.white38,
  );

  static const dark = AppColors(
    deckGradients: [
      [Color(0xFF3A2E5C), Color(0xFF4C3A78)],
      [Color(0xFF223A5C), Color(0xFF2C4A78)],
      [Color(0xFF1E4235), Color(0xFF285A45)],
      [Color(0xFF4A3D1E), Color(0xFF5C4A22)],
      [Color(0xFF4A2530), Color(0xFF5C2E3C)],
      [Color(0xFF1E3A4A), Color(0xFF284A5C)],
    ],
    deckAccents: [
      Color(0xFFC4A7F5),
      Color(0xFF9DBFF5),
      Color(0xFF7FD4B0),
      Color(0xFFF0C178),
      Color(0xFFF592A8),
      Color(0xFF82CDEF),
    ],
    ratingAgain: Color(0xFFEF6B65),
    ratingHard: Color(0xFFFCA84A),
    ratingGood: Color(0xFF66C46E),
    ratingEasy: Color(0xFF5FA8F0),
    streakFlame: Color(0xFFF0B15A),
    successBackground: Color(0xFF17301F),
    successForeground: Color(0xFF5FD39A),
    tileForeground: Colors.white,
    tileForegroundMuted: Colors.white60,
    tileTrackBackground: Color(0x33000000),
  );

  @override
  AppColors copyWith({
    List<List<Color>>? deckGradients,
    List<Color>? deckAccents,
    Color? ratingAgain,
    Color? ratingHard,
    Color? ratingGood,
    Color? ratingEasy,
    Color? streakFlame,
    Color? successBackground,
    Color? successForeground,
    Color? tileForeground,
    Color? tileForegroundMuted,
    Color? tileTrackBackground,
  }) {
    return AppColors(
      deckGradients: deckGradients ?? this.deckGradients,
      deckAccents: deckAccents ?? this.deckAccents,
      ratingAgain: ratingAgain ?? this.ratingAgain,
      ratingHard: ratingHard ?? this.ratingHard,
      ratingGood: ratingGood ?? this.ratingGood,
      ratingEasy: ratingEasy ?? this.ratingEasy,
      streakFlame: streakFlame ?? this.streakFlame,
      successBackground: successBackground ?? this.successBackground,
      successForeground: successForeground ?? this.successForeground,
      tileForeground: tileForeground ?? this.tileForeground,
      tileForegroundMuted: tileForegroundMuted ?? this.tileForegroundMuted,
      tileTrackBackground: tileTrackBackground ?? this.tileTrackBackground,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return this; // Discrete palettes - no need to interpolate between them.
  }
}

extension AppColorsX on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}

ThemeData buildLightTheme() => _buildTheme(Brightness.light, AppColors.light);
ThemeData buildDarkTheme() => _buildTheme(Brightness.dark, AppColors.dark);

ThemeData _buildTheme(Brightness brightness, AppColors appColors) {
  final colorScheme = ColorScheme.fromSeed(seedColor: _seedColor, brightness: brightness);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,
    extensions: [appColors],
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: colorScheme.onSurface,
      titleTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    cardTheme: CardThemeData(
      color: colorScheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),
  );
}
