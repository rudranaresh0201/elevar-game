import 'dart:math' as math;

import 'package:game_core/game_core.dart';

import 'arena.dart';

/// How fast the machine bowls, and how many runs make a win.
enum Pace {
  easy(minSpeed: 900, maxSpeed: 1100, runsPerBall: 1.2, stumpsShare: 0.55),
  medium(minSpeed: 1150, maxSpeed: 1400, runsPerBall: 1.8, stumpsShare: 0.65),
  hard(minSpeed: 1450, maxSpeed: 1750, runsPerBall: 2.5, stumpsShare: 0.75);

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
  /// bounce over â€” which is what makes leaving a ball a decision.
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
      : kind = BallOutcomeKind.runs;

  const BallOutcome.dot()
      : kind = BallOutcomeKind.dot,
        runs = 0,
        zone = null,
        hot = false;

  const BallOutcome.out()
      : kind = BallOutcomeKind.out,
        runs = 0,
        zone = null,
        hot = false;

  final BallOutcomeKind kind;
  final int runs;
  final int? zone;
  final bool hot;
}

enum WallCricketEventType {
  release,
  hit,
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
  const WallCricketInput({this.finger, this.touching = false});

  /// Where the finger is, in normalised arena coordinates.
  final Vec2? finger;
  final bool touching;

  static const WallCricketInput idle = WallCricketInput();

  static WallCricketInput fromChannels(List<double> c) => WallCricketInput(
        finger: Vec2(c[0], c[1]),
        touching: c[2] >= 0.5,
      );
}

/// Top Spinner cricket, as pure state.
///
/// **You hold the bat.** Its direction follows your finger from the batter's
/// hands, rate-limited so it swings rather than teleports, and the ball comes
/// off it with real contact physics: the blade's own velocity at the point of
/// contact is added to the bounce. Swing hard through the ball and it flies;
/// hold the blade still and it drops dead; get under it and it goes up. None of
/// that is a rule someone wrote â€” it falls out of the collision.
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

  static const int channelCount = 3;

  static const int _readyTicks = 60;
  static const int _windupTicks = 54;
  static const int _resultTicks = 90;
  static const int _deadBallTicks = 360;
  static const int _substeps = 6;

  /// Fastest the blade turns while held, and when let go, in radians a second.
  /// Chord lengths per tick below are these divided by the tick rate â€” close
  /// enough to the arc for angles this small, and free of trigonometry.
  static const double _heldTurnRate = 38;
  static const double _restTurnRate = 9;

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
  Vec2 batDirection = Arena.restDirection;
  Vec2 batPrevious = Arena.restDirection;

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
    var target = Arena.restDirection;
    var rate = _restTurnRate;
    if (input.touching && input.finger != null) {
      final finger = Vec2(
        input.finger!.x * Arena.width,
        input.finger!.y * Arena.height,
      );
      final toward = finger - Arena.pivot;
      if (toward.lengthSquared > 40 * 40) {
        target = _constrain(toward.normalized);
        rate = _heldTurnRate;
      } else {
        target = batDirection;
      }
    }

    final maxChord = rate / WallCricketRules.tickHz;
    final delta = target - batDirection;
    final distance = delta.length;
    if (distance <= maxChord) return target;

    Vec2 moved;
    if (distance > 1.9) {
      // Nearly opposite: straight-line interpolation would pass through the
      // pivot. Turn the way the target is leaning instead.
      final left = Vec2(-batDirection.y, batDirection.x);
      final sign = left.dot(target) >= 0 ? 1.0 : -1.0;
      moved = batDirection + left * (maxChord * sign);
    } else {
      moved = batDirection + delta * (maxChord / distance);
    }
    return _constrain(moved.normalized);
  }

  /// Keeps the blade out of the ground and out of the batter's own stumps.
  static Vec2 _constrain(Vec2 direction) {
    var d = direction;
    final maxDown = (Arena.groundY - 10 - Arena.pivot.y) / Arena.batLength;
    if (d.y > maxDown) {
      final x = _sqrt(1 - maxDown * maxDown);
      d = Vec2(d.x >= 0 ? x : -x, maxDown);
    }
    const minX = -0.55;
    if (d.x < minX) {
      final y = _sqrt(1 - minX * minX);
      d = Vec2(minX, d.y >= 0 ? y : -y);
    }
    return d;
  }

  /// `sqrt` is the one root the determinism contract allows â€” IEEE-754
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
    Vec2 candidate = Vec2.zero;
    for (var attempt = 0; attempt < 16; attempt++) {
      final speed =
          _deliveryRng.nextRange(pace.minSpeed, pace.maxSpeed) * overBoost;
      final bounceX = _deliveryRng.nextRange(400, 660);
      final flight = (Arena.machineMouth.x - bounceX) / speed;
      final drop = Arena.groundY - Arena.ballRadius - Arena.machineMouth.y;
      final vy = (drop - 0.5 * Arena.gravity * flight * flight) / flight;
      candidate = Vec2(-speed, vy);
      if (_wouldHitStumps(candidate) == wantStumps) return candidate;
    }
    return candidate;
  }

  static bool _wouldHitStumps(Vec2 velocity) {
    var p = Arena.machineMouth;
    var v = velocity;
    const dt = 1 / (WallCricketRules.tickHz * _substeps);
    for (var i = 0; i < WallCricketRules.tickHz * _substeps * 2; i++) {
      v = Vec2(v.x, v.y + Arena.gravity * dt);
      p = p + v * dt;
      if (p.y > Arena.groundY - Arena.ballRadius && v.y > 0) {
        p = Vec2(p.x, Arena.groundY - Arena.ballRadius);
        v = Vec2(v.x * Arena.groundFriction, -v.y * Arena.groundRestitution);
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
    final restitution = sweet ? 0.82 : 0.42;
    var velocity = ballVelocity - normal * ((1 + restitution) * approach);
    if (velocity.length > Arena.maxBallSpeed) {
      velocity = velocity.withLength(Arena.maxBallSpeed);
    }
    ballVelocity = velocity;

    if (!_ballHit) {
      _ballHit = true;
      hits++;
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
      v = Vec2(v.x * Arena.groundFriction, -v.y * Arena.groundRestitution);
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
