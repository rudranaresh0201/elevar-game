import 'dart:math' as math;

import 'package:game_core/game_core.dart';

import 'field.dart';
import 'state.dart';
import 'track.dart';

/// A difficulty setting, expressed as seven dials rather than three algorithms.
///
/// Every difficulty runs the same driver; only these numbers change. That
/// matters for the same reason it did in ping pong: "hard" cannot contain a bug
/// that "easy" doesn't, and the curve can be retuned without touching logic.
class BotProfile {
  const BotProfile({
    required this.reactionMs,
    required this.paceFraction,
    required this.cornerCaution,
    required this.lineNoise,
    required this.mistakeChance,
    required this.lookaheadBase,
    required this.lookaheadPerSpeed,
  });

  /// How long before the bot reacts to where its car actually is. The single
  /// biggest contributor to how a bot *feels* — a quick bot that reacts late
  /// wanders and corrects like a person, one with no delay tracks the racing
  /// line like a slot car.
  final int reactionMs;

  /// Top speed it will ask for, as a fraction of the car's terminal velocity.
  final double paceFraction;

  /// How much it lifts for a given bend. Above 1 it is over-cautious and loses
  /// time in the corners; below 1 it carries speed and risks running wide.
  final double cornerCaution;

  /// Half-width of its wander off the ideal line, in field units, resampled
  /// during the lap so it drifts rather than tracking on rails.
  final double lineNoise;

  /// Probability of fluffing any given corner entry.
  ///
  /// Not a bug being papered over. A bot that never errs is not hard, it is
  /// unbeatable, and a player who cannot win stops playing — which costs more
  /// than a lost race does.
  final double mistakeChance;

  /// How far up the road it looks, at rest and per unit of speed. Short
  /// lookahead turns in late and scrubs speed; long lookahead flows.
  final double lookaheadBase;
  final double lookaheadPerSpeed;

  /// Terminal velocity of the car, which every pace figure is a fraction of.
  static const double terminalSpeed =
      RaceField.engineForce / RaceField.dragOnTrack;

  double get targetTopSpeed => terminalSpeed * paceFraction;

  int reactionTicks(int tickHz) => (reactionMs * tickHz) ~/ 1000;

  static const BotProfile easy = BotProfile(
    reactionMs: 280,
    paceFraction: 0.90,
    cornerCaution: 1.10,
    lineNoise: 62,
    mistakeChance: 0.11,
    lookaheadBase: 130,
    lookaheadPerSpeed: 0.30,
  );

  /// Aimed at a ~15.9s Dustbowl lap, which is where the mid-range player sits.
  /// Was 0.96/1.045, giving 15.5s — quick enough that medium and hard finished
  /// within 0.4s of each other and the ladder had no middle.
  static const BotProfile medium = BotProfile(
    reactionMs: 170,
    paceFraction: 0.93,
    cornerCaution: 1.09,
    lineNoise: 34,
    mistakeChance: 0.07,
    lookaheadBase: 150,
    lookaheadPerSpeed: 0.42,
  );

  /// Aimed at ~14.5s, matching a player driving as well as this car can be
  /// driven. The higher [RaceField.lateralGripLimit] is what lets caution drop
  /// below 0.99 without the bot simply falling off — it now carries corner
  /// speed the way a quick human does rather than lifting for safety.
  static const BotProfile hard = BotProfile(
    reactionMs: 60,
    paceFraction: 1.00,
    cornerCaution: 1.00,
    lineNoise: 6,
    mistakeChance: 0.025,
    lookaheadBase: 195,
    lookaheadPerSpeed: 0.58,
  );

  static BotProfile of(BotDifficulty difficulty) => switch (difficulty) {
        BotDifficulty.easy => easy,
        BotDifficulty.medium => medium,
        BotDifficulty.hard => hard,
      };
}

/// The computer driver.
///
/// Lives *inside* the simulation, like the pong bot and for the same structural
/// reason: it is driven by the seeded RNG, so a replay only carries the human's
/// input and the bot reproduces itself for free — and a tampered client cannot
/// claim the bot drove worse than it did.
///
/// It is also held to the same controls the player has. [CarInput.steer] is one
/// of three values here exactly as it is for a thumb on a button, so the bot
/// can never make an input a human could not.
class RaceBot {
  RaceBot({
    required this.profile,
    required this.side,
    required int seed,
    required int tickHz,
  })  : _reactionTicks = profile.reactionTicks(tickHz),
        _tickHz = tickHz,
        _lineRng = DeterministicRng.stream(seed, 21),
        _mistakeRng = DeterministicRng.stream(seed, 22) {
    _history = List<_Snapshot>.filled(
      _reactionTicks + 1,
      const _Snapshot(Vec2.zero, Vec2(0, -1), 0, 0),
    );
  }

  final BotProfile profile;
  final RacerSide side;
  final int _tickHz;

  final int _reactionTicks;
  final DeterministicRng _lineRng;
  final DeterministicRng _mistakeRng;

  late final List<_Snapshot> _history;
  int _historyHead = 0;
  bool _historyPrimed = false;

  double _lineOffset = 0;
  int _ticksSinceResample = 0;
  bool _wasInCorner = false;
  int _botchedTicks = 0;

  /// Ticks the car has spent going nowhere, and the recovery window it earns.
  int _stalledTicks = 0;
  int _unstickTicks = 0;

  /// Re-pick the line twice a second.
  static const int _resampleEveryTicks = 60;

  /// Below this speed a car that should be racing is stuck on something.
  static const double _stalledSpeed = 14;
  static const int _stalledLimit = 100;
  static const int _unstickDuration = 55;

