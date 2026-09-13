// ignore_for_file: avoid_print
import 'package:fruitdrop_sim/fruitdrop_sim.dart';

void main() {
  for (final jar in JarSize.values) {
    for (final skill in <double>[0.4, 0.8]) {
      var score = 0, drops = 0, secs = 0, wins = 0, biggest = 0;
      const n = 8;
      final watch = Stopwatch()..start();
      for (var seed = 1; seed <= n; seed++) {
        final sim = simulateFruitDrop(seed: seed, jar: jar, player: ProxyDropper(skill: skill, seed: seed));
        score += sim.score;
        drops += sim.drops;
        secs += sim.tick ~/ 120;
        if (sim.score >= jar.target) wins++;
        if (sim.biggestTier > biggest) biggest = sim.biggestTier;
      }
      print('${jar.name.padRight(8)} skill $skill: score ${score ~/ n} target ${jar.target} '
          'win ${(100 * wins / n).round()}% drops ${drops ~/ n} secs ${secs ~/ n} '
          'biggest $biggest  (sim ms/game ${watch.elapsedMilliseconds ~/ n})');
    }
  }
}
