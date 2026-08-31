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

/// The racing circuit, sampled from the reference art the same way the table
/// was.
///
/// It lives beside [ElevarColors] rather than inside the racing package because
/// a second game that reuses the outdoor look — a kart track, a delivery dash —
/// should reach for the same greens rather than sample them again slightly
/// differently.
abstract final class RacingColors {
  /// Two greens, alternating on a large grid, for the checkerboard the
  /// reference lays under everything.
  static const Color grass = Color(0xFF57C22B);
  static const Color grassAlt = Color(0xFF4EB325);

  /// The dirt surface and the sandy rim that separates it from the grass.
  static const Color dirt = Color(0xFF7B4B2A);
  static const Color dirtLight = Color(0xFF8C5832);
  static const Color rim = Color(0xFFD9A62E);

  /// Scuff marks left by a sliding car, and the dust they throw up.
  static const Color skid = Color(0xFF5E381F);
  static const Color dust = Color(0xFFC9A227);

  /// Scenery.
  static const Color foliage = Color(0xFF2E9B3C);
  static const Color foliageDeep = Color(0xFF1F7A2C);
  static const Color trunk = Color(0xFF6B3F22);
  static const Color water = Color(0xFF2BB6D4);
  static const Color waterDeep = Color(0xFF1C90AC);
  static const Color stone = Color(0xFFD5D8DC);
  static const Color stoneDeep = Color(0xFFAAB0B7);
  static const Color tyre = Color(0xFF2A2A2E);

  /// The cars. P1 keeps the red the paddle had and P2 the blue, so a player's
  /// colour means the same thing in every game in the hub.
  static const Color carP1 = ElevarColors.p1;
  static const Color carP1Deep = ElevarColors.p1Deep;
  static const Color carP2 = Color(0xFF29C7F0);
  static const Color carP2Deep = Color(0xFF1189B5);

  static const Color glass = Color(0xFF1B2733);
}

/// Table soccer, sampled from the reference art the same way the table and the
/// circuit were.
///
/// The pitch is two greens rather than one. A single flat green over a
/// 1000 x 1800 rectangle reads as a bug — there is nothing for the eye to
/// measure the ball's travel against — and mown bands are what a real pitch
/// gives you for free.
abstract final class SoccerColors {
  /// Everything outside the touchline. The reference art puts the pitch on a
  /// flat sky blue rather than on black, and it is most of why the thing looks
  /// like a toy rather than a simulator.
  static const Color surround = Color(0xFF5BB4DC);
  static const Color surroundDeep = Color(0xFF3F9BC4);

  static const Color turf = Color(0xFF4EB537);
  static const Color turfBand = Color(0xFF45A32F);

  /// Line markings, and the one colour that is never anything else.
  static const Color line = Color(0xFFFFFFFF);

  /// The net behind each goal.
  static const Color net = Color(0xFFBFD9E8);
  static const Color netMesh = Color(0xFF8FB6CC);

  /// The woodwork. Ball off the post is the best thing that happens in a
  /// match, so it is worth being able to see which one it hit.
  static const Color post = Color(0xFF1A1A1A);

  /// The counters. P1 keeps the red the paddle and the car had, P2 the blue,
  /// so a player's colour means the same thing in every game in the hub.
  static const Color discP1 = ElevarColors.p1;
  static const Color discP1Deep = ElevarColors.p1Deep;
  static const Color discP2 = Color(0xFF29B6F0);
  static const Color discP2Deep = Color(0xFF0E86BC);

  /// The ball.
  static const Color ball = Color(0xFFFFFFFF);
  static const Color ballMark = Color(0xFF1A1A1A);

  /// The aim band, from a gentle tap to a full-power strike. Power is the one
  /// thing a player has to judge before they commit, so it is worth a colour
  /// and not only a length.
  static const Color powerLow = Color(0xFF27D6A2);
  static const Color powerMid = Color(0xFFFFF200);
  static const Color powerHigh = Color(0xFFFF2B2B);
}
