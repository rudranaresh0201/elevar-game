import 'package:game_core/game_core.dart';

class PenaltyConfig {
  const PenaltyConfig({
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

  PenaltyConfig rematch(int previousSeed) => PenaltyConfig(
        mode: mode,
        botDifficulty: botDifficulty,
        seed: previousSeed + 1,
      );
}

class PenaltyOutcome {
  const PenaltyOutcome({
    required this.result,
    required this.replay,
    required this.kicksEach,
    required this.saves,
    required this.points,
    required this.bullseyes,
    required this.catches,
  });

  final int points;
  final int bullseyes;
  final int catches;

  final GameResult result;
  final List<int> replay;
  final int kicksEach;

  /// Saves made by player one.
  final int saves;
}
