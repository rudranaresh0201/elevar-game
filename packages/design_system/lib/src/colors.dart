import 'package:flutter/painting.dart';

/// Colours sampled directly from the reference artwork.
///
/// The table reads as leaf green at a glance and is actually mint — worth
/// having measured rather than guessed, because the yellow ball only pops
/// against the cooler hue.
abstract final class ElevarColors {
  /// Thick cartoon outlines. Everything is drawn over this.
  static const Color ink = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);

  /// The table.
  static const Color table = Color(0xFF27D6A2);
  static const Color tableLight = Color(0xFF6FE3C0);
  static const Color tableDark = Color(0xFF1AA87C);

  /// The ball, and the one warm colour in the whole scene.
  static const Color ball = Color(0xFFFFF200);

  /// Player one — bottom of the screen, always the account holder.
  static const Color p1 = Color(0xFFFF2B2B);
  static const Color p1Deep = Color(0xFFD4141C);

  /// Player two — top of the screen; the guest, or the bot.
  static const Color p2 = Color(0xFF007AF5);
  static const Color p2Deep = Color(0xFF0B4FD0);

  /// The diagonal split behind everything, off-table.
  static const Color backdropRed = Color(0xFFFF1024);
  static const Color backdropBlue = Color(0xFF3F5BFF);

  /// Menu surfaces.
  static const Color surface = Color(0xFF12161C);
  static const Color surfaceRaised = Color(0xFF1C2028);
  static const Color muted = Color(0xFF8A94A6);
}
