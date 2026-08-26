import 'dart:math' as math;

import 'package:game_core/game_core.dart';

import 'bot.dart';
import 'field.dart';
import 'ground.dart';
import 'state.dart';

/// Both humans' intent for one tick.
///
/// Against the bot only one of these is ever filled: the human is batting or
/// bowling, never both, and the bot supplies the other. On a shared screen
/// both are humans and both are filled. A null side means "no new input" and
/// the simulation holds the last one, exactly as a thumb resting on glass does.
class MatchInput {
  const MatchInput({this.striker, this.bowler});

  static const MatchInput none = MatchInput();

  final CricketInput? striker;
  final CricketInput? bowler;
}

/// The match, as pure state.
///
/// Advance it one tick at a time with [step]. It draws nothing, plays nothing,
/// and reads no clock — call it 120 times and one second of cricket has
/// happened, whether that took a second or two milliseconds. That property is
/// what lets the server replay a submitted match in a few milliseconds and
/// check the score it was sent.
class CricketSimulation {
  CricketSimulation({
    required this.seed,
    required this.mode,
    this.botDifficulty,
    this.rules = CricketRules.powerplay,
    this.fieldSetting = FieldSetting.standard,
    this.humanBatsFirst = true,
  }) : assert(
          mode != GameMode.vsBot || botDifficulty != null,
          'A bot match needs a difficulty',
        ) {
    state = CricketState(
      first: InningsState(
        batting: humanBatsFirst ? CricketSide.p1 : CricketSide.p2,
      ),
      ball: BallState(
        position: const Vec2(
          CricketField.pitchCentreX,
          CricketField.bowlerCreaseY,
        ),
      ),
      fielding: <Fielder>[
        for (final position in fieldSetting.positions)
          Fielder(name: position.name, home: position.home),
      ],
    )..phaseTicks = _runUpTicks;

    if (mode == GameMode.vsBot) {
      _bot = CricketBot(
        profile: BotProfile.of(botDifficulty!),
        seed: seed,
      );
    }
    _deliveryRng = DeterministicRng.stream(seed, 7);
    _catchRng = DeterministicRng.stream(seed, 8);
  }

  final int seed;
  final GameMode mode;
  final BotDifficulty? botDifficulty;
  final CricketRules rules;
  final FieldSetting fieldSetting;

  /// Who faces the first ball. Against the bot the human always bats first —
  /// batting is the half people want, and asking them to bowl cold at a
  /// scoreboard they have no feel for yet is a bad first thirty seconds.
  final bool humanBatsFirst;

  late final CricketState state;
  late final DeterministicRng _deliveryRng;
  late final DeterministicRng _catchRng;
  CricketBot? _bot;

  final List<CricketEvent> _events = <CricketEvent>[];

  /// Events raised by the most recent [step]. Valid until the next one.
  List<CricketEvent> get pendingEvents => _events;

  int _tick = 0;
  int get tick => _tick;

  /// Ticks elapsed in the current innings, for the duration cap.
  int _inningsTicks = 0;

  CricketInput _heldStriker = CricketInput.idle;
  CricketInput _heldBowler = CricketInput.idle;

  /// The bot's committed shot for the ball currently in the air.
  BattingPlan? _plan;

  /// Ticks since the ball was struck. Not used for scoring — see
  /// [CricketField.unitsPerRun] — but it is the stalled-ball backstop's clock.
  int _inPlayTicks = 0;

  /// How long a struck ball may stay live before it is called dead, however
  /// slowly it is rolling and however far the nearest fielder still is.
  static const int _maxInPlayTicks = 120 * 6;

  /// Runs earned by a ball fielded at [where].
  ///
  /// Distance from the striker's end, because that is what the batters would
  /// actually have had time to run.
  int _runsFor(Vec2 where) {
    const striker = Vec2(CricketField.pitchCentreX, CricketField.strikerY);
    final distance = (where - striker).length;
    final runs = (distance / CricketField.unitsPerRun).floor();
    return runs < 0 ? 0 : (runs > CricketField.maxRunRuns
        ? CricketField.maxRunRuns
        : runs);
  }

