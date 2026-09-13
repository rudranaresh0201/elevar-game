import 'dart:math' as math;

import 'package:game_core/game_core.dart';

import 'arena.dart';

/// How fast the machine bowls, and how many runs make a win.
enum Pace {
  easy(minSpeed: 900, maxSpeed: 1100, runsPerBall: 1.6, stumpsShare: 0.55),
  medium(minSpeed: 1150, maxSpeed: 1400, runsPerBall: 2.3, stumpsShare: 0.65),
  hard(minSpeed: 1450, maxSpeed: 1750, runsPerBall: 3.0, stumpsShare: 0.75);

  const Pace({
    required this.minSpeed,
    required this.maxSpeed,
    required this.runsPerBall,
    required this.stumpsShare,
  });

  /// Horizontal release speed, in field units per second.
  final double minSpeed;
  final double maxSpeed;

  /// Sets the target: this many runs per ball in the innings.
  final double runsPerBall;

  /// Share of deliveries that would hit the stumps if left alone. The rest
  /// bounce over — which is what makes leaving a ball a decision.
  final double stumpsShare;

  static Pace of(BotDifficulty difficulty) => switch (difficulty) {
        BotDifficulty.easy => Pace.easy,
        BotDifficulty.medium => Pace.medium,
        BotDifficulty.hard => Pace.hard,
      };
}

/// The length of an innings.
class WallCricketRules {
  const WallCricketRules({required this.overs, required this.wickets});

  final int overs;
  final int wickets;

  int get balls => overs * 6;

  static const WallCricketRules quick = WallCricketRules(overs: 2, wickets: 2);
  static const WallCricketRules classic = WallCricketRules(overs: 3, wickets: 3);
  static const WallCricketRules long = WallCricketRules(overs: 5, wickets: 4);

  static const int tickHz = 120;
}

enum WallCricketPhase { ready, windup, live, result, complete }

enum BallOutcomeKind { runs, dot, out }

/// What happened to the last ball, for the banner.
class BallOutcome {
  const BallOutcome.runs(this.runs, {required this.zone, required this.hot})
      : kind = BallOutcomeKind.runs,
        caught = false;

  const BallOutcome.dot()
      : kind = BallOutcomeKind.dot,
        runs = 0,
        zone = null,
        hot = false,
        caught = false;

  const BallOutcome.out({this.caught = false})
      : kind = BallOutcomeKind.out,
        runs = 0,
        zone = null,
        hot = false;

  final BallOutcomeKind kind;
  final int runs;
  final int? zone;
  final bool hot;

  /// Out caught behind off an edge, rather than bowled.
  final bool caught;
}

enum WallCricketEventType {
  release,
  timing,
  hit,
  edge,
  bounce,
  wall,
  scored,
  dot,
  out,
  overComplete,
  complete,
}

class WallCricketEvent {
  const WallCricketEvent(this.type, {this.at = Vec2.zero, this.value = 0});

  final WallCricketEventType type;
  final Vec2 at;

  /// Intensity 0..1 for hits and bounces; runs for [WallCricketEventType.scored].
  final double value;
}

/// How well a swing was timed.
enum ShotTiming { perfect, goodEarly, goodLate, edgeEarly, edgeLate, missEarly, missLate }

/// One human input sample.
class WallCricketInput {
  const WallCricketInput({this.direction = const Vec2(1, -0.5), this.swing = 0});

  /// Which way the swipe went, screen-style (y down). Read when the bat
  /// meets the ball, so a swipe that finishes just after the tap still
  /// chooses the shot.
  final Vec2 direction;

  /// Rising edge starts the swing.
  final double swing;

  static const WallCricketInput idle = WallCricketInput();

  static WallCricketInput fromChannels(List<double> c) => WallCricketInput(
        direction: Vec2(c[0] * 2 - 1, c[1] * 2 - 1),
        swing: c[2],
      );
}

