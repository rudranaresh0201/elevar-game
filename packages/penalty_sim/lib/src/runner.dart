import 'package:game_core/game_core.dart';

import 'goal.dart';
import 'simulation.dart';

/// Drives a live shootout and records it.
class PenaltyRunner {
  PenaltyRunner({required this.simulation})
      : input = SampledInput(
          seed: simulation.seed,
          channelCount: PenaltyInput.channelCount,
          tickHz: PenaltySimulation.tickHz,
          sampleEveryTicks: 3,
        );

  final PenaltySimulation simulation;
  final SampledInput input;

  /// A swipe has been turned into a shot. The aim, power and curve land on the
  /// same sample as the trigger, so the simulation reads them together.
  void shoot(ShotParams shot) {
    if (input.isPulsePending(4)) return;
    input
      ..set(0, shot.target.normalisedX)
      ..set(1, shot.target.normalisedY)
      ..set(2, shot.power)
      ..set(3, (shot.curve + 1) / 2)
      ..pulse(4);
  }

  void dive(GoalPoint at) {
    if (input.isPulsePending(7)) return;
    input
      ..set(5, at.normalisedX)
      ..set(6, at.normalisedY)
      ..pulse(7);
  }

  void tick() {
    if (simulation.isComplete) return;
    simulation.step(PenaltyInput.fromChannels(input.advance(simulation.tick)));
  }

  List<int> finishRecording() => input.finish();
}

PenaltySimulation replayShootout(
  ReplayReader replay, {
  required GameMode mode,
  BotDifficulty? botDifficulty,
}) {
  final sim = PenaltySimulation(
    seed: replay.seed,
    mode: mode,
    botDifficulty: botDifficulty,
  );
  for (var t = 0; t < replay.tickCount && !sim.isComplete; t++) {
    sim.step(PenaltyInput.fromChannels(replay.sampleAt(t)));
  }
  return sim;
}

/// Scripted people, for tests and for tuning the bots.
///
/// The shooter picks a corner and misses it by an amount set by [skill]; the
/// keeper waits a human reaction time after the kick, then dives at where it
/// judges the ball will cross, misjudged by an amount set by [skill].
class ProxyPlayer {
  ProxyPlayer({this.skill = 0.7, int seed = 99})
      : _rng = DeterministicRng.stream(seed, 55);

  final double skill;
  final DeterministicRng _rng;
  int _flightTicks = 0;

  ShotParams? shotFor(PenaltySimulation sim) {
    if (!sim.acceptsShot) return null;
    final side = _rng.nextSign();
    final error = 1.3 * (1 - skill);
    return ShotParams(
      target: GoalPoint(
        side * _rng.nextRange(2.0, 3.3) + _rng.nextRange(-1, 1) * error,
        _rng.nextRange(0.3, 2.1) + _rng.nextRange(-1, 1) * error * 0.6,
      ),
      power: _rng.nextRange(0.45, 0.85),
      curve: _rng.nextRange(-0.5, 0.5),
    );
  }

  GoalPoint? diveFor(PenaltySimulation sim) {
    if (sim.phase != PenaltyPhase.flight) {
      _flightTicks = 0;
      return null;
    }
    _flightTicks++;
    if (!sim.acceptsDive) return null;
    // In simulation ticks. The game plays a shot at a human keeper at 0.6x
    // speed, so a real 0.3 s reaction costs only 0.18 s of flight.
    final reaction = (0.42 - 0.2 * skill) * 0.6 * PenaltySimulation.tickHz;
    if (_flightTicks < reaction) return null;
    // A person drags the gloves and keeps correcting, a few times a second.
    if ((_flightTicks - reaction.round()) % 8 != 0) return null;
    final crossing = sim.predictCrossing(Goal.keeperZ);
    // Judging where a ball will cross from a perspective view is never exact,
    // but it gets better as the ball comes closer.
    final flight = (Goal.spotZ - sim.ball.z) / Goal.spotZ;
    final error = (0.35 + 1.8 * (1 - skill)) * (1 - 0.6 * flight);
    return GoalPoint(
      crossing.x + _rng.nextRange(-1, 1) * error,
      crossing.y + _rng.nextRange(-1, 1) * error * 0.5,
    );
  }
}

PenaltySimulation simulateShootout({
  required int seed,
  GameMode mode = GameMode.vsBot,
  BotDifficulty? botDifficulty = BotDifficulty.medium,
  ProxyPlayer? human,
  PenaltyRunner Function(PenaltySimulation)? recordWith,
}) {
  final sim = PenaltySimulation(seed: seed, mode: mode, botDifficulty: botDifficulty);
  final runner = recordWith?.call(sim);
  while (!sim.isComplete) {
    final shot = human?.shotFor(sim);
    final dive = human?.diveFor(sim);
    if (runner != null) {
      if (shot != null) runner.shoot(shot);
      if (dive != null) runner.dive(dive);
      runner.tick();
    } else {
      sim.step(PenaltyInput(
        aim: shot?.target ?? const GoalPoint(0, 1),
        power: shot?.power ?? 0,
        curve: shot?.curve ?? 0,
        fire: shot == null ? 0 : 1,
        dive: dive ?? const GoalPoint(0, 1),
        diveTrigger: dive == null ? 0 : 1,
      ));
    }
  }
  return sim;
}
