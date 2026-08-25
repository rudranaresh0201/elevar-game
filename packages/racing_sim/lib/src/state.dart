import 'package:game_core/game_core.dart';

import 'field.dart';

/// Where a race is in its lifecycle.
enum RacePhase {
  /// Lights out in a moment. Cars are on the grid and inputs are ignored.
  countdown,

  /// Green flag.
  racing,

  /// Somebody has taken the flag and the grace period has expired.
  complete,
}

/// Which car. P1 is always the account holder — the guest drives P2 in a
/// shared-screen race, the bot drives it otherwise. Same convention as ping
/// pong, deliberately: the scoring layer should never have to ask which game
/// it is looking at.
enum RacerSide { p1, p2 }

/// What the surface under a car is doing to it.
enum Surface { dirt, grass }

/// One tick of a driver's intent.
///
/// [steer] is already reduced to -1, 0 or +1 by the time the simulation sees
/// it. That is not a simplification of the physics but a property of the
/// controls: a thumb on a button is on or off, and the bot is held to the same
/// three values so it can never make an input a human could not.
class CarInput {
  const CarInput({this.steer = 0, this.throttle = false, this.brake = false});

  static const CarInput coasting = CarInput();

  final int steer;
  final bool throttle;
  final bool brake;

  /// Packs into the three normalised `[0, 1]` channels the replay format
  /// stores. Steering rides the middle of the range so neutral is 0.5.
  List<double> toChannels() => <double>[
        (steer + 1) / 2.0,
        throttle ? 1.0 : 0.0,
        brake ? 1.0 : 0.0,
      ];

  /// The inverse, applied to values that have been through the replay's 16-bit
  /// grid.
  ///
  /// The thresholds are what make the round trip exact. Quantising 0.5 gives
  /// back 0.50000762…, and feeding that straight in as a steering value would
  /// have a "straight" car drift a few degrees a lap — a divergence that a
  /// simulation compounds until the replay and the race disagree about who
  /// won. Snapping to the three states the buttons can actually produce closes
  /// that gap exactly, on the live path and the verifier's alike.
  factory CarInput.fromChannels(List<double> channels, int offset) {
    final rawSteer = channels[offset] * 2 - 1;
    return CarInput(
      steer: rawSteer < -0.33 ? -1 : (rawSteer > 0.33 ? 1 : 0),
      throttle: channels[offset + 1] > 0.5,
      brake: channels[offset + 2] > 0.5,
    );
  }

  /// Channels consumed per car.
  static const int channelCount = 3;
}

/// Both drivers' intent for one tick. A null side means "no new input", and the
/// simulation holds the last one — exactly as a thumb resting on a pedal does.
class RaceInput {
  const RaceInput({this.p1, this.p2});

  static const RaceInput none = RaceInput();

  final CarInput? p1;
  final CarInput? p2;
}

/// A car.
///
/// Fields are mutable and owned by `RaceSimulation`; treat them as read-only
/// from outside it.
class CarState {
  CarState({
    required this.position,
    required this.heading,
    required this.side,
  })  : previousPosition = position,
        previousHeading = heading,
        velocity = Vec2.zero;

  final RacerSide side;

  Vec2 position;
  Vec2 heading;
  Vec2 velocity;

  /// Position and heading at the end of the previous tick, so the renderer can
  /// interpolate between simulation steps instead of snapping to them.
  Vec2 previousPosition;
  Vec2 previousHeading;

  /// Which centreline segment this car projected onto last tick. Carried in
  /// the state rather than recomputed from scratch because the *windowed*
  /// search it seeds is the anti-cut rule — see `RaceTrack.project`.
  int segmentHint = 0;

  /// Raw projected arc distance last tick, before unwrapping.
  double lastProjection = 0;

  /// Total distance travelled along the racing line, unwrapped so it keeps
  /// climbing past the start line and *falls* if the car goes backwards. Race
  /// position is a comparison of this one number.
  double travelled = 0;

  int lap = 0;

  Surface surface = Surface.dirt;

  bool finished = false;
  int finishTick = 0;

  /// Tick each completed lap was finished on.
  final List<int> lapTicks = <int>[];
  int lapStartTick = 0;

  /// Ticks spent with all four wheels on the dirt, and ticks raced in total.
  /// Their ratio is the "clean driving" half of the skill score.
  int onTrackTicks = 0;
  int racingTicks = 0;

  /// Consecutive ticks spent stranded — off the circuit and barely moving.
  /// Reaching [RaceField.rescueDelayTicks] calls the marshals out.
  int strandedTicks = 0;

  /// Counts down after a rescue, purely so the renderer can flash the car and
  /// the HUD can say what just happened. Nothing in the physics reads it.
  int rescueFlashTicks = 0;

  /// How many times this car has been recovered. Shown on the result screen,
  /// and a far more honest measure of a scrappy race than lap time alone.
  int rescues = 0;

  /// True while the marshals are on their way — the car is stranded and the
  /// clock is running down. The HUD uses this to explain itself *before* the
  /// screen changes under the player, which is the difference between a rescue
  /// reading as help and reading as a glitch.
  bool get awaitingRescue => strandedTicks > RaceField.rescueDelayTicks ~/ 3;

  /// Ticks until the pickup, for the HUD's countdown ring.
  int get ticksToRescue =>
      (RaceField.rescueDelayTicks - strandedTicks).clamp(0, 1 << 30);

  /// How sideways the car is, 0..1. Derived state, but the simulation owns it
  /// because both the dust plumes and the skid marks key off it and they must
  /// not disagree.
  double slip = 0;

  double get speed => velocity.length;

  /// Speed along the direction the car is pointing. Negative when reversing.
  double get forwardSpeed => velocity.dot(heading);

  bool get onTrack => surface == Surface.dirt;

  /// Unit vector out of the driver's right window.
  Vec2 get right => Vec2(-heading.y, heading.x);
}

/// Something worth reacting to. The simulation never plays a sound or throws a
/// particle — it says what happened and lets the renderer decide.
class RaceEvent {
  const RaceEvent(this.type, {required this.at, this.side, this.intensity = 1});

  final RaceEventType type;
  final Vec2 at;
  final RacerSide? side;

  /// 0..1 — how hard, for scaling shake, dust and haptics.
  final double intensity;
}

enum RaceEventType {
  countdownBeep,
  /// The marshals lifted a stranded car back onto the racing line.
  rescued,
  go,
  lapComplete,
  carContact,
  obstacleContact,
  wentOffTrack,
  cameBackOn,
  finish,
  raceComplete,
}

/// Everything the renderer needs and everything the verifier compares.
class RaceState {
  RaceState({required this.p1, required this.p2, required this.phase});

  final CarState p1;
  final CarState p2;

  RacePhase phase;

  /// Ticks left in the countdown, then unused.
  int countdownTicks = 0;

  /// Ticks left before a finished race is called, once the winner is home.
  int graceTicks = 0;

  RacerSide? winner;

  bool get isComplete => phase == RacePhase.complete;

  CarState car(RacerSide side) => side == RacerSide.p1 ? p1 : p2;

  /// Who is ahead right now, by distance travelled along the racing line.
  RacerSide get leader => p1.travelled >= p2.travelled ? RacerSide.p1 : RacerSide.p2;

  /// 1 or 2 — where [side] currently runs.
  int positionOf(RacerSide side) => leader == side ? 1 : 2;
}
