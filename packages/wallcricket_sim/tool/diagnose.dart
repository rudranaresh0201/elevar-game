// ignore_for_file: avoid_print
import 'package:wallcricket_sim/wallcricket_sim.dart';

/// Prints what a scripted batter scores at each pace, for tuning the targets.
///
/// `dart run tool/diagnose.dart`. Skill "idle" is nobody touching the screen.
void main() {
  for (final pace in Pace.values) {
    for (final skill in <double?>[null, 0.4, 0.7, 1.0]) {
      var runs = 0, wickets = 0, hits = 0, balls = 0, wins = 0, secs = 0;
      const n = 40;
      for (var seed = 1; seed <= n; seed++) {
        final sim = simulateInnings(
          seed: seed,
          pace: pace,
          batter: skill == null ? null : proxyBatter(skill: skill),
        );
        runs += sim.runs;
        wickets += sim.wickets;
        hits += sim.hits;
        balls += sim.ballsBowled;
        secs += sim.tick ~/ 120;
        if (sim.runs >= sim.target) wins++;
      }
      print('${pace.name.padRight(6)} ${skill ?? 'idle'}: '
          'target ${(18 * pace.runsPerBall).round()} '
          'runs ${(runs / n).toStringAsFixed(1)} '
          'wkts ${(wickets / n).toStringAsFixed(1)} '
          'balls ${(balls / n).toStringAsFixed(1)} '
          'hit% ${(100 * hits / balls).round()} '
          'win% ${(100 * wins / n).round()} '
          'secs ${secs ~/ n}');
    }
  }
}
