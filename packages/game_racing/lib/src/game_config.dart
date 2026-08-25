import 'package:game_core/game_core.dart';
import 'package:racing_sim/racing_sim.dart';

/// Everything chosen on the mode-select screen.
class RaceConfig {
  const RaceConfig({
    required this.mode,
    required this.seed,
    required this.trackName,
    this.botDifficulty,
    this.rules = RaceRules.standard,
    this.sessionToken,
    this.autoGas = true,
  });

  final GameMode mode;
  final BotDifficulty? botDifficulty;
  final RaceRules rules;
  final String trackName;

  /// The race seed. In production this comes from a server-issued session
  /// token; offline, it is drawn locally and the race submits unverified.
  final int seed;

  final String? sessionToken;

  /// Holds the throttle down automatically so the player only steers and
  /// brakes.
  ///
  /// **On by default.** It started as an accessibility option and turned out to
  /// be the better game: four targets for two thumbs is a lot to coordinate
  /// while also reading a circuit, and holding the throttle is not a decision —
  /// nobody chooses to go slower on a straight. Turning it off leaves a manual
  /// throttle for anyone who wants one.
  final bool autoGas;

  bool get isTwoHuman => mode == GameMode.local2P;

  RaceTrack buildTrack() => Tracks.byName(trackName);
}

/// What the game hands back when the race ends.
class RaceOutcome {
  const RaceOutcome({
    required this.result,
    required this.replay,
    required this.bestLapMs,
    required this.cleanliness,
  });

  final GameResult result;
  final List<int> replay;

  /// P1's quickest lap, or null if they never completed one. Carried here
  /// rather than read back off the simulation because the game widget — and
  /// with it the simulation — is torn down before the result screen builds.
  final int? bestLapMs;

  /// Fraction of P1's race spent on the dirt, 0..1.
  final double cleanliness;
}