  /// Produces this tick's controls.
  CarInput update(RaceState state, RaceTrack track) {
    final me = state.car(side);
    if (state.phase != RacePhase.racing || me.finished) {
      return CarInput.coasting;
    }

    _remember(me);
    final seen = _delayed();

    _ticksSinceResample++;
    if (_ticksSinceResample >= _resampleEveryTicks) _resampleLine();

    // --- unstick ----------------------------------------------------------
    // A bot wedged against a tyre stack would otherwise sit there until the
    // race timed out, which is a worse outcome for the player than any amount
    // of bad driving.
    if (me.speed < _stalledSpeed) {
      _stalledTicks++;
    } else {
      _stalledTicks = 0;
    }
    if (_stalledTicks > _stalledLimit && _unstickTicks == 0) {
      _unstickTicks = _unstickDuration;
      _stalledTicks = 0;
    }
    if (_unstickTicks > 0) {
      _unstickTicks--;
      // Back up, turned away from whatever it is leaning on.
      return CarInput(steer: _lineOffset < 0 ? 1 : -1, brake: true);
    }

    // --- where to aim -----------------------------------------------------
    final lookahead =
        profile.lookaheadBase + seen.speed * profile.lookaheadPerSpeed;
    final aimDistance = seen.distance + lookahead;
    final aimCentre = track.pointAt(aimDistance);
    final aimForward = track.directionAt(aimDistance);
    final aimRight = Vec2(-aimForward.y, aimForward.x);
    final aim = aimCentre + aimRight * _lineOffset;

    final toAim = aim - seen.position;
    final range = toAim.length;

    // Component of the aim vector out of the driver's right window, over the
    // distance to it: the sine of the angle it needs to turn through. Built
    // from a dot product and one sqrt — no angle is ever formed.
    final steerSine = range < 1e-6
        ? 0.0
        : toAim.dot(Vec2(-seen.heading.y, seen.heading.x)) / range;

    // A dead zone stops the wheel chattering left-right on a straight.
    final steer = steerSine > 0.05 ? 1 : (steerSine < -0.05 ? -1 : 0);

    // --- how fast ---------------------------------------------------------
    final brakingSpan = 90 + seen.speed * 0.55;
    final bend = track.curvatureAhead(seen.distance, brakingSpan);

    // Entering a corner is where a driver makes a mistake, so that is where
    // the dice are rolled.
    final inCorner = bend > 0.16;
    if (inCorner && !_wasInCorner) {
      if (_mistakeRng.chance(profile.mistakeChance)) {
        // Miss the braking point entirely: carry terminal velocity into a
        // corner the tyres cannot hold, understeer wide, and pay for it on
        // the grass. Measured at 46 ticks this was invisible — the car ran
        // wide and tidied itself up inside the track's width, so every
        // difficulty finished every race perfectly clean and the whole ladder
        // collapsed into a comparison of top speeds. It has to be long enough
        // to actually put a wheel on the grass.
        _botchedTicks = 95;
      }
      _resampleLine();
    }
    _wasInCorner = inCorner;
    if (_botchedTicks > 0) _botchedTicks--;

    // Turn the bend into the speed the tyres will actually hold.
    //
    // Over an arc of length `s` and radius `r` the direction turns by
    // θ = s/r, and `curvatureAhead` reports (1 − cos θ)/2. For the shallow
    // angles a braking zone spans, 1 − cos θ ≈ θ²/2, so θ ≈ 2√bend and the
    // radius falls straight out. `sqrt` only — no arc-cosine, no trig, so the
    // bot stays as reproducible as the physics it is driving.
    final theta = 2 * math.sqrt(bend);
    final cornerRadius =
        theta < 1e-4 ? 1e9 : brakingSpan / theta;
    final gripSpeed = math.sqrt(RaceField.lateralGripLimit * cornerRadius);

    // Caution above 1 lifts earlier than it needs to and loses time; below 1
    // asks for more than the tyres have and runs wide. That is the dial the
    // player feels as the difference between a bot that is slow and one that
    // is quick but fallible.
    final targetSpeed = math.min(
      profile.targetTopSpeed,
      gripSpeed / profile.cornerCaution,
    );

    var throttle = false;
    var brake = false;
    if (_botchedTicks > 0) {
      // Mid-mistake: foot in, no brakes.
      throttle = true;
    } else if (seen.speed > targetSpeed * 1.06) {
      brake = true;
    } else if (seen.speed < targetSpeed) {
      throttle = true;
    }

    // Off the track it is always worth getting back up to speed, whatever the
    // corner ahead is doing.
    if (!me.onTrack && !brake) throttle = true;

    return CarInput(steer: steer, throttle: throttle, brake: brake);
  }

  void _resampleLine() {
    // Triangular distribution: the sum of two uniforms peaks at zero, so the
    // bot is usually near its line and occasionally well off it, like a person.
    final t = _lineRng.nextDouble() + _lineRng.nextDouble() - 1.0;
    _lineOffset = t * profile.lineNoise;
    _ticksSinceResample = 0;
  }

  void _remember(CarState car) {
    _history[_historyHead] = _Snapshot(
      car.position,
      car.heading,
      car.lastProjection,
      car.speed,
    );
    _historyHead = (_historyHead + 1) % _history.length;
    if (_historyHead == 0) _historyPrimed = true;
  }

  /// The car as it was [_reactionTicks] ago — the bot's delayed perception of
  /// its own machine.
  _Snapshot _delayed() =>
      _historyPrimed ? _history[_historyHead] : _history[0];

  /// Exposed for the balance tool's reporting.
  int get reactionTicks => _reactionTicks;
  int get tickHz => _tickHz;
}

class _Snapshot {
  const _Snapshot(this.position, this.heading, this.distance, this.speed);
  final Vec2 position;
  final Vec2 heading;
  final double distance;
  final double speed;
}
