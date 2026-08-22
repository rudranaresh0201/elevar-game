import 'package:game_core/game_core.dart';

import 'field.dart';
import 'state.dart';

/// A difficulty setting, expressed as five dials rather than five algorithms.
///
/// Every difficulty runs the same code; only these numbers change. That matters
/// because it means "hard" cannot contain a bug that "easy" doesn't, and
/// because the difficulty curve can be retuned without touching logic.
class BotProfile {
  const BotProfile({
    required this.reactionMs,
    required this.speedFraction,
    required this.trackingErrorSigma,
    required this.predictionBounces,
    required this.missChance,
    required this.forwardLean,
  });

  /// How long before the bot reacts to what the ball is doing. The single
  /// biggest contributor to how a bot *feels* — a fast bot with a long delay
  /// reads as human, a slow bot with no delay reads as robotic.
  final int reactionMs;

  /// Fraction of [PongField.referenceHumanSpeed] the paddle may travel at.
  final double speedFraction;

  /// Half-width of the aim error, in field units. Resampled during the rally so
  /// the paddle wobbles instead of tracking on rails.
  final double trackingErrorSigma;

  /// How many wall bounces the bot can see through when predicting where the
  /// ball will arrive. 0 means it just chases the ball's current x.
  final int predictionBounces;

  /// Probability of committing to a miss at the start of a rally.
  ///
  /// This is not a bug being papered over. A bot that never misses isn't hard,
  /// it's unplayable, and a player who cannot win stops playing — which costs
  /// more than a lost point does.
  final double missChance;

  /// How far the bot advances from its goal line when the ball approaches.
  /// Aggression: better return angles, less time to recover.
  final double forwardLean;

  double get maxSpeed => PongField.referenceHumanSpeed * speedFraction;

  int reactionTicks(int tickHz) => (reactionMs * tickHz) ~/ 1000;

  // Every difficulty anticipates the bounce; they differ in how far ahead they
  // see and how accurately. An earlier cut had Easy chase the ball's current
  // position instead, which turned out to be the difference between "hopeless"
  // and "unbeatable" with nothing in between — the difficulty curve collapsed
  // into a cliff. Graded dials, not a capability switch.
  static const BotProfile easy = BotProfile(
    reactionMs: 300,
    speedFraction: 0.55,
    trackingErrorSigma: 190,
    predictionBounces: 1,
    missChance: 0.24,
    forwardLean: 0,
  );

  static const BotProfile medium = BotProfile(
    reactionMs: 195,
    speedFraction: 0.82,
    trackingErrorSigma: 82,
    predictionBounces: 2,
    missChance: 0.11,
    forwardLean: 45,
  );

  static const BotProfile hard = BotProfile(
    reactionMs: 110,
    speedFraction: 1.00,
    trackingErrorSigma: 34,
    predictionBounces: 4,
    missChance: 0.055,
    forwardLean: 95,
  );

  static BotProfile of(BotDifficulty difficulty) => switch (difficulty) {
        BotDifficulty.easy => easy,
        BotDifficulty.medium => medium,
        BotDifficulty.hard => hard,
      };
}

/// The computer opponent.
///
/// Lives *inside* the simulation rather than alongside it. Two reasons, one of
/// them structural: the bot is driven by the seeded RNG, so a replay only needs
/// to carry the human's input and the bot reproduces itself for free — and a
/// tampered client therefore cannot claim the bot played worse than it did.
class PongBot {
  PongBot({
    required this.profile,
    required this.side,
    required int seed,
    required int tickHz,
  })  : _reactionTicks = profile.reactionTicks(tickHz),
        _aimRng = DeterministicRng.stream(seed, 11),
        _missRng = DeterministicRng.stream(seed, 12) {
    _history = List<_Snapshot>.filled(
      _reactionTicks + 1,
      const _Snapshot(Vec2.zero, Vec2.zero),
    );
  }

  final BotProfile profile;
  final PongSide side;

  final int _reactionTicks;
  final DeterministicRng _aimRng;
  final DeterministicRng _missRng;

  late final List<_Snapshot> _history;
  int _historyHead = 0;
  bool _historyPrimed = false;

  bool _incoming = false;
  bool _committedToMiss = false;
  double _aimError = 0;
  int _ticksSinceResample = 0;

