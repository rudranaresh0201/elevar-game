import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:game_core/game_core.dart';
import 'package:wallcricket_sim/wallcricket_sim.dart';

import 'game_config.dart';
import 'wallcricket_scene.dart';

/// Hosts the innings: the clock, the camera, the juice. No rules.
class WallCricketGame extends FlameGame {
  WallCricketGame({required this.config, required this.onComplete})
      : simulation = WallCricketSimulation(
          seed: config.seed,
          pace: config.pace,
          rules: config.rules,
        ) {
    runner = WallCricketRunner(simulation: simulation);
  }

  final WallCricketConfig config;
  final void Function(WallCricketOutcome outcome) onComplete;

  final WallCricketSimulation simulation;
  late final WallCricketRunner runner;
  final FixedLoop _loop = FixedLoop(tickHz: WallCricketRules.tickHz);

  /// Bumped when the scoreboard changes.
  final ValueNotifier<int> hudRevision = ValueNotifier<int>(0);

  /// The last thing worth shouting about, and how long ago.
  String bannerText = '';
  Color bannerColour = const Color(0xFFFFFFFF);
  double bannerAge = 99;

  /// Bumped per banner, so the same words twice still pop twice.
  int bannerSerial = 0;

  /// Outcomes of the balls in the current over, for the dots.
  final List<BallOutcome> thisOver = <BallOutcome>[];

  double fieldScale = 1;
  Offset fieldOrigin = Offset.zero;

  double get interpolation => _loop.alpha;

  // --- juice ---------------------------------------------------------------
  double shake = 0;
  Offset shakeOffset = Offset.zero;
  double flash = 0;

  /// Real seconds left to hold the frame on a clean strike. The simulation
  /// is not paused *inside* — it simply is not advanced — so the replay is
  /// untouched by it.
  double hitStop = 0;

  final List<CricketParticle> particles = <CricketParticle>[];
  final List<FloatingText> floaters = <FloatingText>[];
  final List<Vec2> ballTrail = <Vec2>[];

  /// Recent blade tips, for the swoosh.
  final List<({Vec2 tip, double speed})> batTrail =
      <({Vec2 tip, double speed})>[];

  /// 0..1, decaying, per stump — they fly on a wicket.
  double stumpsFly = 0;
  double wallGlow = 0;
  int? glowZone;

  Vec2? finger;

  final math.Random _visual = math.Random(5);
  bool _finished = false;

  @override
  Future<void> onLoad() async {
    await add(WallCricketScene(game: this));
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // Top of the screen is the scoreboard; the room letterboxes under it.
    const hudHeight = 118.0;
    final available = Size(size.x, size.y - hudHeight);
    final scale = math.min(
      available.width / Arena.width,
      available.height / Arena.height,
    );
    fieldScale = scale;
    fieldOrigin = Offset(
      (size.x - Arena.width * scale) / 2,
      hudHeight + (available.height - Arena.height * scale) / 2,
    );
  }

  Vec2 screenToArena(Offset screen) => Vec2(
        (screen.dx - fieldOrigin.dx) / fieldScale,
        (screen.dy - fieldOrigin.dy) / fieldScale,
      );

  Offset? _swingStart;

  /// How far the drag has to travel for a full swing, as a share of the
  /// screen's height. A third is a confident swipe with a thumb.
  static const double fullSwingDrag = 0.34;

  /// A finger has landed: the batter is in the backlift, ready.
  void beginSwing(Offset screen) {
    _swingStart = screen;
    finger = screenToArena(screen);
    runner.setSwing(0);
  }

  /// The drag so far becomes how far through the swing the bat is. Any
  /// direction counts — a swipe down, across or diagonally all swing the bat —
  /// so nobody has to learn which way is "right".
  void moveSwing(Offset screen) {
    final start = _swingStart;
    if (start == null) return;
    finger = screenToArena(screen);
    final distance = (screen - start).distance;
    runner.setSwing(clampD(distance / (size.y * fullSwingDrag), 0, 1));
  }

  void endSwing() {
    _swingStart = null;
    finger = null;
    runner.setSwing(null);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_finished) return;

    if (hitStop > 0) {
      hitStop -= dt;
      _advanceJuice(dt * 0.25);
      return;
    }

    _loop.advance(dt, (_) {
      runner.tick();
      _reactTo(simulation.pendingEvents);
    });
    _advanceJuice(dt);