/// Top Spinner cricket, as pure state.
///
/// **Batting is timing.** Touch the screen as the ball arrives and the batter
/// swings; the swing meets the ball at whatever height it is, so a bouncer
/// and a yorker are as playable as a half-volley. How early or late the touch
/// was decides the shot: perfect is a big hit, good is solid, a little off is
/// an edge, well off is a miss. The swipe that follows the touch picks the
/// shot: up to loft it, forward to drive, back to pull, down to keep it on
/// the ground.
///
/// Two earlier versions made the player steer the blade into the ball with
/// real collision physics. They were accurate and they were not fun — a
/// short ball could simply not be reached, and a swipe in the "wrong"
/// direction did nothing. Every mobile cricket game that people actually play
/// works like this one now does.
///
/// Runs come from the numbered wall the ball hits first. A delivery that
/// reaches the stumps without touching the bat is bowled. Once it has touched
/// the bat it cannot get you out — a ball popped straight up that drops back
/// onto the stumps was a swing, and punishing swings teaches people not to.
class WallCricketSimulation {
  WallCricketSimulation({
    required this.seed,
    required this.pace,
    this.rules = WallCricketRules.classic,
  })  : _deliveryRng = DeterministicRng.stream(seed, 1),
        _hotRng = DeterministicRng.stream(seed, 2) {
    target = (rules.balls * pace.runsPerBall).round();
    hotZone = _pickHotZone();
  }

  final int seed;
  final Pace pace;
  final WallCricketRules rules;
  late final int target;

  final DeterministicRng _deliveryRng;
  final DeterministicRng _hotRng;
  late final DeterministicRng _shotRng = DeterministicRng.stream(seed, 4);
  final EdgeTrigger _swingEdge = EdgeTrigger();

  /// Ticks from the touch to the bat meeting the ball: the swing's wind-up.
  static const int contactDelayTicks = 14;

  /// The whole swing animation, backlift to follow-through.
  static const int swingTicks = 24;

  /// Where the bat meets the ball.
  static const double hitX = 400;

  /// Timing windows, in seconds either side of perfect.
  ({double perfect, double good, double edge}) get windows => switch (pace) {
        Pace.easy => (perfect: 0.045, good: 0.1, edge: 0.14),
        Pace.medium => (perfect: 0.035, good: 0.08, edge: 0.12),
        Pace.hard => (perfect: 0.028, good: 0.066, edge: 0.1),
      };

  /// Chance a late edge carries to the keeper.
  double get edgeCatchChance => switch (pace) {
        Pace.easy => 0.2,
        Pace.medium => 0.35,
        Pace.hard => 0.5,
      };

  int? _swingStartTick;
  int? _contactTick;
  ShotTiming? _plannedTiming;

  /// The last ball's timing, for the player to learn from.
  ShotTiming? lastTiming;

  /// How far off perfect it was, seconds: positive early, negative late.
  double lastTimingError = 0;

  static const int channelCount = 3;

  static const int _readyTicks = 60;
  static const int _windupTicks = 54;
  static const int _resultTicks = 90;
  static const int _deadBallTicks = 360;
  static const int _substeps = 6;

  /// How fast the bat eases back up to the backlift between balls, as arc
  /// fraction per tick.
  static const double _returnRate = 0.012;

  /// The swing, as blade directions from backlift to follow-through (y down,
  /// batter facing right). Interpolated by normalising the straight blend of
  /// neighbours, which stays on the circle without a single sin or cos.
  static const List<Vec2> swingArc = <Vec2>[
    Vec2(-0.4226, -0.9063), // backlift, over the shoulder
    Vec2(-0.9535, -0.3014), // behind, above the bails
    Vec2(-0.4000, 0.9165), // down past the back leg
    Vec2(0.2000, 0.9798), // bottom of the arc, grounded
    Vec2(0.8480, 0.5300), // through the line: where most balls are met
    Vec2(0.9798, -0.2000), // level, arms extended
    Vec2(0.4540, -0.8910), // follow-through
  ];

