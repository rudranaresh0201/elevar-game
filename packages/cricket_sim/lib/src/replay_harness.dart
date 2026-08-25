import 'package:game_core/game_core.dart';

import 'field.dart';
import 'ground.dart';
import 'simulation.dart';
import 'state.dart';

/// Drives a match and records the human input as it goes.
///
/// The recording is the anti-cheat story: the server re-runs it and derives
/// the score itself rather than believing the one it was sent. That only works
/// if the live match consumes exactly the values the recording holds, which is
/// why every input goes through [CricketInput.quantised] on the way in.
class CricketMatchRunner {
  CricketMatchRunner({required this.simulation})
      : recorder = ReplayRecorder(
          seed: simulation.seed,
          channelCount: simulation.replayChannelCount,
          tickHz: simulation.rules.tickHz,
          sampleEveryTicks: sampleStride,
        );

  /// 120 Hz / 4 = 30 Hz.
  ///
  /// The same reasoning as racing rather than ping pong: a swipe is an *edge*,
  /// and the tick it lands on decides whether a shot is middled or top-edged.
  /// At 20 Hz a swing could sit 50 ms from the thumb, which is most of the
  /// perfect window. A held value delta-encodes to one zero byte per channel,
  /// so this costs almost nothing.
  static const int sampleStride = 4;

  final CricketSimulation simulation;
  final ReplayRecorder recorder;

  /// What the screen has most recently reported.
  CricketInput _pendingStriker = CricketInput.idle;
  CricketInput _pendingBowler = CricketInput.idle;

  /// What the simulation is actually being fed, which changes only on sample
  /// boundaries. See [tick].
  CricketInput _liveStriker = CricketInput.idle;
  CricketInput _liveBowler = CricketInput.idle;

  /// Both setters quantise on the way in. See the class comment.
  void setStrikerInput(CricketInput input) =>
      _pendingStriker = input.quantised();

  void setBowlerInput(CricketInput input) => _pendingBowler = input.quantised();

  /// Advances the match by one tick, recording what it fed in.
  ///
  /// **Input reaches the simulation only on sample ticks.** That looks like an
  /// odd restriction and it is the whole reason this class exists.
  ///
  /// A swing is a one-tick edge, not a held position like a paddle or a pedal.
  /// Sampling the input stream every fourth tick therefore *misses* three
  /// swings in four outright: the live match played the shot, the recording
  /// never saw it, and re-running the recording produced a different innings —
  /// measured at 4 runs against the 12 actually scored. Racing learned that the
  /// live path has to consume the same quantised *values* as the recording;
  /// cricket adds that it must consume them at the same quantised *times*.
  ///
  /// Between samples the last value is held, which is exactly what
  /// `ReplayReader.valueAt` does on the way back.
  void tick() {
    if (simulation.isComplete) return;

    if (simulation.tick % sampleStride == 0) {
      _liveStriker = _pendingStriker;
      _liveBowler = _pendingBowler;
      recorder.addSample(_channels());

      // The swing has now been both played and written down, so it is spent.
      // Leaving it set would swing again at the next ball.
      _pendingStriker = _withoutAction(_pendingStriker);
      _pendingBowler = _withoutAction(_pendingBowler);
    }

    simulation.step(MatchInput(
      striker: _liveStriker,
      bowler: simulation.isTwoHuman ? _liveBowler : null,
    ));
  }

  static CricketInput _withoutAction(CricketInput input) =>
      CricketInput(x: input.x, y: input.y, power: input.power);

  List<double> _channels() {
    if (!simulation.isTwoHuman) {
      // Against the bot, only the acting human is recorded. Which role that
      // is follows from the ball count, so a verifier never has to be told.
      final acting =
          simulation.humanRole == Role.batting ? _liveStriker : _liveBowler;
      return acting.toChannels();
    }
    return <double>[..._liveStriker.toChannels(), ..._liveBowler.toChannels()];
  }

  List<int> finishRecording() => recorder.finish();
}

/// Re-runs a recorded match and returns the simulation it produced.
///
/// This is the function the server calls. If what it returns disagrees with the
/// submitted score, the submission is a lie.
CricketSimulation replayMatch(
  ReplayReader reader, {
  required GameMode mode,
  BotDifficulty? botDifficulty,
  CricketRules rules = CricketRules.powerplay,
  FieldSetting fieldSetting = FieldSetting.standard,
  bool humanBatsFirst = true,
}) {
  final simulation = CricketSimulation(
    seed: reader.seed,
    mode: mode,
    botDifficulty: botDifficulty,
    rules: rules,
    fieldSetting: fieldSetting,
    humanBatsFirst: humanBatsFirst,
  );

  final twoHuman = mode == GameMode.local2P;
  var tick = 0;
  while (!simulation.isComplete && tick < reader.tickCount) {
    final sample = reader.sampleAt(tick);
    final striker = CricketInput.fromChannels(sample, 0);
    final bowler = twoHuman
        ? CricketInput.fromChannels(sample, CricketInput.channelCount)
        : null;

    simulation.step(MatchInput(striker: striker, bowler: bowler));
    tick++;
  }
  return simulation;
}

