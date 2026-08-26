import 'package:cricket_sim/cricket_sim.dart';
import 'package:game_core/game_core.dart';

/// Everything chosen on the mode-select screen.
class CricketConfig {
  const CricketConfig({
    required this.mode,
    required this.seed,
    this.botDifficulty,
    this.rules = CricketRules.powerplay,
    this.fieldSetting = FieldSetting.standard,
    this.sessionToken,
    this.assistedTiming = true,
  });

  final GameMode mode;
  final BotDifficulty? botDifficulty;
  final CricketRules rules;
  final FieldSetting fieldSetting;

  /// The match seed. In production this comes from a server-issued session
  /// token; offline, it is drawn locally and the match submits unverified.
  final int seed;

  final String? sessionToken;

  /// Draws the timing bar and flashes it as the ball arrives.
  ///
  /// On by default. Timing is the entire skill of batting and it is invisible
  /// — a new player who mistimes three balls has no way of knowing whether
  /// they were early or late, and "I don't know what I did wrong" is the
  /// fastest way to lose someone in the first thirty seconds.
  final bool assistedTiming;

  bool get isTwoHuman => mode == GameMode.local2P;

  String get formatName => switch (rules.overs) {
        1 => 'SUPER OVER',
        4 => 'CHASE',
        _ => 'POWERPLAY',
      };
}

/// What the game hands back when the match ends.
class CricketOutcome {
  const CricketOutcome({
    required this.result,
    required this.replay,
    required this.runs,
    required this.wickets,
    required this.balls,
    required this.boundaries,
  });

  final GameResult result;
  final List<int> replay;

  /// P1's own innings, carried here rather than read back off the simulation
  /// because the game widget is torn down before the result screen builds.
  final int runs;
  final int wickets;
  final int balls;

  /// Fours and sixes hit, which is the stat people actually want to see.
  final int boundaries;
}