  bool get isComplete => state.phase == CricketPhase.complete;

  bool get isTwoHuman => mode == GameMode.local2P;

  /// Which role the account holder is performing right now.
  Role get humanRole =>
      state.current.batting == CricketSide.p1 ? Role.batting : Role.bowling;

  /// Input channels a replay of this match must carry.
  ///
  /// Against the bot exactly one human acts at any moment and which one is
  /// derivable from the ball count, so four channels cover a whole match. On a
  /// shared screen both people act on every ball, so both need recording.
  int get replayChannelCount =>
      isTwoHuman ? CricketInput.channelCount * 2 : CricketInput.channelCount;

  int get _runUpTicks => (rules.tickHz * 1.15).round();

  // --- the loop ------------------------------------------------------------

  /// Advances the match by exactly one tick.
  void step(MatchInput input) {
    _events.clear();
    if (state.phase == CricketPhase.complete) return;

    final dt = rules.stepSeconds;

    if (input.striker != null) _heldStriker = input.striker!;
    if (input.bowler != null) _heldBowler = input.bowler!;

    switch (state.phase) {
      case CricketPhase.runUp:
        state.phaseTicks--;
        if (state.phaseTicks <= 0) _release();

      case CricketPhase.delivery:
        _advanceDelivery(dt);

      case CricketPhase.ballInPlay:
        _advanceInPlay(dt);

      case CricketPhase.betweenBalls:
        state.phaseTicks--;
        _recoverFielders(dt);
        if (state.phaseTicks <= 0) _beginNextBall();

      case CricketPhase.inningsBreak:
        state.phaseTicks--;
        if (state.phaseTicks <= 0) _startSecondInnings();

      case CricketPhase.complete:
        break;
    }

    _tick++;
    _inningsTicks++;

    // The backstop. An innings where nobody ever swings still has to end, or
    // the server has no duration to sanity-check and two players could farm
    // playtime by never touching the screen.
    if (_inningsTicks >= rules.maxTicksPerInnings &&
        state.phase != CricketPhase.complete) {
      _endInnings();
    }
  }

  // --- bowling -------------------------------------------------------------

  /// Puts a ball on its way, from whichever side is bowling.
  void _release() {
    final bowlingIsHuman = isTwoHuman || humanRole == Role.bowling;
    final plan = bowlingIsHuman ? _heldBowler : _bot!.planDelivery(
          pressure: _pressure(),
        );

    final aim = plan.aimPoint;
    final kind = plan.deliveryKind;

    // Nobody, bot or human, puts the ball exactly where they meant to.
    //
    // This was +/-9 across and +/-24 down, which was small enough that the
    // delivery barely varied: three different match seeds produced a
    // bit-identical first innings, every ball a single or a two. A ball has to
    // be worth watching. It is still small against the 92-unit pitch, so aiming
    // remains most of the skill of bowling — but a length is now something you
    // land near rather than on.
    final wobbleX = _deliveryRng.nextRange(-17, 17);
    final wobbleY = _deliveryRng.nextRange(-42, 42);

    final pitchY = clampD(
      aim.y + wobbleY,
      CricketField.shortestLength,
      CricketField.fullestLength,
    );
    final targetX = clampD(
      aim.x + wobbleX,
      CricketField.pitchCentreX - CricketField.pitchHalfWidth * 2.6,
      CricketField.pitchCentreX + CricketField.pitchHalfWidth * 2.6,
    );

    final speed = switch (kind) {
      DeliveryKind.pace => CricketField.fastestDelivery,
      DeliveryKind.spin => CricketField.slowestDelivery,
      DeliveryKind.yorker => CricketField.fastestDelivery * 0.96,
      DeliveryKind.bouncer => CricketField.fastestDelivery * 0.90,
    };

    final deviationScale = switch (kind) {
      DeliveryKind.pace => 0.35,
      DeliveryKind.spin => 1.0,
      DeliveryKind.yorker => 0.20,
      DeliveryKind.bouncer => 0.55,
    };

    final from = const Vec2(
      CricketField.pitchCentreX,
      CricketField.bowlerCreaseY,
    );
    final travel = Vec2(targetX - from.x, pitchY - from.y);
    final velocity = travel.normalized * speed;

    // Ticks until the ball reaches the contact line. `vy` is constant for the
    // whole delivery — the bounce changes sideways travel only — so this is
    // exact rather than predicted, and both the bot and the swing window key
    // off the same number.
    final ticksToContact =
        ((CricketField.contactY - from.y) / (velocity.y * rules.stepSeconds))
            .round();

    state.ball = BallState(position: from)
      ..velocity = velocity
      ..pitchY = pitchY
      ..deviation = _deliveryRng.nextRange(-1, 1) *
          CricketField.maxDeviation *
          deviationScale
      ..idealContactTick = _tick + ticksToContact
      ..height = 22;

    state.phase = CricketPhase.delivery;
    _plan = null;
    _emit(CricketEventType.release, at: from, text: kind.wire);

    // The bot commits to its shot the moment the ball leaves the hand, which
    // is what makes it look like it is playing a shot rather than tracking.
    if (!_battingIsHuman) {
      _plan = _bot!.planShot(
        ball: state.ball,
        required: _requiredRate(),
        deliveryDifficulty: _deliveryDifficulty(pitchY, targetX),
      );
    }
  }

