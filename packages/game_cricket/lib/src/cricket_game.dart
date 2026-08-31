import 'dart:async';
import 'dart:math' as math;

import 'package:cricket_sim/cricket_sim.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:game_core/game_core.dart';

import 'camera.dart';
import 'cricket_scene.dart';
import 'game_config.dart';

/// One piece of celebration debris.
class Spark {
  Spark({
    required this.position,
    required this.velocity,
    required this.life,
    required this.hue,
  }) : age = 0;

  Vec2 position;
  Vec2 velocity;
  final double life;

  /// 0..1 — picked at spawn so a burst is many colours rather than one.
  final double hue;

  double age;

  double get t => age / life;
  bool get dead => age >= life;

  void advance(double dt) {
    age += dt;
    position += velocity * dt;
    velocity = Vec2(velocity.x * 0.94, velocity.y * 0.94 + 340 * dt);
  }
}

/// Hosts the cricket simulation and turns it into something to look at.
///
/// The split is the same one the other two games use and is strict: this class
/// owns the clock, the layout, the sparks and the haptics, and owns *no* rules.
/// It advances the simulation in fixed ticks and reads the events that come
/// back out.
class CricketGame extends FlameGame {
  CricketGame({required this.config, required this.onComplete}) {
    simulation = CricketSimulation(
      seed: config.seed,
      mode: config.mode,
      botDifficulty: config.botDifficulty,
      rules: config.rules,
      fieldSetting: config.fieldSetting,
    );
    runner = CricketMatchRunner(simulation: simulation);
  }

  final CricketConfig config;
  final void Function(CricketOutcome outcome) onComplete;

  late final CricketSimulation simulation;
  late final CricketMatchRunner runner;

  final FixedLoop _loop = FixedLoop(tickHz: 120);

  /// Bumped whenever anything the HUD shows changes, so it rebuilds on those
  /// rather than on every frame.
  final ValueNotifier<int> hudRevision = ValueNotifier<int>(0);

  // --- layout --------------------------------------------------------------

  /// Height of the control band reserved at the bottom of the screen.
  ///
  /// Reserved *first*, with the ground letterboxed into what is left — the same
  /// rule racing follows, and for the same reason: the swipe pad must never sit
  /// on top of the part of the ground the player is trying to watch.
  double bandHeight = 190;

  /// The view from behind the stumps.
  ///
  /// Rebuilt on resize and whenever the player swaps ends, because batting and
  /// bowling are watched from opposite ends of the pitch. See [PitchCamera] for
  /// why this exists at all — the short version is that the simulation's own
  /// top-down layout is correct and unplayable to look at.
  PitchCamera pitchCamera = PitchCamera.unset;

  /// The last size handed to [onGameResize], so the camera can be rebuilt when
  /// the role changes without waiting for another resize.
  Vector2 _lastSize = Vector2(390, 844);

  /// Which role the camera was last built for.
  Role _cameraRole = Role.batting;

  /// Fraction of a tick already elapsed, for interpolating between simulation
  /// steps. Without it the ball visibly steps at 120 Hz against a 60 Hz display
  /// instead of gliding.
  double get interpolation => _loop.alpha;

  // --- juice ---------------------------------------------------------------

  double shake = 0;
  Offset shakeOffset = Offset.zero;
  double flash = 0;
  final List<Spark> sparks = <Spark>[];

  /// The banner currently up, and how long it has left.
  String? bannerText;
  double bannerTicks = 0;

  final math.Random _visualRandom = math.Random(23);
  bool _finished = false;

  // --- what the HUD reads --------------------------------------------------

  int _boundaries = 0;
  int get boundaries => _boundaries;

