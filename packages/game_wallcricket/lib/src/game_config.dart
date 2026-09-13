import 'package:game_core/game_core.dart';
import 'package:wallcricket_sim/wallcricket_sim.dart';

/// Everything chosen on the mode-select screen.
class WallCricketConfig {
  const WallCricketConfig({
    required this.pace,
    required this.seed,
    this.rules = WallCricketRules.classic,
    this.sessionToken,
  });

  final Pace pace;
  final WallCricketRules rules;
  final int seed;
  final String? sessionToken;

  String get formatName => switch (rules.overs) {
        2 => 'QUICK',
        5 => 'LONG',
        _ => 'CLASSIC',
      };

  WallCricketConfig rematch(int previousSeed) => WallCricketConfig(
        pace: pace,
        rules: rules,
        seed: previousSeed + 1,
      );
}

/// What the game hands back when the innings ends.
class WallCricketOutcome {
  const WallCricketOutcome({
    required this.result,
    required this.replay,
    required this.runs,
    required this.wickets,
    required this.balls,
    required this.fours,
    required this.sixes,
    required this.target,
  });

  final GameResult result;
  final List<int> replay;
  final int runs;
  final int wickets;
  final int balls;
  final int fours;
  final int sixes;
  final int target;
}
