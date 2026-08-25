import 'dart:math' as math;

import 'package:game_core/game_core.dart';

import 'bot.dart';
import 'field.dart';
import 'state.dart';
import 'track.dart';

/// The race, as pure state.
///
/// Advance it one tick at a time with [step]. It draws nothing, plays nothing,
/// and reads no clock — call it 120 times and one second of racing has
/// happened, whether that took a second or two milliseconds. That property is
/// what lets the server replay a submitted race in a few milliseconds and check
/// who actually won.
class RaceSimulation {
  RaceSimulation({
    required this.seed,
    required this.mode,
    required this.track,
    this.botDifficulty,
    this.rules = RaceRules.standard,
  }) : assert(
          mode != GameMode.vsBot || botDifficulty != null,
          'A bot race needs a difficulty',
        ) {
    // Line the cars up just short of the start line, so they cross it under
    // power at lights-out and lap one begins the way every other lap does.
    final gridDistance = track.wrapDistance(-RaceField.gridStagger);
    final gridCentre = track.pointAt(gridDistance);
    final gridForward = track.directionAt(gridDistance);
    final gridRight = Vec2(-gridForward.y, gridForward.x);

    CarState place(RacerSide side, double lateralOffset) {
      final car = CarState(
        position: gridCentre + gridRight * lateralOffset,
        heading: gridForward,
        side: side,
      );
      final projection = track.project(car.position);
      car
        ..segmentHint = projection.segment
        ..lastProjection = projection.distance
        // Negative: the line is still ahead. Lap one completes when this
        // passes one full track length, exactly like every lap after it.
        ..travelled = -RaceField.gridStagger;
      return car;
    }

    state = RaceState(
      p1: place(RacerSide.p1, -RaceField.gridLateralOffset),
      p2: place(RacerSide.p2, RaceField.gridLateralOffset),
      phase: RacePhase.countdown,
    )..countdownTicks = rules.countdownTicks;

    if (mode == GameMode.vsBot) {
      _bot = RaceBot(
        profile: BotProfile.of(botDifficulty!),
        side: RacerSide.p2,
        seed: seed,
        tickHz: rules.tickHz,
      );
    }
  }

  final int seed;
  final GameMode mode;
  final RaceTrack track;
  final BotDifficulty? botDifficulty;
  final RaceRules rules;

  late final RaceState state;
  RaceBot? _bot;

  final List<RaceEvent> _events = <RaceEvent>[];

  /// Events raised by the most recent [step]. Valid until the next one.
  List<RaceEvent> get pendingEvents => _events;

  int _tick = 0;
  int get tick => _tick;

  CarInput _heldP1 = CarInput.coasting;
  CarInput _heldP2 = CarInput.coasting;

  /// The input actually in effect this tick, after holding the last value
  /// through ticks with no new one. The recorder writes *these*, so a replay
  /// feeds back exactly what the live race consumed.
  CarInput get p1Input => _heldP1;
  CarInput get p2Input => _heldP2;

  bool get isComplete => state.phase == RacePhase.complete;

  bool get isTwoHuman => mode == GameMode.local2P;

  /// Input channels a replay of this race must carry: one driver's three
  /// against the bot, both drivers' six for a shared screen.
  int get replayChannelCount =>
      isTwoHuman ? CarInput.channelCount * 2 : CarInput.channelCount;

  /// Advances the race by exactly one tick.
  void step(RaceInput input) {
    _events.clear();
    if (state.phase == RacePhase.complete) return;

    final dt = rules.stepSeconds;

    if (input.p1 != null) _heldP1 = input.p1!;
    if (mode == GameMode.vsBot) {
      _heldP2 = _bot!.update(state, track);
    } else if (input.p2 != null) {
      _heldP2 = input.p2!;
    }

    switch (state.phase) {
      case RacePhase.countdown:
        // Frozen, but the projection still has to track so the first racing
        // tick has a valid hint rather than a stale one.
        for (final car in <CarState>[state.p1, state.p2]) {
          car
            ..previousPosition = car.position
            ..previousHeading = car.heading;
          _observe(car);
        }
        if (state.countdownTicks % rules.tickHz == 0) {
          _emit(RaceEventType.countdownBeep, state.p1.position);
        }
        state.countdownTicks--;
        if (state.countdownTicks <= 0) {
          state.phase = RacePhase.racing;
          state.p1.lapStartTick = _tick;
          state.p2.lapStartTick = _tick;
          _emit(RaceEventType.go, state.p1.position);
        }

      case RacePhase.racing:
        for (final car in <CarState>[state.p1, state.p2]) {
          _observe(car);
          _drive(car, car.side == RacerSide.p1 ? _heldP1 : _heldP2, dt);
          _resolveObstacles(car);
        }
        _resolveCarContact();
        for (final car in <CarState>[state.p1, state.p2]) {
          _constrainToField(car);
          // After the fence, so a car pinned against it counts as stranded and
          // gets picked up rather than being re-pinned every tick.
          if (!car.finished) _maybeRescue(car);
        }
        _checkFinish();

      case RacePhase.complete:
        break;
    }

    _tick++;
  }