  /// Blade direction at [s] (0..1) along [swingArc].
  static Vec2 arcDirection(double s) {
    final f = clampD(s, 0, 1) * (swingArc.length - 1);
    var i = f.floor();
    if (i >= swingArc.length - 1) i = swingArc.length - 2;
    final t = f - i;
    return (swingArc[i] + (swingArc[i + 1] - swingArc[i]) * t).normalized;
  }

  static const int _maxTicks = WallCricketRules.tickHz * 60 * 12;

  int tick = 0;
  WallCricketPhase phase = WallCricketPhase.ready;
  int _phaseTicks = 0;

  int runs = 0;
  int wickets = 0;
  int ballsBowled = 0;
  int fours = 0;
  int sixes = 0;
  int hits = 0;
  int edges = 0;

  /// The scoring zone worth double this over.
  late int hotZone;

  BallOutcome? lastOutcome;

  // --- the ball ------------------------------------------------------------
  Vec2 ballPosition = Arena.machineMouth;
  Vec2 ballPrevious = Arena.machineMouth;
  Vec2 ballVelocity = Vec2.zero;
  bool ballVisible = false;
  bool _ballHit = false;
  bool _resolved = false;
  int _ticksSinceHit = 0;
  int _ticksLive = 0;

  // --- the bat -------------------------------------------------------------
  /// Where along the swing the blade is, 0..1.
  double swing = 0;
  Vec2 batDirection = _constrain(arcDirection(0));
  Vec2 batPrevious = _constrain(arcDirection(0));

  /// How lively the pitch is for this delivery's first bounce. It varies ball
  /// to ball, so the same length can arrive at the knee or the chest.
  double pitchBounce = Arena.groundRestitution;
  bool _bounced = false;

  /// How fast the tip is moving, in field units a second. Drives the swoosh.
  double batTipSpeed = 0;

  // --- the machine, for the renderer ---------------------------------------
  /// 0..1 through the windup. The light blinks on it.
  double get windupProgress =>
      phase == WallCricketPhase.windup ? _phaseTicks / _windupTicks : 0;

  final List<WallCricketEvent> pendingEvents = <WallCricketEvent>[];

  bool get isComplete => phase == WallCricketPhase.complete;

  Vec2 get batTip => Arena.pivot + batDirection * Arena.batLength;

  int get ballsLeft => rules.balls - ballsBowled;

  int get over => ballsBowled ~/ 6;

  double get normalizedSkill {
    final value = runs / (target * 1.5);
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }

  /// Advances one tick.
  void step(WallCricketInput input) {
    pendingEvents.clear();
    if (isComplete) return;
    tick++;
    _phaseTicks++;

    final previousTip = batTip;
    if (_swingEdge.rising(input.swing)) _startSwing();
    if (_contactTick != null && tick == _contactTick) _contact(input.direction);
    batPrevious = batDirection;
    batDirection = _batPose();

    switch (phase) {
      case WallCricketPhase.ready:
        if (_phaseTicks >= _readyTicks) {
          _enter(WallCricketPhase.windup);
          ballVisible = false;
        }
      case WallCricketPhase.windup:
        if (_phaseTicks >= _windupTicks) _release();
      case WallCricketPhase.live:
        _advanceBall();
      case WallCricketPhase.result:
        _advanceBall();
        if (_phaseTicks >= _resultTicks) _nextBall();
      case WallCricketPhase.complete:
        break;
    }

    batTipSpeed = (batTip - previousTip).length * WallCricketRules.tickHz;

    if (tick >= _maxTicks && !isComplete) _complete();
  }

  /// The bat follows the swing's clock once a swing starts, and eases back up
  /// to the backlift between balls.
  Vec2 _batPose() {
    final start = _swingStartTick;
    if (start != null) {
      swing = clampD((tick - start) / swingTicks, 0, 1);
    } else if (swing > 0) {
      swing = swing > _returnRate * 3 ? swing - _returnRate * 3 : 0;
    }
    return _constrain(arcDirection(swing));
  }

