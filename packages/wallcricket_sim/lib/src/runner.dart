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

  /// The finger, in arena units. Null when nothing is touching.
  void setFinger(Vec2? arenaPoint) {
    if (arenaPoint == null) {
      input.set(2, 0);
      return;
    }
    input
      ..set(0, arenaPoint.x / Arena.width)
      ..set(1, arenaPoint.y / Arena.height)
      ..set(2, 1);
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
/// It reads the ball with a reaction delay, holds the blade low across the
/// line, and swings up through the ball as it arrives. [skill] moves the delay
/// and how well the swing is timed; nothing else.
Vec2? Function(WallCricketSimulation) proxyBatter({
  double skill = 0.8,
  int noiseSeed = 1,
}) {
  final rng = DeterministicRng.stream(noiseSeed, 77);
  var swingTicks = 0;
  var triggerGap = 0.0;
  var heightError = 0.0;
  var planned = false;
  return (sim) {
    if (sim.phase != WallCricketPhase.live || !sim.ballVisible) {
      swingTicks = 0;
      planned = false;
      return null;
    }
    if (!planned) {
      planned = true;
      // A person misjudges both when to go and how high the ball will be.
      // Seconds before arrival to start the swing. A blade sweeps the last
      // stretch in about 30 ms, so a perfect batter goes just before that.
      triggerGap = 0.03 + rng.nextRange(-1, 1) * 0.09 * (1 - skill);
      heightError = rng.nextRange(-1, 1) * 120 * (1 - skill);
    }

    final interceptX = Arena.pivot.x + Arena.batLength * 0.72;
    final arrival = predictBallAt(sim, interceptX);
    final secondsAway = sim.ballVelocity.x < 0
        ? (sim.ballPosition.x - interceptX) / -sim.ballVelocity.x
        : 99.0;

    if (swingTicks > 0 || secondsAway < triggerGap) {
      swingTicks++;
      // Up and through, toward the top of the far wall.
      return swingTicks < 24 ? const Vec2(950, 200) : null;
    }
    // Ready: the blade held just under where the ball will arrive.
    final y = (arrival?.y ?? Arena.groundY - 80) + 60 + heightError;
    return Vec2(interceptX + 200, y);
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
      v = Vec2(v.x * Arena.groundFriction, -v.y * Arena.groundRestitution);
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
  while (!simulation.isComplete) {
    final finger = batter?.call(simulation);
    simulation.step(
      WallCricketInput(
        finger: finger == null
            ? null
            : Vec2(finger.x / Arena.width, finger.y / Arena.height),
        touching: finger != null,
      ),
    );
  }
  return simulation;
}
