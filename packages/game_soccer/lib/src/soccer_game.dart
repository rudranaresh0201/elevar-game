import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:game_core/game_core.dart';
import 'package:soccer_sim/soccer_sim.dart';

import 'game_config.dart';
import 'soccer_scene.dart';

/// Hosts the simulation and turns it into something to look at.
///
/// The split is strict: this class owns the clock, the camera, the particles
/// and the haptics, and owns *no* rules. It advances the simulation in fixed
/// ticks and reads the events that come back out.
class SoccerGame extends FlameGame {
  SoccerGame({required this.config, required this.onComplete})
      // Built here rather than in onLoad: Flame's onLoad is async and the
      // engine can call update() before that future resolves, which would
      // leave the simulation briefly null on the first frame. Nothing about
      // constructing it needs to be async.
      : simulation = SoccerSimulation(
          seed: config.seed,
          mode: config.mode,
          botDifficulty: config.botDifficulty,
          rules: config.rules,
        ) {
    runner = SoccerMatchRunner(simulation: simulation);
  }

  final SoccerConfig config;
  final void Function(SoccerOutcome outcome) onComplete;

  final SoccerSimulation simulation;
  late final SoccerMatchRunner runner;

  final FixedLoop _loop = FixedLoop(tickHz: 120);

  /// The live drag. Written through [beginGesture] and friends, read once per
  /// tick by [feedInput].
  SoccerGesture? _gesture;

  SoccerGesture? get gesture => _gesture;

  /// True once the simulation has confirmed it is holding a disc for the
  /// current gesture. See [_retireSpentGesture] for why it has to be tracked.
  bool _gestureAcknowledged = false;

  /// Ticks since the finger came off, for a released gesture the simulation
  /// never acknowledged.
  int _ticksSinceRelease = 0;

  /// How long a released-but-unacknowledged gesture is kept alive.
  ///
  /// A grab is only registered on a replay sample boundary, up to six ticks
  /// after the finger lands, so a flick taken in under 50 ms would otherwise be
  /// thrown away before the simulation ever saw it. Twenty-four ticks is four
  /// boundaries: long enough that no real flick is lost, short enough that a
  /// tap on empty grass stops being sent well within the same turn.
  static const int _releaseGraceTicks = 24;

  /// Bumped whenever anything the HUD displays changes, so it can rebuild
  /// without rebuilding every frame.
  ///
  /// This tracks the match *phase* and whose turn it is as well as the score.
  /// In a turn-based game the phase is most of what the HUD says, and a HUD
  /// that only rebuilt on goals would leave "YOUR TURN" painted over the
  /// opponent's.
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
  double flash = 0;

  /// 0..1 per body, decaying. Drives the squash on a struck disc.
  final Map<int, double> impact = <int, double>{};
  final List<SoccerParticle> particles = <SoccerParticle>[];
  final List<Vec2> ballTrail = <Vec2>[];

  /// Counts up while the ball is in the net, for the celebration.
  double goalPulse = 0;

  final math.Random _visualRandom = math.Random(11);
  bool _finished = false;
  SoccerPhase _hudPhase = SoccerPhase.kickoff;
  SoccerSide _hudTurn = SoccerSide.p1;
  int _hudSecondsLeft = -1;

  @override
  Future<void> onLoad() async {
    await add(SoccerScene(game: this));
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // Letterbox the fixed 1000x1800 field: the match must play identically on
    // every screen, so the field never reshapes to fit the device.
    final scale = math.min(
      size.x / SoccerField.width,
      size.y / SoccerField.height,
    );
    fieldScale = scale;
    fieldOrigin = Offset(
      (size.x - SoccerField.width * scale) / 2,
      (size.y - SoccerField.height * scale) / 2,
    );
  }

  /// Converts a screen point into field units.
  Vec2 screenToField(Offset screen) => Vec2(
        (screen.dx - fieldOrigin.dx) / fieldScale,
        (screen.dy - fieldOrigin.dy) / fieldScale,
      );

  /// Converts a screen *displacement* into field units. Not the same call as
  /// [screenToField] — a delta must not pick up the letterbox origin.
  Vec2 screenDeltaToField(Offset delta) =>
      Vec2(delta.dx / fieldScale, delta.dy / fieldScale);

