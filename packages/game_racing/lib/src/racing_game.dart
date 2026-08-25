import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:game_core/game_core.dart';
import 'package:racing_sim/racing_sim.dart';

import 'game_config.dart';
import 'race_scene.dart';

/// Hosts the race simulation and turns it into something to look at.
///
/// The split is the same one ping pong uses and is strict: this class owns the
/// clock, the layout, the dust and the haptics, and owns *no* rules. It
/// advances the simulation in fixed ticks and reads the events that come back
/// out.
class RacingGame extends FlameGame {
  RacingGame({required this.config, required this.onComplete})
      // Built in the constructor rather than onLoad: Flame's onLoad is async
      // and the engine can call update() before that future resolves, which
      // would leave the simulation briefly null on the first frame.
      : track = config.buildTrack(),
        super() {
    simulation = RaceSimulation(
      seed: config.seed,
      mode: config.mode,
      track: track,
      botDifficulty: config.botDifficulty,
      rules: config.rules,
    );
    runner = RaceMatchRunner(simulation: simulation);
  }

  final RaceConfig config;
  final void Function(RaceOutcome outcome) onComplete;

  final RaceTrack track;
  late final RaceSimulation simulation;
  late final RaceMatchRunner runner;

  final FixedLoop _loop = FixedLoop(tickHz: 120);

  /// Bumped whenever anything the HUD shows changes — lap, position, phase —
  /// so it rebuilds on those rather than on every frame.
  final ValueNotifier<int> hudRevision = ValueNotifier<int>(0);

  // --- layout --------------------------------------------------------------

  /// Height of the control band reserved at the top and bottom of the screen.
  ///
  /// Reserved *first*, with the circuit letterboxed into whatever is left. Two
  /// players sharing a phone need eight thumb targets, and the alternative —
  /// fitting the track first and overlaying the controls on its corners — puts
  /// fingers on the racing line exactly when the racing gets close.
  double bandHeight = 150;

  double fieldScale = 1;
  Offset fieldOrigin = Offset.zero;

  /// Fraction of a tick already elapsed, for interpolating between simulation
  /// steps. Without it the cars visibly step at 120 Hz against a 60 Hz display
  /// instead of gliding.
  double get interpolation => _loop.alpha;

  // --- juice ---------------------------------------------------------------
  double shake = 0;
  Offset shakeOffset = Offset.zero;
  double flash = 0;
  final List<DustMote> dust = <DustMote>[];
  final List<SkidMark> skids = <SkidMark>[];

  final math.Random _visualRandom = math.Random(11);
  bool _finished = false;
  RacePhase _hudPhase = RacePhase.countdown;
  int _hudLapP1 = 0;
  int _hudLapP2 = 0;

  /// Seconds left on the countdown clock, for the 3-2-1 banner.
  int get countdownSeconds =>
      (simulation.state.countdownTicks / config.rules.tickHz).ceil();

  /// Whether to point at the pedal and say what it is for.
  ///
  /// Shown for the first four seconds of green-flag running, and dismissed the
  /// moment the car is actually moving — so it appears exactly for the player
  /// who does not yet know, and never for the one who does. The lights going
  /// out on a car that then sits still is otherwise indistinguishable from the
  /// game having hung.
  bool get showStartHint {
    final state = simulation.state;
    if (state.phase != RacePhase.racing) return false;
    if (state.p1.speed > 30) return false;
    return _ticksSinceGo < config.rules.tickHz * 4;
  }

  int _ticksSinceGo = 0;
  bool _overlayWasUp = false;

  @override
  Future<void> onLoad() async {
    await add(RaceScene(game: this));
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);

    // A band proportional to the screen, floored so it stays thumb-sized on a
    // small phone and capped so it does not eat a tablet.
    bandHeight = clampD(size.y * 0.155, 132, 240);

