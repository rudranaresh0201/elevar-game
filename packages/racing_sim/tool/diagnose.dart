// ignore_for_file: avoid_print
// Why is the difficulty ladder a cliff? Look at the numbers the bot actually
// sees, rather than the ones it was designed around.
import 'dart:math' as math;

import 'package:game_core/game_core.dart';
import 'package:racing_sim/racing_sim.dart';

void main() {
  final track = Tracks.dustbowl();

  // 1. What does `curvatureAhead` actually report at racing speed? The bot's
  //    "am I in a corner" test and its mistake roll both hang off this.
  const span = 244.0; // 90 + 280 * 0.55, a realistic braking span
  final bends = <double>[];
  for (var d = 0.0; d < track.totalLength; d += 10) {
    bends.add(track.curvatureAhead(d, span));
  }
  bends.sort();
  double pct(double p) => bends[(bends.length * p).floor().clamp(0, bends.length - 1)];
  print('curvatureAhead over a $span-unit span:');
  print('  min ${bends.first.toStringAsFixed(3)}'
      '  p50 ${pct(0.5).toStringAsFixed(3)}'
      '  p75 ${pct(0.75).toStringAsFixed(3)}'
      '  p90 ${pct(0.90).toStringAsFixed(3)}'
      '  max ${bends.last.toStringAsFixed(3)}');
  final overThreshold = bends.where((b) => b > 0.16).length / bends.length;
  print('  fraction of the lap reading as "in a corner" (>0.16): '
      '${(overThreshold * 100).toStringAsFixed(1)}%');

  // 2. What corner speed does that imply, and how does it compare to terminal?
  const terminal = RaceField.engineForce / RaceField.dragOnTrack;
  print('');
  print('terminal speed ${terminal.toStringAsFixed(0)}');
  for (final p in <double>[0.5, 0.75, 0.9, 1.0]) {
    final bend = p == 1.0 ? bends.last : pct(p);
    final theta = 2 * math.sqrt(bend);
    final radius = theta < 1e-4 ? 1e9 : span / theta;
    final gripSpeed = math.sqrt(RaceField.lateralGripLimit * radius);
    print('  bend ${bend.toStringAsFixed(3)}'
        ' -> radius ${radius.toStringAsFixed(0)}'
        ' -> grip speed ${gripSpeed.toStringAsFixed(0)}'
        '  (${(gripSpeed / terminal * 100).toStringAsFixed(0)}% of terminal)');
  }

  // 3. Do the difficulties actually produce different lap times on their own?
  //    Race each bot against a car that never moves, so the only thing being
  //    measured is the bot's own pace.
  print('');
  print('bot solo pace (racing a parked car):');
  for (final difficulty in BotDifficulty.values) {
    final laps = <double>[];
    var offTrack = 0;
    var racing = 0;
    for (var i = 0; i < 6; i++) {
      final sim = simulateHeadless(
        seed: 7777 * (i + 1),
        mode: GameMode.vsBot,
        track: track,
        botDifficulty: difficulty,
        rules: const RaceRules(laps: 3, maxSeconds: 200),
        p1Controller: (_, __) => CarInput.coasting,
      );
      for (final t in sim.state.p2.lapTicks) {
        laps.add(t / 120);
      }
      offTrack += sim.state.p2.racingTicks - sim.state.p2.onTrackTicks;
      racing += sim.state.p2.racingTicks;
    }
    laps.sort();
    final mean = laps.isEmpty
        ? 0.0
        : laps.reduce((a, b) => a + b) / laps.length;
    print('  ${difficulty.name.padRight(6)}'
        ' laps ${laps.length}'
        '  mean ${mean.toStringAsFixed(2)}s'
        '  best ${laps.isEmpty ? "-" : laps.first.toStringAsFixed(2)}'
        '  worst ${laps.isEmpty ? "-" : laps.last.toStringAsFixed(2)}'
        '  offtrack ${(offTrack / math.max(racing, 1) * 100).toStringAsFixed(1)}%');
  }

  // 4. And the proxy human, across skill.
  print('');
  print('proxy human solo pace:');
  for (final skill in <double>[0.35, 0.60, 0.85, 1.00]) {
    final laps = <double>[];
    var offTrack = 0;
    var racing = 0;
    for (var i = 0; i < 6; i++) {
      final seed = 31337 * (i + 1);
      final sim = simulateHeadless(
        seed: seed,
        mode: GameMode.local2P,
        track: track,
        rules: const RaceRules(laps: 3, maxSeconds: 200),
        p1Controller: proxyDriver(
          side: RacerSide.p1,
          track: track,
          skill: skill,
          seed: seed ^ 0x5EED,
        ),
        p2Controller: (_, __) => CarInput.coasting,
      );
      for (final t in sim.state.p1.lapTicks) {
        laps.add(t / 120);
      }
      offTrack += sim.state.p1.racingTicks - sim.state.p1.onTrackTicks;
      racing += sim.state.p1.racingTicks;
    }
    laps.sort();
    final mean = laps.isEmpty
        ? 0.0
        : laps.reduce((a, b) => a + b) / laps.length;
    print('  skill ${skill.toStringAsFixed(2)}'
        ' laps ${laps.length}'
        '  mean ${mean.toStringAsFixed(2)}s'
        '  best ${laps.isEmpty ? "-" : laps.first.toStringAsFixed(2)}'
        '  worst ${laps.isEmpty ? "-" : laps.last.toStringAsFixed(2)}'
        '  offtrack ${(offTrack / math.max(racing, 1) * 100).toStringAsFixed(1)}%');
  }
}
