import 'package:game_core/game_core.dart';

import 'field.dart';
import 'state.dart';

/// A difficulty setting, expressed as dials rather than three algorithms.
///
/// Every difficulty runs the same batter and the same bowler; only these
/// numbers change. Same reason as the other two games: "hard" cannot contain a
/// bug that "easy" doesn't, and the curve is retunable without touching logic.
class BotProfile {
  const BotProfile({
    required this.timingSpreadTicks,
    required this.aggression,
    required this.wildSwingChance,
    required this.lineReadError,
    required this.bowlingAccuracy,
    required this.yorkerChance,
    required this.catchReliability,
  });

  /// How far off perfect the bot's bat arrives, in ticks, at the wide end of
  /// its spread. The single biggest contributor to how many runs it scores.
  ///
  /// It buys more than it used to. A tick of lateness is now a *place* the bat
  /// is not — about 2.5 units of the 39 either side of centre that the blade
  /// covers — rather than a fraction of a timing window, so the same numbers
  /// bite harder and the spread between difficulties had to be widened to keep
  /// the ladder a slope.
  final int timingSpreadTicks;

  /// How hard it swings, 0..1 — and therefore how often it goes aerial and
  /// how often it holes out.
  ///
  /// **Barely varies with difficulty, on purpose.** Tying aggression to skill
  /// inverted the entire ladder twice, once in the scripted proxy and then
  /// again here: the hard bot swung hardest, went aerial most, holed out most,
  /// and ended up the *easiest* of the three to beat — 90% against it versus
  /// 60% against easy. Choosing to slog is a decision available to any player
  /// at any standard. Skill lives in [timingSpreadTicks], [lineReadError],
  /// [wildSwingChance] and [bowlingAccuracy], all of which are monotonic.
  final double aggression;

  /// Probability of a heave across the line on any given ball.
  ///
  /// Not a bug being papered over. A bot that never errs is not hard, it is
  /// unbeatable, and a player who cannot take a wicket stops playing.
  final double wildSwingChance;

  /// How badly it misreads where the ball is going, in field units. Drives
  /// the alignment half of shot quality, so a high value produces plenty of
  /// contact but very little of it out of the middle.
  final double lineReadError;

  /// How close its deliveries land to where it aimed, 0..1. One is perfect.
  final double bowlingAccuracy;

  /// How often it goes for the hard ball at the death rather than the safe
  /// one. Pure flavour at easy, genuinely awkward at hard.
  final double yorkerChance;

  /// Probability of holding a catch it gets under.
  final double catchReliability;

  static const BotProfile easy = BotProfile(
    timingSpreadTicks: 40,
    aggression: 0.50,
    wildSwingChance: 0.34,
    lineReadError: 82,
    bowlingAccuracy: 0.40,
    yorkerChance: 0.06,
    catchReliability: 0.62,
  );

  static const BotProfile medium = BotProfile(
    timingSpreadTicks: 22,
    aggression: 0.55,
    wildSwingChance: 0.18,
    lineReadError: 42,
    bowlingAccuracy: 0.66,
    yorkerChance: 0.20,
    catchReliability: 0.80,
  );

  static const BotProfile hard = BotProfile(
    // Widened from 9 and 15 once the field stopped swallowing every lofted
    // shot. Against a slow, realistic field those numbers meant the hard bot
    // middled essentially everything and made 34 off twelve balls, which no
    // human innings could chase: it won 97-100% at every standard. A bot that
    // cannot be beaten is not a difficulty setting.
    timingSpreadTicks: 12,
    aggression: 0.60,
    wildSwingChance: 0.11,
    lineReadError: 22,
    bowlingAccuracy: 0.90,
    yorkerChance: 0.38,
    catchReliability: 0.92,
  );

  static BotProfile of(BotDifficulty difficulty) => switch (difficulty) {
        BotDifficulty.easy => easy,
        BotDifficulty.medium => medium,
        BotDifficulty.hard => hard,
      };
}

/// The bot's plan for one delivery, decided at release and then executed.
///
/// Deciding once rather than re-deciding every tick is what makes the bot look
/// like it is playing a shot instead of tracking the ball: a batter commits,
/// and commitment is what produces both the good shots and the mistakes.
///
/// The bot has no thumb, but it has the same bat everybody else has, so a plan
/// is now a *movement* rather than a trigger: hold the stance, then sweep from
/// there through [aim] and on to [aim] + [through], taking [swingTicks] over
/// it. Everything that used to be a separate dial falls out of that one
/// movement — the bat's speed at contact is how hard the shot was hit, and
/// arriving early or late is how a mistimed one happens.
class BattingPlan {
  const BattingPlan({
    required this.swingStartTick,
    required this.swingTicks,
    required this.aim,
    required this.through,
    required this.intent,
  });

  /// When the bat leaves the stance.
  final int swingStartTick;

  /// How long the sweep takes. Short is fast, and fast is hard — this is what
  /// the bot's power is, rather than a number it declares.
  final int swingTicks;

