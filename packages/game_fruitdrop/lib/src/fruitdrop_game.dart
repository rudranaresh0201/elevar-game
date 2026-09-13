import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:fruitdrop_sim/fruitdrop_sim.dart';
import 'package:game_core/game_core.dart';

import 'fruit_art.dart';
import 'fruitdrop_scene.dart';
import 'game_config.dart';

class FruitDropGame extends FlameGame {
  FruitDropGame({required this.config, required this.onComplete})
      : simulation = FruitDropSimulation(seed: config.seed, jar: config.jar) {
    runner = FruitDropRunner(simulation: simulation);
  }

  final FruitDropConfig config;
  final void Function(FruitDropOutcome outcome) onComplete;
  final FruitDropSimulation simulation;
  late final FruitDropRunner runner;
  final FixedLoop _loop = FixedLoop(tickHz: FruitDropSimulation.tickHz);

  final ValueNotifier<int> hudRevision = ValueNotifier<int>(0);

  /// Jar-to-screen transform.
  double jarScale = 1;
  Offset jarOrigin = Offset.zero;

  static const double hudTop = 150;
  static const double barBottom = 96;
  static const double wall = 26;

  // --- juice ---------------------------------------------------------------
  double shake = 0;
  Offset shakeOffset = Offset.zero;
  double flash = 0;
  final Map<int, double> rotation = <int, double>{};
  final Map<int, double> squash = <int, double>{};
  final Map<int, Offset> _lastSeen = <int, Offset>{};
  final List<Juice> juice = <Juice>[];
  final List<ScorePop> pops = <ScorePop>[];
  String comboText = '';
  double comboAge = 99;
  int comboSerial = 0;
  bool touching = false;

  final math.Random _visual = math.Random(6);
  bool _finished = false;
  double _endDelay = 0;

  @override
  Future<void> onLoad() async {
    await add(FruitDropScene(game: this));
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    final availW = size.x - 24;
    final availH = size.y - hudTop - barBottom;
    final w = simulation.width + wall * 2;
    final h = FruitDropSimulation.height + wall;
    jarScale = math.min(availW / w, availH / h);
    jarOrigin = Offset(
      (size.x - simulation.width * jarScale) / 2,
      hudTop + (availH - h * jarScale) / 2,
    );
  }

  Offset toScreen(Vec2 p) =>
      Offset(jarOrigin.dx + p.x * jarScale, jarOrigin.dy + p.y * jarScale);

  double screenToAim(Offset screen) =>
      clampD((screen.dx - jarOrigin.dx) / jarScale / simulation.width, 0, 1);

  // --- input ---------------------------------------------------------------

  void press(Offset at) {
    touching = true;
    runner.aimAt(screenToAim(at));
  }

  void drag(Offset at) => runner.aimAt(screenToAim(at));

  void release(Offset at) {
    touching = false;
    if (simulation.canDrop) runner.dropAt(screenToAim(at));
  }

  // --- loop ----------------------------------------------------------------

  @override
  void update(double dt) {
    super.update(dt);
    if (_finished) return;
    if (!simulation.isComplete) {
      _loop.advance(dt, (_) {
        runner.tick();
        _react(simulation.pendingEvents);
      });
    } else {
      _endDelay += dt;
      if (_endDelay > 1.6) {
        _finished = true;
        final replay = runner.finishRecording();
        onComplete(FruitDropOutcome(
          result: simulation.buildResult(sessionToken: config.sessionToken, replay: replay),
          replay: replay,
          score: simulation.score,
          biggestTier: simulation.biggestTier,
          merges: simulation.merges,
          drops: simulation.drops,
        ));
      }
    }
    _advanceJuice(dt);
  }

