import 'package:game_core/game_core.dart';

import 'field.dart';
import 'simulation.dart';
import 'state.dart';

/// Drives a live match and records it in one pass.
///
/// The runner exists because of one subtle requirement: a replay is only proof
/// of anything if replaying it reproduces the match *exactly*. That cannot be
/// achieved by recording a full-precision match at 20 Hz and hoping — a
/// simulation amplifies the smallest divergence until the scores differ.
///
/// So the runner makes the live match play by the replay's rules. Input is
/// snapped to the replay's 16-bit grid and only allowed to change on sample
/// boundaries; between them the last value is held, for the player and for the
/// verifier alike. The recording is then not an approximation of the match. It
/// *is* the match.
class PongMatchRunner {
  PongMatchRunner({required this.simulation})
      : _recorder = ReplayRecorder(
          seed: simulation.seed,
          channelCount: simulation.replayChannelCount,
          tickHz: simulation.rules.tickHz,
          sampleEveryTicks: ReplayRecorder.defaultSampleEveryTicks,
        ) {
    _heldP1 = simulation.p1Target;
    _heldP2 = simulation.p2Target;
  }

  final PingPongSimulation simulation;
  final ReplayRecorder _recorder;

  Vec2? _pendingP1;
  Vec2? _pendingP2;
  late Vec2 _heldP1;
  late Vec2 _heldP2;

  int get sampleEveryTicks => _recorder.sampleEveryTicks;

  bool get isTwoHuman => simulation.mode == GameMode.local2P;

  /// Latest thumb position for P1, in normalised field coordinates. Called as
  /// often as the gesture recogniser fires; only sampled on tick boundaries.
  void setP1Target(Vec2 normalised) => _pendingP1 = normalised;

  void setP2Target(Vec2 normalised) => _pendingP2 = normalised;

  /// Advances one simulation tick, recording input on sample boundaries.
  void tick() {
    if (simulation.tick % sampleEveryTicks == 0) {
      if (_pendingP1 != null) _heldP1 = _snap(_pendingP1!);
      if (isTwoHuman && _pendingP2 != null) _heldP2 = _snap(_pendingP2!);

      _recorder.addSample(
        isTwoHuman
            ? <double>[_heldP1.x, _heldP1.y, _heldP2.x, _heldP2.y]
            : <double>[_heldP1.x, _heldP1.y],
      );
    }

    simulation.step(
      PongInput(p1: _heldP1, p2: isTwoHuman ? _heldP2 : null),
    );
  }

  /// Advances by [dtSeconds] of real time using [loop], so rendering can run at
  /// any frame rate while the match still advances in exact ticks.
  int advance(FixedLoop loop, double dtSeconds) =>
      loop.advance(dtSeconds, (_) => tick());

  /// Seals the recording. Safe to call once the match is complete.
  List<int> finishRecording() => _recorder.finish();

  static Vec2 _snap(Vec2 v) =>
      Vec2(quantiseNormalised(v.x), quantiseNormalised(v.y));
}

/// Re-runs a recorded match from its input log.
///
/// This is the function the Phase 5 server worker calls. It imports no Flutter
/// and touches no clock, so a three-minute match verifies in a few milliseconds
/// on the API box. If the returned score differs from the one the client
/// submitted, the submission was tampered with.
PingPongSimulation replayMatch(
  ReplayReader replay, {
  required GameMode mode,
  BotDifficulty? botDifficulty,
  PongRules rules = PongRules.standard,
}) {
  final simulation = PingPongSimulation(
    seed: replay.seed,
    mode: mode,
    botDifficulty: botDifficulty,
    rules: rules,
  );

  final twoHuman = mode == GameMode.local2P;
  for (var tick = 0; tick < replay.tickCount; tick++) {
    if (simulation.isComplete) break;
    final sample = replay.sampleAt(tick);
    simulation.step(
      PongInput(
        p1: Vec2(sample[0], sample[1]),
        p2: twoHuman ? Vec2(sample[2], sample[3]) : null,
      ),
    );
  }
  return simulation;
}

