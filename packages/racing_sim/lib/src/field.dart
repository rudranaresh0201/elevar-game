/// Fixed dimensions and handling constants, in simulation units.
///
/// As with ping pong, the simulation never sees pixels: it runs in a 1000 x
/// 1500 space that the renderer scales onto whatever screen it is given. A
/// race therefore plays identically on a cheap phone and a tablet — which is a
/// correctness requirement rather than a nicety, because two devices must agree
/// on the finishing order for a replay to verify anything.
class RaceField {
  const RaceField._();

  static const double width = 1000;
  static const double height = 1500;

  // --- the car -------------------------------------------------------------

  /// Collision circle. Cars are drawn as rectangles but collide as circles:
  /// exact enough at this size, and it keeps car-car and car-scenery contact on
  /// one code path instead of three.
  static const double carRadius = 21;

  static const double carLength = 50;
  static const double carWidth = 28;

  // --- longitudinal --------------------------------------------------------

  /// Forward acceleration under full throttle, units/s².
  static const double engineForce = 265;

  /// Deceleration under the brake pedal. Stronger than the engine, as a real
  /// car's brakes are — stopping should always feel more decisive than going.
  static const double brakeForce = 540;

  /// Rolling + air resistance on dirt, as a fraction of speed shed per second.
  /// Top speed is not a clamp anywhere; it emerges where thrust meets drag, at
  /// `engineForce / dragOnTrack`.
  static const double dragOnTrack = 0.80;

  /// Grass. Slow enough that cutting a corner costs more than it saves — the
  /// whole reason a track has a shape at all — but no longer a tar pit.
  ///
  /// This was 3.30, which put terminal speed on grass at 80 units/s. Combined
  /// with the old fence behaviour that was measurably a trap: `tool/stuck.dart`
  /// drove off deliberately and then held full throttle with the wheel hard
  /// over for six seconds, and the car ended up at **0.6 units/s travelling
  /// backwards**. A player who runs wide should lose a second, not the race.
  static const double dragOnGrass = 2.30;

  /// Reversing is deliberately feeble: enough to undo a bad crash, never a
  /// tactic. Reached by holding the brake once already stopped.
  static const double reverseMaxSpeed = 110;
  static const double reverseForce = 190;

  // --- lateral -------------------------------------------------------------

  /// How quickly sideways velocity is scrubbed off on dirt, per second. This
  /// single number is what separates "on rails" from "ice rink"; the gap
  /// between it and [gripOnGrass] is what makes leaving the track feel like a
  /// mistake rather than a shortcut.
  static const double gripOnTrack = 7.6;

  /// Grass still slides — that is the point of it — but 2.6 meant a car that
  /// stepped a wheel off never stopped sliding, and the slide always ended
  /// against the fence.
  static const double gripOnGrass = 3.6;

  // --- steering ------------------------------------------------------------

  /// Peak yaw rate in radians per second, applied as a tangent — see
  /// `RaceSimulation._rotate` for why this never touches `sin` or `cos`.
  static const double turnRate = 2.65;

  /// Speed at which steering reaches full authority. Below it the car turns in
  /// proportion to how fast it is going, so a stationary car cannot pirouette.
  static const double fullSteeringSpeed = 90;

  /// The floor under that proportion, applied **only while the driver is on
  /// the throttle or the brake**.
  ///
  /// Without it, authority at a standstill is zero, and a car nosed into the
  /// fence at zero speed can never turn away from it: the throttle pushes into
  /// the fence, the fence cancels the velocity, speed stays at zero, and
  /// steering stays dead. That is a deadlock, and it is the single biggest
  /// reason the game felt unfair. Gating the floor on throttle-or-brake keeps
  /// the other half of the rule intact — a parked car with a thumb only on the
  /// rocker still does not pirouette, and there is a test for it.
  static const double minSteeringAuthority = 0.5;

