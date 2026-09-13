import 'package:game_core/game_core.dart';

import 'terrain.dart';

enum ArcherSide { p1, p2 }

enum DuelPhase { aim, flight, impact, complete }

enum HitKind { head, body, close, ground, lost }

class ArcherBotProfile {
  const ArcherBotProfile({
    required this.baseError,
    required this.decay,
    required this.floor,
  });

  /// Relative error on power and slope for the bot's first shot.
  final double baseError;

  /// How much the error shrinks each shot after — the bot finds its range
  /// the way a person does.
  final double decay;
  final double floor;

  static ArcherBotProfile of(BotDifficulty d) => switch (d) {
        BotDifficulty.easy =>
          const ArcherBotProfile(baseError: 0.3, decay: 0.9, floor: 0.14),
        BotDifficulty.medium =>
          const ArcherBotProfile(baseError: 0.19, decay: 0.84, floor: 0.07),
        BotDifficulty.hard =>
          const ArcherBotProfile(baseError: 0.11, decay: 0.75, floor: 0.035),
      };
}

enum DuelEventType { loose, hit, stuck, lost, turn, complete }

class DuelEvent {
  const DuelEvent(this.type,
      {this.at = Vec2.zero, this.kind, this.damage = 0, this.side});

  final DuelEventType type;
  final Vec2 at;
  final HitKind? kind;
  final int damage;

  /// For a hit, who was hit. For a turn, whose turn it now is.
  final ArcherSide? side;
}

class DuelInput {
  const DuelInput({this.direction = const Vec2(1, 0), this.power = 0, this.fire = 0});

  final Vec2 direction;
  final double power;
  final double fire;

  static const int channelCount = 4;

  static DuelInput fromChannels(List<double> c) => DuelInput(
        direction: Vec2(c[0] * 2 - 1, c[1] * 2 - 1),
        power: c[2],
        fire: c[3],
      );
}

/// An arrow stuck in the world, kept so the landscape remembers the match.
class StuckArrow {
  const StuckArrow(this.at, this.direction, {this.inSide});

  final Vec2 at;
  final Vec2 direction;

  /// When stuck in an archer, which one — so it moves with them.
  final ArcherSide? inSide;
}

/// A turn-based archery duel, as pure state.
///
/// Drag back to aim, let go to loose. Angle and force decide where it lands;
/// wind changes every turn. Head is worth more than body. Nothing here is
/// hidden from the player that matters: the wind is shown, the arc's first
/// stretch is shown, and the rest is judgement.
class DuelSimulation {
  DuelSimulation({
    required this.seed,
    required this.mode,
    this.botDifficulty,
  })  : assert(mode != GameMode.vsBot || botDifficulty != null),
        terrain = Terrain.generate(seed),
        _windRng = DeterministicRng.stream(seed, 1),
        _botRng = DeterministicRng.stream(seed, 2) {
    _startTurn(ArcherSide.p1);
  }

  final int seed;
  final GameMode mode;
  final BotDifficulty? botDifficulty;
  final Terrain terrain;
  final DeterministicRng _windRng;
  final DeterministicRng _botRng;
  final EdgeTrigger _fire = EdgeTrigger();

  static const int tickHz = 120;
  static const double gravity = 900;
  static const double maxSpeed = 1550;
  static const double maxWind = 140;
  static const int maxHp = 100;
  static const int headDamage = 55;
  static const int bodyDamage = 34;
  static const double headRadius = 30;
  static const double headHeight = 160;
  static const double bodyHalfWidth = 28;
  static const double bodyHeight = 128;

  static const int _aimTimeoutTicks = tickHz * 15;
  static const int _botThinkTicks = 100;
  static const int _impactTicks = 130;
  static const int _maxFlightTicks = tickHz * 6;
  static const int _maxTurns = 30;
  static const int _substeps = 3;

  int tick = 0;
  DuelPhase phase = DuelPhase.aim;
  int _phaseTicks = 0;

  ArcherSide turn = ArcherSide.p1;
  int turnsTaken = 0;
  int p1Hp = maxHp;
  int p2Hp = maxHp;
  int p1Hits = 0;
  int p2Hits = 0;
  int p1Headshots = 0;
  int _botShots = 0;

