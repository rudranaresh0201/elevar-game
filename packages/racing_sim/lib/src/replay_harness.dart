import 'package:game_core/game_core.dart';

import 'bot.dart';
import 'field.dart';
import 'simulation.dart';
import 'state.dart';
import 'track.dart';

/// Drives a live race and records it in one pass.
///
/// The runner exists for one subtle reason: a replay only proves anything if
/// replaying it reproduces the race *exactly*, and that cannot be achieved by
/// recording a full-precision race at a lower rate and hoping. A simulation
/// amplifies the smallest divergence until the finishing order differs.
///
/// So the runner makes the live race play by the replay's rules. Input is put
/// through the replay's own 16-bit grid and only allowed to change on sample
/// boundaries; between them the last value is held, for the driver and for the
/// verifier alike. The recording is not an approximation of the race. It *is*
/// the race.
class RaceMatchRunner {
  RaceMatchRunner({required this.simulation})
      : _recorder = ReplayRecorder(
          seed: simulation.seed,
          channelCount: simulation.replayChannelCount,
          tickHz: simulation.rules.tickHz,
          sampleEveryTicks: sampleStride,
        );

  /// 30 Hz against a 120 Hz simulation.
  ///
  /// Finer than ping pong's 20 Hz, and deliberately. A dragged paddle is a
  /// smooth signal that survives coarse sampling; a button press is an edge,
  /// and at 20 Hz a stab at the brake could sit up to 50 ms behind the thumb
  /// that made it. Racing is the game where that is felt. It costs almost
  /// nothing to store, because a held button delta-encodes to a single zero
  /// byte per channel per sample.
  static const int sampleStride = 4;

  final RaceSimulation simulation;
  final ReplayRecorder _recorder;

  CarInput? _pendingP1;
  CarInput? _pendingP2;
  CarInput _heldP1 = CarInput.coasting;
  CarInput _heldP2 = CarInput.coasting;

  int get sampleEveryTicks => _recorder.sampleEveryTicks;

  bool get isTwoHuman => simulation.isTwoHuman;

  /// Latest control state for P1. Call it as often as the touch layer fires;
  /// it is only consumed on sample boundaries.
  void setP1Input(CarInput input) => _pendingP1 = input;

  void setP2Input(CarInput input) => _pendingP2 = input;

  /// Advances one simulation tick, recording input on sample boundaries.
  void tick() {
    if (simulation.tick % sampleEveryTicks == 0) {
      if (_pendingP1 != null) _heldP1 = snapThroughReplayGrid(_pendingP1!);
      if (isTwoHuman && _pendingP2 != null) {
        _heldP2 = snapThroughReplayGrid(_pendingP2!);
      }

      _recorder.addSample(
        isTwoHuman
            ? <double>[..._heldP1.toChannels(), ..._heldP2.toChannels()]
            : _heldP1.toChannels(),
      );
    }

    simulation.step(
      RaceInput(p1: _heldP1, p2: isTwoHuman ? _heldP2 : null),
    );
  }

  /// Advances by [dtSeconds] of real time using [loop], so rendering can run at
  /// any frame rate while the race still advances in exact ticks.
  int advance(FixedLoop loop, double dtSeconds) =>
      loop.advance(dtSeconds, (_) => tick());

  /// Seals the recording. Safe to call once the race is complete.
  List<int> finishRecording() => _recorder.finish();

  /// Puts an input through the replay's quantiser and back.
  ///
  /// This is the live half of the determinism contract. Skipping it would let
  /// the race consume a value the recording cannot represent.
  static CarInput snapThroughReplayGrid(CarInput raw) {
    final channels = raw.toChannels().map(quantiseNormalised).toList();
    return CarInput.fromChannels(channels, 0);
  }
}

/// Re-runs a recorded race from its input log.
///
/// This is the function the Phase 5 server worker calls. It imports no Flutter
/// and touches no clock, so a one-minute race verifies in a few milliseconds on
/// the API box. If the finishing order or lap count differs from what the
/// client submitted, the submission was tampered with.
RaceSimulation replayRace(
  ReplayReader replay, {
  required GameMode mode,
  required RaceTrack track,
  BotDifficulty? botDifficulty,
  RaceRules rules = RaceRules.standard,
}) {
  final simulation = RaceSimulation(
    seed: replay.seed,
    mode: mode,
    track: track,
    botDifficulty: botDifficulty,
    rules: rules,
  );

  final twoHuman = mode == GameMode.local2P;
  for (var tick = 0; tick < replay.tickCount; tick++) {
    if (simulation.isComplete) break;
    final sample = replay.sampleAt(tick);
    simulation.step(
      RaceInput(
        p1: CarInput.fromChannels(sample, 0),
        p2: twoHuman
            ? CarInput.fromChannels(sample, CarInput.channelCount)
            : null,
      ),
    );
  }
  return simulation;
}

