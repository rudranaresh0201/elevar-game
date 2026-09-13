import 'dart:math' as math;

import 'package:game_core/game_core.dart';

import 'goal.dart';

enum PenaltySide { p1, p2 }

enum PenaltyPhase { aim, runUp, flight, outcome, complete }

enum KickResult { goal, saved, post, missed }

/// A struck ball, before physics: where it is aimed, how hard, how much bend.
class ShotParams {
  const ShotParams({
    required this.target,
    required this.power,
    required this.curve,
  });

  final GoalPoint target;

  /// 0..1. Harder is faster to the line, and past 0.85 it starts to rise.
  final double power;

  /// -1..1. Negative bends left, positive right. The ball still arrives at
  /// the target — curve changes the path and how late the keeper can read it,
  /// not where it ends up.
  final double curve;

  static const ShotParams tame =
      ShotParams(target: GoalPoint(0, 0.6), power: 0.15, curve: 0);
}

/// How the bot keeps goal.
class KeeperProfile {
  const KeeperProfile({
    required this.reactionTicks,
    required this.diveSpeed,
    required this.readChance,
    required this.readNoise,
  });

  final int reactionTicks;
  final double diveSpeed;

  /// Chance the keeper reads the shot rather than guessing a side.
  final double readChance;
  final double readNoise;

  static KeeperProfile of(BotDifficulty d) => switch (d) {
        BotDifficulty.easy => const KeeperProfile(
            reactionTicks: 40, diveSpeed: 5.2, readChance: 0.3, readNoise: 1.1),
        BotDifficulty.medium => const KeeperProfile(
            reactionTicks: 29, diveSpeed: 6.2, readChance: 0.45, readNoise: 0.8),
        BotDifficulty.hard => const KeeperProfile(
            reactionTicks: 24, diveSpeed: 6.8, readChance: 0.52, readNoise: 0.6),
      };
}

/// How the bot takes a penalty.
class ShooterProfile {
  const ShooterProfile({
    required this.aimError,
    required this.punishEarlyDive,
    required this.maxPower,
  });

  final double aimError;

  /// Chance it goes the other way when the keeper has already committed.
  final double punishEarlyDive;
  final double maxPower;

  static ShooterProfile of(BotDifficulty d) => switch (d) {
        BotDifficulty.easy => const ShooterProfile(
            aimError: 0.8, punishEarlyDive: 0.25, maxPower: 0.4),
        BotDifficulty.medium => const ShooterProfile(
            aimError: 0.5, punishEarlyDive: 0.55, maxPower: 0.55),
        BotDifficulty.hard => const ShooterProfile(
            aimError: 0.32, punishEarlyDive: 0.85, maxPower: 0.7),
      };
}

enum PenaltyEventType { kick, keeperDive, save, goal, post, missed, bounce, complete }

class PenaltyEvent {
  const PenaltyEvent(this.type, {this.at = Vec3.zero, this.value = 0});

  final PenaltyEventType type;
  final Vec3 at;
  final double value;
}

/// One tick of human input, role-based: whoever is shooting drives the shot
/// channels and whoever is keeping drives the dive channels.
class PenaltyInput {
  const PenaltyInput({
    this.aim = const GoalPoint(0, 1),
    this.power = 0,
    this.curve = 0,
    this.fire = 0,
    this.dive = const GoalPoint(0, 1),
    this.diveTrigger = 0,
  });

  final GoalPoint aim;
  final double power;
  final double curve;
  final double fire;
  final GoalPoint dive;
  final double diveTrigger;

  static const int channelCount = 8;

  static PenaltyInput fromChannels(List<double> c) => PenaltyInput(
        aim: GoalPoint.fromNormalised(c[0], c[1]),
        power: c[2],
        curve: c[3] * 2 - 1,
        fire: c[4],
        dive: GoalPoint.fromNormalised(c[5], c[6]),
        diveTrigger: c[7],
      );
}