  bool get _battingIsHuman => isTwoHuman || humanRole == Role.batting;

  /// How hard this delivery is to bat at, 0..1.
  ///
  /// Length is worth more than line, which is how bowling actually works: a
  /// ball on a good length is awkward wherever it is, and a ball short and wide
  /// is a gift however straight the seam was pointing.
  double _deliveryDifficulty(double pitchY, double targetX) {
    const goodLength = 790.0;
    const lengthTolerance = 130.0;
    final lengthQuality =
        1 - clampD((pitchY - goodLength).abs() / lengthTolerance, 0, 1);

    final lineQuality = 1 -
        clampD((targetX - CricketField.pitchCentreX).abs() / 95, 0, 1);

    return clampD(0.62 * lengthQuality + 0.38 * lineQuality, 0, 1);
  }

  /// How stretched the chasing side is, 0..1. Zero in the first innings.
  double _pressure() {
    final innings = state.current;
    if (!innings.chasing) return 0;
    final ballsLeft = rules.ballsPerInnings - innings.balls;
    if (ballsLeft <= 0) return 1;
    final needed = innings.target - innings.runs;
    return clampD(needed / (ballsLeft * 2.2), 0, 1);
  }

  /// Required rate as a multiple of a par rate of roughly a run a ball.
  double _requiredRate() {
    final innings = state.current;
    if (!innings.chasing) return 1;
    final ballsLeft = rules.ballsPerInnings - innings.balls;
    if (ballsLeft <= 0) return 2;
    return clampD((innings.target - innings.runs) / ballsLeft, 0, 3);
  }

  // --- the delivery --------------------------------------------------------