  void _react(List<FruitEvent> events) {
    for (final e in events) {
      switch (e.type) {
        case FruitEventType.drop:
          unawaited(HapticFeedback.selectionClick());
          hudRevision.value++;
        case FruitEventType.merge:
          final big = e.tier >= 7;
          shake = math.max(shake, 2 + e.tier * 1.4);
          if (big) flash = 0.35;
          _splash(e.at, e.tier, 10 + e.tier * 3);
          pops.add(ScorePop('+${e.points}', e.at, FruitArt.palette[e.tier].fill));
          if (e.combo >= 2) {
            comboText = e.combo >= 5 ? 'MEGA COMBO ×${e.combo}' : 'COMBO ×${e.combo}';
            comboAge = 0;
            comboSerial++;
          }
          unawaited(big ? HapticFeedback.heavyImpact() : HapticFeedback.lightImpact());
          hudRevision.value++;
        case FruitEventType.pop:
          shake = 26;
          flash = 0.8;
          _splash(e.at, Fruits.watermelon, 80);
          pops.add(ScorePop('+${e.points} WATERMELON!', e.at, const Color(0xFFFF3DA6)));
          comboText = 'WATERMELON POP!';
          comboAge = 0;
          comboSerial++;
          unawaited(HapticFeedback.vibrate());
          hudRevision.value++;
        case FruitEventType.land:
          break;
        case FruitEventType.gameOver:
          shake = 16;
          comboText = 'JAR FULL';
          comboAge = 0;
          comboSerial++;
          unawaited(HapticFeedback.heavyImpact());
          hudRevision.value++;
      }
    }
  }

  void _splash(Vec2 at, int tier, int count) {
    final colour = FruitArt.palette[tier].fill;
    for (var i = 0; i < count; i++) {
      final a = _visual.nextDouble() * math.pi * 2;
      final speed = 120 + _visual.nextDouble() * (300 + tier * 50);
      juice.add(Juice(
        position: at,
        velocity: Vec2(math.cos(a) * speed, math.sin(a) * speed - 200),
        colour: i % 4 == 0 ? const Color(0xFFFFFFFF) : colour,
        size: 5 + _visual.nextDouble() * (6 + tier),
        life: 0.35 + _visual.nextDouble() * 0.35,
      ));
    }
  }

  void _advanceJuice(double dt) {
    shake *= math.pow(0.004, dt).toDouble();
    if (shake < 0.05) shake = 0;
    final a = _visual.nextDouble() * math.pi * 2;
    shakeOffset = Offset(math.cos(a) * shake, math.sin(a) * shake);
    flash *= math.pow(0.02, dt).toDouble();
    if (comboAge < 99) {
      final before = comboAge;
      comboAge += dt;
      if (before < 1.1 && comboAge >= 1.1) hudRevision.value++;
    }

    // Roll: a fruit that moves sideways turns by distance over radius, which
    // is what rolling is. Decorative only.
    final alive = <int>{};
    for (final f in simulation.fruits) {
      alive.add(f.id);
      final now = Offset(f.position.x, f.position.y);
      final last = _lastSeen[f.id];
      if (last != null) {
        rotation[f.id] = (rotation[f.id] ?? 0) + (now.dx - last.dx) / f.fullRadius;
      } else {
        // A fruit made by a merge arrives with a wobble.
        squash[f.id] = f.grow < 1 ? 1 : 0;
      }
      _lastSeen[f.id] = now;
      squash[f.id] = (squash[f.id] ?? 0) * math.pow(0.02, dt).toDouble();
    }
    _lastSeen.removeWhere((id, _) => !alive.contains(id));
    rotation.removeWhere((id, _) => !alive.contains(id));
    squash.removeWhere((id, _) => !alive.contains(id));

    for (var i = juice.length - 1; i >= 0; i--) {
      juice[i].advance(dt);
      if (juice[i].life <= 0) juice.removeAt(i);
    }
    for (var i = pops.length - 1; i >= 0; i--) {
      pops[i].age += dt;
      if (pops[i].age > 0.9) pops.removeAt(i);
    }
  }

  @override
  void onRemove() {
    hudRevision.dispose();
    super.onRemove();
  }
}

class Juice {
  Juice({
    required this.position,
    required this.velocity,
    required this.colour,
    required this.size,
    required this.life,
  }) : maxLife = life;

  Vec2 position;
  Vec2 velocity;
  final Color colour;
  final double size;
  double life;
  final double maxLife;

  void advance(double dt) {
    position += velocity * dt;
    velocity = Vec2(velocity.x * 0.94, velocity.y + 1800 * dt);
    life -= dt;
  }
}

class ScorePop {
  ScorePop(this.text, this.at, this.colour);

  final String text;
  final Vec2 at;
  final Color colour;
  double age = 0;
}
