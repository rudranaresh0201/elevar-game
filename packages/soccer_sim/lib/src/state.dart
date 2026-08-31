import 'package:game_core/game_core.dart';

import 'field.dart';
import 'world.dart';

/// Where a match is in its lifecycle.
enum SoccerPhase {
  /// Everything is on its formation spot and the ball is on the centre spot.
  /// A short freeze so nobody flicks into a screen that is still settling.
  kickoff,

  /// The side to play may grab one of its discs and drag. The shot clock is
  /// running.
  aiming,

  /// A flick has been taken and the physics is running it out. Nobody can do
  /// anything until everything stops.
  resolving,

  /// The ball is in the net; the freeze before the restart.
  goalScored,

  /// Match over.
  complete,
}

/// Why a turn ended. Surfaced to the HUD, because "you ran out of time" and
/// "you took your shot" should not look the same.
enum TurnEnd { flicked, timedOut }

/// One tick of the human's intent.
///
/// Three channels, and the same three whether one human is playing or two —
/// only the side to play can do anything, and whose turn it is derives from
/// the match state rather than from the input. That is what keeps a replay to
/// three channels for a whole match, and it means a verifier never has to be
/// told which mode was played to decode the log.
///
/// | channel | while nothing is held | while a disc is held |
/// |---|---|---|
/// | `pointerDown` | a finger is on the glass | still holding |
/// | `a` | finger x, across the pitch | pull vector x |
/// | `b` | finger y, up the pitch | pull vector y |
///
/// ## Why the second pair changes meaning
///
/// The obvious encoding is "where the finger is", for both. It was built that
/// way first and it has a flaw that only shows up at the edges of the pitch,
/// which is exactly where it matters: a normalised coordinate is clamped to
/// `[0, 1]`, so a player holding the disc nearest the bottom touchline has
/// 140 units of room to pull back into and cannot reach full power *in the
/// one direction they most want to shoot*. Measured rather than guessed — the
/// balance harness plays through the real gesture, and its scripted human was
/// losing turns to a clamp rather than to the bot.
///
/// Sending the pull *vector* instead removes the edge entirely: the finger can
/// travel anywhere on the glass and the disc it left behind does not care. The
/// components are mapped from `[-maxDragLength, +maxDragLength]` onto `[0, 1]`
/// so they still ride the replay's existing 16-bit grid, at a resolution of
/// about a hundredth of a unit.
///
/// What the touch layer gained is only the subtraction. Power, direction,
/// whether the drag was long enough to count and which disc is held are all
/// still decided by the simulation, so a tampered client cannot flick harder
/// than the drag it reports.
class SoccerInput {
  const SoccerInput({
    this.pointerDown = false,
    this.a = 0.5,
    this.b = 0.5,
  });

  /// A finger going down at [fieldPosition], reaching for a disc.
  factory SoccerInput.grab(Vec2 fieldPosition) => SoccerInput(
        pointerDown: true,
        a: clampD(fieldPosition.x / SoccerField.width, 0, 1),
        b: clampD(fieldPosition.y / SoccerField.height, 0, 1),
      );

  /// A finger that has dragged [pull] away from where it went down.
  ///
  /// The disc will travel *opposite* [pull]: the gesture is a slingshot.
  factory SoccerInput.pull(Vec2 pull, {required bool stillDown}) {
    final clamped = pull.length > SoccerField.maxDragLength
        ? pull.withLength(SoccerField.maxDragLength)
        : pull;
    return SoccerInput(
      pointerDown: stillDown,
      a: encodePullComponent(clamped.x),
      b: encodePullComponent(clamped.y),
    );
  }

  static const SoccerInput idle = SoccerInput();

  final bool pointerDown;

  /// Finger x, or pull x. See the table above.
  final double a;

  /// Finger y, or pull y.
  final double b;

  /// Read as a position on the pitch, in field units.
  Vec2 get fieldPosition =>
      Vec2(a * SoccerField.width, b * SoccerField.height);

  /// Read as a pull vector, in field units.
  Vec2 get pullVector =>
      Vec2(decodePullComponent(a), decodePullComponent(b));

  static double encodePullComponent(double v) =>
      clampD(0.5 + v / (2 * SoccerField.maxDragLength), 0, 1);

  static double decodePullComponent(double channel) =>
      (channel - 0.5) * 2 * SoccerField.maxDragLength;

  /// Packs into the three normalised `[0, 1]` channels the replay stores.
  List<double> toChannels() => <double>[pointerDown ? 1.0 : 0.0, a, b];

  /// The inverse, applied to values that have been through the replay's
  /// 16-bit grid.
  factory SoccerInput.fromChannels(List<double> channels) => SoccerInput(
        pointerDown: channels[0] > 0.5,
        a: channels[1],
        b: channels[2],
      );