  /// Horizontal wind acceleration this turn, field units per second squared.
  double wind = 0;

  Vec2 arrow = Vec2.zero;
  Vec2 arrowPrevious = Vec2.zero;
  Vec2 arrowVelocity = Vec2.zero;
  bool arrowFlying = false;

  /// What the bot is showing on screen while it "draws".
  Vec2 botAimDirection = const Vec2(-0.7, 0.7);
  double botAimPower = 0;
  ({Vec2 direction, double power})? _botPlan;

  /// The archer's aim at the moment of loosing, for the pose.
  Vec2 lastDirection = const Vec2(1, 0);

  HitKind? lastHit;
  final List<StuckArrow> stuck = <StuckArrow>[];
  final List<DuelEvent> pendingEvents = <DuelEvent>[];

  bool get isComplete => phase == DuelPhase.complete;
  bool get isTwoHuman => mode == GameMode.local2P;
  bool get turnIsHuman => isTwoHuman || turn == ArcherSide.p1;
  bool get acceptsAim => phase == DuelPhase.aim && turnIsHuman;

  int get aimTicksLeft => phase == DuelPhase.aim ? _aimTimeoutTicks - _phaseTicks : 0;

  /// 0..1 through the bot's draw, for the animation.
  double get botDrawProgress => (!turnIsHuman && phase == DuelPhase.aim)
      ? clampD(_phaseTicks / _botThinkTicks, 0, 1)
      : 0;

  static double xOf(ArcherSide side) =>
      side == ArcherSide.p1 ? Terrain.p1X : Terrain.p2X;

  double groundOf(ArcherSide side) => terrain.heightAt(xOf(side));

  /// Where an arrow leaves the bow.
  Vec2 launchPoint(ArcherSide side) => Vec2(
        xOf(side) + (side == ArcherSide.p1 ? 34 : -34),
        groundOf(side) + 112,
      );

  Vec2 headCentre(ArcherSide side) => Vec2(xOf(side), groundOf(side) + headHeight);

  void step(DuelInput input) {
    pendingEvents.clear();
    if (isComplete) return;
    tick++;
    _phaseTicks++;
    final fired = _fire.rising(input.fire);

    switch (phase) {
      case DuelPhase.aim:
        if (turnIsHuman) {
          if (fired && input.power > 0.05) {
            _loose(input.direction, input.power);
          } else if (_phaseTicks >= _aimTimeoutTicks) {
            _endTurn();
          }
        } else {
          _botAim();
        }
      case DuelPhase.flight:
        _advanceArrow();
        if (_phaseTicks > _maxFlightTicks && arrowFlying) _land(HitKind.lost, null);
      case DuelPhase.impact:
        if (_phaseTicks >= _impactTicks) _endTurn();
      case DuelPhase.complete:
        break;
    }
  }

  // --- turns ---------------------------------------------------------------

  void _startTurn(ArcherSide side) {
    turn = side;
    // Wind is triangular around zero: usually a breeze, sometimes a gale.
    wind = (_windRng.nextDouble() + _windRng.nextDouble() - 1) * maxWind;
    _botPlan = null;
    botAimPower = 0;
    _enter(DuelPhase.aim);
    pendingEvents.add(DuelEvent(DuelEventType.turn, side: side));
  }

  void _endTurn() {
    turnsTaken++;
    if (p1Hp <= 0 || p2Hp <= 0 || turnsTaken >= _maxTurns) {
      _enter(DuelPhase.complete);
      pendingEvents.add(const DuelEvent(DuelEventType.complete));
      return;
    }
    _startTurn(turn == ArcherSide.p1 ? ArcherSide.p2 : ArcherSide.p1);
  }

  void _loose(Vec2 direction, double power) {
    final d = direction.lengthSquared < 1e-6 ? const Vec2(1, 0) : direction.normalized;
    lastDirection = d;
    arrow = launchPoint(turn);
    arrowPrevious = arrow;
    arrowVelocity = d * (clampD(power, 0, 1) * maxSpeed);
    arrowFlying = true;
    _enter(DuelPhase.flight);
    pendingEvents.add(DuelEvent(DuelEventType.loose, at: arrow));
  }