/// A penalty shootout, as pure state.
///
/// Five kicks each, alternating, then sudden death. The human always takes
/// kick one. Against the bot you shoot *and* keep: swipe to shoot, tap where
/// to dive. With two people on one phone, the shooter swipes at the bottom
/// while the keeper taps the goal at the top — at the same time, which is the
/// entire game: a keeper who goes early can be sent the wrong way.
class PenaltySimulation {
  PenaltySimulation({
    required this.seed,
    required this.mode,
    this.botDifficulty,
  })  : assert(mode != GameMode.vsBot || botDifficulty != null),
        _keeperRng = DeterministicRng.stream(seed, 1),
        _shooterRng = DeterministicRng.stream(seed, 2) {
    _startKick();
  }

  final int seed;
  final GameMode mode;
  final BotDifficulty? botDifficulty;

  final DeterministicRng _keeperRng;
  final DeterministicRng _shooterRng;
  final EdgeTrigger _fireEdge = EdgeTrigger();
  final EdgeTrigger _diveEdge = EdgeTrigger();

  static const int tickHz = 120;
  static const int _substeps = 4;
  static const int _aimTimeoutTicks = tickHz * 10;
  static const int _humanRunUpTicks = 16;
  static const int _botRunUpTicks = 110;
  static const int _outcomeTicks = 180;
  static const int _maxFlightTicks = tickHz * 3;
  static const int _regulationKicks = 5;
  static const int _maxKicks = 10;

  /// A person in goal gets a quicker, longer dive than the bot does. They are
  /// reacting to a ball on a phone screen through a camera, not reading a
  /// shot in the flesh, and the first build asked them to do it at the bot's
  /// speed: a tap on exactly the right spot still watched the ball go in.
  static const double _humanDiveSpeed = 8.5;
  static const double _humanHalfLength = 0.9;
  static const double _humanRadius = 0.3;
  static const double _botHalfLength = 0.85;
  static const double _botRadius = 0.24;

  double get _keeperHalfLength => keeperIsHuman ? _humanHalfLength : _botHalfLength;
  double get _keeperRadius => keeperIsHuman ? _humanRadius : _botRadius;
  static const GoalPoint keeperHome = GoalPoint(0, 1.05);

  int tick = 0;
  PenaltyPhase phase = PenaltyPhase.aim;
  int _phaseTicks = 0;

  final List<KickResult> p1Kicks = <KickResult>[];
  final List<KickResult> p2Kicks = <KickResult>[];

  PenaltySide shooter = PenaltySide.p1;
  KickResult? lastResult;

  // --- ball ----------------------------------------------------------------
  Vec3 ball = const Vec3(0, Goal.ballRadius, Goal.spotZ);
  Vec3 ballPrevious = const Vec3(0, Goal.ballRadius, Goal.spotZ);
  Vec3 ballVelocity = Vec3.zero;
  double _curveAccel = 0;
  bool _resolved = false;
  ShotParams? _pendingShot;
  ShotParams? lastShot;

  // --- keeper --------------------------------------------------------------
  GoalPoint keeper = keeperHome;
  GoalPoint keeperPrevious = keeperHome;
  GoalPoint? keeperTarget;
  int _diveStartTick = 0;
  bool keeperCommitted = false;

  /// True once the keeper committed before the ball was struck.
  bool keeperWentEarly = false;

  final List<PenaltyEvent> pendingEvents = <PenaltyEvent>[];

  bool get isComplete => phase == PenaltyPhase.complete;
  bool get isTwoHuman => mode == GameMode.local2P;

  int get p1Goals => p1Kicks.where((k) => k == KickResult.goal).length;
  int get p2Goals => p2Kicks.where((k) => k == KickResult.goal).length;

  bool get shooterIsHuman => isTwoHuman || shooter == PenaltySide.p1;
  bool get keeperIsHuman => isTwoHuman || shooter == PenaltySide.p2;

  /// True while the human shooter may swipe.
  bool get acceptsShot =>
      phase == PenaltyPhase.aim && shooterIsHuman && _pendingShot == null;

