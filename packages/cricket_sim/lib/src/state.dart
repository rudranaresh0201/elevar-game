import 'package:game_core/game_core.dart';

import 'field.dart';
import 'ground.dart';

/// Where the match is.
enum CricketPhase {
  /// The bowler is running in. Nothing can be done yet, and this is where the
  /// player reads the field and decides what they are going to try.
  runUp,

  /// The ball is on its way down the pitch. The batter's swing window is
  /// inside this phase.
  delivery,

  /// Struck, missed, or nicked — the ball is loose and the fielders are
  /// chasing it.
  ballInPlay,

  /// The ball is dead, the scoreboard has moved, and the next run-up has not
  /// begun.
  betweenBalls,

  /// First innings done, second not started. The phone changes hands here in
  /// a two-player match.
  inningsBreak,

  complete,
}

/// Which side. P1 is always the account holder, as in every other game in the
/// hub — the scoring layer must never have to ask which game it is looking at.
enum CricketSide { p1, p2 }

/// Which role the human is performing right now.
enum Role { batting, bowling }

/// How a batter got out. Run-outs and stumpings are deliberately absent — see
/// `CricketField.ticksPerRun` for why there are no simulated bodies between
/// the creases.
enum Dismissal { none, bowled, caught }

/// What a delivery is trying to do. Pace and spin are the same mechanic with
/// different numbers: how fast, and how much it moves after pitching.
enum DeliveryKind {
  /// Quick and straight. Hardest to time, least movement.
  pace,

  /// Slower through the air, big deviation off the pitch. Easy to hit if you
  /// read it, easy to nick if you don't.
  spin,

  /// Very full and very fast. Bowled if missed, but sits up to be driven.
  yorker,

  /// Short. Sails through above the stumps so it cannot bowl anyone, but it
  /// arrives late and high and is the easiest ball to top-edge.
  bouncer;

  String get wire => name;
}

/// One tick of the human's intent.
///
/// The same four numbers mean different things depending on whether the human
/// is batting or bowling, and that is deliberate: it keeps the replay format
/// to four channels for a whole match rather than eight, and which role is
/// active at a given tick is derivable from the ball count, so a verifier
/// never has to be told.
///
/// | channel | batting | bowling |
/// |---|---|---|
/// | `action` | unused | release now |
/// | `x` | bat position across the crease | aim: line across the pitch |
/// | `y` | bat height, `0` up and `1` on the deck | aim: length down the pitch |
/// | `power` | unused | delivery kind |
///
/// Batting used to spend all four: a swing trigger, a shot direction and a
/// power. It now spends two, and they are the two a thumb already produces —
/// because the bat is a thing you *hold somewhere* rather than a button you
/// press. How hard the ball goes is not a channel at all any more; it is how
/// fast the bat happened to be moving, which the simulation measures for
/// itself.
class CricketInput {
  const CricketInput({
    this.action = false,
    this.x = 0.5,
    this.y = 0.5,
    this.power = 0.5,
  });

  static const CricketInput idle = CricketInput();

  final bool action;
  final double x;
  final double y;
  final double power;

  /// Packs into the four normalised `[0, 1]` channels the replay stores.
  List<double> toChannels() =>
      <double>[action ? 1.0 : 0.0, x, y, power];

  /// The inverse, applied to values that have been through the replay's 16-bit
  /// grid.
  ///
  /// Racing learned this the hard way and cricket inherits the lesson: the
  /// live match must consume the *quantised* values, not the raw touch, or a
  /// replay diverges from the match it claims to verify. Here the boolean is
  /// snapped to a threshold and the three continuous channels are already on
  /// the grid, so this is exact in both directions.
  factory CricketInput.fromChannels(List<double> channels, int offset) =>
      CricketInput(
        action: channels[offset] > 0.5,
        x: channels[offset + 1],
        y: channels[offset + 2],
        power: channels[offset + 3],
      );

  /// This input with every continuous channel snapped onto the replay grid.
  /// The live path calls this before the simulation ever sees a touch.
  CricketInput quantised() => CricketInput(
        action: action,
        x: quantiseNormalised(x),
        y: quantiseNormalised(y),
        power: quantiseNormalised(power),
      );