  /// The grip limit, in units/s² of sideways acceleration.
  ///
  /// This is the most important number in the file. A tyre can only pull so
  /// hard sideways; ask for more yaw than that and the car pushes wide instead
  /// of turning. Without it a car can take any corner at any speed, braking
  /// becomes pointless, and — measured, not guessed — the whole difficulty
  /// ladder collapses into a comparison of top speeds. Every driver simply
  /// drove flat out and the faster one won 100% of the time.
  ///
  /// With it, arriving too fast costs you the corner. That is what makes a
  /// racing line exist, what makes the brake pedal worth a thumb, and what
  /// turns the bot's caution dial into something a player can feel.
  ///
  /// At 330 the fastest a car can hold a 300-unit radius is about 315 units/s
  /// against a terminal velocity of 331 — so the quick corners still need a
  /// lift and the slow ones still need the brake, but the margin for a
  /// slightly-late lift is real rather than notional. It was 270, which made
  /// almost every corner a braking corner and left a new player spinning off
  /// on lap one.
  static const double lateralGripLimit = 330;

  /// On grass there is much less to lean on — but enough to aim the car back
  /// at the circuit, which at 95 there was not.
  static const double lateralGripLimitGrass = 170;

  // --- contact -------------------------------------------------------------

  /// How bouncy a car-on-car shunt is. Low: nudging an opponent wide should
  /// cost them a line, not launch them into the scenery.
  static const double carRestitution = 0.42;

  /// Scenery is springier than a rival — hitting a tyre stack should sting.
  static const double obstacleRestitution = 0.55;

  /// How far past the dirt a car may stray before an invisible fence turns it
  /// back. Keeps a spun car inside the field without a wall the player can see
  /// and resent.
  static const double grassMargin = 132;

  // --- recovery ------------------------------------------------------------

  /// Below this speed, off the circuit, a car counts as stranded.
  static const double rescueSpeedThreshold = 42;

  /// How long it must stay stranded before the marshals pick it up. Two
  /// seconds: long enough that a scruffy corner exit is still the player's
  /// problem to drive out of, short enough that being beached never turns into
  /// watching the rest of the race happen.
  static const int rescueDelayTicks = 240;

  /// Dropped back on the racing line at a walking pace, pointing the right
  /// way. Not a free launch — rejoining slowly is itself the penalty, and it is
  /// a far better one than a rule telling the player their lap did not count.
  static const double rescueLaunchSpeed = 70;

  /// Cars line up this far either side of the centreline on the grid.
  static const double gridLateralOffset = 52;

  /// And this far apart along the track, so nobody is punted at lights-out.
  static const double gridStagger = 74;
}

/// Race format. Everything about how a race is won lives here, so a "quick
/// race" is a configuration rather than a second code path.
class RaceRules {
  const RaceRules({
    this.laps = 3,
    this.tickHz = 120,
    this.countdownTicks = 360,
    this.maxSeconds = 300,
    this.finishGraceSeconds = 12,
  });

  /// The default: three laps, roughly a minute of racing.
  static const RaceRules standard = RaceRules();

  /// Two laps, for the "one more go" loop.
  static const RaceRules quick = RaceRules(laps: 2);

  /// Five laps, for people who want a race rather than a sprint.
  static const RaceRules endurance = RaceRules(laps: 5);

  final int laps;
  final int tickHz;

  /// Three seconds of lights before the start. Long enough to get a thumb onto
  /// the pedal, short enough not to be skipped.
  final int countdownTicks;

  /// Hard duration cap.
  ///
  /// Not defensive padding: a race where somebody simply never drives has no
  /// natural end, which would leave the server's plausibility rules with no
  /// duration to check and would let two players farm playtime by parking on
  /// the grid. Every race terminates.
  final int maxSeconds;

  /// How long the loser gets to finish after the winner crosses the line
  /// before the race is called. Being lapped should not mean watching someone
  /// else's victory lap.
  final int finishGraceSeconds;

  double get stepSeconds => 1.0 / tickHz;
  int get maxTicks => maxSeconds * tickHz;
  int get finishGraceTicks => finishGraceSeconds * tickHz;
}