  // --- perception ----------------------------------------------------------

  /// Projects a car onto the racing line and books the consequences: what it is
  /// driving on, how far round it has got, and whether that completed a lap.
  void _observe(CarState car) {
    final projection = track.project(
      car.position,
      hintSegment: car.segmentHint,
    );
    car.segmentHint = projection.segment;

    final wasOnTrack = car.onTrack;
    car.surface =
        projection.lateralAbs <= track.halfWidth ? Surface.dirt : Surface.grass;

    if (state.phase == RacePhase.racing && !car.finished) {
      // Fold the raw projection into a signed step. Without this, the tick a
      // car crosses the start line reads as a whole lap backwards.
      final step = track.shortestDelta(car.lastProjection, projection.distance);

      // A car cannot bank more progress in one tick than it could physically
      // have driven. The windowed search makes a wild jump unlikely; this makes
      // it impossible, and costs one comparison. Anything larger is the
      // projection flipping between two parts of the circuit that happen to
      // pass close together, never a car that actually got there.
      final reach = car.speed * rules.stepSeconds * 1.5 + 1.0;
      if (step.abs() <= reach) car.travelled += step;

      car.racingTicks++;
      if (car.onTrack) {
        car.onTrackTicks++;
      }

      if (wasOnTrack != car.onTrack) {
        _emit(
          car.onTrack ? RaceEventType.cameBackOn : RaceEventType.wentOffTrack,
          car.position,
          side: car.side,
        );
      }

      final lapsDone = car.travelled <= 0
          ? 0
          : (car.travelled / track.totalLength).floor();
      if (lapsDone > car.lap) {
        car.lap = lapsDone;
        car.lapTicks.add(_tick - car.lapStartTick);
        car.lapStartTick = _tick;
        _emit(RaceEventType.lapComplete, car.position, side: car.side);
      }
    }

    car.lastProjection = projection.distance;
  }

  // --- driving -------------------------------------------------------------

