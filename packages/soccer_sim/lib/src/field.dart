/// Fixed dimensions and handling constants, in simulation units.
///
/// As with every other game in the hub, the simulation never sees pixels: it
/// runs in a 1000 x 1800 space that the renderer letterboxes onto whatever
/// screen it is given. A match therefore plays identically on a cheap phone
/// and a tablet, which is a correctness requirement rather than a nicety — the
/// server must be able to re-simulate a submitted match and reach the same
/// score.
///
/// The pitch is portrait and the two goals face each other up the screen,
/// because two people share one phone and sit at opposite ends of it. P1 is
/// always at the bottom, as in ping pong and racing, so a player's colour and
/// a player's end mean the same thing in every game in the hub.
abstract final class SoccerField {
  static const double width = 1000;
  static const double height = 1800;

  static const double halfwayY = height / 2;
  static const double centreX = width / 2;

  // --- the pitch -----------------------------------------------------------

  /// Distance from the edge of the simulation space to the touchline. The
  /// band outside it is where the goal nets are drawn, so it has to be at
  /// least [goalDepth] deep.
  static const double margin = 96;

  static const double left = margin;
  static const double right = width - margin;

  /// P2 defends the top, P1 the bottom.
  static const double topGoalLine = margin;
  static const double bottomGoalLine = height - margin;

  /// Half-width of the goal mouth. The ball passes through this gap in the
  /// end line; a disc never does — a keeper cannot leave the pitch.
  ///
  /// At 168 against a disc radius of 46 the mouth is a little under two discs
  /// wide, which is the number that decides whether a parked keeper is a wall
  /// or a defender. Wider and the keeper is decorative; narrower and a 1-goal
  /// match can stall out entirely.
  static const double goalHalfWidth = 168;

  /// How far the net sits behind the goal line, for drawing and for the point
  /// at which a scored ball is parked.
  static const double goalDepth = 74;

  /// The posts, as immovable circles at each corner of each mouth. Without
  /// them a ball crossing the end line one unit outside the mouth teleports
  /// from "goal" to "goal kick" with nothing in between; with them it rattles,
  /// which is both fairer and the best thing that happens in a match.
  static const double postRadius = 13;

  // --- the bodies ----------------------------------------------------------

  static const double discRadius = 46;
  static const double ballRadius = 26;

  /// Discs are heavy and the ball is light, which is what makes a struck ball
  /// leave a disc faster than the disc was travelling. Stored as inverse mass
  /// because every impulse in `simulation.dart` divides by mass and never
  /// multiplies by it.
  static const double discInvMass = 1.0;
  static const double ballInvMass = 1.0 / 0.42;

  // --- flicking ------------------------------------------------------------

  /// Drag length, in field units, that counts as full power. About a fifth of
  /// the pitch: long enough that power is a real choice, short enough that a
  /// thumb can reach the end of it without leaving the glass.
  static const double maxDragLength = 300;

  /// Shorter than this and the flick is cancelled rather than dribbled — a
  /// mis-grab should hand the disc back, not waste the turn.
  static const double minDragLength = 26;

  /// Launch speed at full power.
  ///
  /// Paired with [discDamping] this is the number that sets the size of the
  /// game: a full-power flick travels about 1030 units before stopping, which
  /// is a little over half the pitch. A shot from the halfway line reaches the
  /// goal; a shot from your own box does not.
  static const double maxFlickSpeed = 2450;

  /// Speed at the shortest drag that still counts. Sets the floor on a tap
  /// that was meant to be a nudge.
  static const double minFlickSpeed = 380;

  /// How close a touch must start to a disc's centre to grab it. Generous on
  /// purpose — a 46-unit disc is about 9 mm on a phone, and a thumb is wider
  /// than that.
  static const double grabRadius = 108;

  // --- how motion dies -----------------------------------------------------

  /// Per-tick velocity retention at 120 Hz.
  ///
  /// Exponential rather than a constant friction force, for one reason that
  /// matters: `pow` with a variable exponent is libm and is banned by the
  /// determinism contract, but a repeated multiply by a literal is exact
  /// everywhere. Total travel for a launch at speed `v` is roughly
  /// `v / tickHz / (1 - damping)`.
  static const double discDamping = 0.9772;

  /// The ball keeps rolling after the discs have stopped, which is what makes
  /// a shot feel struck rather than carried.
  static const double ballDamping = 0.9855;

  /// Below this, a body is stopped outright. Without a floor, exponential
  /// decay never actually reaches zero and a turn never ends.
  static const double restSpeed = 15;

  /// Hard ceiling on any body's speed.
  ///
  /// This is not a game-feel dial, it is the tunnelling bound. The physics
  /// runs [substepsPerTick] substeps of `1/120` s, so the furthest any body
  /// moves between overlap tests is `speedCap / 120 / substeps` = 7.3 units
  /// against a smallest radius of 26. Deep tunnelling is arithmetically
  /// impossible; raise this without raising the substep count and it stops
  /// being.
  static const double speedCap = 3500;

  /// Physics substeps per simulation tick. See [speedCap].
  static const int substepsPerTick = 4;

  // --- how hard things bounce ---------------------------------------------