  void _advanceDelivery(double dt) {
    final ball = state.ball;
    ball.previousPosition = ball.position;

    // Register the swing. One per ball: a player who could keep swinging
    // would eventually connect with everything.
    if (!ball.swung) {
      final swinging = _battingIsHuman
          ? _heldStriker.action
          : (_plan != null && _tick >= _plan!.swingTick);
      if (swinging) {
        ball.swung = true;
        ball.swingTick = _tick;
      }
    }

    ball.position += ball.velocity * dt;

    // The bounce. Sideways deviation is applied here and not before, which is
    // what makes length matter: a fuller ball has less pitch left to move on.
    if (!ball.pitched && ball.position.y >= ball.pitchY) {
      ball.pitched = true;
      ball.velocity = Vec2(
        ball.velocity.x + ball.deviation,
        ball.velocity.y,
      );
      // How much it sits up. Short balls climb, yorkers skid.
      final shortness = clampD(
        (CricketField.fullestLength - ball.pitchY) /
            (CricketField.fullestLength - CricketField.shortestLength),
        0,
        1,
      );
      ball.height = 4;
      ball.verticalSpeed = 40 + 150 * shortness;
      _emit(CricketEventType.pitched, at: ball.position);
    }

    _integrateHeight(ball, dt);

    // Freeze the ball as it passes the bat, but do not resolve the shot yet.
    //
    // Resolving on the crossing itself is the obvious thing to do and it is
    // wrong: the crossing happens on exactly `idealContactTick`, so a swing
    // one tick late could never be registered at all. The window was silently
    // one-sided — a player could be early but never late — and every late
    // swing became a play-and-miss, which made bowled far and away the most
    // common dismissal. The ball is allowed to travel on to the keeper while
    // the rest of the window runs out.
    if (!ball.reachedBat && ball.position.y >= CricketField.contactY) {
      ball
        ..contactPosition = ball.position
        ..contactVelocity = ball.velocity
        ..contactHeight = ball.height;
    }

    if (ball.reachedBat &&
        _tick >= ball.idealContactTick + CricketField.contactWindowTicks) {
      _resolveContact();
    }
  }

  /// Bat meets ball, or does not.
  void _resolveContact() {
    final ball = state.ball;

    final timingError = ball.swung
        ? (ball.swingTick - ball.idealContactTick).abs()
        : CricketField.contactWindowTicks + 1;

    if (timingError > CricketField.contactWindowTicks) {
      _resolveMiss();
      return;
    }

    // Timing is most of it, and deliberately generous: this is an arcade
    // game, and a player who cannot make contact never learns anything else.
    final timing = 1.0 -
        timingError / CricketField.contactWindowTicks.toDouble();

    final direction = _battingIsHuman
        ? _heldStriker.shotDirection
        : _plan!.direction;
    final intent = _battingIsHuman ? _heldStriker.power : _plan!.power;

    // Playing with the line. Where the ball crossed the bat decides which shot
    // was the right one, so a wide ball wants to be cut and a straight one
    // wants to be driven.
    //
    // The right shot is expressed as a **direction**, in the same normalised
    // space the played shot is in. It used to be a bare ratio capped at one,
    // compared against the x of a unit vector which can never exceed 0.707 for
    // anything played down the ground — so a wide ball could not be aligned
    // with no matter how well it was read, and a straight one aligned almost
    // for free. Accurate bowling was therefore *punished*: against the hard
    // bot, a bowler at skill 0.9 conceded 34 off twelve balls and a bowler at
    // skill 0.3 conceded 22. The whole difficulty ladder inverted on this one
    // line.
    final contactAt = ball.contactPosition ?? ball.position;
    final lineOffset = contactAt.x - CricketField.pitchCentreX;
    final preferred =
        Vec2(clampD(lineOffset / 70, -1, 1), -1).normalized.x;
    final alignment =
        1.0 - clampD((direction.x - preferred).abs() / 1.6, 0, 1);

    final quality = clampD(0.72 * timing + 0.28 * alignment, 0, 1);

    // The shot is played from where the ball met the bat, not from wherever it
    // has rolled on to while the window ran down.
    ball
      ..struck = true
      ..pitched = true
      ..position = contactAt
      ..height = ball.contactHeight;

    var shot = direction;
    // Intent has to matter across its whole range, not just at the top.
    //
    // This was `0.55 + 0.45 * intent`, which left a gentle push travelling at
    // 628 units/s — far enough to beat the field to a single almost every time.
    // Poking at everything therefore scored about a run a ball with no risk
    // attached, and dominated hitting out completely: the *easy* bot outscored
    // the hard one because it swung softer. A soft shot now has to be soft.
    var speed = CricketField.maxHitSpeed *
        (0.30 + 0.70 * quality) *
        (0.30 + 0.70 * intent);

    // Loft rises continuously with intent rather than switching on at a
    // threshold. A cliff here makes the whole middle of the power range a trap:
    // just under it every shot stays down and earns a single, just over it
    // every shot is a catchable lob that lands on the ring, and hitting the
    // ball harder is therefore *punished* until you can hit it out of the
    // ground. Skill inverted in the balance table because of it.
    final loftIntent = clampD((intent - 0.30) / 0.70, 0, 1);
    var lift = CricketField.maxLoftSpeed *
        loftIntent *
        (0.40 + 0.60 * quality);

    if (quality < 0.35) {
      // A mishit. The bat turns in the hand, the ball leaves at an angle
      // nobody chose, and it goes up — which is what makes a top edge a
      // catch rather than a boundary.
      final leading = Vec2(
        shot.x * 0.35 + ball.contactVelocity.normalized.x * 0.65,
        shot.y * 0.55,
      ).normalized;
      shot = leading;
      speed *= 0.55;
      lift = math.max(lift, CricketField.maxLoftSpeed * 0.62);
      _emit(CricketEventType.edged, at: ball.position);
    } else {
      _emit(
        quality >= 0.70
            ? CricketEventType.middled
            : CricketEventType.edged,
        at: contactAt,
        value: (quality * 100).round(),
      );
    }

    ball
      ..velocity = shot * speed
      ..verticalSpeed = lift
      ..height = math.max(ball.height, 6);

    _beginInPlay();
  }

