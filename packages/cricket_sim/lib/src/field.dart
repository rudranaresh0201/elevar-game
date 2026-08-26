/// Fixed dimensions and handling constants, in simulation units.
///
/// As with the other two games, the simulation never sees pixels: it runs in a
/// 1000 x 1500 space that the renderer letterboxes onto whatever screen it is
/// given. An over therefore plays identically on a cheap phone and a tablet,
/// which is a correctness requirement rather than a nicety — the server must be
/// able to re-simulate a submitted innings and get the same score.
///
/// The numbers are *not* scaled from a real cricket ground. A 22-yard pitch on
/// a 150-yard field would be a thread down the middle of the screen, and the
/// pitch is where the entire game happens. The pitch is exaggerated and the
/// ground compressed, which is what every top-down cricket game does and what
/// the reference art assumes.
abstract final class CricketField {
  static const double width = 1000;
  static const double height = 1500;

  // --- the ground ----------------------------------------------------------

  /// The boundary is an ellipse, centred on the middle of the pitch.
  ///
  /// The proportions matter more than they look. The first version ran an
  /// 820-unit pitch through a 1312-unit ground — 62% of the height — which put
  /// the batter almost on the rope: the square boundary was 362 units away
  /// against 1072 straight. A 3:1 asymmetry makes slogging square strictly
  /// dominant, and it quietly decided every balance table, because the bot that
  /// heaved across the line most often was the one that scored most. A real
  /// pitch is a small strip in the middle of a large field and the ratio here
  /// is now about 1.9:1, which is roughly what a real ground gives you.
  static const double groundCentreX = 500;
  static const double groundCentreY = 720;
  static const double groundRadiusX = 468;
  static const double groundRadiusY = 590;

  /// The 30-yard circle, drawn and used for nothing else — fielding positions
  /// are literal coordinates, not derived from it.
  static const double innerCircleRadiusX = 262;
  static const double innerCircleRadiusY = 330;

  // --- the pitch -----------------------------------------------------------

  static const double pitchCentreX = 500;
  static const double pitchHalfWidth = 46;

  /// Where the bowler lets go, and where the batter stands. The ball travels
  /// between them down the negative-to-positive y axis.
  static const double bowlerCreaseY = 520;
  static const double strikerCreaseY = 920;

  /// The batter stands just behind their crease.
  static const double strikerY = 946;

  /// Contact happens here — a little in front of the stumps, where a bat
  /// actually meets a ball.
  static const double contactY = 904;

  /// Half-width of the stumps. A ball passing the crease within this of the
  /// pitch centre, unstruck, is out.
  static const double stumpsHalfWidth = 15;

  static const double ballRadius = 9;

  // --- the delivery --------------------------------------------------------

  /// How fast the ball leaves the hand, in units/s, at the two ends of the
  /// pace range. A slower ball is easier to time and easier to hit hard.
  /// The pitch is 426 units end to end, so these are what set reaction time:
  /// roughly 0.76 s for the quickest ball and 1.18 s for the slowest. They came
  /// down from 980/620 when the pitch was shortened — at the old speeds the
  /// quick ball arrived in 0.43 s, which is not a contest.
  static const double slowestDelivery = 360;
  static const double fastestDelivery = 560;

  /// How far off a straight line the ball moves after pitching, at full
  /// deviation. Seam and spin are the same mechanic with different numbers.
  static const double maxDeviation = 145;

  /// Furthest up and back the ball may pitch. Beyond the first it is a
  /// full toss, before the second a bouncer — both still legal here, both
  /// easier to hit.
  static const double fullestLength = 880;
  static const double shortestLength = 660;

  // --- the bat -------------------------------------------------------------

  /// Ticks either side of the ideal contact tick that still count as contact
  /// at all. Quarter of a second either way at 120 Hz, and most of that window
  /// produces a bad shot rather than a good one.
  ///
  /// This has been wrong in both directions and the history is worth keeping.
  /// At 20 it was too tight *and* silently one-sided — the shot resolved on the
  /// tick the ball crossed the bat, so a late swing could never register at
  /// all, and both sides were bowled out for single figures. Fixing the
  /// asymmetry doubled the effective window, and at 30 nobody was ever beaten:
  /// across 240 innings there was not one bowled dismissal. 22 leaves a sloppy
  /// batter missing roughly one ball in seven and a good one hardly ever.
  static const int contactWindowTicks = 22;