  /// True when the player is allowed to touch the pitch right now.
  bool get acceptsTouch =>
      simulation.state.acceptsInput && !simulation.botToPlay;

  // --- input ---------------------------------------------------------------

  /// Translates the live gesture into the simulation's three channels.
  ///
  /// Called before every tick rather than on every pointer event, and that is
  /// the whole point. The channels mean different things depending on whether
  /// a disc is held, and the simulation only registers a grab on a replay
  /// sample boundary — up to 50 ms after the finger landed. Feeding the pull
  /// vector before that boundary would have the simulation read it as a finger
  /// position and grab the wrong disc, or none.
  ///
  /// So the rule here is: keep sending the grab until the simulation says it
  /// has the disc, then send pulls, and hold a released gesture alive until
  /// the simulation has consumed it. A quick flick — down, drag and up inside
  /// three frames — survives all of that, which the earlier version did not.
  void feedInput() {
    final live = _gesture;
    if (live == null) {
      runner.setInput(const SoccerInput());
      return;
    }

    if (!simulation.state.aim.isHolding) {
      runner.setInput(SoccerInput.grab(screenToField(live.grabScreen)));
      return;
    }

    _gestureAcknowledged = true;
    runner.setInput(
      SoccerInput.pull(
        screenDeltaToField(live.currentScreen - live.grabScreen),
        stillDown: !live.released,
      ),
    );
  }

  // --- the gesture, as the touch layer drives it ---------------------------

  /// A finger has landed. Ignored unless the pitch is actually accepting
  /// touches, so a stray tap during the bot's turn cannot leave a stale
  /// gesture waiting to fire on yours.
  void beginGesture(Offset at) {
    if (!acceptsTouch) return;
    _gesture = SoccerGesture(grabScreen: at, currentScreen: at);
    _gestureAcknowledged = false;
    _ticksSinceRelease = 0;
  }

  void updateGesture(Offset at) {
    final live = _gesture;
    if (live == null || live.released) return;
    _gesture = live.movedTo(at);
  }

  /// The finger has come off. The gesture is *marked* released rather than
  /// dropped — see [_releaseGraceTicks].
  void releaseGesture(Offset at) {
    final live = _gesture;
    if (live == null || live.released) return;
    _gesture = live.movedTo(at).lifted;
    _ticksSinceRelease = 0;
  }

  /// The system took the touch away — a notification shade, an incoming call.
  /// Dropping it outright means the turn is still there when the player comes
  /// back, rather than having been spent on a flick they did not choose.
  void cancelGesture() {
    _gesture = null;
    _gestureAcknowledged = false;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_finished) return;

    feedInput();
    _loop.advance(dt, (_) {
      runner.tick();
      _reactTo(simulation.pendingEvents);
      // Re-fed inside the loop as well: a frame that runs several ticks would
      // otherwise replay one stale gesture into all of them, and a release
      // consumed on the first tick would be re-sent on the rest.
      feedInput();
    });

    _retireSpentGesture();
    _refreshHud();
    _advanceJuice(dt);

