import 'package:game_core/game_core.dart';
import 'package:pingpong_sim/pingpong_sim.dart';

/// Everything chosen on the mode-select screen.
class PongConfig {
  const PongConfig({
    required this.mode,
    required this.seed,
    this.botDifficulty,
    this.rules = PongRules.standard,
    this.sessionToken,
  });

  final GameMode mode;
  final BotDifficulty? botDifficulty;
  final PongRules rules;

  /// The match seed. In production this comes from a server-issued session
  /// token; offline, it is drawn locally and the match is submitted unverified.
  final int seed;

  final String? sessionToken;

  bool get isTwoHuman => mode == GameMode.local2P;
}

/// What the game hands back when the match ends.
class PongOutcome {
  const PongOutcome({required this.result, required this.replay});

  final GameResult result;
  final List<int> replay;
}