  /// True while the human keeper may still commit.
  bool get acceptsDive =>
      keeperIsHuman &&
      !keeperCommitted &&
      (phase == PenaltyPhase.runUp ||
          phase == PenaltyPhase.flight ||
          (phase == PenaltyPhase.aim && isTwoHuman));

  int get aimTicksLeft =>
      phase == PenaltyPhase.aim ? _aimTimeoutTicks - _phaseTicks : 0;

  /// 0..1 through the run-up, for the kicker animation.
  double get runUpProgress => phase == PenaltyPhase.runUp
      ? _phaseTicks / (shooterIsHuman ? _humanRunUpTicks : _botRunUpTicks)
      : (phase == PenaltyPhase.aim ? 0 : 1);

  /// How far through the dive the keeper is, 0..1, for the pose.
  double get diveProgress {
    final target = keeperTarget;
    if (target == null) return 0;
    final total = _distance(keeperHome, target);
    if (total < 0.05) return 0;
    return clampD(_distance(keeperHome, keeper) / total, 0, 1);
  }

  void step(PenaltyInput input) {
    pendingEvents.clear();
    if (isComplete) return;
    tick++;
    _phaseTicks++;
    keeperPrevious = keeper;
    ballPrevious = ball;

    final fired = _fireEdge.rising(input.fire);
    final dived = _diveEdge.rising(input.diveTrigger);

    if (dived && acceptsDive) {
      _commitKeeper(_clampDive(input.dive), startTick: tick + 1);
    }

    switch (phase) {
      case PenaltyPhase.aim:
        if (shooterIsHuman) {
          if (fired) {
            _pendingShot = ShotParams(
              target: input.aim,
              power: clampD(input.power, 0, 1),
              curve: clampD(input.curve, -1, 1),
            );
            _enter(PenaltyPhase.runUp);
          } else if (_phaseTicks >= _aimTimeoutTicks) {
            _pendingShot = ShotParams.tame;
            _enter(PenaltyPhase.runUp);
          }
        } else {
          _enter(PenaltyPhase.runUp);
        }
      case PenaltyPhase.runUp:
        final length = shooterIsHuman ? _humanRunUpTicks : _botRunUpTicks;
        if (_phaseTicks >= length) {
          _kick(_pendingShot ?? _botShot());
        }
      case PenaltyPhase.flight:
        _moveKeeper();
        _advanceBall();
        if (_phaseTicks > _maxFlightTicks && !_resolved) {
          _resolve(KickResult.missed);
        }
      case PenaltyPhase.outcome:
        _moveKeeper();
        _advanceBall();
        if (_phaseTicks >= _outcomeTicks) _afterKick();
      case PenaltyPhase.complete:
        break;
    }
    if (phase == PenaltyPhase.runUp || phase == PenaltyPhase.aim) {
      _moveKeeper();
    }
  }

  // --- the kick ------------------------------------------------------------

  void _startKick() {
    ball = const Vec3(0, Goal.ballRadius, Goal.spotZ);
    ballPrevious = ball;
    ballVelocity = Vec3.zero;
    _curveAccel = 0;
    _resolved = false;
    _pendingShot = null;
    keeper = keeperHome;
    keeperPrevious = keeperHome;
    keeperTarget = null;
    keeperCommitted = false;
    keeperWentEarly = false;
    _enter(PenaltyPhase.aim);
  }

  /// Flight time falls with power; overhit shots rise over the bar.
  static double flightTime(double power) => 0.86 - 0.4 * power;

  void _kick(ShotParams shot) {
    lastShot = shot;
    final time = flightTime(shot.power);
    var targetY = shot.target.y;
    if (shot.power > 0.85) targetY += (shot.power - 0.85) * 6;
    _curveAccel = shot.curve * 9;

    const start = Vec3(0, Goal.ballRadius, Goal.spotZ);
    final vz = -Goal.spotZ / time;
    final vx = (shot.target.x - 0.5 * _curveAccel * time * time) / time;
    final vy = (targetY - start.y + 0.5 * Goal.gravity * time * time) / time;
    ball = start;
    ballVelocity = Vec3(vx, vy, vz);
    keeperWentEarly = keeperCommitted;

    if (!keeperIsHuman) _botKeeperDecide(time);

    _enter(PenaltyPhase.flight);
    pendingEvents.add(PenaltyEvent(PenaltyEventType.kick,
        at: start, value: shot.power));
  }