  /// Disc on disc. Low: two heavy counters clack and stop rather than scatter.
  static const double discDiscRestitution = 0.42;

  /// Disc on ball. High: this is the one collision the whole game is about.
  static const double discBallRestitution = 0.88;

  static const double discWallRestitution = 0.38;
  static const double ballWallRestitution = 0.72;

  /// Ball on post. Slightly livelier than a wall, because a ball coming back
  /// off the woodwork is the most exciting thing on the pitch.
  static const double postRestitution = 0.80;

  // --- the formation -------------------------------------------------------

  /// Five discs a side, laid out as the reference art has them: a keeper on
  /// the line, one out in front of it, and a front three around the centre
  /// circle.
  ///
  /// Written for P1 (bottom half) and mirrored through [halfwayY] for P2, so
  /// the two sides are exactly symmetric — a formation that favoured one end
  /// would show up as a bot win rate that moved when you swapped sides, which
  /// is a bug that takes a day to find.
  static const List<(double, double)> p1Formation = <(double, double)>[
    (centreX, 1660), // keeper
    (centreX, 1420), // sweeper
    (centreX - 178, 1120), // left
    (centreX, 1010), // centre
    (centreX + 178, 1120), // right
  ];

  static const int discsPerSide = 5;

  /// The kickoff spot.
  static const double centreSpotY = halfwayY;

  /// Radius of the centre circle. Drawn, and used for one rule: at kickoff the
  /// side not taking it may not be inside it. Since both formations start
  /// outside it anyway, this only matters if the formation is ever retuned.
  static const double centreCircleRadius = 150;

  /// Mirrors a P1 y-coordinate into P2's half.
  static double mirrorY(double y) => height - y;

  /// Which way is "forward" for [side] — the direction of the goal it attacks.
  /// Built as a component, never from an angle.
  static double attackDirection(SoccerSide side) =>
      side == SoccerSide.p1 ? -1.0 : 1.0;

  /// The centre of the goal [side] is attacking.
  static double attackGoalY(SoccerSide side) =>
      side == SoccerSide.p1 ? topGoalLine : bottomGoalLine;

  /// The centre of the goal [side] is defending.
  static double defendGoalY(SoccerSide side) =>
      side == SoccerSide.p1 ? bottomGoalLine : topGoalLine;
}

/// Which end of the phone. P1 is always the bottom, and always the account
/// holder — in a two-human match the guest plays P2, and in a bot match the
/// bot does.
enum SoccerSide {
  p1,
  p2;

  SoccerSide get other => this == SoccerSide.p1 ? SoccerSide.p2 : SoccerSide.p1;

  String get wire => name;
}

/// Match rules. Everything tunable about how a match is won lives here, so a
/// "quick match" is a config change rather than a code path.
class SoccerRules {
  const SoccerRules({
    this.targetGoals = 3,
    this.maxTurns = 44,
    this.tickHz = 120,
    this.aimTicks = 1440,
    this.kickoffFreezeTicks = 66,
    this.goalFreezeTicks = 180,
    this.maxResolveTicks = 660,
    this.botThinkTicks = 78,
  });

  /// The default. First to three, which is about three and a half minutes.
  static const SoccerRules standard = SoccerRules();

  /// The "one more go" loop: first to two, under two minutes.
  static const SoccerRules quick =
      SoccerRules(targetGoals: 2, maxTurns: 26);

  /// A longer tie for two people who have settled in.
  static const SoccerRules cup = SoccerRules(targetGoals: 5, maxTurns: 70);

  /// Goals that win the match.
  final int targetGoals;

  /// Hard ceiling on turns taken.
  ///
  /// Every match must terminate, and not only for tidiness: the server's
  /// plausibility rules check score against elapsed time, and a format with no
  /// upper bound gives them nothing to check. At the cap, whoever is ahead
  /// wins and a level score is a draw.
  final int maxTurns;

  final int tickHz;

  /// How long a player has to take their turn. Twelve seconds at 120 Hz.
  ///
  /// A shot clock is the difference between a shared-screen game and a
  /// hostage situation. It also bounds match duration independently of
  /// [maxTurns], which is what makes the duration check on the server mean
  /// something.
  final int aimTicks;

  /// Pause on the kickoff before the clock starts.
  final int kickoffFreezeTicks;

  /// Pause after a goal, for the celebration to land. 1.5 s.
  final int goalFreezeTicks;

  /// Longest a single turn's physics may run before every body is stopped by
  /// force. 5.5 s — comfortably longer than anything a full-power flick
  /// actually produces, and a guarantee that a pathological pinball between
  /// two discs cannot hang the match.
  final int maxResolveTicks;

  /// How long the bot appears to think before it flicks.
  ///
  /// Not decoration. The bot's shot is chosen in one burst at the start of
  /// this window (see `SoccerBot.chooseShot`), and the pause is what turns
  /// that single frame of work into something that reads as deliberation
  /// rather than a stutter.
  final int botThinkTicks;

  double get stepSeconds => 1.0 / tickHz;

  /// True when [a] versus [b] ends the match on goals alone.
  bool isMatchOver(int a, int b) => a >= targetGoals || b >= targetGoals;
}