  /// Where the ball is heading across the crease, normalised to the bat's own
  /// reach, or null when there is nothing on its way.
  ///
  /// Projected from the ball's *current* line, which before it pitches is the
  /// line it looks like it is on and after it pitches is the line it is
  /// actually on. That is exactly the information a batter has, and it is why
  /// a ball that deviates is still worth bowling: the marker moves at the
  /// bounce, and by then the blade may not have time to follow it.
  ///
  /// Without something showing this, batting on a phone is a guess — the ball
  /// is a few pixels wide at the bowler's end, and a player who cannot tell
  /// where it is going has no way to get better.
  double? get ballLineAcrossCrease {
    final state = simulation.state;
    if (state.phase != CricketPhase.delivery) return null;
    final ball = state.ball;
    if (ball.reachedBat) return null;
    final vy = ball.velocity.y;
    if (vy.abs() < 1e-6) return null;

    final remaining = CricketField.batPlaneY - ball.position.y;
    if (remaining <= 0) return null;
    final crossX = ball.position.x + ball.velocity.x * (remaining / vy);

    return clampD(
      (crossX - CricketField.pitchCentreX) / CricketField.batReachX * 0.5 + 0.5,
      0,
      1,
    );
  }

  /// Which role the player on this device is performing right now.
  Role get role => config.isTwoHuman
      ? (simulation.state.current.batting == CricketSide.p1
          ? Role.batting
          : Role.bowling)
      : simulation.humanRole;

  @override
  Future<void> onLoad() async {
    await add(CricketScene(game: this));
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);

    // Proportional to the screen, floored so it stays thumb-sized on a small
    // phone and capped so it does not eat a tablet.
    // Taller than it was: the batting band now carries the three shot
    // buttons under the swipe pad, and a shot you cannot reach is a shot
    // nobody plays.
    bandHeight = clampD(size.y * 0.29, 208, 340);

