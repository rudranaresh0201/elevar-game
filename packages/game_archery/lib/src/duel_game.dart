import 'dart:async';
import 'dart:math' as math;

import 'package:archery_sim/archery_sim.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:game_core/game_core.dart';

import 'duel_scene.dart';
import 'duel_theme.dart';
import 'game_config.dart';

/// Hosts the duel: camera, drag-to-aim, juice. No rules.
class DuelGame extends FlameGame {
  DuelGame({required this.config, required this.onComplete})
      : simulation = DuelSimulation(
          seed: config.seed,
          mode: config.mode,
          botDifficulty: config.botDifficulty,
        ) {
    runner = DuelRunner(simulation: simulation);
    camX = simulation.launchPoint(ArcherSide.p1).x + 260;
    camY = simulation.groundOf(ArcherSide.p1) + 80;
  }

  final DuelConfig config;
  final void Function(DuelOutcome outcome) onComplete;
  final DuelSimulation simulation;
  late final DuelRunner runner;
  final FixedLoop _loop = FixedLoop(tickHz: DuelSimulation.tickHz);

  final ValueNotifier<int> hudRevision = ValueNotifier<int>(0);

  double get interpolation => _loop.alpha;

  // --- camera --------------------------------------------------------------
  double camX = 0;
  double camY = 0;
  double zoom = 1;

  /// World units across the screen at zoom 1.
  static const double viewWidth = 1050;

  double get scale => size.x / viewWidth * zoom;

  /// Where world height [camY] sits on screen.
  double get horizonY => size.y * 0.6;

  Offset toScreen(Vec2 world) => Offset(
        size.x / 2 + (world.x - camX) * scale,
        horizonY - (world.y - camY) * scale,
      );

  // --- aiming --------------------------------------------------------------
  Offset? dragStart;
  Offset? dragNow;

  /// The live aim, while a finger is down.
  ({Vec2 direction, double power})? get liveAim {
    final start = dragStart;
    final now = dragNow;
    if (start == null || now == null || !simulation.acceptsAim) return null;
    final pull = start - now;
    final length = pull.distance;
    if (length < 12) return null;
    final direction = Vec2(pull.dx, -pull.dy).normalized;
    final power = clampD(length / (size.x * 0.42), 0, 1);
    return (direction: direction, power: power);
  }

  void beginAim(Offset at) {
    if (!simulation.acceptsAim) return;
    dragStart = at;
    dragNow = at;
  }

  void moveAim(Offset at) {
    if (dragStart != null) dragNow = at;
  }

  void endAim() {
    final aim = liveAim;
    dragStart = null;
    dragNow = null;
    if (aim == null || aim.power < 0.08) return;
    runner.loose(aim.direction, aim.power);
  }

  void cancelAim() {
    dragStart = null;
    dragNow = null;
  }

  // --- juice ---------------------------------------------------------------
  double shake = 0;
  Offset shakeOffset = Offset.zero;
  double flash = 0;
  final Map<ArcherSide, double> flinch = <ArcherSide, double>{
    ArcherSide.p1: 0,
    ArcherSide.p2: 0,
  };

  /// Displayed health, easing toward the real number so a hit drains visibly.
  final Map<ArcherSide, double> shownHp = <ArcherSide, double>{
    ArcherSide.p1: DuelSimulation.maxHp.toDouble(),
    ArcherSide.p2: DuelSimulation.maxHp.toDouble(),
  };

  final List<DuelFloater> floaters = <DuelFloater>[];
  final List<DuelParticle> particles = <DuelParticle>[];
  final List<Vec2> arrowTrail = <Vec2>[];

  String bannerText = '';
  Color bannerColour = const Color(0xFFFFFFFF);
  double bannerAge = 99;
  int bannerSerial = 0;

  /// The world this duel is set in, from the seed.
  late final DuelTheme theme = DuelTheme.forSeed(config.seed);

  /// Leaves, dust or snow blowing across the screen, in screen fractions. The
  /// wind indicator says a number; these make it visible.
  final List<WindBit> windBits = <WindBit>[];

  /// Per stuck arrow, how much it is still quivering, 0..1.
  final Map<StuckArrow, double> wobble = <StuckArrow, double>{};

  /// A white flash on an archer who has just been hit.
  final Map<ArcherSide, double> hitTint = <ArcherSide, double>{
    ArcherSide.p1: 0,
    ArcherSide.p2: 0,
  };

  /// Real seconds of slow motion left, after a headshot. Only the wall clock
  /// is slowed, so the replay is unaffected.
  double slowMo = 0;
  double punch = 0;
  double clock = 0;

