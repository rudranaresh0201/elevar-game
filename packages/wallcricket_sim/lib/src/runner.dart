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

  /// A touch: start the swing now, heading [direction] (screen-style, y down).
  void swing(Vec2 direction) {
    aim(direction);
    input.pulse(2);
  }

  /// Updates the shot direction as the swipe develops, before contact.
  void aim(Vec2 direction) {
    final d = direction.lengthSquared < 1e-6 ? const Vec2(1, -0.5) : direction.normalized;
    input
      ..set(0, (d.x + 1) / 2)
      ..set(1, (d.y + 1) / 2);
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
/// Touches a reaction-noisy moment before the ball reaches the hitting point,
/// with a lofted swipe. [skill] is how well that moment is judged. Returns a
/// direction on the tick it swings, and null otherwise.
Vec2? Function(WallCricketSimulation) proxyBatter({
  double skill = 0.8,
  int noiseSeed = 1,
}) {
  final rng = DeterministicRng.stream(noiseSeed, 77);
  var swung = false;
  var lead = 0.0;
  var planned = false;
  return (sim) {
    if (sim.phase != WallCricketPhase.live || !sim.ballVisible) {
      swung = false;
      planned = false;
      return null;
    }
    if (swung) return null;
    if (!planned) {
      planned = true;
      final ideal = WallCricketSimulation.contactDelayTicks / WallCricketRules.tickHz;
      // A thumb on glass is never exact: even a sharp player is off by a few
      // hundredths of a second, a casual one by a tenth or more.
      lead = ideal + rng.nextRange(-1, 1) * (0.03 + 0.17 * (1 - skill));
    }
    final secondsAway = sim.ballVelocity.x < 0
        ? (sim.ballPosition.x - WallCricketSimulation.hitX) / -sim.ballVelocity.x
        : 99.0;
    if (secondsAway <= lead) {
      swung = true;
      return Vec2(1, rng.nextRange(-1.2, 0.2));
    }
    return null;
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
  Vec2? Function(WallCricketSimulation)? batter,
}) {
  final simulation =
      WallCricketSimulation(seed: seed, pace: pace, rules: rules);
  var direction = const Vec2(1, -0.5);
  while (!simulation.isComplete) {
    final swing = batter?.call(simulation);
    if (swing != null) direction = swing;
    simulation.step(
      WallCricketInput(direction: direction, swing: swing == null ? 0 : 1),
    );
  }
  return simulation;
}