/// Runs a whole race headlessly with scripted input, for tests and for
/// balancing the bot over hundreds of simulated races.
RaceSimulation simulateHeadless({
  required int seed,
  required GameMode mode,
  required RaceTrack track,
  BotDifficulty? botDifficulty,
  RaceRules rules = RaceRules.standard,
  CarInput Function(RaceState state, int tick)? p1Controller,
  CarInput Function(RaceState state, int tick)? p2Controller,
}) {
  final simulation = RaceSimulation(
    seed: seed,
    mode: mode,
    track: track,
    botDifficulty: botDifficulty,
    rules: rules,
  );

  while (!simulation.isComplete && simulation.tick < rules.maxTicks) {
    simulation.step(
      RaceInput(
        p1: p1Controller?.call(simulation.state, simulation.tick),
        p2: mode == GameMode.local2P
            ? p2Controller?.call(simulation.state, simulation.tick)
            : null,
      ),
    );
  }
  return simulation;
}

/// A scripted stand-in for a human driver, used to balance the bot.
///
/// It is the bot, with its dials set from one [skill] number — which is the
/// honest way to build a yardstick. The alternative, a hand-written "human"
/// that drives by different rules, measures the difference between two
/// algorithms rather than the difficulty of the ladder.
///
/// **Lookahead does not scale with skill**, and that is the lesson ping pong
/// paid for: a proxy that anticipates *partway* is worse than one that either
/// anticipates or doesn't, and scaling it turned a difficulty slope into a
/// cliff. Skill moves reaction, pace, tidiness and error rate only, so the win
/// rate varies smoothly with it.
CarInput Function(RaceState, int) proxyDriver({
  required RacerSide side,
  required RaceTrack track,
  double skill = 0.7,
  int tickHz = 120,
  int seed = 0x5EED,
}) {
  final bot = RaceBot(
    profile: proxyProfile(skill),
    side: side,
    seed: seed,
    tickHz: tickHz,
  );
  return (state, tick) => bot.update(state, track);
}

/// The dials a scripted human of a given [skill] drives with.
///
/// This is the measuring instrument the whole balance table is read off, so its
/// calibration matters as much as the bots it is used to judge.
///
/// **It was wrong at the top of its range and the balance table lied because of
/// it.** [cornerCaution] used to run down to 0.98 at skill 1.0, but anything
/// below about 1.0 asks for more yaw than [RaceField.lateralGripLimit] will
/// give, so the clamp binds and the extra ambition buys nothing. Skill 0.85 and
/// skill 1.00 therefore both drove at the car's absolute limit and finished
/// 0.35 s apart, which made every bot look like a cliff — 0% against one column
/// and 100% against the next — when the columns themselves were barely
/// distinguishable.
///
/// The range now spans a real spread of drivers: 16.5 s a lap at 0.35 down to
/// 14.4 s at 1.0 on Dustbowl, with the top of the scale still short of perfect,
/// because a human who never lifts a fraction early does not exist.
BotProfile proxyProfile(double skill) {
  final s = clampD(skill, 0, 1);
  return BotProfile(
    // 300 ms of lag at skill 0 down to 80 ms at skill 1 — the human range.
    reactionMs: (300 - 220 * s).round(),
    paceFraction: 0.86 + 0.14 * s,
    // Kept deliberately narrow, and bottoming out just under 1.0. Caution is a
    // multiplier against a hard wall: a hair above 1.0 costs real time, and
    // anything below it buys nothing because the grip clamp binds first. It is
    // therefore the worst possible dial to express a skill range on, and the
    // spread lives in the linear dials below instead.
    cornerCaution: 1.22 - 0.24 * s,
    lineNoise: 70 * (1 - s) + 6,
    mistakeChance: 0.26 * (1 - s) + 0.02,
    // Reading further up the road is a skill in itself, and holding it constant
    // flattened the difference between a good driver and a great one.
    lookaheadBase: 120 + 70 * s,
    lookaheadPerSpeed: 0.36 + 0.20 * s,
  );
}

/// A driver that simply holds the throttle down and never steers.
///
/// Useful as a floor in tests: whatever else changes, this must still produce a
/// race that terminates.
CarInput Function(RaceState, int) flatOutDriver() =>
    (state, tick) => const CarInput(throttle: true);

/// Terminal velocity of the car, exposed for tests and tuning.
const double terminalSpeed = RaceField.engineForce / RaceField.dragOnTrack;