  ShotParams _botShot() {
    final profile = ShooterProfile.of(botDifficulty!);
    final rng = _shooterRng;
    double side;
    if (keeperCommitted && rng.chance(profile.punishEarlyDive)) {
      final kx = keeperTarget!.x;
      side = kx.abs() < 0.5 ? rng.nextSign() : (kx > 0 ? -1 : 1);
    } else {
      final roll = rng.nextDouble();
      side = roll < 0.42 ? -1 : (roll < 0.84 ? 1 : 0);
    }
    var x = side == 0 ? rng.nextRange(-0.7, 0.7) : side * rng.nextRange(1.5, 3.2);
    var y = rng.nextRange(0.25, 2.1);
    x += rng.nextRange(-1, 1) * profile.aimError * 1.2;
    y += rng.nextRange(-1, 1) * profile.aimError * 0.7;
    return ShotParams(
      target: GoalPoint(x, y < 0.12 ? 0.12 : y),
      power: rng.nextRange(profile.maxPower - 0.35, profile.maxPower),
      curve: rng.nextRange(-0.4, 0.4),
    );
  }

  void _botKeeperDecide(double flight) {
    final profile = KeeperProfile.of(botDifficulty!);
    final rng = _keeperRng;
    final crossing = predictCrossing(Goal.keeperZ);
    GoalPoint target;
    if (rng.chance(profile.readChance)) {
      target = GoalPoint(
        crossing.x + rng.nextRange(-1, 1) * profile.readNoise,
        crossing.y + rng.nextRange(-1, 1) * profile.readNoise * 0.6,
      );
    } else {
      final roll = rng.nextDouble();
      final side = roll < 0.44 ? -1.0 : (roll < 0.88 ? 1.0 : 0.0);
      target = GoalPoint(
        side * 2.4 + rng.nextRange(-0.8, 0.8),
        rng.nextRange(0.4, 1.9),
      );
    }
    _commitKeeper(_clampDive(target), startTick: tick + profile.reactionTicks);
  }

  /// Where the ball, as struck, will pass the plane at [z]. Curve and gravity
  /// included; the ground and the woodwork are not.
  GoalPoint predictCrossing(double z) {
    final t = (ball.z - z) / -ballVelocity.z;
    return GoalPoint(
      ball.x + ballVelocity.x * t + 0.5 * _curveAccel * t * t,
      ball.y + ballVelocity.y * t - 0.5 * Goal.gravity * t * t,
    );
  }

  // --- the keeper ----------------------------------------------------------

  static GoalPoint _clampDive(GoalPoint p) => GoalPoint(
        clampD(p.x, -3.5, 3.5),
        clampD(p.y, 0.35, 2.2),
      );

  void _commitKeeper(GoalPoint target, {required int startTick}) {
    keeperTarget = target;
    keeperCommitted = true;
    _diveStartTick = startTick;
    pendingEvents.add(PenaltyEvent(
      PenaltyEventType.keeperDive,
      at: Vec3(target.x, target.y, Goal.keeperZ),
    ));
  }

  void _moveKeeper() {
    final target = keeperTarget;
    if (target == null || tick < _diveStartTick) return;
    final speed = keeperIsHuman ? _humanDiveSpeed : KeeperProfile.of(botDifficulty!).diveSpeed;
    final step = speed / tickHz;
    final dx = target.x - keeper.x;
    final dy = target.y - keeper.y;
    final distance = _distance(keeper, target);
    if (distance <= step) {
      keeper = target;
    } else {
      keeper = GoalPoint(keeper.x + dx / distance * step, keeper.y + dy / distance * step);
    }
  }

