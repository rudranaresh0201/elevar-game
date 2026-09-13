import 'package:game_core/game_core.dart';

import 'simulation.dart';

class DuelRunner {
  DuelRunner({required this.simulation})
      : input = SampledInput(
          seed: simulation.seed,
          channelCount: DuelInput.channelCount,
          tickHz: DuelSimulation.tickHz,
        );

  final DuelSimulation simulation;
  final SampledInput input;

  /// Looses an arrow along [direction] at [power] (0..1).
  void loose(Vec2 direction, double power) {
    if (input.isPulsePending(3)) return;
    final d = direction.normalized;
    input
      ..set(0, (d.x + 1) / 2)
      ..set(1, (d.y + 1) / 2)
      ..set(2, power)
      ..pulse(3);
  }

  void tick() {
    if (simulation.isComplete) return;
    simulation.step(DuelInput.fromChannels(input.advance(simulation.tick)));
  }

  List<int> finishRecording() => input.finish();
}

DuelSimulation replayDuel(
  ReplayReader replay, {
  required GameMode mode,
  BotDifficulty? botDifficulty,
}) {
  final sim = DuelSimulation(seed: replay.seed, mode: mode, botDifficulty: botDifficulty);
  for (var t = 0; t < replay.tickCount && !sim.isComplete; t++) {
    sim.step(DuelInput.fromChannels(replay.sampleAt(t)));
  }
  return sim;
}

/// A scripted archer: solves the shot, then misses it by [skill]-scaled noise
/// that does not shrink — people improve less predictably than bots.
class ProxyArcher {
  ProxyArcher({this.skill = 0.6, int seed = 1})
      : _rng = DeterministicRng.stream(seed, 31);

  final double skill;
  final DeterministicRng _rng;
  int _waited = 0;

  ({Vec2 direction, double power})? shotFor(DuelSimulation sim) {
    if (!sim.acceptsAim) {
      _waited = 0;
      return null;
    }
    // Takes a moment to aim, like a person.
    if (++_waited < 60) return null;
    final side = sim.turn;
    final other = side == ArcherSide.p1 ? ArcherSide.p2 : ArcherSide.p1;
    final best = solveShot(sim, from: side, at: other);
    final error = 0.02 + 0.16 * (1 - skill);
    final d = best.direction;
    return (
      direction: Vec2(d.x, d.y + (_rng.nextDouble() * 2 - 1) * error).normalized,
      power: clampD(best.power * (1 + (_rng.nextDouble() * 2 - 1) * error), 0.1, 1),
    );
  }
}

DuelSimulation simulateDuel({
  required int seed,
  GameMode mode = GameMode.vsBot,
  BotDifficulty? botDifficulty = BotDifficulty.medium,
  ProxyArcher? human,
  DuelRunner Function(DuelSimulation)? recordWith,
}) {
  final sim = DuelSimulation(seed: seed, mode: mode, botDifficulty: botDifficulty);
  final runner = recordWith?.call(sim);
  while (!sim.isComplete) {
    final shot = human?.shotFor(sim);
    if (runner != null) {
      if (shot != null) runner.loose(shot.direction, shot.power);
      runner.tick();
    } else {
      sim.step(DuelInput(
        direction: shot?.direction ?? const Vec2(1, 0),
        power: shot?.power ?? 0,
        fire: shot == null ? 0 : 1,
      ));
    }
  }
  return sim;
}