    final usableHeight = size.y - bandHeight * 2;
    final scale = math.min(
      size.x / RaceField.width,
      usableHeight / RaceField.height,
    );
    fieldScale = scale;
    fieldOrigin = Offset(
      (size.x - RaceField.width * scale) / 2,
      bandHeight + (usableHeight - RaceField.height * scale) / 2,
    );
  }

  // --- driving -------------------------------------------------------------

  void setInput(RacerSide side, CarInput input) {
    if (side == RacerSide.p1) {
      runner.setP1Input(input);
    } else if (config.isTwoHuman) {
      runner.setP2Input(input);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_finished) return;

    _loop.advance(dt, (_) {
      runner.tick();
      _reactTo(simulation.pendingEvents);
      _layDownSkids();
    });

    final state = simulation.state;
    if (state.phase != _hudPhase ||
        state.p1.lap != _hudLapP1 ||
        state.p2.lap != _hudLapP2) {
      _hudPhase = state.phase;
      _hudLapP1 = state.p1.lap;
      _hudLapP2 = state.p2.lap;
      hudRevision.value++;
    }
    // The countdown banner counts seconds, so it has to rebuild during it.
    if (state.phase == RacePhase.countdown) hudRevision.value++;
    if (state.phase == RacePhase.racing) {
      _ticksSinceGo++;
      // The start hint and the recovery countdown both change every frame
      // while they are up, so the HUD has to keep pace with them.
      //
      // The `_overlayWasUp` half is not redundant: the HUD only rebuilds when
      // this notifier changes, so bumping *only while* an overlay is up leaves
      // the last frame that contained it painted on screen forever once the
      // condition goes false. The banner has to be told to leave, not merely
      // stop being told to stay.
      final overlayUp = showStartHint ||
          state.p1.awaitingRescue ||
          state.p1.rescueFlashTicks > 0;
      if (overlayUp || _overlayWasUp) hudRevision.value++;
      _overlayWasUp = overlayUp;
    }

    _advanceJuice(dt);

    if (simulation.isComplete && !_finished) {
      _finished = true;
      // Seal the recording exactly once — finishing drains the buffer.
      final replay = runner.finishRecording();
      final bestLapTicks = simulation.p1BestLapTicks;
      onComplete(
        RaceOutcome(
          result: simulation.buildResult(
            sessionToken: config.sessionToken,
            replay: replay,
          ),
          replay: replay,
          bestLapMs: bestLapTicks == null
              ? null
              : (bestLapTicks * 1000) ~/ config.rules.tickHz,
          cleanliness: simulation.p1Cleanliness,
        ),
      );
    }
  }

  /// Turns simulation events into things you can see and feel.
  void _reactTo(List<RaceEvent> events) {
    for (final event in events) {
      switch (event.type) {
        case RaceEventType.countdownBeep:
          unawaited(HapticFeedback.selectionClick());
        case RaceEventType.go:
          shake = math.max(shake, 8);
          unawaited(HapticFeedback.mediumImpact());
        case RaceEventType.lapComplete:
          flash = math.max(flash, 0.5);
          hudRevision.value++;
          unawaited(HapticFeedback.selectionClick());
        case RaceEventType.carContact:
          shake = math.max(shake, 4 + event.intensity * 10);
          _spawnDust(event.at, 10, event.intensity);
          unawaited(HapticFeedback.mediumImpact());
        case RaceEventType.obstacleContact:
          shake = math.max(shake, 3 + event.intensity * 12);
          _spawnDust(event.at, 8, event.intensity);
          unawaited(HapticFeedback.heavyImpact());
        case RaceEventType.wentOffTrack:
          _spawnDust(event.at, 6, 0.6);
        case RaceEventType.cameBackOn:
          _spawnDust(event.at, 4, 0.4);
        case RaceEventType.rescued:
          // A puff of dust where the marshals set it down, and a bump you can
          // feel — the player needs to know the car moved because it was
          // helped, not because the game glitched.
          _spawnDust(event.at, 14, 0.8);
          flash = math.max(flash, 0.35);
          hudRevision.value++;
          unawaited(HapticFeedback.mediumImpact());
        case RaceEventType.finish:
          shake = math.max(shake, 14);
          flash = 1;
          _spawnDust(event.at, 24, 1);
          hudRevision.value++;
          unawaited(HapticFeedback.heavyImpact());
        case RaceEventType.raceComplete:
          hudRevision.value++;
      }
    }
  }

  /// Cars throw dust when they slide and when they are off the racing line.
  void _layDownSkids() {
    if (simulation.state.phase != RacePhase.racing) return;
    for (final car in <CarState>[simulation.state.p1, simulation.state.p2]) {
      final sliding = car.slip > 0.22;
      final ploughing = !car.onTrack && car.speed > 40;
      if (!sliding && !ploughing) continue;

      // One mote every few ticks rather than every tick: a continuous stream
      // reads as a solid bar, and costs sixty times as much to draw.
      if (simulation.tick % 3 != 0) continue;

      _spawnDust(car.position, 1, sliding ? car.slip : 0.5);

      if (sliding && car.onTrack) {
        skids.add(
          SkidMark(
            from: car.previousPosition,
            to: car.position,
            side: car.side,
          ),
        );
        // Bounded: a five-minute race would otherwise accumulate tens of
        // thousands of segments and take the frame rate with it.
        if (skids.length > 420) skids.removeAt(0);
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

    for (var i = dust.length - 1; i >= 0; i--) {
      final mote = dust[i];
      mote.advance(dt);
      if (mote.dead) dust.removeAt(i);
    }
    for (var i = skids.length - 1; i >= 0; i--) {
      skids[i].fade(dt);
      if (skids[i].gone) skids.removeAt(i);
    }
  }

  void _spawnDust(Vec2 at, int count, double energy) {
    for (var i = 0; i < count; i++) {
      final angle = _visualRandom.nextDouble() * math.pi * 2;
      final speed = (25 + _visualRandom.nextDouble() * 120) * (0.4 + energy);
      dust.add(
        DustMote(
          position: at,
          velocity: Vec2(math.cos(angle) * speed, math.sin(angle) * speed),
          life: 0.3 + _visualRandom.nextDouble() * 0.5,
          size: 4 + _visualRandom.nextDouble() * 9,
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

/// A puff of dirt. Purely decorative — dust never touches the simulation.
class DustMote {
  DustMote({
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
    // Dust slows and swells as it settles.
    velocity = velocity * 0.90;
    life -= dt;
  }
}

/// A scuff of rubber left where a car slid.
class SkidMark {
  SkidMark({required this.from, required this.to, required this.side});

  final Vec2 from;
  final Vec2 to;
  final RacerSide side;
  double alpha = 0.55;

  bool get gone => alpha <= 0.01;

  /// Marks linger for most of a lap, then wash out — long enough to read the
  /// line somebody took, short enough that the circuit does not turn black.
  void fade(double dt) => alpha -= dt * 0.045;
}
