import 'dart:async';
import 'dart:math' as math;

import 'package:cricket_sim/cricket_sim.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:game_core/game_core.dart';

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

  double fieldScale = 1;
  Offset fieldOrigin = Offset.zero;

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

  /// True while the ball is close enough that a swing would connect.
  ///
  /// Drives the timing ring. Without something showing this, batting is a
  /// guess — and a player who cannot tell whether they were early or late has
  /// no way to get better, which is the difference between a game people come
  /// back to and one they bounce off.
  bool get inSwingWindow {
    final state = simulation.state;
    if (state.phase != CricketPhase.delivery) return false;
    final ball = state.ball;
    final away = (ball.idealContactTick - simulation.tick).abs();
    return away <= CricketField.contactWindowTicks;
  }

  /// -1 for far too early through to 1 for far too late, 0 on the money.
  double get swingOffset {
    final ball = simulation.state.ball;
    final delta = simulation.tick - ball.idealContactTick;
    return clampD(delta / CricketField.contactWindowTicks.toDouble(), -1, 1);
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
    bandHeight = clampD(size.y * 0.24, 168, 300);

    final usableHeight = size.y - bandHeight;

    // Fit the **ground**, not the whole simulation field.
    //
    // The field is 1000 x 1500 but the rope only encloses the middle of it, so
    // letterboxing the field left roughly a third of the screen as empty grass
    // above and below the oval — the game looked like it was being viewed from
    // too far away. Fitting the ground's bounding box instead fills the space
    // with the part anybody is actually looking at.
    const groundWidth = CricketField.groundRadiusX * 2;
    const groundHeight = CricketField.groundRadiusY * 2;
    const margin = 14.0;

    final scale = math.min(
      (size.x - margin * 2) / groundWidth,
      (usableHeight - margin * 2) / groundHeight,
    );
    fieldScale = scale;

    // Place the origin so the ground's centre lands in the middle of the space
    // left over above the band.
    fieldOrigin = Offset(
      size.x / 2 - CricketField.groundCentreX * scale,
      usableHeight / 2 - CricketField.groundCentreY * scale,
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