  /// The keeper's body as a capsule in the goal plane: upright at rest, tipping
  /// along the dive as it progresses.
  ({GoalPoint a, GoalPoint b}) keeperBody() {
    final target = keeperTarget;
    var dx = 0.0, dy = 1.0;
    if (target != null) {
      final ox = target.x - keeperHome.x;
      final oy = target.y - keeperHome.y;
      final length = _sqrt(ox * ox + oy * oy);
      if (length > 0.3) {
        final t = diveProgress;
        // Upright, tipping toward the dive as it happens. The b end is the
        // hands end, so the renderer can put the head and gloves there.
        final bx = t * ox / length;
        final by = (1 - t) + t * oy / length;
        final bl = _sqrt(bx * bx + by * by);
        if (bl > 0.2) {
          dx = bx / bl;
          dy = by / bl;
        }
      }
    }
    return (
      a: GoalPoint(keeper.x - dx * _keeperHalfLength, keeper.y - dy * _keeperHalfLength),
      b: GoalPoint(keeper.x + dx * _keeperHalfLength, keeper.y + dy * _keeperHalfLength),
    );
  }

  bool _keeperTouches(double x, double y) {
    final body = keeperBody();
    final abx = body.b.x - body.a.x;
    final aby = body.b.y - body.a.y;
    final apx = x - body.a.x;
    final apy = y - body.a.y;
    final lengthSq = abx * abx + aby * aby;
    var t = lengthSq == 0 ? 0.0 : (apx * abx + apy * aby) / lengthSq;
    t = clampD(t, 0, 1);
    final cx = body.a.x + abx * t - x;
    final cy = body.a.y + aby * t - y;
    final reach = _keeperRadius + Goal.ballRadius;
    return cx * cx + cy * cy <= reach * reach;
  }

  // --- the ball ------------------------------------------------------------

  void _advanceBall() {
    if (phase != PenaltyPhase.flight && phase != PenaltyPhase.outcome) return;
    const dt = 1 / (tickHz * _substeps);
    for (var s = 0; s < _substeps; s++) {
      final before = ball;
      final inPlay = !_resolved;
      ballVelocity = Vec3(
        ballVelocity.x + (inPlay ? _curveAccel * dt : 0),
        ballVelocity.y - Goal.gravity * dt,
        ballVelocity.z,
      );
      ball = ball + ballVelocity * dt;

      if (ball.y < Goal.ballRadius && ballVelocity.y < 0) {
        ball = ball.copyWith(y: Goal.ballRadius);
        final impact = -ballVelocity.y;
        ballVelocity = Vec3(ballVelocity.x * 0.8, impact * 0.5, ballVelocity.z * 0.8);
        if (impact > 2) {
          pendingEvents.add(PenaltyEvent(PenaltyEventType.bounce, at: ball, value: impact / 10));
        }
      }

      if (!_resolved) {
        if (before.z > Goal.keeperZ && ball.z <= Goal.keeperZ) {
          final t = (before.z - Goal.keeperZ) / (before.z - ball.z);
          final x = before.x + (ball.x - before.x) * t;
          final y = before.y + (ball.y - before.y) * t;
          if (_keeperTouches(x, y)) {
            final push = x - keeper.x;
            ballVelocity = Vec3(
              ballVelocity.x * 0.25 + (push >= 0 ? 3.2 : -3.2),
              ballVelocity.y.abs() * 0.4 + 2.2,
              -ballVelocity.z * 0.3,
            );
            ball = Vec3(x, y, Goal.keeperZ + 0.05);
            _resolve(KickResult.saved);
            continue;
          }
        }
        if (before.z > 0 && ball.z <= 0) {
          final t = before.z / (before.z - ball.z);
          final x = before.x + (ball.x - before.x) * t;
          final y = before.y + (ball.y - before.y) * t;
          _judgeLine(x, y);
        }
      } else if (lastResult == KickResult.goal && ball.z < -Goal.netDepth + 0.2) {
        // Caught by the net.
        ball = ball.copyWith(z: -Goal.netDepth + 0.2);
        ballVelocity = Vec3(ballVelocity.x * 0.2, ballVelocity.y * 0.3, 0);
      }
    }
  }

