import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:game_core/game_core.dart';
import 'package:penalty_sim/penalty_sim.dart';

import 'camera.dart';
import 'game_config.dart';
import 'penalty_scene.dart';

/// A swipe in progress, in screen space.
class Swipe {
  Swipe(Offset start, double time) {
    points.add((at: start, time: time));
  }

  final List<({Offset at, double time})> points = <({Offset at, double time})>[];

  Offset get start => points.first.at;
  Offset get end => points.last.at;
}

/// Hosts the shootout: clock, camera, gestures, juice. No rules.
class PenaltyGame extends FlameGame {
  PenaltyGame({required this.config, required this.onComplete})
      : simulation = PenaltySimulation(
          seed: config.seed,
          mode: config.mode,
          botDifficulty: config.botDifficulty,
        ) {
    runner = PenaltyRunner(simulation: simulation);
  }

  final PenaltyConfig config;
  final void Function(PenaltyOutcome outcome) onComplete;
  final PenaltySimulation simulation;
  late final PenaltyRunner runner;
  final FixedLoop _loop = FixedLoop(tickHz: PenaltySimulation.tickHz);

  final ValueNotifier<int> hudRevision = ValueNotifier<int>(0);

  PenaltyCamera camera3d = PenaltyCamera(const Size(390, 844));

  double get interpolation => _loop.alpha;
  double _clock = 0;

  // --- gestures ------------------------------------------------------------
  Swipe? swipe;

  /// Where the last shot was aimed, for the reticle, and how long ago.
  GoalPoint? aimMarker;
  double aimMarkerAge = 99;

  /// Where the human keeper asked to dive, for the glove marker.
  GoalPoint? diveMarker;

  /// Shown when a swipe was too short or went the wrong way.
  double swipeHintAge = 99;

  // --- juice ---------------------------------------------------------------
  double shake = 0;
  Offset shakeOffset = Offset.zero;
  double flash = 0;
  double netBulge = 0;
  GoalPoint? bulgeAt;
  final List<Confetti> confetti = <Confetti>[];
  final List<Vec3> ballTrail = <Vec3>[];
  String bannerText = '';
  Color bannerColour = const Color(0xFFFFFFFF);
  double bannerAge = 99;

  /// Bumped per banner, so the same words twice still pop twice.
  int bannerSerial = 0;

  final math.Random _visual = math.Random(3);
  bool _finished = false;
  int saves = 0;

  @override
  Future<void> onLoad() async {
    await add(PenaltyScene(game: this));
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    camera3d = PenaltyCamera(Size(size.x, size.y));
  }

  Offset get ballScreen => camera3d.at(0, 0, Goal.spotZ);
  double get goalBaseScreenY => camera3d.at(0, 0, 0).dy;

  // --- input ---------------------------------------------------------------

  /// Which role a touch at [at] should play, or null if it plays none.
  ///
  /// With two people on one phone both roles can be live at once, so the
  /// screen is split at a line between the goal and the ball: below it is the
  /// kicker's, above it the keeper's.
  PenaltyRole? roleFor(Offset at) {
    final split = (goalBaseScreenY + ballScreen.dy) / 2;
    if (at.dy >= split && simulation.acceptsShot) return PenaltyRole.shooter;
    if (at.dy < split && simulation.acceptsDive) return PenaltyRole.keeper;
    // Against the bot there is only ever one thing you can do, so anywhere
    // on the screen does it.
    if (!simulation.isTwoHuman) {
      if (simulation.acceptsShot) return PenaltyRole.shooter;
      if (simulation.acceptsDive) return PenaltyRole.keeper;
    }
    return null;
  }

  void beginSwipe(Offset at) => swipe = Swipe(at, _clock);

  void moveSwipe(Offset at) => swipe?.points.add((at: at, time: _clock));

  void endSwipe(Offset at) {
    final live = swipe;
    swipe = null;
    if (live == null || !simulation.acceptsShot) return;
    live.points.add((at: at, time: _clock));
    final shot = shotFromSwipe(live);
    if (shot == null) {
      swipeHintAge = 0;
      hudRevision.value++;
      return;
    }
    aimMarker = shot.target;
    aimMarkerAge = 0;
    runner.shoot(shot);
  }

  void cancelSwipe() => swipe = null;

  /// Turns a finger's path into a shot.
  ///
  /// * **Where** is where the swipe points: its end, pushed on up the line
  ///   into the goal mouth if the finger stopped short.
  /// * **How hard** is how fast the finger moved.
  /// * **Bend** is how far the path bowed off its own chord — a swipe that
  ///   arcs right sends a ball that starts right and swings back.
  ShotParams? shotFromSwipe(Swipe s) {
    final chord = s.end - s.start;
    final length = chord.distance;
    if (length < 36 || chord.dy > -24) return null;

    final seconds = math.max(0.04, s.points.last.time - s.points.first.time);
    final speed = length / seconds;
    final reference = camera3d.width;
    final power = clampD((speed / reference - 1.1) / 5.5, 0, 1);

    var target = s.end;
    final goalBase = goalBaseScreenY;
    if (target.dy > goalBase - 10) {
      final rise = s.start.dy - (goalBase - 10);
      final k = rise / -chord.dy;
      target = s.start + chord * math.max(1, k);
    }
    final point = camera3d.unproject(target);

    var deviation = 0.0;
    final normal = Offset(-chord.dy / length, chord.dx / length);
    for (final p in s.points) {
      final d = (p.at - s.start).dx * normal.dx + (p.at - s.start).dy * normal.dy;
      if (d.abs() > deviation.abs()) deviation = d;
    }
    final curve = clampD(-(deviation / length) * 4, -1, 1);

    return ShotParams(
      target: GoalPoint(
        clampD(point.x, -Goal.aimHalfWidth, Goal.aimHalfWidth),
        clampD(point.y, 0.05, Goal.aimHeight),
      ),
      power: power,
      curve: curve.abs() < 0.12 ? 0 : curve,
    );
  }