  /// Beaten. The only question left is whether the stumps were behind it.
  void _resolveMiss() {
    final ball = state.ball;

    // Where the ball crossed the stumps, projected from where it passed the
    // bat rather than from wherever it has reached by now.
    final from = ball.contactPosition ?? ball.position;
    final velocity = ball.contactPosition != null
        ? ball.contactVelocity
        : ball.velocity;
    final ticksToStumps = (CricketField.strikerCreaseY - from.y) /
        (velocity.y * rules.stepSeconds);
    final xAtStumps =
        from.x + velocity.x * rules.stepSeconds * ticksToStumps;

    final onTarget =
        (xAtStumps - CricketField.pitchCentreX).abs() <=
            CricketField.stumpsHalfWidth;

    // A ball over the top of the stumps cannot bowl anyone, which is the
    // whole trade the bouncer makes: unmissable-looking, and harmless.
    final underTheBails = ball.contactHeight < 58;

    if (onTarget && underTheBails) {
      _emit(CricketEventType.wicket,
          at: const Vec2(CricketField.pitchCentreX,
              CricketField.strikerCreaseY),
          text: 'BOWLED');
      _settle(const BallResult(
        runs: 0,
        dismissal: Dismissal.bowled,
        boundary: 0,
        contactQuality: 0,
      ));
      return;
    }

    _emit(CricketEventType.playedAndMissed, at: from);
    _settle(const BallResult(
      runs: 0,
      dismissal: Dismissal.none,
      boundary: 0,
      contactQuality: 0,
    ));
  }

  void _beginInPlay() {
    state.phase = CricketPhase.ballInPlay;
    _inPlayTicks = 0;
    for (final fielder in state.fielding) {
      fielder.hasBall = false;
    }
  }

  // --- the ball in play ----------------------------------------------------

  void _advanceInPlay(double dt) {
    final ball = state.ball;
    ball.previousPosition = ball.position;

    _integrateHeight(ball, dt);
    ball.position += ball.velocity * dt;

    // Air resistance is light; the outfield is not.
    final drag = ball.airborne ? 0.22 : CricketField.outfieldDrag;
    ball.velocity -= ball.velocity * (drag * dt);

    _inPlayTicks++;

    // Over the rope. Six if it was still in the air when it crossed, four if
    // it had already touched down — which is exactly the real rule and needs
    // no special casing.
    if (Ground.isOverBoundary(ball.position)) {
      final six = ball.airborne;
      ball.position = Ground.clampInside(ball.position);
      ball
        ..velocity = Vec2.zero
        ..height = 0
        ..verticalSpeed = 0;
      _emit(six ? CricketEventType.six : CricketEventType.four,
          at: ball.position, value: six ? 6 : 4);
      _settle(BallResult(
        runs: six ? 6 : 4,
        dismissal: Dismissal.none,
        boundary: six ? 6 : 4,
        contactQuality: 1,
      ));
      return;
    }

    _chaseBall(dt);
  }