  /// One car, one tick of physics.
  ///
  /// Order matters and is the whole model: **steer first, then decompose.**
  /// Turning the nose is what converts some of the car's forward momentum into
  /// sideways momentum, and grip is what scrubs that back off. Decomposing
  /// before rotating instead would leave the lateral term permanently zero, and
  /// the car would corner as if on rails with no weight to it at all.
  void _drive(CarState car, CarInput input, double dt) {
    car
      ..previousPosition = car.position
      ..previousHeading = car.heading;

    // A car that has taken the flag coasts to a halt rather than vanishing.
    final effective = car.finished
        ? const CarInput(brake: true)
        : input;

    final onGrass = car.surface == Surface.grass;
    final drag = onGrass ? RaceField.dragOnGrass : RaceField.dragOnTrack;
    final grip = onGrass ? RaceField.gripOnGrass : RaceField.gripOnTrack;

    final speedBefore = car.velocity.length;
    final movingBackwards = car.velocity.dot(car.heading) < 0;

    // 1. Steer, within what the tyres can actually hold.
    if (effective.steer != 0) {
      // Below walking pace the car turns in proportion to how fast it is
      // going, so a stationary car cannot pirouette on the spot — unless the
      // driver is actually asking for drive, in which case a floor applies.
      //
      // That exception is the fix for a real deadlock: nosed into the fence at
      // zero speed, the throttle pushes into the fence, the fence cancels the
      // velocity, speed stays zero, and with no floor the steering stays dead
      // forever. `tool/stuck.dart` measured exactly that — 0.6 units/s and
      // going backwards after six seconds of full throttle and full lock.
      final asking = effective.throttle || effective.brake;
      final authority = clampD(
        speedBefore / RaceField.fullSteeringSpeed,
        asking ? RaceField.minSteeringAuthority : 0,
        1,
      );

      var yawRate = RaceField.turnRate * authority;

      // The grip limit. Cornering at speed `v` on a radius `r` demands `v²/r`
      // of sideways acceleration, and yaw rate is `v/r` — so the most yaw the
      // tyres can support is `gripLimit / v`. Beyond that the car understeers
      // wide instead of turning, which is what makes braking for a corner
      // worth doing and what stops every difficulty driving flat out.
      final gripLimit = onGrass
          ? RaceField.lateralGripLimitGrass
          : RaceField.lateralGripLimit;
      final maxYaw = gripLimit / (speedBefore < 1 ? 1 : speedBefore);
      if (yawRate > maxYaw) yawRate = maxYaw;

      // Reversing turns the other way, as a real car does.
      final sense = movingBackwards ? -1.0 : 1.0;
      final tangent = effective.steer * yawRate * dt * sense;
      car.heading = _rotate(car.heading, tangent);
    }

    // 2. Decompose onto the new axes. Whatever the rotation just made
    //    sideways shows up here as slip.
    final right = car.right;
    var forward = car.velocity.dot(car.heading);
    var lateral = car.velocity.dot(right);

    // 3. Longitudinal forces.
    if (effective.brake) {
      if (forward > 1.0) {
        forward -= RaceField.brakeForce * dt;
        if (forward < 0) forward = 0;
      } else {
        forward -= RaceField.reverseForce * dt;
        if (forward < -RaceField.reverseMaxSpeed) {
          forward = -RaceField.reverseMaxSpeed;
        }
      }
    } else if (effective.throttle) {
      forward += RaceField.engineForce * dt;
    }
    forward -= forward * drag * dt;

    // 4. Grip scrubs sideways velocity off. The gap between the dirt and the
    //    grass values here is what makes leaving the track feel like a mistake.
    lateral -= lateral * grip * dt;

    // 5. Recompose and integrate.
    car.velocity = car.heading * forward + right * lateral;
    car.position += car.velocity * dt;

    final speedNow = car.velocity.length;
    car.slip = speedNow < 25 ? 0 : clampD(lateral.abs() / speedNow, 0, 1);
  }

  /// Rotates [v] by the angle whose tangent is [k].
  ///
  /// Multiplying by the complex number `(1, k)` rotates by `atan(k)` and scales
  /// by `sqrt(1 + k²)`; normalising removes the scale and leaves a pure
  /// rotation. The point is that no angle is ever formed: `sin`, `cos` and
  /// `atan2` come from the platform's libm and are not guaranteed to agree
  /// bit-for-bit between a phone and the server, which would break every replay
  /// the server tried to verify. `sqrt` is safe — IEEE-754 requires it to be
  /// correctly rounded.
  static Vec2 _rotate(Vec2 v, double k) =>
      Vec2(v.x - v.y * k, v.y + v.x * k).normalized;

  // --- contact -------------------------------------------------------------

  void _resolveObstacles(CarState car) {
    for (final obstacle in track.obstacles) {
      final delta = car.position - obstacle.position;
      final minimum = RaceField.carRadius + obstacle.radius;
      final gapSquared = delta.lengthSquared;
      if (gapSquared >= minimum * minimum) continue;

      final gap = math.sqrt(gapSquared);
      final normal = gap < 1e-9 ? const Vec2(0, -1) : delta / gap;
      car.position = obstacle.position + normal * minimum;

      final closing = car.velocity.dot(normal);
      if (closing < 0) {
        car.velocity =
            car.velocity - normal * (closing * (1 + RaceField.obstacleRestitution));
        _emit(
          RaceEventType.obstacleContact,
          car.position,
          side: car.side,
          intensity: clampD(-closing / 320, 0, 1),
        );
      }
    }
  }

  /// Two cars, equal mass, one shared push.
  void _resolveCarContact() {
    final a = state.p1;
    final b = state.p2;
    final delta = b.position - a.position;
    final minimum = RaceField.carRadius * 2;
    final gapSquared = delta.lengthSquared;
    if (gapSquared >= minimum * minimum || gapSquared < 1e-9) return;

    final gap = math.sqrt(gapSquared);
    final normal = delta / gap;
    final overlap = (minimum - gap) / 2;

    a.position -= normal * overlap;
    b.position += normal * overlap;

    final closing = (b.velocity - a.velocity).dot(normal);
    if (closing < 0) {
      final impulse = -(1 + RaceField.carRestitution) * closing / 2;
      a.velocity -= normal * impulse;
      b.velocity += normal * impulse;
      _emit(
        RaceEventType.carContact,
        a.position + normal * RaceField.carRadius,
        intensity: clampD(-closing / 380, 0, 1),
      );
    }
  }

