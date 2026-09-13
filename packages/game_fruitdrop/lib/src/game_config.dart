import 'package:fruitdrop_sim/fruitdrop_sim.dart';
import 'package:game_core/game_core.dart';

class FruitDropConfig {
  const FruitDropConfig({required this.jar, required this.seed, this.sessionToken});

  final JarSize jar;
  final int seed;
  final String? sessionToken;

  FruitDropConfig rematch(int previousSeed) =>
      FruitDropConfig(jar: jar, seed: previousSeed + 1);
}

class FruitDropOutcome {
  const FruitDropOutcome({
    required this.result,
    required this.replay,
    required this.score,
    required this.biggestTier,
    required this.merges,
    required this.drops,
    required this.endReason,
    required this.stars,
    required this.target,
  });

  final RoundEnd? endReason;
  final int stars;
  final int target;

  final GameResult result;
  final List<int> replay;
  final int score;
  final int biggestTier;
  final int merges;
  final int drops;
}
