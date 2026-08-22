import 'package:game_core/game_core.dart';

import 'field.dart';

/// Where a match is in its lifecycle.
enum PongPhase {
  /// Ball parked at the centre, waiting out the serve freeze.
  serving,

  /// Ball live.
  rally,

  /// A point has just been scored; the freeze before the next serve.
  pointScored,

  /// Match over.
  complete,
}

/// Which side of the net. P1 is always the bottom of the screen, and always the
/// logged-in account holder — in a two-human match the guest plays P2, and in a
/// bot match the bot does.
enum PongSide { p1, p2 }

/// A paddle.
///
/// Fields are mutable and owned by [PingPongSimulation]; treat them as
/// read-only from outside it.
class PaddleState {
  PaddleState({
    required this.position,
    required this.bounds,
    required this.maxSpeed,
    this.halfExtents = const Vec2(
      PongField.paddleHalfWidth,
      PongField.paddleHalfHeight,
    ),
  })  : previousPosition = position,
        velocity = Vec2.zero;

  Vec2 position;

  /// Position at the end of the previous tick, so the renderer can interpolate
  /// between simulation steps rather than snapping to them.
  Vec2 previousPosition;

  /// Units per second, measured over the last tick. Feeds the spin term on
  /// contact, so it is simulation state rather than a rendering convenience.
  Vec2 velocity;

  /// The rectangle this paddle may move within.
  Aabb bounds;

  /// Units per second this paddle may travel. For a human this is a generous
  /// cap that still forbids teleporting onto the ball; for the bot it is the
  /// primary difficulty dial.
  double maxSpeed;

  /// Full-size half-extents.
  Vec2 halfExtents;

  /// Current size as a fraction of [halfExtents]. Driven down during a
  /// stalemate (see [PongRules.stalemateAfterHits]) and reset each point.
  double scale = 1.0;

  /// The collider, at its current size.
  Aabb get body => Aabb(position, halfExtents * scale);

  double get currentHalfWidth => halfExtents.x * scale;
}

/// The ball.
class BallState {
  BallState({required this.position, required this.velocity})
      : previousPosition = position;

  Vec2 position;
  Vec2 previousPosition;
  Vec2 velocity;

  double get speed => velocity.length;
}

/// Something worth reacting to, emitted by a simulation step.
///
/// The simulation never plays a sound or shakes a screen — it says what
/// happened and lets the renderer decide. That separation is what keeps the
/// simulation runnable headlessly on a server.
class PongEvent {
  const PongEvent(this.type, {required this.at, this.side, this.intensity = 1});

  final PongEventType type;
  final Vec2 at;
  final PongSide? side;

  /// 0..1 — how hard, for scaling shake, particles and pitch.
  final double intensity;
}

enum PongEventType { serve, paddleHit, wallHit, point, matchComplete }

/// One tick of player intent.
///
/// Targets are **normalised** field coordinates in `[0, 1]`, not pixels and not
/// simulation units. That is deliberate: the replay format stores exactly these
/// numbers, so a replayed match feeds the simulation the identical values the
/// live match did, with no unit conversion in between to drift.
class PongInput {
  const PongInput({this.p1, this.p2});

  /// Null means "no new input this tick" — the simulation holds the last
  /// target, exactly as a thumb resting still on the glass would.
  final Vec2? p1;
  final Vec2? p2;

  static const PongInput none = PongInput();

  PongInput withP1(Vec2? v) => PongInput(p1: v, p2: p2);
  PongInput withP2(Vec2? v) => PongInput(p1: p1, p2: v);
}

/// Everything the renderer needs, and everything the verifier compares.
class PongState {
  PongState({
    required this.ball,
    required this.p1,
    required this.p2,
    required this.phase,
  });

  final BallState ball;
  final PaddleState p1;
  final PaddleState p2;

  PongPhase phase;

  int p1Score = 0;
  int p2Score = 0;

  /// Paddle hits in the current rally. Drives ball speed, audio pitch, and the
  /// rally component of the skill score.
  int rallyHits = 0;

  /// Longest rally of the match, for the end-of-match summary.
  int longestRally = 0;

  /// Ticks remaining in a serve or point freeze.
  int freezeTicks = 0;

  /// Side that will be served *towards* — always the one that just conceded, so
  /// the player who lost the point gets the ball.
  PongSide serveToward = PongSide.p1;

  int totalRallyHits = 0;
  int pointsPlayed = 0;

  bool get isComplete => phase == PongPhase.complete;

  int get leaderScore => p1Score > p2Score ? p1Score : p2Score;

  double get averageRally =>
      pointsPlayed == 0 ? 0 : totalRallyHits / pointsPlayed;
}