  /// Shot direction in field space, as a unit vector.
  ///
  /// The batter faces up the screen, so a swipe with negative y is straight
  /// down the ground. A zero-length swipe defaults to straight, which is what
  /// a panicked jab should do.
  Vec2 get shotDirection {
    final v = Vec2(x * 2 - 1, y * 2 - 1);
    return v.lengthSquared < 1e-6 ? const Vec2(0, -1) : v.normalized;
  }

  /// Where on the pitch the bowler is aiming: line across, length down.
  Vec2 get aimPoint => Vec2(
        CricketField.pitchCentreX +
            (x * 2 - 1) * CricketField.pitchHalfWidth * 2.4,
        CricketField.shortestLength +
            y * (CricketField.fullestLength - CricketField.shortestLength),
      );

  /// Which delivery the bowler asked for. Four buckets across the channel, so
  /// the value survives quantisation exactly.
  DeliveryKind get deliveryKind {
    if (power < 0.25) return DeliveryKind.pace;
    if (power < 0.5) return DeliveryKind.spin;
    if (power < 0.75) return DeliveryKind.yorker;
    return DeliveryKind.bouncer;
  }

  /// Where the batter wants the blade, as a normalised point.
  ///
  /// `x` runs leg to off across the crease and `y` runs from bat-up to
  /// bat-down, so a thumb dragged down the glass lowers the bat.
  Vec2 get batTarget => Vec2(clampD(x, 0, 1), clampD(y, 0, 1));

  /// Channels consumed per human. One human is acting at any moment, so this
  /// is the whole match's channel count.
  ///
  /// Still four, though batting now only uses two of them. Bowling needs all
  /// four, and a format that changed width depending on who was acting would
  /// make the replay unreadable without first replaying it.
  static const int channelCount = 4;
}

/// The ball, in flight or on the deck.
///
/// [height] is a scalar carried beside a top-down position rather than a third
/// axis. The simulation is two-dimensional and the number simply says how far
/// off the ground the ball is, which is all that catching and clearing the
/// rope actually need.
class BallState {
  BallState({required this.position})
      : previousPosition = position,
        velocity = Vec2.zero;

  Vec2 position;
  Vec2 previousPosition;
  Vec2 velocity;

  double height = 0;

  /// Height at the end of the previous tick.
  ///
  /// Needed for exactly one thing, and it is not rendering: finding the ball's
  /// height at the instant it crosses the bat's plane, which falls between two
  /// ticks. Interpolating between this and [height] is what makes the contact
  /// test exact rather than "whichever tick we happened to notice on".
  double previousHeight = 0;

  double verticalSpeed = 0;

  /// Set once the delivery has pitched, after which the deviation applies.
  bool pitched = false;

  /// Where down the wicket this delivery lands.
  double pitchY = CricketField.strikerCreaseY;

  /// Sideways kick off the seam or out of the hand, applied at the bounce.
  double deviation = 0;

  bool struck = false;

  /// True once the bat has actually met this ball.
  ///
  /// It used to mean "the player has committed to their one swing". There is
  /// no swing to commit to now: the bat is somewhere, continuously, and this
  /// records whether it turned out to be somewhere useful.
  bool swung = false;

  /// The tick a bat placed on the ball's line would meet it.
  ///
  /// Nothing is resolved by this any more — contact is decided by where the
  /// bat actually is when the ball crosses its plane. It survives because the
  /// bot and the scripted proxy both need something to time a swing against,
  /// and because the renderer counts down to it.
  int idealContactTick = 0;

  /// The tick the bat actually met the ball on, or -1 for a play and miss.
  int swingTick = -1;

  /// Where the ball was as it passed the bat, and how fast.
  ///
  /// Frozen at the contact line and used to resolve the shot afterwards. The
  /// resolution deliberately happens *later* than the crossing — see
  /// `CricketSimulation._advanceDelivery` — so the ball has moved on by then
  /// and its live position is no longer the right thing to hit from.
  Vec2? contactPosition;
  Vec2 contactVelocity = Vec2.zero;
  double contactHeight = 0;

  /// True once the ball has passed the bat, whether or not it was struck.
  bool get reachedBat => contactPosition != null;

  bool get airborne => height > 0.5;

  double get speed => velocity.length;
}

/// The blade, as a rectangle the player moves.
///
/// Lives in the `(across the pitch, height off the ground)` plane at
/// [CricketField.batPlaneY]. It is not a body in the top-down world — nothing
/// else on the field can collide with it — which is why it gets its own small
/// class rather than joining the fielders.
class BatState {
  BatState({required this.position, required this.halfExtents})
      : previousPosition = position,
        velocity = Vec2.zero;

