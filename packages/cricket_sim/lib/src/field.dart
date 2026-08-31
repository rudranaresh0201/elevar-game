import 'package:game_core/game_core.dart';

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
  /// Raised from 360 with the physical bat. A slower ball is meant to be
  /// easier to *time*, not to be a gift: at 360 the extra flight let a batter
  /// re-place the blade after the bounce, so the difficulty that bowls the
  /// most spin — the hardest one — conceded the most runs.
  static const double slowestDelivery = 410;
  static const double fastestDelivery = 560;

  /// How far off a straight line the ball moves after pitching, at full
  /// deviation. Seam and spin are the same mechanic with different numbers.
  ///
  /// Raised from 145 when the bat became a place rather than a swing window,
  /// and that change is the reason. A bat you *hold on a line* is beaten by
  /// exactly one thing: the ball not staying on the line. With 145 against a
  /// good length, the ball moved about 38 units in the distance left after
  /// pitching, which a 47-unit blade covered comfortably — so an accurate
  /// bowler, who repeats a line, was *easier* to face than a wild one, and the
  /// measured win rate went the wrong way with difficulty. At 200 a
  /// well-pitched seamer moves past the edge of the blade, which is both the
  /// correct answer and the interesting one.
  static const double maxDeviation = 200;

  /// Furthest up and back the ball may pitch. Beyond the first it is a
  /// full toss, before the second a bouncer — both still legal here, both
  /// easier to hit.
  static const double fullestLength = 880;
  static const double shortestLength = 660;

  // --- the bat -------------------------------------------------------------

  /// The plane the bat lives in, down the wicket.
  ///
  /// The bat is not an event any more. It is a **place**: a rectangle the
  /// player moves around in the `(across, height)` plane at [contactY], and a
  /// delivery is struck if the ball happens to pass through it.
  ///
  /// That replaced a timing window, and the reason is structural rather than
  /// cosmetic. A window has to be resolved some number of ticks *after* the
  /// ball crosses the bat, which made the window silently one-sided for a
  /// while and needed a paragraph of apology in the code to explain. A place
  /// resolves on the crossing tick, exactly, because there is nothing to wait
  /// for — the bat either was there or it was not.
  ///
  /// The three things a player controls fall straight out of it:
  ///
  /// * **across** — play the line. Get this wrong and you are beaten.
  /// * **height** — get under the ball to loft it, on top of it to keep it
  ///   down. Only a badly wrong height misses entirely; mostly it decides
  ///   *what kind of shot* you played.
  /// * **when you move** — the bat's own speed at the moment of contact is
  ///   what sends the ball anywhere. Park the bat on the line and you have
  ///   played a dead bat, however perfectly it was placed.
  static const double batPlaneY = contactY;

  /// Half-extents of the blade: across the pitch, and up off the ground.
  ///
  /// 30 rather than 38, and the eight units matter more than they look. With
  /// the ball radius the blade covers 39 units either side, against a
  /// good-length ball that can move up to 52 off the seam — so a bat placed on
  /// the pre-bounce line can be beaten by movement. At 38 it could not be, and
  /// the whole bowling ladder inverted on it: see [maxDeviation].
  static const double batHalfWidth = 30;

  /// Deliberately generous against the ball's actual height range, which is
  /// only about 5 to 35 units. Height is a shot-shaping axis, not a
  /// hit-or-miss one — only a bat on the deck against a climbing bouncer, or
  /// held high against a yorker, misses on height alone.
  static const double batHalfHeight = 20;

  /// How far either side of the stumps the bat may reach.
  static const double batReachX = 130;

  static const double batMinHeight = 0;
  static const double batMaxHeight = 70;

  /// Where the bat sits when nobody is doing anything with it.
  static const double batRestHeight = 14;

  /// How fast the bat may travel, in units/s.
  ///
  /// Two jobs, and the second one is why this number is as low as it is.
  ///
  /// It is the anti-teleport bound — a client that could move the bat
  /// infinitely fast would put it on every ball at the last instant, and the
  /// game would be a formality.
  ///
  /// And it is what makes deviation mean anything. This was 520 first, and at
  /// 520 the bat crossed the whole crease in half a second: after the ball
  /// pitched there were still 0.2 to 0.3 seconds left, in which the bat could
  /// travel 100 to 150 units and comfortably chase down any movement off the
  /// seam. Every ball was correctable, so nothing a bowler did mattered and the
  /// measured difficulty ladder ran the wrong way.
  ///
  /// 380 is the compromise, and it was measured in both directions. At 300 the
  /// ladder was clean but a thumb dragged across the pad took nearly nine
  /// tenths of a second to be followed, which reads as lag rather than as
  /// weight. At 380 the blade still only covers about 80 units after the
  /// bounce, against movement of up to 70 for a seamer and 200 for a big
  /// turner, so committing to a line is still a real decision with a real
  /// cost — and the win-rate ladder measured at both values is the same
  /// shape. **This is the first number to retune against real thumbs.**
  static const double batMaxSpeed = 380;

  /// The bat speed that counts as a full-blooded swing. Everything about how
  /// hard the ball leaves is measured against this, so it sits just under
  /// [batMaxSpeed]: a sweep at the cap is a shot played at full power.
  static const double batSwingReference = 310;

  /// How much of the return direction comes from where on the blade the ball
  /// was met.
  static const double batOffsetInfluence = 0.85;

  /// And how much from how fast the bat was travelling across the line.
  ///
  /// This is the term that separates a player who swings through the ball from
  /// one who holds the bat out and waits — which is to say, the one that makes
  /// this a game rather than a placement puzzle.
  static const double batVelocityInfluence = 0.0012;

  /// Bat centre for a normalised across-the-crease value, `0` leg to `1` off.
  static double batXFor(double normalised) =>
      pitchCentreX + (clampD(normalised, 0, 1) * 2 - 1) * batReachX;

  /// Bat centre height for a normalised value. `0` is bat up, `1` is bat on
  /// the deck — a thumb dragged down the glass lowers the bat.
  static double batHeightFor(double normalised) =>
      batMaxHeight +
      (batMinHeight - batMaxHeight) * clampD(normalised, 0, 1);

  /// How hard a delivery pitching at [pitchY], aimed at [targetX], is to bat
  /// at. Zero for a long hop down the leg side, one for a ball on a length
  /// hitting the top of off.
  ///
  /// Length is worth more than line, which is how bowling actually works: a
  /// ball on a good length is awkward wherever it is, and a ball short and wide
  /// is a gift however straight the seam was pointing.
  ///
  /// Lives here rather than in the simulation because three separate things
  /// need it and they must agree: the bot batter, the scripted proxy human in
  /// the balance harness, and the simulation itself. A proxy that was *not*
  /// punished by good bowling made the whole bowling half of the ladder
  /// unmeasurable — every difficulty looked the same from the batting end,
  /// because the yardstick could not tell a jaffa from a long hop.
  static double deliveryDifficulty(double pitchY, double targetX) {
    const goodLength = 790.0;
    const lengthTolerance = 130.0;
    final lengthQuality =
        1 - clampD((pitchY - goodLength).abs() / lengthTolerance, 0, 1);
    final lineQuality =
        1 - clampD((targetX - pitchCentreX).abs() / 95, 0, 1);
    return clampD(0.62 * lengthQuality + 0.38 * lineQuality, 0, 1);
  }

  /// The normalised target the bat rests at between deliveries.
  static const Vec2 batStance = Vec2(
    0.5,
    (batMaxHeight - batRestHeight) / (batMaxHeight - batMinHeight),
  );

  /// Speed off the bat for a perfectly middled shot at full intent.
  /// Nudged up with the physical bat: the ceiling is now only reached by a
  /// blade moving at its own top speed through the middle of the bat, which is
  /// rarer than a full-intent slider ever was.
  static const double maxHitSpeed = 1420;

  /// How quickly a ball rolling along the ground gives up its speed, as a
  /// fraction shed per second.
  static const double outfieldDrag = 0.92;

  /// Upward speed imparted by a lofted shot at full intent, and the gravity
  /// that brings it back. Height is a scalar carried alongside the top-down
  /// position — there is no third axis in the simulation, only a number that
  /// says how far off the deck the ball is.
  /// Raised from 470 once loft came from getting under the ball rather than
  /// from a power slider. With the old value a well-middled lofted shot
  /// carried about 450 units against a straight boundary at 816: measured over
  /// three hundred innings, the game contained no sixes at all, which is a
  /// cricket game missing its best moment.
  static const double maxLoftSpeed = 690;
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
