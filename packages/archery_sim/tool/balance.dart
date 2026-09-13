// ignore_for_file: avoid_print
import 'package:archery_sim/archery_sim.dart';
import 'package:game_core/game_core.dart';

void main() {
  for (final d in BotDifficulty.values) {
    for (final skill in <double>[0.3, 0.6, 0.9]) {
      var wins = 0, turns = 0, secs = 0, hits = 0, shots = 0;
      const n = 30;
      for (var seed = 1; seed <= n; seed++) {
        final sim = simulateDuel(
          seed: seed,
          botDifficulty: d,
          human: ProxyArcher(skill: skill, seed: seed),
        );
        if (sim.p1Hp > sim.p2Hp) wins++;
        turns += sim.turnsTaken;
        secs += sim.tick ~/ 120;
        hits += sim.p1Hits;
        shots += (sim.turnsTaken + 1) ~/ 2;
      }
      print('${d.name.padRight(6)} skill $skill: win ${(100 * wins / n).round()}% '
          'turns ${(turns / n).toStringAsFixed(1)} '
          'hit ${(100 * hits / shots).round()}% secs ${secs ~/ n}');
    }
  }
}