/// Runs a whole match headlessly with scripted input, for tests and for
/// balancing the bot over thousands of simulated matches.
PingPongSimulation simulateHeadless({
  required int seed,
  required GameMode mode,
  BotDifficulty? botDifficulty,
  PongRules rules = PongRules.standard,
  int maxTicks = 120 * 60 * 10,
  Vec2 Function(PongState state, int tick)? p1Controller,
  Vec2 Function(PongState state, int tick)? p2Controller,
}) {
  final simulation = PingPongSimulation(
    seed: seed,
    mode: mode,
    botDifficulty: botDifficulty,
    rules: rules,
  );

  for (var tick = 0; tick < maxTicks && !simulation.isComplete; tick++) {
    simulation.step(
      PongInput(
        p1: p1Controller?.call(simulation.state, tick),
        p2: mode == GameMode.local2P ? p2Controller?.call(simulation.state, tick) : null,
      ),
    );
  }
  return simulation;
}

/// A scripted stand-in for a human player, used to balance the bot.
///
/// Two dials, and the second one matters more than it looks. **Reaction delay**
/// is what makes a fast ball genuinely hard to reach — an opponent reading the
/// ball's current position with no lag returns everything, however bad its aim,
/// because the paddle outruns the ball.
///
/// **Anticipation** is the other half: the bot predicts where the ball will
/// arrive, so a proxy that merely chases where the ball *is* loses to it every
/// time and tells you nothing about whether a person could win. This proxy
/// always reads the bounce, at every skill level — an earlier version scaled
/// anticipation with skill and produced a useless yardstick, because aiming
/// *part* of the way toward a predicted intercept is worse than either aiming
/// at it or ignoring it. Skill moves lag and accuracy only, so win rate varies
/// smoothly with it.
Vec2 Function(PongState, int) proxyHuman({
  required PongSide side,
  double skill = 0.8,
  int tickHz = 120,
}) {
  // 300 ms of lag at skill 0 down to 70 ms at skill 1 — the human range.
  final reactionTicks = (((300 - 230 * skill) * tickHz) / 1000).round();
  final errorScale = 260 * (1 - skill) + 10;
  final perceived = <({Vec2 position, Vec2 velocity})>[];
  // Seeded, so the proxy stays reproducible while still drawing from a real
  // distribution. A flat error swings its full range every time it resamples,
  // which against a hard paddle edge means the proxy either always reaches the
  // ball or never does — a step function masquerading as a skill curve. A
  // triangular error is usually small and occasionally large, like a person's,
  // and turns that step back into a slope.
  final rng = DeterministicRng.stream(0x9E3779B9, side.index);
  var wobble = 0.0;

  return (state, tick) {
    perceived.add(
      (position: state.ball.position, velocity: state.ball.velocity),
    );
    if (perceived.length > reactionTicks + 1) perceived.removeAt(0);
    final seen = perceived.first;

    if (tick % 15 == 0) {
      wobble = rng.nextDouble() + rng.nextDouble() - 1.0;
    }

    final paddle = side == PongSide.p1 ? state.p1 : state.p2;
    final homeY =
        side == PongSide.p1 ? paddle.bounds.bottom - 40 : paddle.bounds.top + 40;

    // Where the ball will cross this player's line, folded through the walls.
    var anticipated = seen.position.x;
    if (seen.velocity.y.abs() > 1e-6) {
      final t = (homeY - seen.position.y) / seen.velocity.y;
      if (t > 0) {
        anticipated = foldIntoRange(
          seen.position.x + seen.velocity.x * t,
          PongField.ballRadius,
          PongField.width - PongField.ballRadius,
        );
      }
    }

    final targetX = anticipated + wobble * errorScale;

    return Vec2(
      clampD(targetX, 0, PongField.width) / PongField.width,
      homeY / PongField.height,
    );
  };
}