  /// Where it wants to meet the ball, normalised.
  final Vec2 aim;

  /// How far past [aim] the sweep carries on, normalised.
  ///
  /// Without a follow-through the bat would decelerate onto its target and be
  /// stationary at exactly the moment the ball arrived — a dead bat, every
  /// ball, however well aimed. This is what makes the blade still be moving
  /// when the two meet.
  final Vec2 through;

  final double intent;

  /// The fraction of the sweep at which the bat passes [aim]. Fixed rather
  /// than derived so the arrival time can be solved for in one line when the
  /// plan is built.
  static const double aimFraction = 0.7;

  /// Builds a sweep that travels at [intent] of the bat's top speed and passes
  /// through [aim] at [contactTick], give or take [timingError] ticks.
  ///
  /// The duration is *solved for* rather than chosen, and that is the whole
  /// point of this constructor. The first version picked a tick count directly
  /// and let the distance fall where it may; because the normalised
  /// follow-through was small, the blade turned out to be crawling at about a
  /// third of its top speed on every shot, and across three hundred simulated
  /// innings not one ball was hit for six. How hard you hit it is how fast the
  /// bat is moving, so how fast the bat moves has to be the input.
  ///
  /// Shared by the bot and by the scripted proxy in `replay_harness.dart`. Two
  /// copies of this arithmetic would drift, and the proxy exists to measure the
  /// bot — a yardstick that swings differently is not measuring anything.
  factory BattingPlan.sweep({
    required int contactTick,
    required Vec2 aim,
    required Vec2 through,
    required double intent,
    required int timingError,
  }) {
    final stance = CricketField.batStance;
    final end = Vec2(
      clampD(aim.x + through.x, 0, 1),
      clampD(aim.y + through.y, 0, 1),
    );

    // Normalised to field units: a full sweep across the crease is twice the
    // reach, and a full sweep up is the whole height range.
    final dx = (end.x - stance.x) * 2 * CricketField.batReachX;
    final dy =
        (end.y - stance.y) * (CricketField.batMaxHeight - CricketField.batMinHeight);
    final distance = Vec2(dx, dy).length;

    final speed = clampD(intent, 0.08, 1) * CricketField.batMaxSpeed;
    final ticks = (distance / speed * 120).round();
    final swingTicks = ticks < 6 ? 6 : ticks;

    return BattingPlan(
      swingStartTick:
          contactTick - (swingTicks * aimFraction).round() + timingError,
      swingTicks: swingTicks,
      aim: aim,
      through: through,
      intent: intent,
    );
  }

  /// The normalised bat target at [tick].
  Vec2 targetAt(int tick) {
    if (tick < swingStartTick) return CricketField.batStance;
    final elapsed = tick - swingStartTick;
    final progress =
        swingTicks <= 0 ? 1.0 : clampD(elapsed / swingTicks, 0, 1);
    final stance = CricketField.batStance;
    final end = Vec2(aim.x + through.x, aim.y + through.y);
    return Vec2(
      clampD(stance.x + (end.x - stance.x) * progress, 0, 1),
      clampD(stance.y + (end.y - stance.y) * progress, 0, 1),
    );
  }
}

/// The scripted opponent, batting and bowling.
///
/// Holds its own RNG streams so that adding a random call to one decision
/// cannot shift the sequence another decision sees — which would silently
/// change replay behaviour everywhere.
class CricketBot {
  CricketBot({
    required this.profile,
    required int seed,
  })  : _battingRng = DeterministicRng.stream(seed, 41),
        _bowlingRng = DeterministicRng.stream(seed, 42);

  final BotProfile profile;

  final DeterministicRng _battingRng;
  final DeterministicRng _bowlingRng;

  /// Chooses where to bowl and what to bowl.
  ///
  /// [pressure] rises as the required rate climbs, which is what turns a bot
  /// defending a big total into one that bowls yorkers.
  CricketInput planDelivery({required double pressure}) {
    // Aim: a line just outside off and a length on a good spot, blurred by
    // however accurate this difficulty is.
    final slop = 1.0 - profile.bowlingAccuracy;
    final line = 0.5 + _bowlingRng.nextRange(-0.30, 0.30) * slop -
        0.06 * profile.bowlingAccuracy;
    final length = 0.56 + _bowlingRng.nextRange(-0.34, 0.34) * slop;

    // What a better bowler actually buys, now that the bat is a place rather
    // than a swing window: **movement**. A repeated line is easy to cover
    // however well it is repeated, so accuracy that only bought a tighter line
    // made a good bowler easier to face than a bad one. Accuracy now also
    // decides how often the ball is one that deviates off the pitch, which is
    // the single thing a bat held on a line cannot answer.
    final wantsYorker =
        _bowlingRng.chance(profile.yorkerChance + 0.25 * pressure);
    final kind = wantsYorker
        ? DeliveryKind.yorker
        : (_bowlingRng.chance(0.18 + 0.52 * profile.bowlingAccuracy)
            ? DeliveryKind.spin
            : DeliveryKind.pace);

    return CricketInput(
      action: true,
      x: clampD(line, 0, 1),
      y: clampD(wantsYorker ? 0.88 : length, 0, 1),
      power: _powerFor(kind),
    ).quantised();
  }