  /// An invisible fence a little way out into the grass.
  ///
  /// Deliberately not a visible wall: a barrier the player can see is a barrier
  /// they resent bouncing off, whereas grass that eventually refuses to let you
  /// go further reads as the edge of the world. It also guarantees a spun car
  /// stays inside the field, which the renderer's fixed letterbox depends on.
  void _constrainToField(CarState car) {
    final projection = track.project(
      car.position,
      hintSegment: car.segmentHint,
    );
    final limit = track.halfWidth + RaceField.grassMargin;
    if (projection.lateralAbs <= limit) return;

    final sign = projection.lateral < 0 ? -1.0 : 1.0;
    final right = Vec2(-projection.forward.y, projection.forward.x);

    car.position = projection.closest + right * (sign * limit);

    // Cancel the outward component and keep the rest, so the car *slides*
    // along the fence rather than being stopped dead by it.
    //
    // This used to subtract 1.35x the outward speed, which reflected the car
    // back inwards — but with the nose still pointing out, the throttle drove
    // it straight back into the fence, and the pair of them held the car at a
    // standstill where (before the authority floor above) it could not steer.
    // The two changes together are what make the fence survivable; either one
    // alone leaves a way to get stuck.
    final outward = right * sign;
    final escaping = car.velocity.dot(outward);
    if (escaping > 0) car.velocity -= outward * escaping;
  }

  // --- the marshals --------------------------------------------------------

  /// Lifts a car that has beached itself back onto the racing line.
  ///
  /// Every arcade racer has this and it is not a concession: a shared-screen
  /// race where one player spends forty seconds in a hedge is not a race, and
  /// the other player is punished for it just as much. The penalty for going
  /// off is already paid in the seconds lost getting slow enough to qualify,
  /// plus rejoining at [RaceField.rescueLaunchSpeed] rather than at pace.
  ///
  /// Deterministic: it keys off a tick counter and the projection, never a
  /// clock and never the RNG, so a replay recovers on exactly the same tick.
  void _maybeRescue(CarState car) {
    if (car.rescueFlashTicks > 0) car.rescueFlashTicks--;

    final stranded =
        !car.onTrack && car.speed < RaceField.rescueSpeedThreshold;
    if (!stranded) {
      car.strandedTicks = 0;
      return;
    }

    car.strandedTicks++;
    if (car.strandedTicks < RaceField.rescueDelayTicks) return;

    // Back onto the centreline at the point it had reached, facing the way the
    // circuit goes. Using the *projection* rather than a fixed respawn point
    // means a car is never teleported forwards — the distance it had banked is
    // exactly the distance it resumes from.
    final forward = track.directionAt(car.lastProjection);
    car
      ..position = track.pointAt(car.lastProjection)
      ..heading = forward
      ..velocity = forward * RaceField.rescueLaunchSpeed
      ..slip = 0
      ..strandedTicks = 0
      ..rescueFlashTicks = rules.tickHz;
    car.rescues++;

    _emit(RaceEventType.rescued, car.position, side: car.side);
  }

  // --- the flag ------------------------------------------------------------

  void _checkFinish() {
    for (final car in <CarState>[state.p1, state.p2]) {
      if (!car.finished && car.lap >= rules.laps) {
        car
          ..finished = true
          ..finishTick = _tick;
        _emit(RaceEventType.finish, car.position, side: car.side);
        if (state.winner == null) {
          state.winner = car.side;
          state.graceTicks = rules.finishGraceTicks;
        }
      }
    }

    if (state.p1.finished && state.p2.finished) {
      _finishRace();
      return;
    }
    if (state.winner != null) {
      state.graceTicks--;
      if (state.graceTicks <= 0) {
        _finishRace();
        return;
      }
    }
    // The backstop. A race where nobody ever drives has no natural end, which
    // would leave the server no duration to sanity-check and would let two
    // players farm playtime by parking on the grid.
    //
    // `+ 1` because this runs before the tick counter is incremented: the race
    // must be over *on* the tick that reaches the cap, not one after it, or a
    // caller looping `while (tick < maxTicks)` stops driving the simulation
    // before the tick that would have ended it ever runs.
    if (_tick + 1 >= rules.maxTicks) _finishRace();
  }

