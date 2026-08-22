/// Fixed dimensions of the play field, in simulation units.
///
/// The simulation never sees pixels. It runs in a 1000 x 1800 space and the
/// renderer scales that to whatever the device is; a match therefore plays
/// identically on a small phone and a tablet, which is a correctness
/// requirement, not just a nicety — two devices must agree on the outcome for
/// replay verification to mean anything.
class PongField {
  const PongField._();

  static const double width = 1000;
  static const double height = 1800;

  /// Halfway line. Below it belongs to P1 (red), above to P2 (blue).
  static const double netY = height / 2;

  static const double ballRadius = 30;

  /// Paddles are wide and shallow, so where you hit matters more than whether.
  static const double paddleHalfWidth = 74;
  static const double paddleHalfHeight = 30;

  /// Neither paddle may camp on the net; there has to be room to react.
  static const double paddleGapFromNet = 150;

  /// Nor may a paddle retreat into the goal line and become a wall.
  static const double paddleGapFromEnd = 120;

  /// How fast a dragged paddle may travel. High enough to feel one-to-one with
  /// a thumb, low enough that a tampered client cannot teleport a paddle onto
  /// the ball at the last instant.
  static const double humanPaddleMaxSpeed = 3600;

  /// The speed a strong human actually sustains. Bot speeds are expressed as a
  /// fraction of this, so difficulty means something concrete.
  static const double referenceHumanSpeed = 2600;

  static const double ballInitialSpeed = 1500;
  static const double ballMaxSpeed = 4200;

  /// Multiplier applied to ball speed on every paddle hit. Rallies accelerate,
  /// which is what makes a long one tense rather than tedious.
  static const double ballSpeedGain = 1.085;

  /// How much of the return direction comes from where on the paddle you hit.
  static const double hitOffsetInfluence = 1.25;

  /// How much comes from how fast the paddle was moving at contact. This is the
  /// term that separates a player who swipes through the ball from one who
  /// parks the paddle and waits — i.e. the one that makes the game skilful.
  static const double paddleVelocityInfluence = 0.00018;

  /// Minimum vertical share of the ball's direction. Without this, a grazing
  /// hit sends the ball nearly horizontal and the rally stalls forever.
  static const double minVerticalDirection = 0.30;

  static double p1MinY() => netY + paddleGapFromNet;
  static double p1MaxY() => height - paddleGapFromEnd;
  static double p2MinY() => paddleGapFromEnd;
  static double p2MaxY() => netY - paddleGapFromNet;

  static double minPaddleX() => paddleHalfWidth;
  static double maxPaddleX() => width - paddleHalfWidth;
}

/// Match rules. Everything tunable about how a match is won lives here so that
/// a "quick match" is a config change rather than a code path.
class PongRules {
  const PongRules({
    this.targetScore = 11,
    this.winBy = 2,
    this.hardCeiling = 21,
    this.tickHz = 120,
    this.serveFreezeTicks = 84,
    this.pointFreezeTicks = 96,
    this.stalemateAfterHits = 12,
    this.stalemateShrinkPerHit = 0.045,
    this.minPaddleScale = 0.26,
  });

  /// A three-minute-ish match.
  static const PongRules standard = PongRules();

  /// A sub-minute match, for the "one more go" loop.
  static const PongRules quick = PongRules(targetScore: 7, hardCeiling: 13);

  final int targetScore;

  /// Win-by-two, as real table tennis plays it.
  final int winBy;

  /// Deuce cannot run forever: at this score the next point simply wins. Bounds
  /// match duration, which the server's plausibility rules depend on.
  final int hardCeiling;

  final int tickHz;

  /// Pause before the ball is launched, so nobody is serving into a thumb that
  /// is still travelling. 0.7 s at 120 Hz.
  final int serveFreezeTicks;

  /// Pause after a point, for the celebration to land. 0.8 s at 120 Hz.
  final int pointFreezeTicks;

  /// Rally length past which both paddles start shrinking.
  ///
  /// Two evenly matched players can otherwise rally indefinitely: the ball
  /// speed is capped, paddles are not, and neither side is ever forced into an
  /// error. That is a real problem beyond aesthetics — a match that never ends
  /// has no duration for the server's plausibility rules to check, and two
  /// players could park their paddles and farm playtime forever.
  ///
  /// Shrinking guarantees termination and, happily, is also the most exciting
  /// thing that could happen at that point in a rally.
  final int stalemateAfterHits;

  /// Fraction of paddle size lost per hit once shrinking has begun.
  final double stalemateShrinkPerHit;

  /// Paddles never shrink below this fraction of full size.
  final double minPaddleScale;

  double get stepSeconds => 1.0 / tickHz;

  /// Paddle size, as a fraction of full, for a rally [hits] long.
  double paddleScaleForRally(int hits) {
    if (hits <= stalemateAfterHits) return 1;
    final shrunk = 1 - (hits - stalemateAfterHits) * stalemateShrinkPerHit;
    return shrunk < minPaddleScale ? minPaddleScale : shrunk;
  }

  /// True when [a] versus [b] ends the match.
  bool isMatchOver(int a, int b) {
    final leader = a > b ? a : b;
    final trailer = a > b ? b : a;
    if (leader >= hardCeiling) return true;
    return leader >= targetScore && leader - trailer >= winBy;
  }
}