    if (simulation.isComplete && !_finished) {
      _finished = true;
      // Seal the recording exactly once — finishing drains the buffer.
      final replay = runner.finishRecording();
      onComplete(
        SoccerOutcome(
          result: simulation.buildResult(
            sessionToken: config.sessionToken,
            replay: replay,
          ),
          replay: replay,
        ),
      );
    }
  }

  /// Drops a released gesture once the simulation has acted on it — either by
  /// flicking, or by cancelling a drag that was too short.
  ///
  /// The acknowledgement flag is the whole subtlety. Retiring on
  /// `!aim.isHolding` alone looks right and silently eats every fast flick:
  /// immediately after the finger lifts the simulation has usually not reached
  /// a sample boundary yet, so it is not holding anything *and never was*, and
  /// the shot is dropped before it can be taken.
  void _retireSpentGesture() {
    final live = _gesture;
    if (live == null || !live.released) return;
    _ticksSinceRelease++;

    if (_gestureAcknowledged && !simulation.state.aim.isHolding) {
      _gesture = null;
      _gestureAcknowledged = false;
      return;
    }
    // Never acknowledged: the grab missed every disc, or the turn ended
    // underneath it. Give up rather than holding a phantom finger down.
    if (_ticksSinceRelease > _releaseGraceTicks) {
      _gesture = null;
      _gestureAcknowledged = false;
    }
  }

  void _refreshHud() {
    final state = simulation.state;
    final seconds = state.phase == SoccerPhase.aiming
        ? state.aimTicksLeft ~/ config.rules.tickHz
        : -1;
    if (state.phase != _hudPhase ||
        state.turn != _hudTurn ||
        seconds != _hudSecondsLeft) {
      _hudPhase = state.phase;
      _hudTurn = state.turn;
      _hudSecondsLeft = seconds;
      hudRevision.value++;
    }
  }

  /// Turns simulation events into things you can see and feel.
  void _reactTo(List<SoccerEvent> events) {
    for (final event in events) {
      switch (event.type) {
        case SoccerEventType.grab:
          unawaited(HapticFeedback.selectionClick());
        case SoccerEventType.flick:
          shake = math.max(shake, 2 + event.intensity * 4);
          _spawnBurst(event.at, 6, event.intensity);
          unawaited(HapticFeedback.lightImpact());
        case SoccerEventType.ballHit:
          shake = math.max(shake, 3 + event.intensity * 9);
          _spawnBurst(event.at, 8, event.intensity);
          // A short, sharp tick on contact is most of what makes a strike feel
          // physical on a device with no buttons.
          unawaited(HapticFeedback.selectionClick());
        case SoccerEventType.discHit:
          shake = math.max(shake, 1.5 + event.intensity * 5);
          _spawnBurst(event.at, 4, event.intensity * 0.6);
        case SoccerEventType.wallHit:
          shake = math.max(shake, 1 + event.intensity * 2);
        case SoccerEventType.postHit:
          shake = math.max(shake, 12);
          _spawnBurst(event.at, 14, 1);
          unawaited(HapticFeedback.mediumImpact());
        case SoccerEventType.goal:
          shake = math.max(shake, 20);
          flash = 1;
          goalPulse = 1;
          _spawnBurst(event.at, 34, 1);
          ballTrail.clear();
          hudRevision.value++;
          unawaited(HapticFeedback.heavyImpact());
        case SoccerEventType.turnStart:
          ballTrail.clear();
          hudRevision.value++;
        case SoccerEventType.turnTimeout:
          hudRevision.value++;
        case SoccerEventType.matchComplete:
          shake = 24;
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

    flash *= math.pow(0.02, dt).toDouble();
    goalPulse *= math.pow(0.25, dt).toDouble();

    impact.updateAll((_, value) => value * decay);
    impact.removeWhere((_, value) => value < 0.02);

    for (var i = particles.length - 1; i >= 0; i--) {
      final particle = particles[i];
      particle.advance(dt);
      if (particle.dead) particles.removeAt(i);
    }

    if (simulation.state.phase == SoccerPhase.resolving) {
      ballTrail.add(simulation.state.world.ball.position);
      if (ballTrail.length > 16) ballTrail.removeAt(0);
    }
  }

  void _spawnBurst(Vec2 at, int count, double energy) {
    for (var i = 0; i < count; i++) {
      // Trigonometry is fine here and nowhere in `soccer_sim` — particles are
      // decoration and never touch the simulation, so they cannot make a
      // replay diverge.
      final angle = _visualRandom.nextDouble() * math.pi * 2;
      final speed = (100 + _visualRandom.nextDouble() * 460) * (0.4 + energy);
      particles.add(
        SoccerParticle(
          position: at,
          velocity: Vec2(math.cos(angle) * speed, math.sin(angle) * speed),
          life: 0.22 + _visualRandom.nextDouble() * 0.3,
          size: 4 + _visualRandom.nextDouble() * 8,
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

/// A speck of turf. Purely decorative — particles never touch the simulation.
class SoccerParticle {
  SoccerParticle({
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
    // Top-down, so debris slows rather than falls — a gravity term here would
    // make the pitch look like a wall.
    velocity = velocity * 0.90;
    life -= dt;
  }
}