    if (simulation.isComplete && !_finished) {
      _finished = true;
      final replay = runner.finishRecording();
      onComplete(
        WallCricketOutcome(
          result: simulation.buildResult(
            sessionToken: config.sessionToken,
            replay: replay,
          ),
          replay: replay,
          runs: simulation.runs,
          wickets: simulation.wickets,
          balls: simulation.ballsBowled,
          fours: simulation.fours,
          sixes: simulation.sixes,
          target: simulation.target,
        ),
      );
    }
  }

  void _reactTo(List<WallCricketEvent> events) {
    for (final event in events) {
      switch (event.type) {
        case WallCricketEventType.release:
          ballTrail.clear();
          unawaited(HapticFeedback.selectionClick());
        case WallCricketEventType.hit:
          final power = event.value;
          shake = math.max(shake, 4 + power * 16);
          _burst(event.at, (8 + power * 22).round(), power, const Color(0xFFFFF4C2));
          if (power > 0.55) {
            hitStop = 0.06;
            flash = 0.5;
            unawaited(HapticFeedback.heavyImpact());
          } else {
            unawaited(HapticFeedback.mediumImpact());
          }
        case WallCricketEventType.edge:
          shake = math.max(shake, 6);
          _burst(event.at, 8, 0.4, const Color(0xFFFFFFFF));
          floaters.add(FloatingText('EDGE', event.at, const Color(0xFFFF9F1C)));
          unawaited(HapticFeedback.lightImpact());
        case WallCricketEventType.bounce:
          _burst(event.at, 4, event.value * 0.5, const Color(0xFFC9A36B));
        case WallCricketEventType.wall:
          shake = math.max(shake, 1 + event.value * 6);
          _burst(event.at, 5, event.value, const Color(0xFFFFFFFF));
        case WallCricketEventType.scored:
          final runs = event.value.round();
          final outcome = simulation.lastOutcome!;
          glowZone = outcome.zone;
          wallGlow = 1;
          shake = math.max(shake, runs >= 6 ? 22 : 10);
          if (runs >= 6) flash = 0.7;
          _burst(event.at, runs >= 6 ? 40 : 20, 1, _runColour(runs));
          floaters.add(FloatingText('+$runs', event.at, _runColour(runs)));
          _banner(
            switch (runs) {
              >= 12 => 'HOT SIX! +$runs',
              >= 8 => 'HOT FOUR! +$runs',
              6 => 'SIX!',
              4 => 'FOUR!',
              _ => outcome.hot ? 'HOT ZONE +$runs' : '$runs RUN${runs == 1 ? '' : 'S'}',
            },
            _runColour(runs),
          );
          thisOver.add(outcome);
          unawaited(HapticFeedback.heavyImpact());
          hudRevision.value++;
        case WallCricketEventType.dot:
          _banner('DOT BALL', const Color(0xFF8A94A6));
          thisOver.add(const BallOutcome.dot());
          hudRevision.value++;
        case WallCricketEventType.out:
          stumpsFly = 1;
          shake = 26;
          flash = 0.8;
          _burst(
            const Vec2((Arena.stumpsLeft + Arena.stumpsRight) / 2,
                Arena.stumpsTop + 10),
            30,
            1,
            const Color(0xFFF2D16B),
          );
          final caught = simulation.lastOutcome?.caught ?? false;
          if (caught) stumpsFly = 0;
          _banner(caught ? 'CAUGHT BEHIND!' : 'BOWLED!', const Color(0xFFFF2B2B));
          thisOver.add(const BallOutcome.out());
          unawaited(HapticFeedback.vibrate());
          hudRevision.value++;
        case WallCricketEventType.overComplete:
          thisOver.clear();
          _banner('NEW OVER · HOT ZONE MOVED', const Color(0xFFFFF200));
          hudRevision.value++;
        case WallCricketEventType.complete:
          hudRevision.value++;
      }
    }
  }

  static Color _runColour(int runs) => switch (runs) {
        >= 6 => const Color(0xFFFF3DA6),
        4 => const Color(0xFF29C7F0),
        2 => const Color(0xFF27D6A2),
        _ => const Color(0xFFFFF200),
      };

  void _banner(String text, Color colour) {
    bannerText = text;
    bannerColour = colour;
    bannerAge = 0;
    bannerSerial++;
    hudRevision.value++;
  }

  void _advanceJuice(double dt) {
    final decay = math.pow(0.002, dt).toDouble();
    shake *= decay;
    if (shake < 0.05) shake = 0;
    final angle = _visual.nextDouble() * math.pi * 2;
    shakeOffset = Offset(math.cos(angle) * shake, math.sin(angle) * shake);
    flash *= math.pow(0.01, dt).toDouble();
    stumpsFly = stumpsFly > 0 ? math.max(0, stumpsFly - dt * 0.9) : 0;
    wallGlow *= math.pow(0.15, dt).toDouble();
    if (bannerAge < 99) {
      final before = bannerAge;
      bannerAge += dt;
      if (before < 1.3 && bannerAge >= 1.3) hudRevision.value++;
    }

    for (var i = particles.length - 1; i >= 0; i--) {
      particles[i].advance(dt);
      if (particles[i].dead) particles.removeAt(i);
    }
    for (var i = floaters.length - 1; i >= 0; i--) {
      floaters[i].age += dt;
      if (floaters[i].age > 1.1) floaters.removeAt(i);
    }

    if (simulation.ballVisible) {
      ballTrail.add(simulation.ballPosition);
      if (ballTrail.length > 10) ballTrail.removeAt(0);
    }
    batTrail.add((tip: simulation.batTip, speed: simulation.batTipSpeed));
    if (batTrail.length > 6) batTrail.removeAt(0);
  }

  void _burst(Vec2 at, int count, double energy, Color colour) {
    for (var i = 0; i < count; i++) {
      final angle = _visual.nextDouble() * math.pi * 2;
      final speed = (180 + _visual.nextDouble() * 900) * (0.35 + energy);
      particles.add(
        CricketParticle(
          position: at,
          velocity: Vec2(math.cos(angle) * speed, math.sin(angle) * speed),
          life: 0.3 + _visual.nextDouble() * 0.4,
          size: 5 + _visual.nextDouble() * 9,
          colour: colour,
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

class CricketParticle {
  CricketParticle({
    required this.position,
    required this.velocity,
    required this.life,
    required this.size,
    required this.colour,
  }) : maxLife = life;

  Vec2 position;
  Vec2 velocity;
  double life;
  final double maxLife;
  final double size;
  final Color colour;

  bool get dead => life <= 0;
  double get fade => (life / maxLife).clamp(0.0, 1.0);

  void advance(double dt) {
    position += velocity * dt;
    velocity = Vec2(velocity.x * 0.92, velocity.y * 0.92 + 1600 * dt);
    life -= dt;
  }
}

class FloatingText {
  FloatingText(this.text, this.at, this.colour);

  final String text;
  final Vec2 at;
  final Color colour;
  double age = 0;
}