  /// Where a ball in the air is going to come down.
  ///
  /// Fielders run at this rather than at the ball's live position, which is
  /// the difference between a field that can be cleared and one that cannot.
  /// Chasing the live position means trailing the ball and arriving underneath
  /// it exactly as it drops — every lofted shot is a catch, and hitting it
  /// harder only makes it worse.
  ///
  /// Solves `h + v·t - ½g·t² = 0` for the positive root. No trigonometry, and
  /// `sqrt` is safe under the determinism contract.
  Vec2 _landingPoint(BallState ball) {
    if (!ball.airborne) return ball.position;
    final v = ball.verticalSpeed;
    final h = ball.height;
    final discriminant = v * v + 2 * CricketField.gravity * h;
    if (discriminant <= 0) return ball.position;
    final t = (v + math.sqrt(discriminant)) / CricketField.gravity;
    return ball.position + ball.velocity * t;
  }

  /// The nearest fielder chases. The rest hold their ground.
  ///
  /// This used to be *every* fielder running at the landing point, and it is
  /// the single reason the game had no boundaries in it. Ten players
  /// converging on one spot means somebody is always underneath it, so every
  /// lofted shot was a catch and hitting the ball harder only chose which
  /// fielder took it. The balance table showed it plainly — four and a half
  /// wickets an innings out of six, and a boundary once in eight balls.
  ///
  /// One chaser is also simply what a real field does. Everybody else still
  /// stops what comes to them: standing still is not the same as being a hole
  /// in the field, and a shot hit straight at cover is still a shot hit
  /// straight at cover.
  void _chaseBall(double dt) {
    final ball = state.ball;
    final target = _landingPoint(ball);

    Fielder? chaser;
    var nearest = double.infinity;
    for (final fielder in state.fielding) {
      final distance = (target - fielder.position).length;
      if (distance < nearest) {
        nearest = distance;
        chaser = fielder;
      }
    }

    for (final fielder in state.fielding) {
      fielder.previousPosition = fielder.position;

      if (identical(fielder, chaser)) {
        final toBall = target - fielder.position;
        final distance = toBall.length;
        if (distance > 1) {
          final step = CricketField.fielderSpeed * dt;
          fielder.position +=
              toBall.normalized * (step > distance ? distance : step);
        }
      } else {
        // A half-hearted amble towards the ball, capped so nobody drifts into
        // becoming a second chaser. Purely so the field does not look frozen.
        final toBall = ball.position - fielder.position;
        final distance = toBall.length;
        if (distance > CricketField.backingUpRadius) {
          final step = CricketField.fielderSpeed * CricketField.backingUpPace * dt;
          fielder.position += toBall.normalized * step;
        }
      }

      final gap = (ball.position - fielder.position).length;

      // A catch. Four conditions now, and each one exists to stop a different
      // way of making every lofted shot out:
      //
      //  * low enough to get a hand to, so a real hit sails over the top;
      //  * **on the way down**, or a fielder standing where the ball happens
      //    to pass on its way up takes a catch nobody would call a catch;
      //  * travelling slowly enough to hold — a ball middled at 900 units/s
      //    into somebody's hands is a chance, not a wicket;
      //  * and either they are the one who chased it, or it has come straight
      //    to them. A fielder rooted at deep midwicket does not catch a ball
      //    that lands twenty units away.
      final theirs = identical(fielder, chaser) ||
          gap <= CricketField.catchRadius * 0.6;

      if (theirs &&
          ball.airborne &&
          ball.verticalSpeed < 0 &&
          ball.height <= CricketField.catchReach &&
          gap <= CricketField.catchRadius) {
        final reliability = _bot?.profile.catchReliability ?? 0.80;
        final hardness = clampD(ball.speed / 620, 0, 0.88);
        final held = _catchRng.chance(reliability * (1 - hardness));
        if (held) {
          fielder.hasBall = true;
          _emit(CricketEventType.wicket,
              at: fielder.position, text: 'CAUGHT · ${fielder.name}');
          _settle(const BallResult(
            runs: 0,
            dismissal: Dismissal.caught,
            boundary: 0,
            contactQuality: 0.3,
          ));
          return;
        }
      }

      if (!ball.airborne && gap <= CricketField.fieldingRadius) {
        fielder.hasBall = true;
        final runs = _runsFor(ball.position);
        _emit(CricketEventType.fielded,
            at: fielder.position, text: fielder.name);
        if (runs > 0) {
          _emit(CricketEventType.runsScored,
              at: fielder.position, value: runs);
        }
        _settle(BallResult(
          runs: runs,
          dismissal: Dismissal.none,
          boundary: 0,
          contactQuality: 0.6,
        ));
        return;
      }
    }

    // Nobody has got to it and it has stopped rolling. Award what was run and
    // move on rather than watching a stationary ball.
    if ((!ball.airborne && ball.speed < 12) ||
        _inPlayTicks > _maxInPlayTicks) {
      final runs = _runsFor(ball.position);
      _settle(BallResult(
        runs: runs,
        dismissal: Dismissal.none,
        boundary: 0,
        contactQuality: 0.6,
      ));
    }
  }

