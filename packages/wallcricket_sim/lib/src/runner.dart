import 'package:game_core/game_core.dart';

import 'arena.dart';
import 'simulation.dart';

/// Drives a live innings and records it in the same pass.
class WallCricketRunner {
  WallCricketRunner({required this.simulation})
      : input = SampledInput(
          seed: simulation.seed,
          channelCount: WallCricketSimulation.channelCount,
          tickHz: WallCricketRules.tickHz,
          // 30 Hz. The bat is a held position like a paddle, but a swing is
          // fast, and at 20 Hz the blade would visibly step through it.
          sampleEveryTicks: 4,
        );

  final WallCricketSimulation simulation;
  final SampledInput input;

  /// How far through the swing the drag has reached, 0..1, or null when the
  /// finger is off the glass.
  void setSwing(double? swing) {
    if (swing == null) {
      input.set(1, 0);
      return;
    }
    input
      ..set(0, swing)
      ..set(1, 1);
  }

  void tick() {
    if (simulation.isComplete) return;
    final channels = input.advance(simulation.tick);
    simulation.step(WallCricketInput.fromChannels(channels));
  }

  List<int> finishRecording() => input.finish();
}

/// Re-runs a recorded innings. The server calls this and trusts only what it
/// returns.
WallCricketSimulation replayInnings(
  ReplayReader replay, {
  required Pace pace,
  WallCricketRules rules = WallCricketRules.classic,
}) {
  final simulation = WallCricketSimulation(
    seed: replay.seed,
    pace: pace,
    rules: rules,
  );
  for (var t = 0; t < replay.tickCount && !simulation.isComplete; t++) {
    simulation.step(WallCricketInput.fromChannels(replay.sampleAt(t)));
  }
  return simulation;
}

/// A scripted batter, for tests and for tuning the pace ladder.
///
/// Waits in the backlift and starts the swing a moment before the ball
/// reaches the hitting zone. [skill] sets how well that moment is judged;
/// nothing else. It returns the swing fraction to hold, or null for no touch.
double? Function(WallCricketSimulation) proxyBatter({
  double skill = 0.8,
  int noiseSeed = 1,
}) {
  final rng = DeterministicRng.stream(noiseSeed, 77);
  var swingTicks = 0;
  var lead = 0.0;
  var planned = false;
  return (sim) {
    if (sim.phase != WallCricketPhase.live || !sim.ballVisible) {
      swingTicks = 0;
      planned = false;
      return null;
    }
    if (!planned) {
      planned = true;
      // Seconds before the ball arrives to start the swing. A person
      // misjudges it, more so at low skill.
      lead = 0.16 + rng.nextRange(-1, 1) * (0.015 + 0.11 * (1 - skill));
    }
    final hitX = Arena.pivot.x + Arena.batLength * 0.8;
    final secondsAway = sim.ballVelocity.x < 0
        ? (sim.ballPosition.x - hitX) / -sim.ballVelocity.x
        : 99.0;
    if (swingTicks > 0 || secondsAway < lead) {
      swingTicks++;
      return swingTicks < 40 ? 1.0 : null;
    }
    return 0.0;
  };
}

/// Where the ball will be when it reaches [x], following gravity and one
/// bounce, or null if it will not get there. Ignores the bat — this is what a
/// batter's eye does before deciding.
Vec2? predictBallAt(WallCricketSimulation sim, double x) {
  var p = sim.ballPosition;
  var v = sim.ballVelocity;
  if (v.x >= 0) return null;
  const dt = 1 / 240;
  for (var i = 0; i < 480; i++) {
    v = Vec2(v.x, v.y + Arena.gravity * dt);
    p = p + v * dt;
    if (p.y > Arena.groundY - Arena.ballRadius && v.y > 0) {
      p = Vec2(p.x, Arena.groundY - Arena.ballRadius);
      v = Vec2(v.x * Arena.groundFriction, -v.y * sim.pitchBounce);
    }
    if (p.x <= x) return p;
  }
  return null;
}

WallCricketSimulation simulateInnings({
  required int seed,
  Pace pace = Pace.medium,
  WallCricketRules rules = WallCricketRules.classic,
  double? Function(WallCricketSimulation)? batter,
}) {
  final simulation =
      WallCricketSimulation(seed: seed, pace: pace, rules: rules);
  while (!simulation.isComplete) {
    final swing = batter?.call(simulation);
    simulation.step(
      WallCricketInput(swing: swing ?? 0, touching: swing != null),
    );
  }
  return simulation;
}
