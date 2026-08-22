import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:game_core/game_core.dart';
import 'package:pingpong_sim/pingpong_sim.dart';

import 'game_config.dart';
import 'pong_scene.dart';

/// Hosts the simulation and turns it into something to look at.
///
/// The split is strict: this class owns the clock, the camera, the particles
/// and the haptics, and owns *no* rules. It advances the simulation in fixed
/// ticks and reads the events that come back out.
class PingPongGame extends FlameGame {
  PingPongGame({required this.config, required this.onComplete})
      // Built here rather than in onLoad: Flame's onLoad is async, and the
      // engine can call update() before that future resolves. A simulation that
      // exists only after loading is a simulation that is briefly null on the
      // first frame — and nothing about constructing it needs to be async.
      : simulation = PingPongSimulation(
          seed: config.seed,
          mode: config.mode,
          botDifficulty: config.botDifficulty,
          rules: config.rules,
        ) {
    runner = PongMatchRunner(simulation: simulation);
  }

  final PongConfig config;
  final void Function(PongOutcome outcome) onComplete;

  final PingPongSimulation simulation;
  late final PongMatchRunner runner;

  final FixedLoop _loop = FixedLoop(tickHz: 120);

  /// Bumped whenever anything the HUD displays changes, so it can rebuild
  /// without rebuilding every frame.
  ///
  /// This tracks the match *phase* as well as the score. An earlier version
  /// bumped only on points, which left the "GET READY" banner painted over a
  /// rally already in progress — the HUD was showing a phase the simulation had
  /// left half a second earlier.
  final ValueNotifier<int> hudRevision = ValueNotifier<int>(0);

  /// Field-to-screen transform, recomputed on resize.
  double fieldScale = 1;
  Offset fieldOrigin = Offset.zero;

  /// Fraction of a tick already elapsed, for interpolating between simulation
  /// steps. Without this the ball visibly steps at 120 Hz against a 60 Hz
  /// display instead of gliding.
  double get interpolation => _loop.alpha;

  // --- juice ---------------------------------------------------------------
  double shake = 0;
  Offset shakeOffset = Offset.zero;
  double p1Squash = 0;
  double p2Squash = 0;
  final List<Particle> particles = <Particle>[];
  final List<Vec2> ballTrail = <Vec2>[];
  double flash = 0;

  final math.Random _visualRandom = math.Random(7);
  bool _finished = false;
  PongPhase _hudPhase = PongPhase.serving;

  @override
  Future<void> onLoad() async {
    await add(PongScene(game: this));
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // Letterbox the fixed 1000x1800 field: the match must play identically on
    // every screen, so the field never reshapes to fit the device.
    final scale = math.min(
      size.x / PongField.width,
      size.y / PongField.height,
    );
    fieldScale = scale;
    fieldOrigin = Offset(
      (size.x - PongField.width * scale) / 2,
      (size.y - PongField.height * scale) / 2,
    );
  }

  /// Converts a screen position into the normalised field coordinate the
  /// simulation expects.
  Vec2 screenToNormalised(Offset screen) {
    final fieldX = (screen.dx - fieldOrigin.dx) / fieldScale;
    final fieldY = (screen.dy - fieldOrigin.dy) / fieldScale;
    return Vec2(
      clampD(fieldX / PongField.width, 0, 1),
      clampD(fieldY / PongField.height, 0, 1),
    );
  }

  /// Which player owns a touch that began at [normalised].
  PongSide sideForTouch(Vec2 normalised) =>
      normalised.y > 0.5 ? PongSide.p1 : PongSide.p2;