  /// Commits to a shot the instant the ball is released.
  ///
  /// [required] is the run rate this innings needs, as a multiple of a par
  /// rate — above one the bot starts swinging harder, which is the only
  /// tactical behaviour it has and the only one it needs.
  /// [deliveryDifficulty] is 0 for a long hop down the leg side and 1 for a
  /// ball on a length hitting the top of off.
  ///
  /// Without it the bot batted exactly as well against a filthy delivery as
  /// against a jaffa: its timing error came only from its own profile, so
  /// nothing the bowler did could ever induce a mistake. That left the whole
  /// second innings — the half the *player* bowls — with no way to influence
  /// the result except waiting for the bot to make an unforced error.
  BattingPlan planShot({
    required BallState ball,
    required double required,
    required double deliveryDifficulty,
  }) {
    // The multiplier spans roughly 3x. A narrower range (0.68..1.43) was
    // measurably swamped by the delivery wobble: bowling at skill 0.9 took 59
    // wickets against 62 at skill 0.2, so aiming well was worth nothing.
    final spread =
        (profile.timingSpreadTicks * (0.55 + 1.15 * deliveryDifficulty))
            .round();
    final error = _battingRng.nextInt(spread * 2 + 1) - spread;

    // A good ball also makes the batter play at where it *isn't*, not just
    // when it isn't. Line and length both deserve a way of causing an edge.
    final readPenalty = 1.0 + 0.6 * deliveryDifficulty;

    // Where it thinks the ball will be, which is not where the ball will be.
    final misread = _battingRng.nextRange(
      -profile.lineReadError * readPenalty,
      profile.lineReadError * readPenalty,
    );

    final wild = _battingRng.chance(profile.wildSwingChance);

    // Chasing lifts the bat speed, which is right — a side needing eleven an
    // over swings harder. It is a smaller lift than it was, because the bot
    // always bats second and therefore always collects it: at 0.28 a good
    // human innings simply handed the bot the extra power it needed to chase
    // that innings down.
    final chasingHard = clampD(required - 1, 0, 1);
    final intent = clampD(
      profile.aggression +
          0.17 * chasingHard +
          (wild ? 0.25 : 0) +
          _battingRng.nextRange(-0.12, 0.12),
      0.05,
      1,
    );

    // Where to put the blade. Across the crease it goes to where the bot
    // believes the ball is coming, which is the perceived line and not the
    // real one; vertically it plays the length, because how high the ball
    // arrives is decided by where it pitched.
    final perceivedX = ball.position.x + misread;
    final aimX = clampD(
      (perceivedX - CricketField.pitchCentreX) / CricketField.batReachX * 0.5 +
          0.5,
      0,
      1,
    );

    // Short balls sit up, yorkers skid. A batter reads that off the length,
    // and getting it wrong is how a bot ends up chopping on or skying one.
    final shortness = clampD(
      (CricketField.fullestLength - ball.pitchY) /
          (CricketField.fullestLength - CricketField.shortestLength),
      0,
      1,
    );
    // Then it drops the hands to get *under* the ball, in proportion to how
    // much it wants to hit it in the air. This coupling used to be a third as
    // strong, and the consequence was measurable: the blade arrived at almost
    // exactly the ball's height on every shot, so nothing was ever got under,
    // and across three hundred simulated innings not one ball was hit for six.
    // Lofting a ball is a decision with a cost — a bat under the ball is a bat
    // that misses a full one — and it has to be available to make.
    //
    // Height carries its own execution error, scaled off the same dial as the
    // line read, so a weaker bot gets under the ball by luck rather than by
    // choice — which is what separates a lofted six from a top edge.
    final heightSlip =
        _battingRng.nextRange(-1, 1) * (profile.lineReadError / 340);
    final aimY =
        clampD(0.90 - 0.34 * shortness + 0.34 * intent + heightSlip, 0, 1);

    // The follow-through. A heave goes across the line; a played shot carries
    // on roughly where it was going. Negative y is upward, so every shot lifts
    // the hands a little and a big one lifts them a lot.
    final acrossTheLine = wild
        ? _battingRng.nextSign() * _battingRng.nextRange(0.30, 0.48)
        : _battingRng.nextRange(-0.20, 0.20);
    final through = Vec2(
      acrossTheLine * (0.55 + 0.45 * intent),
      -(0.14 + 0.34 * intent),
    );

    return BattingPlan.sweep(
      contactTick: ball.idealContactTick,
      aim: Vec2(aimX, aimY),
      through: through,
      intent: intent,
      timingError: error,
    );
  }

  static double _powerFor(DeliveryKind kind) => switch (kind) {
        DeliveryKind.pace => 0.12,
        DeliveryKind.spin => 0.37,
        DeliveryKind.yorker => 0.62,
        DeliveryKind.bouncer => 0.87,
      };
}
