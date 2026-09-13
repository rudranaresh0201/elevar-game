import 'package:game_core/game_core.dart';

import 'simulation.dart';

class FruitDropRunner {
  FruitDropRunner({required this.simulation})
      : input = SampledInput(
          seed: simulation.seed,
          channelCount: FruitInput.channelCount,
          tickHz: FruitDropSimulation.tickHz,
          sampleEveryTicks: 3,
        );

  final FruitDropSimulation simulation;
  final SampledInput input;

  void aimAt(double normalisedX) => input.set(0, normalisedX);

  /// Aims and drops on the same sample, so the fruit falls where the finger
  /// lifted rather than where it was a frame earlier.
  void dropAt(double normalisedX) {
    if (input.isPulsePending(1)) return;
    input
      ..set(0, normalisedX)
      ..pulse(1);
  }

  void tick() {
    if (simulation.isComplete) return;
    simulation.step(FruitInput.fromChannels(input.advance(simulation.tick)));
  }

  List<int> finishRecording() => input.finish();
}

FruitDropSimulation replayFruitDrop(ReplayReader replay, {required JarSize jar}) {
  final sim = FruitDropSimulation(seed: replay.seed, jar: jar);
  for (var t = 0; t < replay.tickCount && !sim.isComplete; t++) {
    sim.step(FruitInput.fromChannels(replay.sampleAt(t)));
  }
  return sim;
}

/// A scripted player: drops each fruit above the fruit it would merge with, or
/// failing that at the lowest point in the pile, with some aim error.
class ProxyDropper {
  ProxyDropper({this.skill = 0.7, int seed = 1})
      : _rng = DeterministicRng.stream(seed, 12);

  final double skill;
  final DeterministicRng _rng;
  int _wait = 0;

  double? dropFor(FruitDropSimulation sim) {
    if (!sim.canDrop) return null;
    if (++_wait < 20) return null;
    _wait = 0;
    final w = sim.width;
    double? x;
    var bestY = -1.0;
    for (final f in sim.fruits) {
      if (f.tier == sim.current && f.position.y > bestY) {
        bestY = f.position.y;
        x = f.position.x;
      }
    }
    if (x == null || _rng.chance(1 - skill)) {
      // The lowest column: sample and take the deepest free drop.
      var lowest = -1.0;
      for (var i = 0; i <= 10; i++) {
        final cx = w * (0.05 + 0.9 * i / 10);
        var top = FruitDropSimulation.height;
        for (final f in sim.fruits) {
          if ((f.position.x - cx).abs() < f.radius) {
            final t = f.position.y - f.radius;
            if (t < top) top = t;
          }
        }
        if (top > lowest) {
          lowest = top;
          x = cx;
        }
      }
    }
    final error = (1 - skill) * 80;
    return clampD((x! + (_rng.nextDouble() * 2 - 1) * error) / w, 0, 1);
  }
}

FruitDropSimulation simulateFruitDrop({
  required int seed,
  JarSize jar = JarSize.standard,
  ProxyDropper? player,
  FruitDropRunner Function(FruitDropSimulation)? recordWith,
  int maxTicks = FruitDropSimulation.tickHz * 60 * 20,
}) {
  final sim = FruitDropSimulation(seed: seed, jar: jar);
  final runner = recordWith?.call(sim);
  while (!sim.isComplete && sim.tick < maxTicks) {
    final drop = player?.dropFor(sim);
    if (runner != null) {
      if (drop != null) runner.dropAt(drop);
      runner.tick();
    } else {
      sim.step(FruitInput(aimX: drop ?? sim.aim, drop: drop == null ? 0 : 1));
    }
  }
  return sim;
}