  void setTarget(PongSide side, Vec2 normalised) {
    if (side == PongSide.p1) {
      runner.setP1Target(normalised);
    } else if (config.isTwoHuman) {
      runner.setP2Target(normalised);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_finished) return;

    _loop.advance(dt, (_) {
      runner.tick();
      _reactTo(simulation.pendingEvents);
    });

    if (simulation.state.phase != _hudPhase) {
      _hudPhase = simulation.state.phase;
      hudRevision.value++;
    }

    _advanceJuice(dt);

    if (simulation.isComplete && !_finished) {
      _finished = true;
      // Seal the recording exactly once — finishing drains the buffer.
      final replay = runner.finishRecording();
      onComplete(
        PongOutcome(
          result: simulation.buildResult(
            sessionToken: config.sessionToken,
            replay: replay,
          ),
          replay: replay,
        ),
      );
    }
  }

  /// Turns simulation events into things you can see and feel.
  void _reactTo(List<PongEvent> events) {
    for (final event in events) {
      switch (event.type) {
        case PongEventType.paddleHit:
          shake = math.max(shake, 3 + event.intensity * 7);
          if (event.side == PongSide.p1) {
            p1Squash = 1;
          } else {
            p2Squash = 1;
          }
          _spawnBurst(event.at, 6, event.intensity);
          // A short, sharp tick on contact is most of what makes a hit feel
          // physical on a device with no buttons.
          unawaited(HapticFeedback.selectionClick());
        case PongEventType.wallHit:
          shake = math.max(shake, 2);
          _spawnBurst(event.at, 3, 0.4);
        case PongEventType.point:
          shake = math.max(shake, 16);
          flash = 1;
          _spawnBurst(event.at, 26, 1);
          ballTrail.clear();
          hudRevision.value++;
          unawaited(HapticFeedback.mediumImpact());
        case PongEventType.serve:
          ballTrail.clear();
        case PongEventType.matchComplete:
          shake = 22;
          hudRevision.value++;
          unawaited(HapticFeedback.heavyImpact());
      }
    }
  }

  void _advanceJuice(double dt) {
    // Frame-rate independent decay, so shake feels the same at 60 and 120 fps.
    final decay = math.pow(0.0012, dt).toDouble();
    shake *= decay;
    if (shake < 0.05) shake = 0;
    shakeOffset = shake == 0
        ? Offset.zero
        : Offset(
            (_visualRandom.nextDouble() * 2 - 1) * shake,
            (_visualRandom.nextDouble() * 2 - 1) * shake,
          );

    p1Squash *= decay;
    p2Squash *= decay;
    flash *= math.pow(0.02, dt).toDouble();

    for (var i = particles.length - 1; i >= 0; i--) {
      final p = particles[i];
      p.advance(dt);
      if (p.dead) particles.removeAt(i);
    }

    if (simulation.state.phase == PongPhase.rally) {
      ballTrail.add(simulation.state.ball.position);
      if (ballTrail.length > 12) ballTrail.removeAt(0);
    }
  }

  void _spawnBurst(Vec2 at, int count, double energy) {
    for (var i = 0; i < count; i++) {
      final angle = _visualRandom.nextDouble() * math.pi * 2;
      final speed = (120 + _visualRandom.nextDouble() * 520) * (0.4 + energy);
      particles.add(
        Particle(
          position: at,
          velocity: Vec2(math.cos(angle) * speed, math.sin(angle) * speed),
          life: 0.25 + _visualRandom.nextDouble() * 0.35,
          size: 5 + _visualRandom.nextDouble() * 9,
        ),
      );
    }
  }

  @override
  void onRemove() {
    hudRevision.dispose();
    super.onRemove();
  }
}

/// A speck of debris. Purely decorative — particles never touch the simulation.
class Particle {
  Particle({
    required this.position,
    required this.velocity,
    required this.life,
    required this.size,
  }) : maxLife = life;

  Vec2 position;
  Vec2 velocity;
  double life;
  final double maxLife;
  final double size;

  bool get dead => life <= 0;
  double get fade => (life / maxLife).clamp(0.0, 1.0);

  void advance(double dt) {
    position += velocity * dt;
    velocity = Vec2(velocity.x * 0.94, velocity.y * 0.94 + 900 * dt);
    life -= dt;
  }
}
