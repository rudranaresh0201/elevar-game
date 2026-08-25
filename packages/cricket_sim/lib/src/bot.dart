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
    timingSpreadTicks: 36,
    aggression: 0.50,
    wildSwingChance: 0.34,
    lineReadError: 72,
    bowlingAccuracy: 0.40,
    yorkerChance: 0.06,
    catchReliability: 0.62,
  );

  static const BotProfile medium = BotProfile(
    timingSpreadTicks: 21,
    aggression: 0.55,
    wildSwingChance: 0.18,
    lineReadError: 40,
    bowlingAccuracy: 0.66,
    yorkerChance: 0.20,
    catchReliability: 0.80,
  );

  static const BotProfile hard = BotProfile(
    timingSpreadTicks: 9,
    aggression: 0.60,
    wildSwingChance: 0.07,
    lineReadError: 15,
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
class BattingPlan {
  const BattingPlan({
    required this.swingTick,
    required this.direction,
    required this.power,
  });

  final int swingTick;
  final Vec2 direction;
  final double power;
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

    final wantsYorker =
        _bowlingRng.chance(profile.yorkerChance + 0.25 * pressure);
    final kind = wantsYorker
        ? DeliveryKind.yorker
        : (_bowlingRng.chance(0.30) ? DeliveryKind.spin : DeliveryKind.pace);

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
    final perceivedLine = ball.pitchY > 0
        ? (ball.position.x + misread - CricketField.pitchCentreX)
        : misread;

    final wild = _battingRng.chance(profile.wildSwingChance);

    // Play with the line, unless this is one of the heaves.
    var lateral = clampD(perceivedLine / 70, -1, 1);
    if (wild) lateral = _battingRng.nextSign() * _battingRng.nextRange(0.7, 1.0);

    final direction = Vec2(lateral, -1).normalized;

    final chasingHard = clampD(required - 1, 0, 1);
    final power = clampD(
      profile.aggression + 0.28 * chasingHard + (wild ? 0.25 : 0) +
          _battingRng.nextRange(-0.12, 0.12),
      0.05,
      1,
    );

    return BattingPlan(
      swingTick: ball.idealContactTick + error,
      direction: direction,
      power: power,
    );
  }

  static double _powerFor(DeliveryKind kind) => switch (kind) {
        DeliveryKind.pace => 0.12,
        DeliveryKind.spin => 0.37,
        DeliveryKind.yorker => 0.62,
        DeliveryKind.bouncer => 0.87,
      };
}
