// ignore_for_file: avoid_print
import 'package:game_core/game_core.dart';
import 'package:penalty_sim/penalty_sim.dart';

/// Scoring and saving rates for a scripted player against each bot.
void main() {
  for (final d in BotDifficulty.values) {
    for (final skill in <double>[0.3, 0.6, 0.9]) {
      var scored = 0, shots = 0, conceded = 0, faced = 0, wins = 0, secs = 0;
      const n = 60;
      for (var seed = 1; seed <= n; seed++) {
        final sim = simulateShootout(
          seed: seed,
          botDifficulty: d,
          human: ProxyPlayer(skill: skill, seed: seed),
        );
        scored += sim.p1Goals;
        shots += sim.p1Kicks.length;
        conceded += sim.p2Goals;
        faced += sim.p2Kicks.length;
        secs += sim.tick ~/ 120;
        if (sim.p1Goals > sim.p2Goals) wins++;
      }
      print('${d.name.padRight(6)} skill $skill: '
          'score ${(100 * scored / shots).round()}% '
          'save ${(100 - 100 * conceded / faced).round()}% '
          'win ${(100 * wins / n).round()}% secs ${secs ~/ n}');
    }
  }
}
