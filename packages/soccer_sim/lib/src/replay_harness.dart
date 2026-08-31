import 'package:game_core/game_core.dart';

import 'bot.dart';
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
///
/// For soccer that has one visible consequence worth knowing about: a release
/// lands on the next sample boundary, up to 50 ms after the finger left the
/// glass. Nobody notices, because the thing that follows a release is two
/// seconds of physics.
class SoccerMatchRunner {
  SoccerMatchRunner({required this.simulation})
      : _recorder = ReplayRecorder(
          seed: simulation.seed,
          channelCount: simulation.replayChannelCount,
          tickHz: simulation.rules.tickHz,
          sampleEveryTicks: ReplayRecorder.defaultSampleEveryTicks,
        );

  final SoccerSimulation simulation;
  final ReplayRecorder _recorder;

  SoccerInput? _pending;
  SoccerInput _held = SoccerInput.idle;

  int get sampleEveryTicks => _recorder.sampleEveryTicks;

  /// Latest pointer state, in normalised field coordinates. Called as often as
  /// the gesture recogniser fires; only sampled on tick boundaries.
  void setInput(SoccerInput input) => _pending = input;

  /// Advances one simulation tick, recording input on sample boundaries.
  void tick() {
    if (simulation.tick % sampleEveryTicks == 0) {
      final pending = _pending;
      if (pending != null) _held = pending.quantised();
      _recorder.addSample(_held.toChannels());
    }
    simulation.step(_held);
  }

  /// Advances by [dtSeconds] of real time using [loop], so rendering can run
  /// at any frame rate while the match still advances in exact ticks.
  int advance(FixedLoop loop, double dtSeconds) =>
      loop.advance(dtSeconds, (_) => tick());

  /// Seals the recording. Safe to call once the match is complete.
  List<int> finishRecording() => _recorder.finish();
}

/// Re-runs a recorded match from its input log.
///
/// This is the function the Phase 5 server worker calls. It imports no Flutter
/// and touches no clock, so a four-minute match verifies in a few milliseconds
/// on the API box. If the returned score differs from the one the client
/// submitted, the submission was tampered with.
SoccerSimulation replaySoccerMatch(
  ReplayReader replay, {
  required GameMode mode,
  BotDifficulty? botDifficulty,
  SoccerRules rules = SoccerRules.standard,
}) {
  final simulation = SoccerSimulation(
    seed: replay.seed,
    mode: mode,
    botDifficulty: botDifficulty,
    rules: rules,
  );

  for (var tick = 0; tick < replay.tickCount; tick++) {
    if (simulation.isComplete) break;
    simulation.step(SoccerInput.fromChannels(replay.sampleAt(tick)));
  }
  return simulation;
}

/// Runs a whole match headlessly with scripted input, for tests and for
/// balancing the bot over hundreds of simulated matches.
SoccerSimulation simulateSoccerHeadless({
  required int seed,
  required GameMode mode,
  BotDifficulty? botDifficulty,
  SoccerRules rules = SoccerRules.standard,
  int maxTicks = 120 * 60 * 12,
  SoccerInput Function(SoccerState state, int tick)? p1Controller,
  SoccerInput Function(SoccerState state, int tick)? p2Controller,
}) {
  final simulation = SoccerSimulation(
    seed: seed,
    mode: mode,
    botDifficulty: botDifficulty,
    rules: rules,
  );

  for (var tick = 0; tick < maxTicks && !simulation.isComplete; tick++) {
    final state = simulation.state;
    final controller =
        state.turn == SoccerSide.p1 ? p1Controller : p2Controller;
    simulation.step(controller?.call(state, tick) ?? SoccerInput.idle);
  }
  return simulation;
}

/// A scripted stand-in for a human player, used to balance the bot.
///
/// It drives the *gesture*, not the simulation: it puts a finger on a disc,
/// drags it back the right distance in the right direction, and lifts it off.
/// Everything the proxy does goes through exactly the path a thumb does, so a
/// balance run also exercises grabbing, power scaling and release-cancelling.
/// A proxy that called `world.flick` directly would measure a game nobody can
/// play.
///
/// Skill moves imagination and execution together — how many discs and angles
/// it looks at, and how accurately its thumb delivers the answer — which is
/// what varies between two people at a table.
SoccerInput Function(SoccerState, int) proxyHuman({
  required SoccerSide side,
  double skill = 0.8,
  int seed = 0x5EED1E,
}) {
  final bot = SoccerBot(
    profile: proxyProfile(skill),
    side: side,
    seed: seed,
  );

  BotShot? plan;
  var stage = 0;

  // Each stage is held for two full sample periods, so the gesture survives
  // the 20 Hz input grid intact. A one-tick touch would be recorded on some
  // ticks and not others depending on where the turn began.
  const grabTicks = 12;
  const dragTicks = 12;

  return (state, tick) {
    if (state.phase != SoccerPhase.aiming || state.turn != side) {
      plan = null;
      return SoccerInput.idle;
    }

    if (plan == null) {
      plan = bot.chooseShot(state.world, side);
      stage = 0;
    }
    final shot = plan;
    if (shot == null) return SoccerInput.idle;

    final origin = state.world.bodies[shot.discIndex].position;
    final dragLength = SoccerField.minDragLength +
        (SoccerField.maxDragLength - SoccerField.minDragLength) * shot.power;
    final pull = -shot.direction * dragLength;

    final here = stage;
    stage++;

    if (here < grabTicks) return SoccerInput.grab(origin);
    return SoccerInput.pull(pull, stillDown: here < grabTicks + dragTicks);
  };
}

/// The proxy's skill dials. Separate from [SoccerBotProfile.of] on purpose:
/// measuring the bot against a yardstick built from the bot's own three
/// presets would only tell you how the presets compare to each other.
SoccerBotProfile proxyProfile(double skill) {
  final s = clampD(skill, 0, 1);
  return SoccerBotProfile(
    discsConsidered: s < 0.4 ? 2 : (s < 0.75 ? 3 : 4),
    aimsPerDisc: (2 + 4 * s).round(),
    powers: const <double>[0.5, 0.75, 1.0],
    rolloutTicks: 210,
    aimJitter: 0.30 * (1 - s) + 0.02,
    powerJitter: 0.20 * (1 - s) + 0.02,
    blunderChance: 0.28 * (1 - s),
    defenceWeight: 0.10 + 0.25 * s,
  );
}