  /// This input with every continuous channel snapped onto the replay grid.
  ///
  /// The live path calls this before the simulation ever sees a touch. Racing
  /// and cricket both learned the same lesson: a match played at full
  /// precision and recorded at 16 bits is a match that cannot be reproduced,
  /// because a simulation amplifies the smallest divergence until the scores
  /// differ.
  SoccerInput quantised() => SoccerInput(
        pointerDown: pointerDown,
        a: quantiseNormalised(a),
        b: quantiseNormalised(b),
      );
}

/// Something worth reacting to, emitted by a simulation step.
class SoccerEvent {
  const SoccerEvent(
    this.type, {
    required this.at,
    this.side,
    this.intensity = 1,
  });

  final SoccerEventType type;
  final Vec2 at;
  final SoccerSide? side;
  final double intensity;
}

enum SoccerEventType {
  /// A disc was grabbed. The renderer picks the disc up.
  grab,

  /// A flick was released.
  flick,

  discHit,
  ballHit,
  wallHit,
  postHit,
  goal,

  /// The shot clock ran out and the turn passed.
  turnTimeout,

  turnStart,
  matchComplete,
}

/// The live drag, as the simulation understands it.
///
/// The renderer draws the aim line from this rather than from its own copy of
/// the gesture, so what is drawn and what will actually be flicked cannot
/// disagree — including at the edges, where power clamps and the shot is
/// cancelled for being too short.
class AimState {
  const AimState({
    required this.discIndex,
    required this.origin,
    required this.anchor,
    required this.direction,
    required this.power,
  });

  static const AimState none = AimState(
    discIndex: -1,
    origin: Vec2.zero,
    anchor: Vec2.zero,
    direction: Vec2.zero,
    power: 0,
  );

  /// Index into [SoccerWorld.bodies], or -1 when nothing is held.
  final int discIndex;

  /// The held disc's centre.
  final Vec2 origin;

  /// Where the rubber band is stretched to, in field units: the disc's centre
  /// plus the drag. Not where the finger literally is — the finger may be
  /// anywhere on the glass, and after the first frame of a drag it usually is
  /// somewhere else entirely. This is the point the renderer draws the band
  /// back to, and it is derived from the same pull vector the flick will use,
  /// so the band cannot lie about the shot.
  final Vec2 anchor;

  /// Unit vector the disc will travel along — away from the finger, because
  /// the gesture is a slingshot: you pull back and let go.
  final Vec2 direction;

  /// 0..1.
  final double power;

  bool get isHolding => discIndex >= 0;

  /// True when releasing now would cancel rather than flick.
  bool get tooShort => power <= 0;
}

/// Everything the renderer needs, and everything the verifier compares.
class SoccerState {
  SoccerState({required this.world, required this.turn});

  final SoccerWorld world;

  SoccerPhase phase = SoccerPhase.kickoff;

  /// The side to play.
  SoccerSide turn;

  int p1Goals = 0;
  int p2Goals = 0;

  /// Turns taken by both sides together.
  int turnsTaken = 0;

  /// Ticks left in the current freeze, or on the shot clock.
  int freezeTicks = 0;

  /// Shot-clock ticks remaining this turn. Only meaningful in
  /// [SoccerPhase.aiming].
  int aimTicksLeft = 0;

  /// Ticks the current turn's physics has been running.
  int resolveTicks = 0;

  AimState aim = AimState.none;

  /// Who scored last, for the celebration banner.
  SoccerSide? lastScorer;

  /// How the previous turn ended.
  TurnEnd? lastTurnEnd;

  /// Flicks taken by P1 that ended with the ball closer to the opponent's
  /// goal than it started. The accuracy half of the skill score.
  int p1Flicks = 0;
  int p1ProgressiveFlicks = 0;

  /// Flicks by P1 that touched the ball at all. A flick that misses the ball
  /// entirely is the clearest signal of a beginner, and it is worth being able
  /// to see it in the numbers.
  int p1BallTouches = 0;

  bool get isComplete => phase == SoccerPhase.complete;

  int goalsFor(SoccerSide side) =>
      side == SoccerSide.p1 ? p1Goals : p2Goals;

  /// True while the human whose turn it is may touch the pitch.
  bool get acceptsInput => phase == SoccerPhase.aiming;

  /// The five disc indices belonging to the side to play.
  Iterable<int> get playableDiscs sync* {
    final first = SoccerWorld.firstDiscIndex(turn);
    for (var i = 0; i < SoccerField.discsPerSide; i++) {
      yield first + i;
    }
  }
}