  void _judgeLine(double x, double y) {
    final reach = Goal.postRadius + Goal.ballRadius;
    final nearPost = (x.abs() - Goal.halfWidth).abs() < reach && y < Goal.height + reach;
    final nearBar = (y - Goal.height).abs() < reach && x.abs() < Goal.halfWidth + reach;
    if (nearPost || nearBar) {
      ballVelocity = Vec3(
        nearPost ? -ballVelocity.x * 0.5 : ballVelocity.x,
        nearBar ? -ballVelocity.y.abs() * 0.5 : ballVelocity.y,
        -ballVelocity.z * 0.45,
      );
      _resolve(KickResult.post);
      return;
    }
    final inside = x.abs() < Goal.halfWidth && y < Goal.height;
    if (inside) {
      ballVelocity = ballVelocity * 0.45;
      _resolve(KickResult.goal);
    } else {
      _resolve(KickResult.missed);
    }
  }

  void _resolve(KickResult result) {
    _resolved = true;
    lastResult = result;
    (shooter == PenaltySide.p1 ? p1Kicks : p2Kicks).add(result);
    pendingEvents.add(PenaltyEvent(
      switch (result) {
        KickResult.goal => PenaltyEventType.goal,
        KickResult.saved => PenaltyEventType.save,
        KickResult.post => PenaltyEventType.post,
        KickResult.missed => PenaltyEventType.missed,
      },
      at: ball,
    ));
    _enter(PenaltyPhase.outcome);
  }

  void _afterKick() {
    if (_decided()) {
      _enter(PenaltyPhase.complete);
      pendingEvents.add(const PenaltyEvent(PenaltyEventType.complete));
      return;
    }
    shooter = shooter == PenaltySide.p1 ? PenaltySide.p2 : PenaltySide.p1;
    _startKick();
  }

  bool _decided() {
    final n1 = p1Kicks.length;
    final n2 = p2Kicks.length;
    final g1 = p1Goals;
    final g2 = p2Goals;
    if (n1 <= _regulationKicks && n2 <= _regulationKicks) {
      if (g1 + (_regulationKicks - n1) < g2) return true;
      if (g2 + (_regulationKicks - n2) < g1) return true;
      if (n1 < _regulationKicks || n2 < _regulationKicks) return false;
    }
    if (n1 != n2) return false;
    if (g1 != g2) return true;
    return n1 >= _maxKicks;
  }

  void _enter(PenaltyPhase next) {
    phase = next;
    _phaseTicks = 0;
  }

  // --- result --------------------------------------------------------------

  double get normalizedSkill {
    if (isTwoHuman) return 0.5;
    final n1 = p1Kicks.length;
    final n2 = p2Kicks.length;
    final scoring = n1 == 0 ? 0.0 : p1Goals / n1;
    final saving = n2 == 0 ? 0.0 : 1 - p2Goals / n2;
    return clampD(scoring * 0.6 + saving * 0.4, 0, 1);
  }

  GameResult buildResult({String? sessionToken, List<int>? replay}) {
    final g1 = p1Goals;
    final g2 = p2Goals;
    return GameResult(
      gameSlug: 'football',
      mode: mode,
      botDifficulty: botDifficulty,
      durationMs: tick * 1000 ~/ tickHz,
      p1Score: g1,
      p2Score: g2,
      outcome: g1 > g2
          ? MatchOutcome.p1Win
          : (g2 > g1 ? MatchOutcome.p2Win : MatchOutcome.draw),
      normalizedSkill: normalizedSkill,
      seed: seed,
      tickCount: tick,
      replay: replay,
      sessionToken: sessionToken,
    );
  }

  static double _distance(GoalPoint a, GoalPoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return _sqrt(dx * dx + dy * dy);
  }

  /// `sqrt` is correctly rounded on every platform, so the determinism
  /// contract allows it.
  static double _sqrt(double v) => math.sqrt(v < 0 ? 0 : v);
}
