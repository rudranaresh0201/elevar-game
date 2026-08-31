import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';

/// What the hub needs to know about a game, and nothing more.
///
/// `docs/PLAN.md` §4 specified this contract from the start; it is built now
/// rather than then because an interface derived from one implementation is a
/// description of that implementation. With ping pong and racing side by side
/// the seams are real: the hub knows a slug, a look, which modes are offered
/// and how to open the game's own mode-select. It does **not** know what a
/// rally or a lap is, and the scoring layer downstream knows even less — every
/// game reduces to a [GameResult] and the points formula never learns which
/// game produced it.
///
/// Adding game three means adding one of these and one line to the registry.
/// Nothing in scoring, persistence or the hub changes.
abstract class ElevarGame {
  const ElevarGame();

  /// Stable identifier. Matches `games.slug` on the server and the
  /// `gameSlug` on every [GameResult] this game emits.
  String get slug;

  /// Shown on the hub tile. A newline is a deliberate line break.
  String get title;

  /// One line on the mode-select screen.
  String get tagline;

  /// The tile colour, and the accent through the game's own screens.
  Color get accent;

  /// The mark on the tile.
  ///
  /// Part of the contract rather than a lookup table in the hub, for the same
  /// reason [accent] is: the hub must not grow a branch per game. A default is
  /// supplied so a reserved tile does not have to invent one.
  IconData get glyph => Icons.sports_esports_rounded;

  /// Which of the two shared-device modes this game offers.
  Set<GameMode> get supportedModes;

  /// False for a tile that is reserved but not yet playable.
  bool get isPlayable => true;

  /// The game's own mode-select screen. Each game owns this because the
  /// choices differ — ping pong picks a match length, racing picks a circuit —
  /// and forcing them through one shared screen would mean the hub growing a
  /// branch per game, which is the coupling this contract exists to prevent.
  Widget buildModeSelect(BuildContext context);
}

/// A tile with nothing behind it yet.
class ComingSoonGame extends ElevarGame {
  const ComingSoonGame({
    required this.slug,
    required this.title,
    required this.accent,
    this.glyph = Icons.lock_rounded,
  });

  @override
  final String slug;
  @override
  final String title;
  @override
  final Color accent;
  @override
  final IconData glyph;

  @override
  String get tagline => 'Coming soon.';

  @override
  Set<GameMode> get supportedModes => const <GameMode>{};

  @override
  bool get isPlayable => false;

  @override
  Widget buildModeSelect(BuildContext context) =>
      const SizedBox.shrink();
}