    _lastSize = size.clone();
    _rebuildCamera();
  }

  /// Builds the camera for the current screen and the current role.
  void _rebuildCamera() {
    _cameraRole = role;
    pitchCamera = PitchCamera.forScreen(
      width: _lastSize.x,
      // The band is subtracted first, so no part of the ground can end up
      // under a thumb — the same rule racing follows.
      height: _lastSize.y - bandHeight,
      role: _cameraRole,
    );
  }

  // --- input ---------------------------------------------------------------

  void setBattingInput(CricketInput input) => runner.setStrikerInput(input);

  void setBowlingInput(CricketInput input) => runner.setBowlerInput(input);

  // --- the loop ------------------------------------------------------------

  @override
  void update(double dt) {
    super.update(dt);
    if (_finished) return;

    final before = simulation.state.phase;

    _loop.advance(dt, (_) {
      runner.tick();
      _reactTo(simulation.pendingEvents);
    });

    // Batting and bowling are watched from opposite ends, so the camera swaps
    // with the innings.
    if (role != _cameraRole) _rebuildCamera();

    if (simulation.state.phase != before) hudRevision.value++;
    // The timing ring and the run-up both animate every frame.
    if (simulation.state.phase == CricketPhase.delivery ||
        simulation.state.phase == CricketPhase.runUp) {
      hudRevision.value++;
    }

    _advanceJuice(dt);

    if (simulation.isComplete && !_finished) {
      _finished = true;
      final mine = simulation.state.first.batting == CricketSide.p1
          ? simulation.state.first
          : simulation.state.second!;
      // Sealed once. `finishRecording` happens to be idempotent today, but
      // calling it twice for the same match is the kind of thing that stops
      // being true quietly and takes replay verification with it.
      final replay = runner.finishRecording();
      onComplete(
        CricketOutcome(
          result: simulation.buildResult(
            sessionToken: config.sessionToken,
            replay: replay,
          ),
          replay: replay,
          runs: mine.runs,
          wickets: mine.wickets,
          balls: mine.balls,
          boundaries: _boundaries,
        ),
      );
    }
  }

  /// Turns simulation events into things you can see and feel.
  ///
  /// This is where most of the game's personality lives. A six that produces
  /// the same small tick as a dot ball is a six nobody remembers hitting.
  void _reactTo(List<CricketEvent> events) {
    for (final event in events) {
      switch (event.type) {
        case CricketEventType.runUpStart:
          hudRevision.value++;

        case CricketEventType.release:
          unawaited(HapticFeedback.selectionClick());

        case CricketEventType.pitched:
          if (event.at != null) _burst(event.at!, 4, 0.3);

        case CricketEventType.middled:
          shake = math.max(shake, 7);
          if (event.at != null) _burst(event.at!, 10, 0.8);
          unawaited(HapticFeedback.mediumImpact());

        case CricketEventType.edged:
          shake = math.max(shake, 3);
          if (event.at != null) _burst(event.at!, 5, 0.4);
          unawaited(HapticFeedback.lightImpact());

        case CricketEventType.playedAndMissed:
          unawaited(HapticFeedback.selectionClick());

        case CricketEventType.fielded:
          hudRevision.value++;

        case CricketEventType.four:
          _boundaries++;
          _banner('FOUR');
          shake = math.max(shake, 11);
          flash = math.max(flash, 0.45);
          if (event.at != null) _burst(event.at!, 22, 1);
          unawaited(HapticFeedback.mediumImpact());

        case CricketEventType.six:
          _boundaries++;
          _banner('SIX!');
          shake = math.max(shake, 18);
          flash = math.max(flash, 0.8);
          if (event.at != null) _burst(event.at!, 40, 1.4);
          unawaited(HapticFeedback.heavyImpact());

        case CricketEventType.runsScored:
          hudRevision.value++;

        case CricketEventType.wicket:
          _banner(event.text ?? 'OUT');
          shake = math.max(shake, 15);
          flash = math.max(flash, 0.6);
          if (event.at != null) _burst(event.at!, 18, 1);
          unawaited(HapticFeedback.heavyImpact());

        case CricketEventType.overComplete:
          _banner('OVER ${event.value}');

        case CricketEventType.inningsComplete:
          _banner('INNINGS: ${event.value}');
          hudRevision.value++;

        case CricketEventType.matchComplete:
          flash = 1;
          hudRevision.value++;
          unawaited(HapticFeedback.heavyImpact());
      }
    }
  }

  void _banner(String text) {
    bannerText = text;
    bannerTicks = 1.35;
    hudRevision.value++;
  }

  void _advanceJuice(double dt) {
    // Frame-rate independent decay, so the shake feels the same at 60 and 120.
    final decay = math.pow(0.0012, dt).toDouble();
    shake *= decay;
    if (shake < 0.05) shake = 0;
    shakeOffset = shake == 0
        ? Offset.zero
        : Offset(
            (_visualRandom.nextDouble() * 2 - 1) * shake,
            (_visualRandom.nextDouble() * 2 - 1) * shake,
          );

    flash *= math.pow(0.02, dt).toDouble();

    if (bannerTicks > 0) {
      bannerTicks -= dt;
      if (bannerTicks <= 0) {
        bannerText = null;
        hudRevision.value++;
      }
    }

    for (var i = sparks.length - 1; i >= 0; i--) {
      final spark = sparks[i];
      spark.advance(dt);
      if (spark.dead) sparks.removeAt(i);
    }
  }

  /// A burst of debris at [at]. Uses the visual random, never the simulation's
  /// — nothing here may influence the match.
  void _burst(Vec2 at, int count, double energy) {
    for (var i = 0; i < count; i++) {
      // A direction without trigonometry: a point in the square, normalised.
      // The simulation's determinism rules do not bind here, but reusing the
      // same trick keeps one idiom in the codebase rather than two.
      final raw = Vec2(
        _visualRandom.nextDouble() * 2 - 1,
        _visualRandom.nextDouble() * 2 - 1,
      );
      final direction =
          raw.lengthSquared < 1e-6 ? const Vec2(1, 0) : raw.normalized;
      final speed = (60 + _visualRandom.nextDouble() * 260) * energy;
      sparks.add(
        Spark(
          position: at,
          velocity: direction * speed,
          life: 0.35 + _visualRandom.nextDouble() * 0.5,
          hue: _visualRandom.nextDouble(),
        ),
      );
    }
    // A burst that never ends is a frame-rate bug waiting to happen.
    while (sparks.length > 260) {
      sparks.removeAt(0);
    }
  }

  @override
  void onRemove() {
    hudRevision.dispose();
    super.onRemove();
  }
}