  final math.Random _visual = math.Random(8);
  bool _finished = false;
  double _completeDelay = 0;

  @override
  Future<void> onLoad() async {
    await add(DuelScene(game: this));
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_finished) return;
    clock += dt;

    var simDt = dt;
    if (slowMo > 0) {
      slowMo -= dt;
      simDt = dt * 0.3;
    }
    _loop.advance(simDt, (_) {
      runner.tick();
      _react(simulation.pendingEvents);
    });
    _advanceCamera(dt);
    _advanceJuice(dt);

    if (simulation.isComplete) {
      // Let the last hit land on screen before cutting away.
      _completeDelay += dt;
      if (_completeDelay > 1.2) {
        _finished = true;
        final replay = runner.finishRecording();
        onComplete(DuelOutcome(
          result: simulation.buildResult(sessionToken: config.sessionToken, replay: replay),
          replay: replay,
          hits: simulation.p1Hits,
          headshots: simulation.p1Headshots,
          turns: simulation.turnsTaken,
        ));
      }
    }
  }

  void _advanceCamera(double dt) {
    final sim = simulation;
    double tx;
    double ty;
    var tz = 1.0;
    final halfView = viewWidth / 2;
    if (sim.phase == DuelPhase.flight || sim.phase == DuelPhase.impact) {
      tx = sim.arrow.x;
      ty = math.max(sim.arrow.y - 120, sim.terrain.heightAt(sim.arrow.x) + 40);
      tz = sim.phase == DuelPhase.flight ? 0.82 : 1.0;
    } else {
      final side = sim.turn;
      final facing = side == ArcherSide.p1 ? 1.0 : -1.0;
      tx = DuelSimulation.xOf(side) + facing * 280;
      ty = sim.groundOf(side) + 90;
    }
    tx = clampD(tx, halfView - 200, Terrain.width - halfView + 200);
    final k = 1 - math.exp(-5 * dt);
    camX += (tx - camX) * k;
    camY += (ty - camY) * k;
    zoom += (tz + punch * 0.25 - zoom) * (1 - math.exp(-3 * dt));
    punch *= math.pow(0.05, dt).toDouble();
  }

  void _react(List<DuelEvent> events) {
    for (final e in events) {
      switch (e.type) {
        case DuelEventType.loose:
          arrowTrail.clear();
          unawaited(HapticFeedback.lightImpact());
        case DuelEventType.hit:
          final head = e.kind == HitKind.head;
          flinch[e.side!] = 1;
          hitTint[e.side!] = 1;
          wobble[simulation.stuck.last] = 1;
          if (head) {
            slowMo = 0.7;
            punch = 1;
          }
          shake = head ? 22 : 14;
          flash = head ? 0.55 : 0.3;
          _burst(e.at, head ? 30 : 18, const Color(0xFFFFF200));
          floaters.add(DuelFloater(
            head ? '-${e.damage} HEADSHOT!' : '-${e.damage}',
            e.at + const Vec2(0, 60),
            head ? const Color(0xFFFF3DA6) : const Color(0xFFFFFFFF),
          ));
          _banner(head ? 'HEADSHOT!' : 'HIT!',
              head ? const Color(0xFFFF3DA6) : const Color(0xFFFFF200));
          unawaited(HapticFeedback.heavyImpact());
          hudRevision.value++;
        case DuelEventType.stuck:
          wobble[simulation.stuck.last] = 1;
          _burst(e.at, 14, theme.dirt);
          _burst(e.at, 6, theme.grass);
          shake = math.max(shake, 4);
          if (e.kind == HitKind.close) {
            floaters.add(DuelFloater('SO CLOSE!', e.at + const Vec2(0, 60),
                const Color(0xFFFF9F1C)));
          }
        case DuelEventType.lost:
          floaters.add(DuelFloater('WAY OFF', simulation.arrow, const Color(0xFFFFFFFF)));
        case DuelEventType.turn:
          final you = e.side == ArcherSide.p1;
          _banner(
            simulation.isTwoHuman
                ? (you ? 'RED\'S TURN' : 'BLUE\'S TURN')
                : (you ? 'YOUR TURN' : 'BOT\'S TURN'),
            you ? const Color(0xFFFF2B2B) : const Color(0xFF29C7F0),
          );
          hudRevision.value++;
        case DuelEventType.complete:
          hudRevision.value++;
      }
    }
  }

  void _banner(String text, Color colour) {
    bannerText = text;
    bannerColour = colour;
    bannerAge = 0;
    bannerSerial++;
    hudRevision.value++;
  }

  void _burst(Vec2 at, int count, Color colour) {
    for (var i = 0; i < count; i++) {
      final a = _visual.nextDouble() * math.pi * 2;
      final speed = 150 + _visual.nextDouble() * 500;
      particles.add(DuelParticle(
        position: at,
        velocity: Vec2(math.cos(a) * speed, math.sin(a) * speed + 200),
        life: 0.4 + _visual.nextDouble() * 0.4,
        colour: colour,
        size: 5 + _visual.nextDouble() * 7,
      ));
    }
  }

  void _advanceJuice(double dt) {
    shake *= math.pow(0.004, dt).toDouble();
    if (shake < 0.05) shake = 0;
    final a = _visual.nextDouble() * math.pi * 2;
    shakeOffset = Offset(math.cos(a) * shake, math.sin(a) * shake);
    flash *= math.pow(0.02, dt).toDouble();
    flinch.updateAll((_, v) => math.max(0, v - dt * 2.5));
    hitTint.updateAll((_, v) => math.max(0, v - dt * 3));
    wobble.updateAll((_, v) => v * math.pow(0.01, dt).toDouble());
    wobble.removeWhere((arrow, v) => v < 0.01 || !simulation.stuck.contains(arrow));
    _advanceWind(dt);

    var hpMoved = false;
    for (final side in ArcherSide.values) {
      final real = (side == ArcherSide.p1 ? simulation.p1Hp : simulation.p2Hp).toDouble();
      final shown = shownHp[side]!;
      if ((shown - real).abs() > 0.3) {
        shownHp[side] = shown + (real - shown) * (1 - math.exp(-6 * dt));
        hpMoved = true;
      } else if (shown != real) {
        shownHp[side] = real;
        hpMoved = true;
      }
    }
    if (hpMoved) hudRevision.value++;

    if (bannerAge < 99) {
      final before = bannerAge;
      bannerAge += dt;
      if (before < 1.2 && bannerAge >= 1.2) hudRevision.value++;
    }
    for (var i = floaters.length - 1; i >= 0; i--) {
      floaters[i].age += dt;
      if (floaters[i].age > 1.4) floaters.removeAt(i);
    }
    for (var i = particles.length - 1; i >= 0; i--) {
      particles[i].advance(dt);
      if (particles[i].life <= 0) particles.removeAt(i);
    }
    if (simulation.arrowFlying) {
      arrowTrail.add(simulation.arrow);
      if (arrowTrail.length > 40) arrowTrail.removeAt(0);
    }
  }

  void _advanceWind(double dt) {
    if (windBits.isEmpty) {
      for (var i = 0; i < 28; i++) {
        windBits.add(WindBit(
          x: _visual.nextDouble(),
          y: _visual.nextDouble(),
          phase: _visual.nextDouble() * 6.28,
          size: 0.6 + _visual.nextDouble() * 0.8,
        ));
      }
    }
    // Screen fractions a second: a calm day still drifts a little, a gale
    // streams across.
    final push = simulation.wind / DuelSimulation.maxWind;
    final fall = theme.snowing ? 0.05 : 0.012;
    for (final bit in windBits) {
      bit.phase += dt * 2.4;
      bit.x += (push * 0.45 + math.sin(bit.phase) * 0.02) * dt * bit.size;
      bit.y += (fall + math.cos(bit.phase * 0.7) * 0.01) * dt * bit.size;
      if (bit.x > 1.05) bit.x -= 1.1;
      if (bit.x < -0.05) bit.x += 1.1;
      if (bit.y > 1.02) bit.y -= 1.04;
    }
  }

  @override
  void onRemove() {
    hudRevision.dispose();
    super.onRemove();
  }
}

class WindBit {
  WindBit({required this.x, required this.y, required this.phase, required this.size});

  double x;
  double y;
  double phase;
  final double size;
}

class DuelFloater {
  DuelFloater(this.text, this.at, this.colour);

  final String text;
  final Vec2 at;
  final Color colour;
  double age = 0;
}

class DuelParticle {
  DuelParticle({
    required this.position,
    required this.velocity,
    required this.life,
    required this.colour,
    required this.size,
  }) : maxLife = life;

  Vec2 position;
  Vec2 velocity;
  double life;
  final double maxLife;
  final Color colour;
  final double size;

  void advance(double dt) {
    position += velocity * dt;
    velocity = Vec2(velocity.x * 0.95, velocity.y - 1200 * dt);
    life -= dt;
  }
}