  /// Height is a scalar beside the position, not a third axis — see
  /// [BallState.height].
  void _integrateHeight(BallState ball, double dt) {
    if (ball.height <= 0 && ball.verticalSpeed <= 0) {
      ball
        ..height = 0
        ..verticalSpeed = 0;
      return;
    }
    ball.verticalSpeed -= CricketField.gravity * dt;
    ball.height += ball.verticalSpeed * dt;
    if (ball.height <= 0) {
      ball.height = 0;
      // Loses most of it on the bounce, so a lofted shot does not skip to the
      // rope like a stone on a pond.
      ball.verticalSpeed = ball.verticalSpeed.abs() * 0.32;
      if (ball.verticalSpeed < 30) ball.verticalSpeed = 0;
    }
  }

  void _recoverFielders(double dt) {
    for (final fielder in state.fielding) {
      fielder.previousPosition = fielder.position;
      final home = fielder.home - fielder.position;
      final distance = home.length;
      if (distance <= 1) continue;
      final step = CricketField.fielderSpeed * 0.8 * dt;
      fielder.position +=
          home.normalized * (step > distance ? distance : step);
    }
  }

  // --- the scoreboard ------------------------------------------------------

  void _settle(BallResult result) {
    final innings = state.current;

    innings.runs += result.runs;
    innings.balls++;
    if (result.isWicket) {
      innings.wickets++;
      innings.timeline.add(-1);
    } else {
      innings.timeline.add(result.runs);
    }

    state.lastBall = result;
    state.phase = CricketPhase.betweenBalls;
    state.phaseTicks = rules.deliveryGapTicks;

    if (innings.balls % rules.ballsPerOver == 0 &&
        innings.balls < rules.ballsPerInnings) {
      _emit(CricketEventType.overComplete, value: innings.balls ~/ rules.ballsPerOver);
    }
  }

  void _beginNextBall() {
    final innings = state.current;

    final out = innings.wickets >= rules.wickets;
    final done = innings.balls >= rules.ballsPerInnings;
    final chased = innings.hasWon;

    if (out || done || chased) {
      _endInnings();
      return;
    }

    for (final fielder in state.fielding) {
      fielder.resetToHome();
    }
    state
      ..phase = CricketPhase.runUp
      ..phaseTicks = _runUpTicks;
    _emit(CricketEventType.runUpStart);
  }