  void _startSwing() {
    if (phase != WallCricketPhase.live || !ballVisible || _resolved || _ballHit) return;
    if (_swingStartTick != null) return;
    _swingStartTick = tick;
    _contactTick = tick + contactDelayTicks;

    final arrival = _ticksUntilBallAt(hitX);
    final error = arrival == null ? -1.0 : (arrival - contactDelayTicks) / WallCricketRules.tickHz;
    lastTimingError = error;
    final w = windows;
    final early = error > 0;
    final off = error.abs();
    _plannedTiming = off <= w.perfect
        ? ShotTiming.perfect
        : off <= w.good
            ? (early ? ShotTiming.goodEarly : ShotTiming.goodLate)
            : off <= w.edge
                ? (early ? ShotTiming.edgeEarly : ShotTiming.edgeLate)
                : (early ? ShotTiming.missEarly : ShotTiming.missLate);
  }

  /// Ticks until the ball, as it is now, reaches [x]. Null if it will not —
  /// already past, or dead.
  int? _ticksUntilBallAt(double x) {
    var p = ballPosition;
    var v = ballVelocity;
    var bounced = _bounced;
    if (p.x <= x) return null;
    const dt = 1 / (WallCricketRules.tickHz * _substeps);
    for (var t = 1; t <= WallCricketRules.tickHz * 3; t++) {
      for (var sub = 0; sub < _substeps; sub++) {
        v = Vec2(v.x, v.y + Arena.gravity * dt);
        p = p + v * dt;
        if (p.y > Arena.groundY - Arena.ballRadius && v.y > 0) {
          p = Vec2(p.x, Arena.groundY - Arena.ballRadius);
          v = Vec2(v.x * Arena.groundFriction,
              -v.y * (bounced ? Arena.groundRestitution : pitchBounce));
          bounced = true;
        }
      }
      if (p.x <= x) return t;
    }
    return null;
  }

  /// The bat reaches the ball, or where the ball should have been.
  void _contact(Vec2 swipe) {
    final timing = _plannedTiming;
    _contactTick = null;
    if (timing == null || _resolved || _ballHit) return;
    lastTiming = timing;
    pendingEvents.add(WallCricketEvent(WallCricketEventType.timing,
        at: ballPosition, value: timing.index.toDouble()));

    switch (timing) {
      case ShotTiming.missEarly || ShotTiming.missLate:
        return;
      case ShotTiming.edgeEarly:
        // Off the toe: it dies in front of the batter.
        _markHit(edge: true);
        ballVelocity = const Vec2(320, -380);
      case ShotTiming.edgeLate:
        _markHit(edge: true);
        if (_shotRng.chance(edgeCatchChance)) {
          _resolve(const BallOutcome.out(caught: true));
          return;
        }
        // Thick inside edge, fine behind: usually a single off the back wall.
        ballVelocity = const Vec2(-620, -1100);
      case ShotTiming.perfect || ShotTiming.goodEarly || ShotTiming.goodLate:
        final perfect = timing == ShotTiming.perfect;
        _markHit(edge: false);
        final direction = _shotDirection(swipe, spread: perfect ? 0.03 : 0.22);
        ballVelocity = direction * (perfect ? 3700 : 2000);
        pendingEvents.add(WallCricketEvent(WallCricketEventType.hit,
            at: ballPosition, value: perfect ? 1 : 0.55));
    }
    if (ballPosition.y > Arena.groundY - Arena.ballRadius - 1) {
      ballPosition = Vec2(ballPosition.x, Arena.groundY - Arena.ballRadius - 1);
    }
  }

  void _markHit({required bool edge}) {
    _ballHit = true;
    hits++;
    if (edge) {
      edges++;
      pendingEvents.add(WallCricketEvent(WallCricketEventType.edge, at: ballPosition));
    }
  }

