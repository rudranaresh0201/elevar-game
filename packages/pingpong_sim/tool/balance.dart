// ignore_for_file: avoid_print
// Measures how often a scripted human of a given skill beats each bot.
// Run: dart run tool/balance.dart
import 'package:game_core/game_core.dart';
import 'package:pingpong_sim/pingpong_sim.dart';

void main() {
  const matches = 120;
  const skills = <double>[0.35, 0.6, 0.85, 1.0];

  print('bot      ${skills.map((s) => 'skill ${s.toStringAsFixed(2)}').join('  ')}   avgRally  avgSecs');
  for (final difficulty in BotDifficulty.values) {
    final cells = <String>[];
    var rallySum = 0.0;
    var tickSum = 0;
    var count = 0;

    for (final skill in skills) {
      var wins = 0;
      for (var seed = 0; seed < matches; seed++) {
        final sim = simulateHeadless(
          seed: seed * 7919 + 13,
          mode: GameMode.vsBot,
          botDifficulty: difficulty,
          rules: PongRules.standard,
          p1Controller: proxyHuman(side: PongSide.p1, skill: skill),
        );
        if (sim.state.p1Score > sim.state.p2Score) wins++;
        rallySum += sim.state.averageRally;
        tickSum += sim.tick;
        count++;
      }
      cells.add('${(wins * 100 / matches).toStringAsFixed(0).padLeft(9)}%');
    }
    print('${difficulty.name.padRight(8)} ${cells.join('  ')}   '
        '${(rallySum / count).toStringAsFixed(1).padLeft(8)}  '
        '${(tickSum / count / 120).toStringAsFixed(1).padLeft(7)}');
  }
}