  void tapDive(Offset at) {
    if (!simulation.acceptsDive) return;
    final point = camera3d.unproject(at, planeZ: Goal.keeperZ);
    diveMarker = point;
    runner.dive(point);
    unawaited(HapticFeedback.selectionClick());
  }

  // --- loop ----------------------------------------------------------------

  @override
  void update(double dt) {
    super.update(dt);
    _clock += dt;
    if (_finished) return;

    // A shot at a human keeper plays at 0.6x in real time. The
    // simulation still runs the same ticks — only the wall clock stretches —
    // so it changes how it feels, not what the replay says happened.
    final slow = simulation.phase == PenaltyPhase.flight &&
        simulation.keeperIsHuman &&
        !simulation.isTwoHuman;
    _loop.advance(slow ? dt * 0.6 : dt, (_) {
      final before = simulation.shooter;
      runner.tick();
      _react(simulation.pendingEvents);
      if (simulation.shooter != before) {
        diveMarker = null;
        ballTrail.clear();
        hudRevision.value++;
      }
    });
    _advanceJuice(dt);

    if (simulation.isComplete) {
      _finished = true;
      final replay = runner.finishRecording();
      onComplete(PenaltyOutcome(
        result: simulation.buildResult(
          sessionToken: config.sessionToken,
          replay: replay,
        ),
        replay: replay,
        kicksEach: simulation.p1Kicks.length,
        saves: saves,
      ));
    }
  }

  void _react(List<PenaltyEvent> events) {
    for (final e in events) {
      switch (e.type) {
        case PenaltyEventType.kick:
          shake = math.max(shake, 3 + e.value * 6);
          ballTrail.clear();
          unawaited(HapticFeedback.mediumImpact());
          hudRevision.value++;
        case PenaltyEventType.keeperDive:
          hudRevision.value++;
        case PenaltyEventType.goal:
          netBulge = 1;
          bulgeAt = GoalPoint(e.at.x, e.at.y);
          shake = 18;
          flash = 0.6;
          _confetti(simulation.shooter == PenaltySide.p1
              ? const Color(0xFFFF2B2B)
              : const Color(0xFF29B6F0));
          _banner('GOAL!', const Color(0xFF3DFF6E));
          unawaited(HapticFeedback.heavyImpact());
        case PenaltyEventType.save:
          shake = 14;
          if (simulation.shooter == PenaltySide.p2) saves++;
          _banner('SAVED!', const Color(0xFFFFF200));
          unawaited(HapticFeedback.heavyImpact());
        case PenaltyEventType.post:
          shake = 20;
          _banner('OFF THE POST!', const Color(0xFFFF9F1C));
          unawaited(HapticFeedback.vibrate());
        case PenaltyEventType.missed:
          _banner('MISSED!', const Color(0xFFFF2B2B));
          unawaited(HapticFeedback.lightImpact());
        case PenaltyEventType.bounce:
          shake = math.max(shake, e.value * 3);
        case PenaltyEventType.complete:
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

  void _confetti(Color team) {
    final origin = camera3d.at(0, 1.4, 0);
    const palette = <Color>[
      Color(0xFFFFF200),
      Color(0xFFFFFFFF),
      Color(0xFF3DFF6E),
      Color(0xFFFF3DA6),
    ];
    for (var i = 0; i < 90; i++) {
      final angle = -math.pi / 2 + (_visual.nextDouble() - 0.5) * 2.4;
      final speed = 300 + _visual.nextDouble() * 700;
      confetti.add(Confetti(
        position: origin,
        velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
        colour: i.isEven ? team : palette[i % palette.length],
        spin: _visual.nextDouble() * 10,
        life: 1.2 + _visual.nextDouble() * 0.8,
      ));
    }
  }

  void _advanceJuice(double dt) {
    shake *= math.pow(0.003, dt).toDouble();
    if (shake < 0.05) shake = 0;
    final a = _visual.nextDouble() * math.pi * 2;
    shakeOffset = Offset(math.cos(a) * shake, math.sin(a) * shake);
    flash *= math.pow(0.02, dt).toDouble();
    netBulge *= math.pow(0.08, dt).toDouble();
    if (bannerAge < 99) {
      final before = bannerAge;
      bannerAge += dt;
      if (before < 1.4 && bannerAge >= 1.4) hudRevision.value++;
    }
    if (swipeHintAge < 99) {
      final before = swipeHintAge;
      swipeHintAge += dt;
      if (before < 1.5 && swipeHintAge >= 1.5) hudRevision.value++;
    }
    aimMarkerAge += dt;
    for (var i = confetti.length - 1; i >= 0; i--) {
      confetti[i].advance(dt);
      if (confetti[i].life <= 0) confetti.removeAt(i);
    }
    if (simulation.phase == PenaltyPhase.flight ||
        simulation.phase == PenaltyPhase.outcome) {
      ballTrail.add(simulation.ball);
      if (ballTrail.length > 12) ballTrail.removeAt(0);
    }
  }

  @override
  void onRemove() {
    hudRevision.dispose();
    super.onRemove();
  }
}

enum PenaltyRole { shooter, keeper }

class Confetti {
  Confetti({
    required this.position,
    required this.velocity,
    required this.colour,
    required this.spin,
    required this.life,
  });

  Offset position;
  Offset velocity;
  final Color colour;
  double spin;
  double life;

  void advance(double dt) {
    position += velocity * dt;
    velocity = Offset(velocity.dx * 0.97, velocity.dy * 0.97 + 900 * dt);
    spin += dt * 8;
    life -= dt;
  }
}