  /// Which shot a swipe asks for. Every direction is a shot.
  Vec2 _shotDirection(Vec2 swipe, {required double spread}) {
    var d = swipe.lengthSquared < 0.01 ? const Vec2(1, -0.5) : swipe.normalized;
    final up = d.y < 0 ? -d.y : 0.0;
    final down = d.y > 0 ? d.y : 0.0;
    Vec2 launch;
    if (down > up && down > d.x.abs() * 0.8) {
      // Down: kept on the ground, a firm drive into the wall.
      launch = const Vec2(1, -0.14);
    } else if (d.x < -0.3) {
      // Back: the pull, up and over towards the far corner of the roof.
      launch = const Vec2(0.4, -1);
    } else {
      // Forward to up: the steeper the swipe, the higher it goes.
      launch = Vec2(1, -(0.2 + 1.25 * up));
    }
    d = launch.normalized;
    final jitter = _shotRng.nextRange(-spread, spread);
    return Vec2(d.x, d.y + jitter).normalized;
  }

  /// Keeps the blade out of the ground: at the bottom of the arc it scrapes
  /// along the turf rather than through it.
  static Vec2 _constrain(Vec2 direction) {
    var d = direction;
    final maxDown = (Arena.groundY - 10 - Arena.pivot.y) / Arena.batLength;
    if (d.y > maxDown) {
      final x = _sqrt(1 - maxDown * maxDown);
      d = Vec2(d.x >= 0 ? x : -x, maxDown);
    }
    return d;
  }

  /// `sqrt` is the one root the determinism contract allows — IEEE-754
  /// requires it to be correctly rounded on every platform.
  static double _sqrt(double v) => math.sqrt(v < 0 ? 0 : v);

  // --- deliveries ----------------------------------------------------------

  void _release() {
    final delivery = _pickDelivery();
    ballPosition = Arena.machineMouth;
    ballPrevious = Arena.machineMouth;
    ballVelocity = delivery;
    ballVisible = true;
    _ballHit = false;
    _resolved = false;
    _ticksSinceHit = 0;
    _ticksLive = 0;
    _bounced = false;
    _swingStartTick = null;
    _contactTick = null;
    _plannedTiming = null;
    _enter(WallCricketPhase.live);
    pendingEvents.add(
      const WallCricketEvent(
        WallCricketEventType.release,
        at: Arena.machineMouth,
      ),
    );
  }

  /// Picks a delivery, then checks where it would go if nobody played it.
  ///
  /// Checking by simulation rather than solving for it is deliberate: the
  /// bounce and the friction make the closed form ugly, and a candidate that
  /// is run through the same integrator the live ball uses cannot disagree
  /// with it.
  Vec2 _pickDelivery() {
    final overBoost = 1 + over * 0.035;
    final wantStumps = _deliveryRng.chance(pace.stumpsShare);
    // Not every ball should be there to hit. A slower ball arrives after the
    // swing has gone through; a lively pitch lifts one over the blade; a dead
    // one keeps low under it.
    final slower = over > 0 && _deliveryRng.chance(0.18);
    var candidate = Vec2.zero;
    for (var attempt = 0; attempt < 16; attempt++) {
      pitchBounce = _deliveryRng.nextRange(0.42, 0.78);
      var speed =
          _deliveryRng.nextRange(pace.minSpeed, pace.maxSpeed) * overBoost;
      if (slower) speed *= 0.72;
      final bounceX = _deliveryRng.nextRange(360, 700);
      final flight = (Arena.machineMouth.x - bounceX) / speed;
      final drop = Arena.groundY - Arena.ballRadius - Arena.machineMouth.y;
      final vy = (drop - 0.5 * Arena.gravity * flight * flight) / flight;
      candidate = Vec2(-speed, vy);
      if (_wouldHitStumps(candidate, pitchBounce) == wantStumps) {
        return candidate;
      }
    }
    return candidate;
  }