/// Runs a whole match headlessly against scripted input. The workhorse of the
/// test suite and of `tool/balance.dart`.
CricketSimulation simulateHeadless({
  required int seed,
  required GameMode mode,
  BotDifficulty? botDifficulty,
  CricketRules rules = CricketRules.powerplay,
  FieldSetting fieldSetting = FieldSetting.standard,
  bool humanBatsFirst = true,
  CricketInput Function(CricketState, int)? striker,
  CricketInput Function(CricketState, int)? bowler,
  int maxTicks = 120 * 600,
}) {
  final simulation = CricketSimulation(
    seed: seed,
    mode: mode,
    botDifficulty: botDifficulty,
    rules: rules,
    fieldSetting: fieldSetting,
    humanBatsFirst: humanBatsFirst,
  );

  var tick = 0;
  while (!simulation.isComplete && tick < maxTicks) {
    simulation.step(MatchInput(
      striker: striker?.call(simulation.state, tick),
      bowler: bowler?.call(simulation.state, tick),
    ));
    tick++;
  }
  return simulation;
}

/// A scripted human batter of a given [skill], for balancing.
///
/// It swings at every ball with a timing error drawn from its skill, exactly
/// as the bot batter does — the point is to have a yardstick that is not the
/// thing being measured.
CricketInput Function(CricketState, int) proxyBatter({
  required double skill,
  int seed = 0x5EED,
}) {
  final s = clampD(skill, 0, 1);
  final rng = DeterministicRng.stream(seed, 91);
  // Wide enough at the bottom of the range that a poor player is genuinely
  // beaten sometimes: against a 22-tick window, skill 0.3 misses about one
  // ball in seven and skill 0.9 almost never.
  final spread = (34 - 26 * s).round();

  var plannedTick = -1;
  var plannedX = 0.5;
  var plannedY = 0.0;
  var plannedPower = 0.5;
  var lastIdeal = -1;

  return (state, tick) {
    final ball = state.ball;
    if (state.phase != CricketPhase.delivery) return CricketInput.idle;

    // Re-plan once per delivery.
    if (ball.idealContactTick != lastIdeal) {
      lastIdeal = ball.idealContactTick;
      plannedTick =
          ball.idealContactTick + rng.nextInt(spread * 2 + 1) - spread;
      final read = rng.nextRange(-(60 - 45 * s), 60 - 45 * s);
      final lateral = clampD(
        (ball.position.x + read - CricketField.pitchCentreX) / 70,
        -1,
        1,
      );
      // Aim somewhere. The first version of this always hit straight down the
      // ground, which put every shot into mid-off, mid-on and the bowler and
      // made the balance table a measurement of one fielding position rather
      // than of the game. A better player looks for a gap; a worse one swings
      // where the ball happened to be.
      final spray = rng.nextRange(-1.0, 1.0);
      final aimLateral = clampD(lateral * (1 - 0.7 * s) + spray * (0.35 + 0.55 * s), -1, 1);
      plannedX = (aimLateral + 1) / 2;
      // A little squarer as skill rises, which is where the gaps are.
      plannedY = clampD(0.5 - (0.5 - 0.22 * rng.nextDouble() * s), 0, 1);
      // Aggression is deliberately *not* tied to skill.
      //
      // It was, and it inverted the whole balance table: a "better" proxy swung
      // harder, went aerial more, and holed out more, so higher skill scored
      // fewer runs. Choosing to slog is a decision available to any player at
      // any standard. What skill actually buys is timing and placement, which
      // are the two dials above.
      plannedPower = clampD(0.50 + rng.nextRange(-0.18, 0.18), 0, 1);
    }

    return CricketInput(
      action: tick >= plannedTick,
      x: plannedX,
      y: plannedY,
      power: plannedPower,
    );
  };
}

/// A scripted human bowler of a given [skill].
CricketInput Function(CricketState, int) proxyBowler({
  required double skill,
  int seed = 0x5EED,
}) {
  final s = clampD(skill, 0, 1);
  final rng = DeterministicRng.stream(seed, 92);
  return (state, tick) {
    final slop = 1.0 - s;
    return CricketInput(
      action: true,
      x: clampD(0.5 + rng.nextRange(-0.32, 0.32) * slop, 0, 1),
      y: clampD(0.6 + rng.nextRange(-0.35, 0.35) * slop, 0, 1),
      power: rng.chance(0.25 + 0.3 * s) ? 0.62 : 0.12,
    );
  };
}
