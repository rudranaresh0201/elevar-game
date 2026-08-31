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
      bat: BatState(
        position: const Vec2(
          CricketField.pitchCentreX,
          CricketField.batRestHeight,
        ),
        halfExtents: const Vec2(
          CricketField.batHalfWidth,
          CricketField.batHalfHeight,
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

    // Before the phase, and in every phase. The bat is a body now: it has a
    // position at all times and a velocity measured over the last tick, and
    // both have to be true on the tick the ball happens to cross it. Moving it
    // only during the delivery would leave it teleporting into place on the
    // first tick of every ball, arriving at whatever speed the jump implied.
    _moveBat(dt);

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

  // --- the bat -------------------------------------------------------------

  /// Moves the blade toward wherever it is wanted, at up to
  /// [CricketField.batMaxSpeed].
  ///
  /// Structurally the same as ping pong's paddle, and for the same reason: the
  /// speed cap is what stops a tampered client putting the bat on the ball at
  /// the last instant, and it is also what makes timing a skill rather than a
  /// formality.
  void _moveBat(double dt) {
    final bat = state.bat;
    final target = _batTarget();

    final desired = Vec2(
      CricketField.batXFor(target.x),
      CricketField.batHeightFor(target.y),
    );

    final delta = desired - bat.position;
    final maxStep = CricketField.batMaxSpeed * dt;
    final next = delta.lengthSquared <= maxStep * maxStep
        ? desired
        : bat.position + delta.withLength(maxStep);

    bat.previousPosition = bat.position;
    bat.velocity = (next - bat.position) / dt;
    bat.position = next;
  }

  /// Where the blade is wanted this tick, normalised.
  Vec2 _batTarget() {
    if (state.phase == CricketPhase.betweenBalls ||
        state.phase == CricketPhase.inningsBreak ||
        state.phase == CricketPhase.complete) {
      return CricketField.batStance;
    }
    if (_battingIsHuman) return _heldStriker.batTarget;
    final plan = _plan;
    if (plan == null) return CricketField.batStance;
    return plan.targetAt(_tick);
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
      // The quickest ball on the card, now that it is no longer the hardest to
      // time. A yorker barely deviates and always arrives low, so the only
      // difficulty left in it is how little time there is to get the blade
      // down — which means it has to actually be the fast one.
      DeliveryKind.yorker => CricketField.fastestDelivery * 1.06,
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
        deliveryDifficulty:
            CricketField.deliveryDifficulty(pitchY, targetX),
      );
    }
  }

  bool get _battingIsHuman => isTwoHuman || humanRole == Role.batting;

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
    ball.previousHeight = ball.height;

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

    if (!ball.reachedBat && ball.position.y >= CricketField.batPlaneY) {
      _crossBatPlane();
    }
  }

  /// The moment the ball reaches the bat's plane.
  ///
  /// Resolved *on the crossing*, and exactly on it. The ball passes the plane
  /// somewhere between two ticks, so both the ball and the bat are
  /// interpolated to the crossing instant before anything is asked about
  /// either. Testing at the end of the tick instead would let a fast ball be
  /// judged against a bat that had already moved several units past where it
  /// was when the two actually met — a discrepancy that grows with delivery
  /// speed, which is to say it is worst against exactly the balls that are
  /// hardest to hit.
  void _crossBatPlane() {
    final ball = state.ball;
    final bat = state.bat;

    final travelled = ball.position.y - ball.previousPosition.y;
    // A ball that arrived on the plane without moving cannot be interpolated;
    // treat it as crossing at the end of the tick.
    final t = travelled.abs() < 1e-9
        ? 1.0
        : clampD(
            (CricketField.batPlaneY - ball.previousPosition.y) / travelled,
            0,
            1,
          );

    final crossX =
        ball.previousPosition.x + (ball.position.x - ball.previousPosition.x) * t;
    final crossHeight =
        ball.previousHeight + (ball.height - ball.previousHeight) * t;
    final batAt =
        bat.previousPosition + (bat.position - bat.previousPosition) * t;

    ball
      ..contactPosition = Vec2(crossX, CricketField.batPlaneY)
      ..contactVelocity = ball.velocity
      ..contactHeight = crossHeight;

    final covered = (crossX - batAt.x).abs() <=
            CricketField.batHalfWidth + CricketField.ballRadius &&
        (crossHeight - batAt.y).abs() <=
            CricketField.batHalfHeight + CricketField.ballRadius;

    if (!covered) {
      _resolveMiss();
      return;
    }

    ball
      ..swung = true
      ..swingTick = _tick;
    _resolveContact(
      contactAt: Vec2(crossX, CricketField.batPlaneY),
      contactHeight: crossHeight,
      batAt: batAt,
      batVelocity: bat.velocity,
    );
  }

  /// Bat meets ball.
  ///
  /// Everything about the shot now comes out of the collision rather than out
  /// of a menu. Three numbers do all of it:
  ///
  /// * **where on the blade**, across — decides which way the ball goes, and
  ///   how well it was middled.
  /// * **where on the blade**, vertically — the ball met below the blade's
  ///   middle has been got *under*, and goes up.
  /// * **how fast the blade was moving** — how far it goes.
  ///
  /// The old version took a direction and a power straight off two channels
  /// and multiplied them by a timing score. It played fine and it was a menu:
  /// the player chose an outcome and the simulation graded how close they were
  /// to executing it. This one has no opinion about what shot was intended.
  void _resolveContact({
    required Vec2 contactAt,
    required double contactHeight,
    required Vec2 batAt,
    required Vec2 batVelocity,
  }) {
    final ball = state.ball;

    // Where on the blade, in half-extents, so both are on the same -1..1 scale
    // whatever the blade's dimensions are.
    final offsetX = clampD(
      (contactAt.x - batAt.x) / CricketField.batHalfWidth,
      -1.4,
      1.4,
    );
    final offsetHeight = clampD(
      (contactHeight - batAt.y) / CricketField.batHalfHeight,
      -1.4,
      1.4,
    );

    // Middled means near the middle of the blade, and nothing else. It is
    // deliberately forgiving toward the edges — the reference for this hub is
    // an arcade game, and a player who is beaten by their own thumb twice in a
    // row does not play a third time.
    final furthestOff =
        offsetX.abs() > offsetHeight.abs() ? offsetX.abs() : offsetHeight.abs();
    final quality = clampD(1.0 - 0.62 * furthestOff, 0.05, 1);

    // How hard the blade was travelling, against a full-blooded swing.
    final swing =
        clampD(batVelocity.length / CricketField.batSwingReference, 0, 1.25);

    ball
      ..struck = true
      ..pitched = true
      ..position = contactAt
      ..height = contactHeight;

    // Direction: where on the blade it was met, plus how fast the blade was
    // crossing the line. A ball met on the outside edge with the bat coming
    // across goes square; the same ball met dead centre with a straight bat
    // goes down the ground.
    final lateral = offsetX * CricketField.batOffsetInfluence +
        batVelocity.x * CricketField.batVelocityInfluence;
    var shot = Vec2(lateral, -1).normalized;

    var speed = clampD(
      CricketField.maxHitSpeed *
          (0.30 + 0.70 * quality) *
          (0.26 + 0.74 * swing),
      110,
      CricketField.maxHitSpeed * 1.1,
    );

    // Getting under it. A positive vertical offset means the ball passed above
    // the middle of the blade, which is what lofting a ball physically is.
    final under = clampD(offsetHeight, 0, 1.2);
    var lift = CricketField.maxLoftSpeed *
        (0.10 + 0.90 * under) *
        (0.25 + 0.75 * swing);
    // And lifting the blade through the ball adds to it, which is the other
    // half of how anybody actually hits a six.
    lift += CricketField.maxLoftSpeed *
        clampD(batVelocity.y / CricketField.batSwingReference, 0, 1) *
        0.55;

    if (quality < 0.35) {
      // A mishit. The bat turns in the hand, the ball leaves at an angle
      // nobody chose, and it goes up — which is what makes a top edge a catch
      // rather than a boundary.
      shot = Vec2(
        shot.x * 0.35 + ball.contactVelocity.normalized.x * 0.65,
        shot.y * 0.55,
      ).normalized;
      speed *= 0.55;
      lift = math.max(lift, CricketField.maxLoftSpeed * 0.62);
      _emit(CricketEventType.edged, at: contactAt);
    } else {
      _emit(
        quality >= 0.70 ? CricketEventType.middled : CricketEventType.edged,
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
