import 'dart:math' as math;

import 'package:game_core/game_core.dart';

import 'arena.dart';

/// How fast the machine bowls, and how many runs make a win.
enum Pace {
  easy(minSpeed: 900, maxSpeed: 1100, runsPerBall: 1.2, stumpsShare: 0.55),
  medium(minSpeed: 1150, maxSpeed: 1400, runsPerBall: 1.5, stumpsShare: 0.65),
  hard(minSpeed: 1450, maxSpeed: 1750, runsPerBall: 2.0, stumpsShare: 0.75);

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

/// One human input sample.
class WallCricketInput {
  const WallCricketInput({this.swing = 0, this.touching = false});

  /// How far through the swing the player has dragged, 0..1: 0 is the
  /// backlift, about 0.6 is the bat meeting a ball in front of the pads, 1 is
  /// the follow-through.
  final double swing;
  final bool touching;

  static const WallCricketInput idle = WallCricketInput();

  static WallCricketInput fromChannels(List<double> c) => WallCricketInput(
        swing: c[0],
        touching: c[1] >= 0.5,
      );
}

/// Top Spinner cricket, as pure state.
///
/// **You swing the bat.** The blade travels a real cricket arc — backlift over
/// the shoulder, down past the back leg, through the line in front of the
/// pads, up into the follow-through — and the drag on the screen says how far
/// along that arc it is. Drag fast and the blade arrives fast; stop halfway
/// and it is a block. The ball comes off with real contact physics: the
/// blade's own velocity at the point of contact is added to the bounce.
///
/// The first version pointed the bat at the finger, which let it sweep
/// sideways at hip height. Play-testing called it baseball, and it was.
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

  static const int channelCount = 2;

  static const int _readyTicks = 60;
  static const int _windupTicks = 54;
  static const int _resultTicks = 90;
  static const int _deadBallTicks = 360;
  static const int _substeps = 6;

  /// Fastest the blade travels along the swing, and back to the backlift when
  /// let go, as arc fraction per tick. The whole arc is about 5.4 radians, so
  /// 0.036 a tick is ~23 rad/s — a full swing in about a quarter second,
  /// which is what makes a late swing late. At 0.058 the blade got there from
  /// the backlift after the ball had passed the hitting point, and still hit.
  static const double _swingRate = 0.036;
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
    batPrevious = batDirection;
    batDirection = _turnBat(input);

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

  Vec2 _turnBat(WallCricketInput input) {
    final ballInPlay = phase == WallCricketPhase.live;
    double target;
    double rate;
    if (input.touching) {
      target = clampD(input.swing, 0, 1);
      rate = _swingRate;
    } else if (ballInPlay) {
      // Let go mid-ball: the blade stays where the swing left it. Drifting
      // back down the arc would sweep through the line again and block a
      // ball the swing had already missed — which made every ball a hit.
      target = swing;
      rate = 0;
    } else {
      // Between balls, back up to the backlift, ready for the next one.
      target = 0;
      rate = _returnRate;
    }
    if (target > swing) {
      swing = target - swing > rate ? swing + rate : target;
    } else if (target < swing) {
      swing = swing - target > rate ? swing - rate : target;
    }
    return _constrain(arcDirection(swing));
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
      final t = s / _substeps;
      final batNow = (batPrevious + (batDirection - batPrevious) * t).normalized;
      final batBefore =
          (batPrevious + (batDirection - batPrevious) * ((s - 1) / _substeps))
              .normalized;

      ballVelocity = Vec2(ballVelocity.x, ballVelocity.y + Arena.gravity * dt);
      ballPosition = ballPosition + ballVelocity * dt;

      if (phase == WallCricketPhase.live) _collideBat(batNow, batBefore, dt);
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

  void _collideBat(Vec2 batNow, Vec2 batBefore, double dt) {
    // Only a blade in front of the batter plays the ball. The backlift and
    // the backswing pass over the stumps, and letting them collide turned a
    // late swing into a guard that nothing could get past.
    if (batNow.x < 0.05) return;
    // Past the front pad is too late to play. Without this a swing started
    // after the ball had gone through the hitting zone still caught it on the
    // way to the stumps, and lateness cost nothing.
    if (ballPosition.x < Arena.pivot.x + Arena.lateLine) return;
    final axis = batNow * Arena.batLength;
    final rel = ballPosition - Arena.pivot;
    var along = rel.dot(batNow);
    final bladeStart = Arena.batLength * Arena.bladeFrom;
    if (along < bladeStart) along = bladeStart;
    if (along > Arena.batLength) along = Arena.batLength;
    final closest = Arena.pivot + batNow * along;
    final offset = ballPosition - closest;
    final reach = Arena.ballRadius + Arena.batRadius;
    final distanceSq = offset.lengthSquared;
    if (distanceSq >= reach * reach) return;

    final distance = offset.length;
    final normal = distance > 1e-6
        ? offset / distance
        : Vec2(-axis.y, axis.x).normalized;

    final batVelocity = (batNow - batBefore) * (along / dt);
    final relative = ballVelocity - batVelocity;
    final approach = relative.dot(normal);

    ballPosition = closest + normal * (reach + 0.5);
    if (approach >= 0) return;

    final fraction = along / Arena.batLength;
    final sweet = fraction >= Arena.sweetFrom && fraction <= Arena.sweetTo;
    // Where on the blade the ball lands is what timing buys. Swing early and
    // the ball is met out at the toe; late, and it is cramped against the
    // handle. Either is an edge: most of the ball's own pace carries on past
    // the bat, and if it carries on *backwards* the keeper takes it.
    final edge = fraction < Arena.edgeInside || fraction > Arena.edgeToe;
    Vec2 velocity;
    if (edge) {
      velocity = ballVelocity * 0.6 - normal * (0.5 * approach);
    } else {
      final restitution = sweet ? 0.82 : 0.42;
      velocity = ballVelocity - normal * ((1 + restitution) * approach);
    }
    if (velocity.length > Arena.maxBallSpeed) {
      velocity = velocity.withLength(Arena.maxBallSpeed);
    }
    ballVelocity = velocity;

    if (!_ballHit) {
      _ballHit = true;
      hits++;
      if (edge) {
        edges++;
        pendingEvents.add(
          WallCricketEvent(WallCricketEventType.edge, at: closest),
        );
        if (velocity.x < 0 && !_resolved) {
          _resolve(const BallOutcome.out(caught: true));
          return;
        }
      }
      final intensity = velocity.length / Arena.maxBallSpeed;
      pendingEvents.add(
        WallCricketEvent(
          WallCricketEventType.hit,
          at: closest,
          value: sweet ? (intensity < 1 ? intensity : 1) : intensity * 0.5,
        ),
      );
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