  // --- flight --------------------------------------------------------------

  void _advanceArrow() {
    arrowPrevious = arrow;
    const dt = 1 / (tickHz * _substeps);
    for (var s = 0; s < _substeps && arrowFlying; s++) {
      arrowVelocity = Vec2(
        arrowVelocity.x + wind * dt,
        arrowVelocity.y - gravity * dt,
      );
      arrow = arrow + arrowVelocity * dt;
      _collide();
    }
  }

  void _collide() {
    final opponent = turn == ArcherSide.p1 ? ArcherSide.p2 : ArcherSide.p1;
    // The shooter's own body only counts once the arrow has had time to clear
    // it — otherwise every shot would hit the archer who loosed it.
    final sides = _phaseTicks > 24
        ? <ArcherSide>[opponent, turn]
        : <ArcherSide>[opponent];
    for (final side in sides) {
      final kind = hitTest(side, arrow);
      if (kind != null) {
        _land(kind, side);
        return;
      }
    }
    if (arrow.y <= terrain.heightAt(arrow.x)) {
      final close = _closeTo(opponent);
      _land(close ? HitKind.close : HitKind.ground, null);
      return;
    }
    if (arrow.x < -400 || arrow.x > Terrain.width + 400 || arrow.y < -200) {
      _land(HitKind.lost, null);
    }
  }

  /// Which part of [side] a point is inside, if any.
  HitKind? hitTest(ArcherSide side, Vec2 p) {
    final head = headCentre(side);
    if ((p - head).lengthSquared <= headRadius * headRadius) return HitKind.head;
    final x = xOf(side);
    final ground = groundOf(side);
    if ((p.x - x).abs() <= bodyHalfWidth && p.y >= ground && p.y <= ground + bodyHeight) {
      return HitKind.body;
    }
    return null;
  }

  bool _closeTo(ArcherSide side) {
    final centre = Vec2(xOf(side), groundOf(side) + 80);
    return (arrow - centre).lengthSquared < 150 * 150;
  }

  void _land(HitKind kind, ArcherSide? side) {
    arrowFlying = false;
    lastHit = kind;
    final direction = arrowVelocity.normalized;
    var damage = 0;
    if (side != null) {
      damage = kind == HitKind.head ? headDamage : bodyDamage;
      if (side == ArcherSide.p1) {
        p1Hp = p1Hp - damage < 0 ? 0 : p1Hp - damage;
      } else {
        p2Hp = p2Hp - damage < 0 ? 0 : p2Hp - damage;
      }
      if (turn == ArcherSide.p1 && side == ArcherSide.p2) {
        p1Hits++;
        if (kind == HitKind.head) p1Headshots++;
      } else if (turn == ArcherSide.p2 && side == ArcherSide.p1) {
        p2Hits++;
      }
      stuck.add(StuckArrow(arrow, direction, inSide: side));
      pendingEvents.add(DuelEvent(DuelEventType.hit,
          at: arrow, kind: kind, damage: damage, side: side));
    } else if (kind == HitKind.lost) {
      pendingEvents.add(DuelEvent(DuelEventType.lost, at: arrow, kind: kind));
    } else {
      stuck.add(StuckArrow(arrow, direction));
      pendingEvents.add(DuelEvent(DuelEventType.stuck, at: arrow, kind: kind));
    }
    if (stuck.length > 24) stuck.removeAt(0);
    _enter(DuelPhase.impact);
  }

  // --- the bot -------------------------------------------------------------

  void _botAim() {
    _botPlan ??= _planBotShot();
    final plan = _botPlan!;
    final t = botDrawProgress;
    // Swing the bow up from rest toward the plan, drawing as it goes.
    final rest = turn == ArcherSide.p2 ? const Vec2(-1, -0.2) : const Vec2(1, -0.2);
    botAimDirection = (rest + (plan.direction - rest) * clampD(t * 1.5, 0, 1)).normalized;
    botAimPower = plan.power * clampD((t - 0.3) / 0.7, 0, 1);
    if (_phaseTicks >= _botThinkTicks) {
      _botShots++;
      _loose(plan.direction, plan.power);
    }
  }

