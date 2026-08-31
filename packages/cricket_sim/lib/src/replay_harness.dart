import 'package:game_core/game_core.dart';

import 'bot.dart';
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

  // Timing spread, in ticks, on when the sweep starts, and how far off the
  // real line the proxy reads the ball, in field units. Both at the wide end
  // of their range; a good delivery widens them further, below.
  final baseSpread = 30 - 23 * s;
  final baseReadError = 62 - 47 * s;

  var lastIdeal = -1;
  var aim = CricketField.batStance;
  var through = Vec2.zero;
  BattingPlan? plan;

  return (state, tick) {
    if (state.phase != CricketPhase.delivery) {
      // Back to the stance between balls, which is also what a person's thumb
      // does when it stops moving.
      return CricketInput(
        x: CricketField.batStance.x,
        y: CricketField.batStance.y,
      );
    }

    final ball = state.ball;

    // Re-plan once per delivery.
    if (ball.idealContactTick != lastIdeal) {
      lastIdeal = ball.idealContactTick;

      // A good ball is harder to read and harder to time, for a proxy exactly
      // as for the bot. Without this the yardstick could not tell a jaffa from
      // a long hop, and the whole bowling half of the balance table flattened.
      final difficulty = CricketField.deliveryDifficulty(
        ball.pitchY,
        ball.position.x + ball.velocity.x *
            ((CricketField.batPlaneY - ball.position.y) / ball.velocity.y),
      );
      final spread = (baseSpread * (0.55 + 1.15 * difficulty)).round();
      final readError = baseReadError * (1.0 + 0.6 * difficulty);

      final misread = rng.nextRange(-readError, readError);
      final aimX = clampD(
        (ball.position.x + misread - CricketField.pitchCentreX) /
                CricketField.batReachX *
                0.5 +
            0.5,
        0,
        1,
      );

      final shortness = clampD(
        (CricketField.fullestLength - ball.pitchY) /
            (CricketField.fullestLength - CricketField.shortestLength),
        0,
        1,
      );

      // Aggression is deliberately *not* tied to skill.
      //
      // It was, and it inverted the whole balance table: a "better" proxy swung
      // harder, went aerial more, and holed out more, so higher skill scored
      // fewer runs. Choosing to slog is a decision available to any player at
      // any standard. What skill buys is timing and reading the line, which are
      // the two dials above.
      // Skewed upward rather than symmetric, so the proxy sometimes actually
      // goes after one. A yardstick that never plays a big shot cannot measure
      // whether big shots are worth playing.
      final intent = clampD(0.50 + rng.nextRange(-0.26, 0.42), 0.05, 1);

      // Height is executed, not just chosen.
      //
      // Skill buys accuracy, never aggression — that lesson is written twice
      // in this file already. But *where the blade ends up vertically* is
      // accuracy, and leaving it noiseless made a weak player get under the
      // ball exactly as well as a strong one. Since getting under it is what
      // lofts the ball, a weak player was lofting just as often and simply
      // holing out more: better batting produced more dismissals, and runs
      // stopped rising with skill between adjacent levels.
      final heightSlip = rng.nextRange(-1, 1) * 0.24 * (1 - s);
      aim = Vec2(
        aimX,
        clampD(0.90 - 0.34 * shortness + 0.34 * intent + heightSlip, 0, 1),
      );
      through = Vec2(
        rng.nextRange(-0.26, 0.26) * (0.55 + 0.45 * intent),
        -(0.14 + 0.34 * intent),
      );
      plan = BattingPlan.sweep(
        contactTick: ball.idealContactTick,
        aim: aim,
        through: through,
        intent: intent,
        timingError: rng.nextInt(spread * 2 + 1) - spread,
      );
    }

    // The same sweep the bot plays, driven through the input channels rather
    // than handed to the simulation. That matters: a proxy that set the bat
    // position directly would be measuring a game nobody can play, and would
    // skip both the speed cap and the quantisation the real path goes through.
    final live = plan;
    if (live == null) {
      return CricketInput(
        x: CricketField.batStance.x,
        y: CricketField.batStance.y,
      );
    }
    final target = live.targetAt(tick);
    return CricketInput(x: target.x, y: target.y);
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
      // What a skilled bowler picks, and it is not what it used to be.
      //
      // This was "a better bowler bowls more yorkers", which was right when
      // batting was a timing window — a yorker was hard because it arrived at
      // an awkward moment. Against a bat you *place*, a yorker is the easiest
      // ball on the card: it barely deviates and it always arrives low, so it
      // is trivially covered. Measured, the good bowler took fewer wickets
      // than the wild one. Skill now buys movement off the pitch, which is the
      // one thing a placed bat cannot answer, with the yorker kept as a
      // variation rather than as the reward.
      power: rng.chance(0.18 + 0.52 * s)
          ? 0.37 // spin: the big turner
          : (rng.chance(0.12 + 0.20 * s) ? 0.62 : 0.12),
    );
  };
}