  /// `x` is across the pitch in field units; `y` is height off the ground.
  Vec2 position;

  /// Position at the end of the previous tick, so the renderer can interpolate
  /// and so the contact test can find where the bat was mid-tick.
  Vec2 previousPosition;

  /// Units per second, measured over the last tick. This is the number that
  /// decides how hard the ball leaves, so it is simulation state rather than a
  /// rendering convenience.
  Vec2 velocity;

  final Vec2 halfExtents;

  double get speed => velocity.length;

  /// True when the bat covers a ball at [ballX], [ballHeight].
  bool covers(double ballX, double ballHeight, double ballRadius) =>
      (ballX - position.x).abs() <= halfExtents.x + ballRadius &&
      (ballHeight - position.y).abs() <= halfExtents.y + ballRadius;
}

/// One team's innings.
class InningsState {
  InningsState({required this.batting, this.target = -1});

  /// Who is holding the bat.
  final CricketSide batting;

  /// Runs to win, or -1 in the first innings. Present on the state rather
  /// than computed, because the chase needs it every tick to know whether the
  /// match is already over.
  final int target;

  int runs = 0;
  int wickets = 0;
  int balls = 0;

  /// Runs off each ball so far, with -1 marking a wicket. Drives the little
  /// over-by-over strip along the bottom of the HUD, which is the single
  /// clearest way to show a short innings.
  final List<int> timeline = <int>[];

  bool get chasing => target >= 0;

  bool get hasWon => chasing && runs >= target;

  int get oversCompleteBalls => balls;

  /// "1.4" — overs bowled, in the notation everybody already reads.
  String overs(CricketRules rules) =>
      '${balls ~/ rules.ballsPerOver}.${balls % rules.ballsPerOver}';
}

/// What happened off one delivery, once the ball is dead.
class BallResult {
  const BallResult({
    required this.runs,
    required this.dismissal,
    required this.boundary,
    required this.contactQuality,
  });

  final int runs;
  final Dismissal dismissal;

  /// 4 or 6, or 0 for anything that stayed inside the rope.
  final int boundary;

  /// How well the ball was struck, 0..1. Zero for a play and miss.
  final double contactQuality;

  bool get isWicket => dismissal != Dismissal.none;
}

/// Something worth reacting to. The simulation never plays a sound or throws a
/// particle — it says what happened and lets the renderer decide.
class CricketEvent {
  const CricketEvent(this.type, {this.at, this.value = 0, this.text});

  final CricketEventType type;
  final Vec2? at;

  /// Runs, for the scoring events.
  final int value;

  /// A fielder's name, a dismissal, whatever the banner needs.
  final String? text;
}

enum CricketEventType {
  runUpStart,
  release,
  pitched,
  middled,
  edged,
  playedAndMissed,
  fielded,
  four,
  six,
  runsScored,
  wicket,
  overComplete,
  inningsComplete,
  matchComplete,
}

/// Everything the renderer needs and everything the verifier compares.
class CricketState {
  CricketState({
    required this.first,
    required this.ball,
    required this.bat,
    required this.fielding,
  });

  /// The first innings, and the second once it exists.
  InningsState first;
  InningsState? second;

  BallState ball;

  /// The blade, wherever the batter has it.
  BatState bat;

  /// The ten players in the field, in the order the setting lists them.
  final List<Fielder> fielding;

  CricketPhase phase = CricketPhase.runUp;

  /// Ticks left in the current phase, where the phase is timed.
  int phaseTicks = 0;

  /// The innings currently being played.
  InningsState get current => second ?? first;

  /// Whose bat it is right now.
  CricketSide get striking => current.batting;

  /// The result of the last completed delivery, for the banner.
  BallResult? lastBall;

  CricketSide? winner;

  /// True when the match ended with the scores level.
  bool tied = false;

  bool get isComplete => phase == CricketPhase.complete;

  /// Runs for [side] across the whole match. Each side bats exactly once, so
  /// this is a lookup rather than a sum.
  int runsFor(CricketSide side) {
    if (first.batting == side) return first.runs;
    return second?.runs ?? 0;
  }

  int wicketsFor(CricketSide side) {
    if (first.batting == side) return first.wickets;
    return second?.wickets ?? 0;
  }
}
