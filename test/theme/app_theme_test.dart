import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/theme/app_theme.dart';

void main() {
  test('both themes carry the AppColors extension', () {
    final light = buildLightTheme();
    final dark = buildDarkTheme();

    expect(light.extension<AppColors>(), isNotNull);
    expect(dark.extension<AppColors>(), isNotNull);
  });

  test('light and dark themes have the matching brightness', () {
    expect(buildLightTheme().brightness, Brightness.light);
    expect(buildDarkTheme().brightness, Brightness.dark);
  });

  test('light and dark themes use visibly different palettes', () {
    final light = buildLightTheme().extension<AppColors>()!;
    final dark = buildDarkTheme().extension<AppColors>()!;

    expect(light.tileForeground, isNot(dark.tileForeground));
    expect(light.successBackground, isNot(dark.successBackground));
  });
}