  /// Re-aim four times a second. Slower looks like tracking on rails; faster
  /// looks like a twitching paddle.
  static const int _resampleEveryTicks = 30;

  /// Produces this tick's target as a normalised field coordinate.
  Vec2 update(PongState state) {
    final me = side == PongSide.p1 ? state.p1 : state.p2;

    _remember(state.ball);
    final delayed = _delayedBall();

    // "Incoming" means the ball, as the bot currently perceives it, is heading
    // for the bot's own end.
    final towardMe =
        side == PongSide.p2 ? delayed.velocity.y < 0 : delayed.velocity.y > 0;
    final live = state.phase == PongPhase.rally;
    final nowIncoming = live && towardMe;

    if (nowIncoming && !_incoming) {
      // The opponent has just hit it back. Decide now whether this is the
      // rally the bot loses, and re-aim.
      _committedToMiss = _missRng.chance(profile.missChance);
      _resampleAim();
    }
    _incoming = nowIncoming;

    _ticksSinceResample++;
    if (_ticksSinceResample >= _resampleEveryTicks) _resampleAim();

    if (!nowIncoming) return _recoverTarget(me);

    var targetX = _predictInterceptX(delayed, me.position.y);
    targetX += _aimError;
    if (_committedToMiss) {
      // Miss by more than a paddle width, so it reads as beaten rather than
      // as a paddle that mysteriously stopped.
      targetX += _missRng.nextSign() * PongField.paddleHalfWidth * 2.4;
    }

    return _normalise(targetX, _leanY(me, delayed));
  }

  void _resampleAim() {
    // Triangular distribution: the sum of two uniforms peaks at zero, so the
    // paddle is usually about right and occasionally well off, like a person.
    final t = _aimRng.nextDouble() + _aimRng.nextDouble() - 1.0;
    _aimError = t * profile.trackingErrorSigma;
    _ticksSinceResample = 0;
  }

  /// Where the ball will cross [lineY], accounting for wall bounces.
  double _predictInterceptX(BallState ball, double lineY) {
    if (profile.predictionBounces <= 0) return ball.position.x;

    final dy = lineY - ball.position.y;
    if (ball.velocity.y.abs() < 1e-6) return ball.position.x;

    final t = dy / ball.velocity.y;
    if (t <= 0) return ball.position.x;

    final rawX = ball.position.x + ball.velocity.x * t;
    const lo = PongField.ballRadius;
    const hi = PongField.width - PongField.ballRadius;

    if (profile.predictionBounces == 1) {
      // Sees one wall bounce and no further.
      if (rawX < lo) return clampD(lo + (lo - rawX), lo, hi);
      if (rawX > hi) return clampD(hi - (rawX - hi), lo, hi);
      return rawX;
    }
    return foldIntoRange(rawX, lo, hi);
  }

  /// Advance off the goal line as the ball closes, by [BotProfile.forwardLean].
  double _leanY(PaddleState me, BallState ball) {
    final homeY =
        side == PongSide.p2 ? me.bounds.top + 40 : me.bounds.bottom - 40;
    if (profile.forwardLean == 0) return homeY;

    final distance = (ball.position.y - me.position.y).abs();
    final closeness = 1.0 - clampD(distance / 700, 0, 1);
    final lean = profile.forwardLean * closeness;
    return side == PongSide.p2 ? homeY + lean : homeY - lean;
  }

  /// Between rallies, drift back to the middle of the goal line.
  Vec2 _recoverTarget(PaddleState me) {
    final homeY =
        side == PongSide.p2 ? me.bounds.top + 40 : me.bounds.bottom - 40;
    return _normalise(PongField.width / 2, homeY);
  }

  Vec2 _normalise(double x, double y) =>
      Vec2(x / PongField.width, y / PongField.height);

  void _remember(BallState ball) {
    _history[_historyHead] = _Snapshot(ball.position, ball.velocity);
    _historyHead = (_historyHead + 1) % _history.length;
    if (_historyHead == 0) _historyPrimed = true;
  }

  /// The ball as it was [_reactionTicks] ago — the bot's delayed perception.
  BallState _delayedBall() {
    final snapshot = _historyPrimed
        ? _history[_historyHead]
        : _history[0];
    return BallState(position: snapshot.position, velocity: snapshot.velocity);
  }
}

class _Snapshot {
  const _Snapshot(this.position, this.velocity);
  final Vec2 position;
  final Vec2 velocity;
}