  void _endInnings() {
    _emit(CricketEventType.inningsComplete, value: state.current.runs);

    if (state.second == null) {
      state
        ..phase = CricketPhase.inningsBreak
        ..phaseTicks = rules.tickHz * 2;
      return;
    }
    _finishMatch();
  }

  void _startSecondInnings() {
    final firstInnings = state.first;
    state.second = InningsState(
      batting: firstInnings.batting == CricketSide.p1
          ? CricketSide.p2
          : CricketSide.p1,
      target: firstInnings.runs + 1,
    );
    _inningsTicks = 0;
    for (final fielder in state.fielding) {
      fielder.resetToHome();
    }
    state
      ..phase = CricketPhase.runUp
      ..phaseTicks = _runUpTicks;
    _emit(CricketEventType.runUpStart);
  }

  void _finishMatch() {
    final p1 = state.runsFor(CricketSide.p1);
    final p2 = state.runsFor(CricketSide.p2);

    if (p1 == p2) {
      state.tied = true;
    } else {
      state.winner = p1 > p2 ? CricketSide.p1 : CricketSide.p2;
    }
    state.phase = CricketPhase.complete;
    _emit(CricketEventType.matchComplete, value: p1);
  }

  // --- results -------------------------------------------------------------

  int get durationMs => (_tick * 1000) ~/ rules.tickHz;

  /// A par score for this format, used to normalise pace into the 0..1 skill
  /// scale. Derived from the format rather than hand-tuned, so changing the
  /// number of overs does not mean re-deriving what a good score is.
  double get _parScore => rules.ballsPerInnings * 1.35;

  /// Skill on the 0..1 scale every Elevar game reports, from P1's view.
  ///
  /// Half of it is the result, because winning has to be worth more than
  /// anything else. The rest splits between runs scored and wickets taken, so
  /// a player who loses a tight chase after batting well still scores well
  /// above one who was bowled out for nothing. The server's payout formula
  /// sees only this number and must treat cricket, racing and ping pong on the
  /// same terms — which is exactly why it is a fraction and not a run rate.
  double get normalizedSkill {
    final p1 = state.runsFor(CricketSide.p1);
    final p2 = state.runsFor(CricketSide.p2);

    final margin = state.tied
        ? 0.5
        : clampD(0.5 + 0.5 * ((p1 - p2) / _parScore), 0, 1);

    final scoring = clampD(p1 / _parScore, 0, 1);

    final wicketsTaken = state.wicketsFor(
      state.first.batting == CricketSide.p1 ? CricketSide.p2 : CricketSide.p1,
    );
    final bowling = clampD(wicketsTaken / rules.wickets, 0, 1);

    return clampD(0.5 * margin + 0.32 * scoring + 0.18 * bowling, 0, 1);
  }

  /// Packages the finished match for submission to `/v1/matches`.
  ///
  /// Score is runs, which keeps the wire format identical to the other two
  /// games and lets the server's plausibility rules apply to cricket without
  /// learning what an over is.
  GameResult buildResult({String? sessionToken, List<int>? replay}) {
    final p1 = state.runsFor(CricketSide.p1);
    final p2 = state.runsFor(CricketSide.p2);

    final outcome = state.tied
        ? MatchOutcome.draw
        : (state.winner == CricketSide.p1
            ? MatchOutcome.p1Win
            : MatchOutcome.p2Win);

    return GameResult(
      gameSlug: 'cricket',
      mode: mode,
      botDifficulty: botDifficulty,
      durationMs: durationMs,
      p1Score: p1,
      p2Score: p2,
      outcome: outcome,
      normalizedSkill: normalizedSkill,
      seed: seed,
      tickCount: _tick,
      replay: replay,
      sessionToken: sessionToken,
    );
  }

  void _emit(CricketEventType type, {Vec2? at, int value = 0, String? text}) =>
      _events.add(CricketEvent(type, at: at, value: value, text: text));
}
