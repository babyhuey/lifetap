import 'package:flutter/material.dart';

/// Central design tokens for the black + cyan life-counter look. Defined once
/// here so every widget pulls the same values rather than re-declaring colors.
abstract final class LifeTapColors {
  static const background = Color(0xFF000000);
  static const accent = Color(0xFF33C7F0);
  static const surface = Color(0xFF141414);
  static const chip = Color(0xFF1E1E1E);
  static const chipUnselected = Color(0xFF2A2A2A);
  static const divider = Color(0xFF2C2C2C);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);
  static const positive = Color(0xFF47C266);
  static const negative = Color(0xFFE5533C);
  static const poison = Color(0xFF9B6DE8);
}

/// Dark Material theme wired to the design tokens: black scaffold and an accent
/// (cyan) primary so selected chips, toggles, and buttons all read the same.
ThemeData buildLifeTapTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: LifeTapColors.background,
    colorScheme: base.colorScheme.copyWith(
      primary: LifeTapColors.accent,
      surface: LifeTapColors.surface,
    ),
    dividerColor: LifeTapColors.divider,
  );
}