  /// Ticks either side of ideal that count as *middled*. This is the number
  /// that decides whether the game feels generous or punishing, and it is
  /// deliberately generous — the reference for this hub is an arcade game.
  static const int perfectWindowTicks = 9;

  /// Speed off the bat for a perfectly middled shot at full intent.
  static const double maxHitSpeed = 1180;

  /// How quickly a ball rolling along the ground gives up its speed, as a
  /// fraction shed per second.
  static const double outfieldDrag = 0.92;

  /// Upward speed imparted by a lofted shot at full intent, and the gravity
  /// that brings it back. Height is a scalar carried alongside the top-down
  /// position — there is no third axis in the simulation, only a number that
  /// says how far off the deck the ball is.
  static const double maxLoftSpeed = 470;
  static const double gravity = 620;

  /// Above this height a fielder cannot reach the ball at all, so it sails
  /// over them.
  static const double catchReach = 54;

  // --- fielding ------------------------------------------------------------

  /// Was 232, which let the field converge on any shot inside a second and
  /// made placement irrelevant. A gap has to be worth finding.
  static const double fielderSpeed = 78;

  /// How fast a fielder who is *not* chasing wanders towards the ball, as a
  /// fraction of [fielderSpeed], and how close they are allowed to get.
  ///
  /// Purely cosmetic. It exists so a field does not look frozen while one
  /// player runs, and it is capped hard because a second chaser is how the
  /// game lost its boundaries in the first place.
  static const double backingUpPace = 0.22;
  static const double backingUpRadius = 150;

  /// How close a fielder must get to collect a ball on the ground, or to be
  /// under one in the air.
  static const double fieldingRadius = 26;
  /// Deliberately tight. A catch should be something that happens because the
  /// ball went straight to somebody, not because a fielder was vaguely nearby —
  /// and on a ground this size "vaguely nearby" covers a lot of it.
  static const double catchRadius = 19;

  /// Field units between the batter and the ball, per completed run.
  ///
  /// Batters are not simulated as bodies — modelling two people running between
  /// creases adds a run-out mechanic and a lot of code for something the player
  /// never controls. Runs come from **how far the ball is fielded from the
  /// bat**, which is exactly what the player's shot controls.
  ///
  /// This started out as ticks-until-fielded and that was structurally wrong,
  /// not merely mistuned. A harder-struck ball *reaches* a fielder sooner, so
  /// timing the ball well scored fewer runs than dribbling it: every difficulty
  /// ladder came out backwards, and the easy bot consistently outscored the
  /// hard one. Distance rewards the thing the player is trying to do.
  ///
  /// At 200, a ball stopped in the ring is a single, one chased into the deep
  /// is two, and one that beats everybody to the rope is four anyway.
  static const double unitsPerRun = 200;

  /// The most that can ever be run without finding the rope.
  static const int maxRunRuns = 3;
}

/// Match format. Everything about how an innings ends lives here, so a
/// "super over" is a configuration rather than a second code path.
class CricketRules {
  const CricketRules({
    this.overs = 2,
    this.wickets = 3,
    this.tickHz = 120,
    this.ballsPerOver = 6,
    this.deliveryGapTicks = 96,
    this.maxSecondsPerInnings = 240,
  });

  /// The default, and the one the mode-select screen calls POWERPLAY: two
  /// overs a side, three wickets, bat first then defend.
  static const CricketRules powerplay = CricketRules();

  /// One over each. The tiebreak format, and the fastest possible complete
  /// match — about forty seconds a side.
  static const CricketRules superOver = CricketRules(overs: 1, wickets: 2);

  /// Four overs, five wickets, for people who want an actual match.
  static const CricketRules chase = CricketRules(overs: 4, wickets: 5);

  final int overs;

  /// Wickets in hand. The innings ends on the last one — there is no
  /// "batting with a runner" and no tail.
  final int wickets;

  final int tickHz;
  final int ballsPerOver;

  /// Dead time between the ball settling and the next run-up starting. Long
  /// enough to read the score, short enough not to be skipped.
  final int deliveryGapTicks;

  /// Hard cap per innings.
  ///
  /// Not defensive padding. An innings where nobody ever swings has no natural
  /// end if a ball can be re-bowled, and the server needs a duration it can
  /// sanity-check. Every innings terminates.
  final int maxSecondsPerInnings;

  int get ballsPerInnings => overs * ballsPerOver;

  double get stepSeconds => 1.0 / tickHz;

  int get maxTicksPerInnings => maxSecondsPerInnings * tickHz;
}
