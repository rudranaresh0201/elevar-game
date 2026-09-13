import 'package:game_core/game_core.dart';

class DuelConfig {
  const DuelConfig({
    required this.mode,
    required this.seed,
    this.botDifficulty,
    this.sessionToken,
  });

  final GameMode mode;
  final BotDifficulty? botDifficulty;
  final int seed;
  final String? sessionToken;

  bool get isTwoHuman => mode == GameMode.local2P;

  DuelConfig rematch(int previousSeed) =>
      DuelConfig(mode: mode, botDifficulty: botDifficulty, seed: previousSeed + 1);
}

class DuelOutcome {
  const DuelOutcome({
    required this.result,
    required this.replay,
    required this.hits,
    required this.headshots,
    required this.turns,
  });

  final GameResult result;
  final List<int> replay;
  final int hits;
  final int headshots;
  final int turns;
}