  ({Vec2 direction, double power}) _planBotShot() {
    final profile = ArcherBotProfile.of(botDifficulty!);
    final best = solveShot(this, from: turn, at: ArcherSide.p1);
    var error = profile.baseError;
    for (var i = 0; i < _botShots; i++) {
      error *= profile.decay;
    }
    if (error < profile.floor) error = profile.floor;
    final powerNoise = (_botRng.nextDouble() + _botRng.nextDouble() - 1) * error;
    final slopeNoise = (_botRng.nextDouble() + _botRng.nextDouble() - 1) * error;
    final d = best.direction;
    return (
      direction: Vec2(d.x, d.y + slopeNoise).normalized,
      power: clampD(best.power * (1 + powerNoise), 0.1, 1),
    );
  }

  void _enter(DuelPhase next) {
    phase = next;
    _phaseTicks = 0;
  }

  // --- result --------------------------------------------------------------

  double get normalizedSkill {
    if (isTwoHuman) return 0.5;
    final dealt = (maxHp - p2Hp) / maxHp;
    final kept = p1Hp / maxHp;
    return clampD(dealt * 0.6 + kept * 0.4, 0, 1);
  }

  GameResult buildResult({String? sessionToken, List<int>? replay}) => GameResult(
        gameSlug: 'shooting',
        mode: mode,
        botDifficulty: botDifficulty,
        durationMs: tick * 1000 ~/ tickHz,
        p1Score: p1Hp,
        p2Score: p2Hp,
        outcome: p1Hp > p2Hp
            ? MatchOutcome.p1Win
            : (p2Hp > p1Hp ? MatchOutcome.p2Win : MatchOutcome.draw),
        normalizedSkill: normalizedSkill,
        seed: seed,
        tickCount: tick,
        replay: replay,
        sessionToken: sessionToken,
      );
}

/// Finds the angle and force that bring an arrow from [from] closest to the
/// middle of [at], wind and hills included.
///
/// Brute force over a fan of launch slopes, then refined on power. Slopes are
/// rational (rise over run), not angles, so no trigonometry is involved.
({Vec2 direction, double power}) solveShot(
  DuelSimulation sim, {
  required ArcherSide from,
  required ArcherSide at,
}) {
  final facing = from == ArcherSide.p1 ? 1.0 : -1.0;
  final target = Vec2(DuelSimulation.xOf(at), sim.groundOf(at) + 100);
  final origin = sim.launchPoint(from);
  var bestMiss = double.infinity;
  var best = (direction: Vec2(facing, 1).normalized, power: 0.8);

  for (var k = 2; k <= 30; k++) {
    final direction = Vec2(facing, k / 10).normalized;
    for (var p = 0.3; p <= 1.0001; p += 0.035) {
      final miss = _missDistance(sim, origin, direction * (p * DuelSimulation.maxSpeed), target, at);
      if (miss < bestMiss) {
        bestMiss = miss;
        best = (direction: direction, power: p);
      }
    }
  }
  // Refine power around the best.
  final base = best;
  for (var dp = -0.03; dp <= 0.0301; dp += 0.005) {
    final p = clampD(base.power + dp, 0.1, 1);
    final miss = _missDistance(sim, origin, base.direction * (p * DuelSimulation.maxSpeed), target, at);
    if (miss < bestMiss) {
      bestMiss = miss;
      best = (direction: base.direction, power: p);
    }
  }
  return best;
}

double _missDistance(
    DuelSimulation sim, Vec2 origin, Vec2 velocity, Vec2 target, ArcherSide at) {
  var p = origin;
  var v = velocity;
  const dt = 1 / 60;
  var closest = double.infinity;
  for (var i = 0; i < 360; i++) {
    v = Vec2(v.x + sim.wind * dt, v.y - DuelSimulation.gravity * dt);
    p = p + v * dt;
    final d = (p - target).lengthSquared;
    if (d < closest) closest = d;
    if (sim.hitTest(at, p) != null) return 0;
    if (p.y <= sim.terrain.heightAt(p.x)) break;
    if (p.x < -400 || p.x > Terrain.width + 400) break;
  }
  return closest;
}