  static bool _wouldHitStumps(Vec2 velocity, double firstBounce) {
    var p = Arena.machineMouth;
    var v = velocity;
    var bounce = firstBounce;
    const dt = 1 / (WallCricketRules.tickHz * _substeps);
    for (var i = 0; i < WallCricketRules.tickHz * _substeps * 2; i++) {
      v = Vec2(v.x, v.y + Arena.gravity * dt);
      p = p + v * dt;
      if (p.y > Arena.groundY - Arena.ballRadius && v.y > 0) {
        p = Vec2(p.x, Arena.groundY - Arena.ballRadius);
        v = Vec2(v.x * Arena.groundFriction, -v.y * bounce);
        bounce = Arena.groundRestitution;
      }
      if (_touchesStumps(p)) return true;
      if (p.x < Arena.stumpsLeft - Arena.ballRadius) return false;
    }
    return false;
  }

  static bool _touchesStumps(Vec2 p) =>
      p.x + Arena.ballRadius > Arena.stumpsLeft &&
      p.x - Arena.ballRadius < Arena.stumpsRight &&
      p.y + Arena.ballRadius > Arena.stumpsTop &&
      p.y < Arena.groundY;

  // --- the ball in play ----------------------------------------------------

  void _advanceBall() {
    if (!ballVisible) return;
    ballPrevious = ballPosition;
    _ticksLive++;
    if (_ballHit) _ticksSinceHit++;

    const dt = 1 / (WallCricketRules.tickHz * _substeps);
    for (var s = 1; s <= _substeps; s++) {
      ballVelocity = Vec2(ballVelocity.x, ballVelocity.y + Arena.gravity * dt);
      ballPosition = ballPosition + ballVelocity * dt;

      _collideRoom();
      if (phase == WallCricketPhase.live) _checkStumps();
    }

    if (phase != WallCricketPhase.live) return;

    final speed = ballVelocity.length;
    final resting = speed < 60 &&
        ballPosition.y >= Arena.groundY - Arena.ballRadius - 2;
    if (_ballHit && (_ticksSinceHit > 300 || resting)) {
      _resolve(const BallOutcome.dot());
    } else if (!_ballHit &&
        (ballPosition.x < Arena.stumpsLeft - Arena.ballRadius * 2 ||
            resting ||
            _ticksLive > _deadBallTicks)) {
      _resolve(const BallOutcome.dot());
    }
  }

  void _collideRoom() {
    final r = Arena.ballRadius;
    var p = ballPosition;
    var v = ballVelocity;

    if (p.y > Arena.groundY - r && v.y > 0) {
      p = Vec2(p.x, Arena.groundY - r);
      final impact = v.y;
      final bounce =
          !_bounced && !_ballHit ? pitchBounce : Arena.groundRestitution;
      _bounced = true;
      v = Vec2(v.x * Arena.groundFriction, -v.y * bounce);
      if (v.y.abs() < 40) v = Vec2(v.x, 0);
      if (impact > 250) {
        pendingEvents.add(
          WallCricketEvent(
            WallCricketEventType.bounce,
            at: p,
            value: impact / 2500,
          ),
        );
      }
    }

    Wall? wall;
    var along = 0.0;
    if (p.y < r && v.y < 0) {
      p = Vec2(p.x, r);
      v = Vec2(v.x, -v.y * Arena.wallRestitution);
      wall = Wall.ceiling;
      along = p.x;
    }
    if (p.x > Arena.width - r && v.x > 0) {
      p = Vec2(Arena.width - r, p.y);
      v = Vec2(-v.x * Arena.wallRestitution, v.y);
      wall = Wall.right;
      along = p.y;
    }
    if (p.x < r && v.x < 0) {
      p = Vec2(r, p.y);
      v = Vec2(-v.x * Arena.wallRestitution, v.y);
      wall = Wall.left;
      along = p.y;
    }
    // The machine's face, which sticks out of the right wall.
    if (p.x > Arena.machineLeft - r &&
        p.y > Arena.machineTop &&
        p.y < Arena.machineBottom &&
        v.x > 0 &&
        ballPrevious.x <= Arena.machineLeft - r + 1) {
      p = Vec2(Arena.machineLeft - r, p.y);
      v = Vec2(-v.x * Arena.wallRestitution, v.y);
      wall = Wall.machine;
      along = p.y;
    }

    ballPosition = p;
    ballVelocity = v;

    if (wall != null) {
      pendingEvents.add(
        WallCricketEvent(
          WallCricketEventType.wall,
          at: p,
          value: v.length / Arena.maxBallSpeed,
        ),
      );
      if (phase == WallCricketPhase.live && _ballHit && !_resolved) {
        final zone = Arena.zoneIndexAt(wall, along);
        if (zone != null) {
          final hot = zone == hotZone;
          final value = Arena.zones[zone].runs * (hot ? 2 : 1);
          _resolve(BallOutcome.runs(value, zone: zone, hot: hot));
        }
      }
    }
  }