  void _finishRace() {
    state.winner ??= state.leader;
    state.phase = RacePhase.complete;
    _emit(RaceEventType.raceComplete, state.car(state.winner!).position);
  }

  // --- results -------------------------------------------------------------

  /// A representative lap time for this circuit, in ticks.
  ///
  /// Derived from the track's own length and the car's own physics rather than
  /// hand-tuned per track, so adding a circuit does not mean re-deriving what a
  /// good lap is. 62% of terminal velocity is roughly what a tidy lap averages
  /// once braking for corners is accounted for.
  double get _parLapTicks {
    const terminal = RaceField.engineForce / RaceField.dragOnTrack;
    final parSpeed = terminal * 0.62;
    return (track.totalLength / parSpeed) * rules.tickHz;
  }

  /// Fastest lap P1 recorded, in ticks, or null if they never completed one.
  int? get p1BestLapTicks {
    if (state.p1.lapTicks.isEmpty) return null;
    return state.p1.lapTicks.reduce(math.min);
  }

  /// Fraction of P1's race spent with all four wheels on the dirt.
  double get p1Cleanliness => state.p1.racingTicks == 0
      ? 0
      : state.p1.onTrackTicks / state.p1.racingTicks;

  /// Skill on the 0..1 scale every Elevar game reports, from P1's perspective.
  ///
  /// Half of it is the result, because winning has to be worth more than
  /// anything else. The rest splits between raw pace and clean driving, so a
  /// player who loses a close race after driving well still scores meaningfully
  /// above one who spent the race in the scenery. The server's payout formula
  /// sees only this number and must treat racing and ping pong on the same
  /// terms — which is exactly why it is a fraction and not a lap time.
  double get normalizedSkill {
    final margin = _marginComponent;

    final best = p1BestLapTicks;
    final pace = best == null ? 0.0 : clampD(_parLapTicks / best, 0, 1);

    final clean = clampD(p1Cleanliness, 0, 1);

    return clampD(0.5 * margin + 0.3 * pace + 0.2 * clean, 0, 1);
  }

  /// 0 when comprehensively beaten, 0.5 for a dead heat, 1 for a rout.
  double get _marginComponent {
    final a = state.p1;
    final b = state.p2;

    if (a.finished && b.finished) {
      final gap = clampD((b.finishTick - a.finishTick) / _parLapTicks, -1, 1);
      return clampD(0.5 + 0.5 * gap, 0, 1);
    }
    if (a.finished) return 1;
    if (b.finished) return 0;

    // Neither got home — the race timed out. Fall back to who was further on.
    final gapLaps =
        clampD((a.travelled - b.travelled) / track.totalLength, -1, 1);
    return clampD(0.5 + 0.5 * gapLaps, 0, 1);
  }

  int get durationMs => (_tick * 1000) ~/ rules.tickHz;

  /// Packages the finished race for submission to `/v1/matches`.
  ///
  /// Score is laps completed, which keeps the wire format identical to ping
  /// pong's and lets the server's plausibility rules ("max score", "max score
  /// per minute") apply to racing without learning what a lap is.
  GameResult buildResult({String? sessionToken, List<int>? replay}) {
    final p1Laps = state.p1.lap;
    final p2Laps = state.p2.lap;

    final outcome = switch (state.winner) {
      RacerSide.p1 => MatchOutcome.p1Win,
      RacerSide.p2 => MatchOutcome.p2Win,
      null => MatchOutcome.draw,
    };

    return GameResult(
      gameSlug: 'car_racing',
      mode: mode,
      botDifficulty: botDifficulty,
      durationMs: durationMs,
      p1Score: p1Laps,
      p2Score: p2Laps,
      outcome: outcome,
      normalizedSkill: normalizedSkill,
      seed: seed,
      tickCount: _tick,
      replay: replay,
      sessionToken: sessionToken,
    );
  }

  void _emit(
    RaceEventType type,
    Vec2 at, {
    RacerSide? side,
    double intensity = 1,
  }) =>
      _events.add(RaceEvent(type, at: at, side: side, intensity: intensity));
}
