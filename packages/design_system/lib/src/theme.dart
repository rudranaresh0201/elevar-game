import 'package:flutter/material.dart';

import 'colors.dart';

/// Type and theme.
///
/// Two faces, both rounded to match the artwork's soft cartoon geometry: Baloo
/// 2 ExtraBold does all the shouting (scores, titles, buttons) and Fredoka
/// SemiBold handles everything that has to be read rather than seen.
abstract final class ElevarType {
  static const String _display = 'Baloo2';
  static const String _body = 'Fredoka';
  static const String _package = 'design_system';

  static TextStyle display(double size, {Color color = ElevarColors.white}) =>
      TextStyle(
        fontFamily: _display,
        package: _package,
        fontWeight: FontWeight.w800,
        fontSize: size,
        height: 1.0,
        letterSpacing: -0.5,
        color: color,
      );

  static TextStyle body(
    double size, {
    Color color = ElevarColors.white,
    FontWeight weight = FontWeight.w600,
  }) =>
      TextStyle(
        fontFamily: _body,
        package: _package,
        fontWeight: weight,
        fontSize: size,
        height: 1.25,
        color: color,
      );

  /// Uppercase micro-labels — "BEST OF 11", "VS BOT".
  static TextStyle label(double size, {Color color = ElevarColors.muted}) =>
      TextStyle(
        fontFamily: _body,
        package: _package,
        fontWeight: FontWeight.w600,
        fontSize: size,
        height: 1.2,
        letterSpacing: 1.6,
        color: color,
      );
}

abstract final class ElevarTheme {
  /// The game commits to one dark, saturated look rather than tracking the
  /// system theme — an arcade cabinet does not have a light mode.
  static ThemeData build() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: ElevarColors.surface,
      colorScheme: base.colorScheme.copyWith(
        primary: ElevarColors.table,
        secondary: ElevarColors.ball,
        surface: ElevarColors.surface,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: 'Fredoka',
        bodyColor: ElevarColors.white,
        displayColor: ElevarColors.white,
      ),
    );
  }
}