  void _checkStumps() {
    if (_resolved || _ballHit || !_touchesStumps(ballPosition)) return;
    ballVelocity = Vec2(-ballVelocity.x.abs() * 0.3 - 200, -400);
    _resolve(const BallOutcome.out());
  }

  void _resolve(BallOutcome outcome) {
    _resolved = true;
    // A swing whose contact moment never came (the ball was bowled first).
    if (_contactTick != null && _plannedTiming != null) {
      lastTiming = _plannedTiming;
      pendingEvents.add(WallCricketEvent(WallCricketEventType.timing,
          at: ballPosition, value: _plannedTiming!.index.toDouble()));
      _contactTick = null;
    }
    lastOutcome = outcome;
    ballsBowled++;
    switch (outcome.kind) {
      case BallOutcomeKind.runs:
        runs += outcome.runs;
        final base = Arena.zones[outcome.zone!].runs;
        if (base == 4) fours++;
        if (base == 6) sixes++;
        pendingEvents.add(
          WallCricketEvent(
            WallCricketEventType.scored,
            at: ballPosition,
            value: outcome.runs.toDouble(),
          ),
        );
      case BallOutcomeKind.dot:
        pendingEvents.add(
          WallCricketEvent(WallCricketEventType.dot, at: ballPosition),
        );
      case BallOutcomeKind.out:
        wickets++;
        pendingEvents.add(
          WallCricketEvent(WallCricketEventType.out, at: ballPosition),
        );
    }
    _enter(WallCricketPhase.result);
  }

  void _nextBall() {
    if (wickets >= rules.wickets || ballsBowled >= rules.balls) {
      _complete();
      return;
    }
    if (ballsBowled % 6 == 0) {
      hotZone = _pickHotZone();
      pendingEvents.add(
        const WallCricketEvent(WallCricketEventType.overComplete),
      );
    }
    ballVisible = false;
    _swingStartTick = null;
    _contactTick = null;
    _enter(WallCricketPhase.ready);
  }

  int _pickHotZone() {
    // Any zone but the edge behind the stumps, which is not a shot anyone
    // should be encouraged to aim for.
    return 1 + _hotRng.nextInt(Arena.zones.length - 1);
  }

  void _complete() {
    _enter(WallCricketPhase.complete);
    pendingEvents.add(const WallCricketEvent(WallCricketEventType.complete));
  }

  void _enter(WallCricketPhase next) {
    phase = next;
    _phaseTicks = 0;
  }

  GameResult buildResult({String? sessionToken, List<int>? replay}) {
    final won = runs >= target;
    return GameResult(
      gameSlug: 'cricket',
      mode: GameMode.vsBot,
      botDifficulty: switch (pace) {
        Pace.easy => BotDifficulty.easy,
        Pace.medium => BotDifficulty.medium,
        Pace.hard => BotDifficulty.hard,
      },
      durationMs: tick * 1000 ~/ WallCricketRules.tickHz,
      p1Score: runs,
      p2Score: target,
      outcome: won ? MatchOutcome.p1Win : MatchOutcome.p2Win,
      normalizedSkill: normalizedSkill,
      seed: seed,
      tickCount: tick,
      replay: replay,
      sessionToken: sessionToken,
    );
  }
}
