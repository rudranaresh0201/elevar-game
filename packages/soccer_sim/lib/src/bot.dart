import 'package:game_core/game_core.dart';

import 'field.dart';
import 'world.dart';

/// One flick the bot has decided to take.
class BotShot {
  const BotShot({
    required this.discIndex,
    required this.direction,
    required this.power,
  });

  final int discIndex;

  /// Unit vector.
  final Vec2 direction;

  /// 0..1.
  final double power;
}

/// A difficulty setting, expressed as dials rather than as algorithms.
///
/// Every difficulty runs the same search; only these numbers change. That
/// matters because it means "hard" cannot contain a bug that "easy" does not,
/// and because the curve can be retuned from `tool/balance.dart` without
/// touching a line of logic.
class SoccerBotProfile {
  const SoccerBotProfile({
    required this.discsConsidered,
    required this.aimsPerDisc,
    required this.powers,
    required this.rolloutTicks,
    required this.aimJitter,
    required this.powerJitter,
    required this.blunderChance,
    required this.defenceWeight,
  });

  /// How many discs — nearest the ball first — the search will look at.
  ///
  /// The most important dial in the file, and the least obvious. A bot that
  /// considers every disc finds the one good shot on the pitch every single
  /// turn; a bot that considers the two nearest plays like somebody who has
  /// not looked at the whole board. That reads as human in a way that adding
  /// noise to a perfect answer never does.
  final int discsConsidered;

  /// How many aim candidates per disc, taken from the front of
  /// [SoccerBot._aimTargets] — which is ordered best-idea-first, so a small
  /// number is a narrow imagination rather than a random one.
  final int aimsPerDisc;

  final List<double> powers;

  /// How far ahead a candidate is rolled out. Shorter means the bot cannot
  /// see a slow ball trickle in, or a ricochet arrive.
  final int rolloutTicks;

  /// Execution error, as a fraction of the aim direction displaced sideways.
  ///
  /// Applied *after* the shot is chosen, so the bot takes a different shot
  /// from the one it evaluated. That is what a missed shot actually is for a
  /// person — the plan was fine and the thumb was not — and it is why this
  /// dial makes a bot feel weak rather than stupid.
  final double aimJitter;

  final double powerJitter;

  /// Probability of abandoning the search result and playing a candidate at
  /// random.
  ///
  /// Not a bug being papered over. A bot that never errs is not hard, it is
  /// unplayable, and a player who cannot win stops playing — which costs more
  /// than a conceded goal does.
  final double blunderChance;

  /// How much the bot values keeping the ball away from its own goal, against
  /// getting it near the opponent's.
  final double defenceWeight;

  static const SoccerBotProfile easy = SoccerBotProfile(
    discsConsidered: 2,
    aimsPerDisc: 2,
    powers: <double>[0.62, 1.0],
    rolloutTicks: 110,
    aimJitter: 0.42,
    powerJitter: 0.30,
    blunderChance: 0.38,
    defenceWeight: 0,
  );

  static const SoccerBotProfile medium = SoccerBotProfile(
    discsConsidered: 3,
    aimsPerDisc: 4,
    powers: <double>[0.5, 0.75, 1.0],
    rolloutTicks: 180,
    aimJitter: 0.155,
    powerJitter: 0.13,
    blunderChance: 0.15,
    defenceWeight: 0.24,
  );

  static const SoccerBotProfile hard = SoccerBotProfile(
    discsConsidered: 4,
    aimsPerDisc: 6,
    powers: <double>[0.42, 0.62, 0.82, 1.0],
    rolloutTicks: 240,
    aimJitter: 0.055,
    powerJitter: 0.05,
    blunderChance: 0.06,
    defenceWeight: 0.34,
  );

  static SoccerBotProfile of(BotDifficulty difficulty) => switch (difficulty) {
        BotDifficulty.easy => easy,
        BotDifficulty.medium => medium,
        BotDifficulty.hard => hard,
      };
}

/// The computer opponent.
///
/// It does not evaluate a position with a hand-written opinion about soccer.
/// It clones the world, takes each candidate flick, and *plays it out* with
/// the same physics the match uses, then scores where the ball ended up. Two
/// consequences fall out of that, and both are why it is worth the cycles:
///
/// * **It plays the physics, not a model of the physics.** Rebounds off the
///   posts, cannons off its own defenders and cannoning the ball in off an
///   opponent are all found for free, because they are found by doing them.
///   Nothing in this file knows what a ricochet is.
/// * **It cannot drift out of sync with the game.** Retuning restitution or
///   damping retunes the bot in the same commit. A bot built on a separate
///   predictive model is a second implementation of the physics that has to
///   be kept honest by hand, and it never is.
///
/// The search is one burst of work per turn — roughly 50 candidates rolled out
/// for two seconds of simulated time each — and it lives inside the *thinking*
/// pause the player already sees, so the cost is invisible. Rollouts run at
/// half the match's substep count, which halves the price for a loss of
/// fidelity that only ever makes the bot slightly wrong about a ricochet.
///
/// Like every bot in the hub it lives *inside* the simulation, driven by the
/// seeded RNG, so a replay carries only the human's input and the bot
/// reproduces itself for free — and a tampered client cannot claim the bot
/// played worse than it did.
class SoccerBot {
  SoccerBot({
    required this.profile,
    required this.side,
    required int seed,
  })  : _judgementRng = DeterministicRng.stream(seed, 21),
        _executionRng = DeterministicRng.stream(seed, 22);

  final SoccerBotProfile profile;
  final SoccerSide side;

  final DeterministicRng _judgementRng;
  final DeterministicRng _executionRng;

  /// Rollouts run at half fidelity. See the class doc.
  static const int _rolloutSubsteps = 2;

  static const double _goalScore = 500000;

  /// Picks this turn's flick. [turn] is passed rather than assumed so the same
  /// bot can be pointed at either side by the balancing tool.
  BotShot? chooseShot(SoccerWorld world, SoccerSide turn) {
    final candidates = _candidates(world, turn);
    if (candidates.isEmpty) return null;

    final blunder = _judgementRng.chance(profile.blunderChance);
    late BotShot chosen;

    if (blunder) {
      chosen = candidates[_judgementRng.nextInt(candidates.length)];
    } else {
      var best = candidates.first;
      var bestScore = double.negativeInfinity;
      for (final candidate in candidates) {
        final score = _rollout(world, candidate, turn);
        if (score > bestScore) {
          bestScore = score;
          best = candidate;
        }
      }
      chosen = best;
    }

    return _withExecutionError(chosen);
  }

  // --- what it is willing to try -------------------------------------------

  /// The candidate flicks, cheapest ideas first.
  List<BotShot> _candidates(SoccerWorld world, SoccerSide turn) {
    final ball = world.ball.position;
    final indices = _discsNearestBall(world, turn);

    final shots = <BotShot>[];
    for (final index in indices) {
      final origin = world.bodies[index].position;
      for (final target in _aimTargets(ball, turn)) {
        final direction = (target - origin).normalized;
        if (direction == Vec2.zero) continue;
        for (final power in profile.powers) {
          shots.add(
            BotShot(discIndex: index, direction: direction, power: power),
          );
        }
      }
    }
    return shots;
  }

  /// The bot's own discs, nearest the ball first, capped at
  /// [SoccerBotProfile.discsConsidered].
  ///
  /// A selection sort over five elements. Sorting properly would be shorter
  /// and would also import a comparator whose tie-breaking is not specified
  /// to be stable across Dart versions — which is exactly the kind of thing
  /// that makes a replay verify on one machine and fail on another.
  List<int> _discsNearestBall(SoccerWorld world, SoccerSide turn) {
    final first = SoccerWorld.firstDiscIndex(turn);
    final remaining = <int>[
      for (var i = 0; i < SoccerField.discsPerSide; i++) first + i,
    ];
    final ball = world.ball.position;
    final picked = <int>[];
    final wanted = profile.discsConsidered < remaining.length
        ? profile.discsConsidered
        : remaining.length;

    for (var n = 0; n < wanted; n++) {
      var bestAt = 0;
      var bestDistance = double.infinity;
      for (var i = 0; i < remaining.length; i++) {
        final d =
            (world.bodies[remaining[i]].position - ball).lengthSquared;
        if (d < bestDistance) {
          bestDistance = d;
          bestAt = i;
        }
      }
      picked.add(remaining.removeAt(bestAt));
    }
    return picked;
  }

  /// Points on the pitch worth aiming a disc *at*, best idea first.
  ///
  /// The first is the "ghost ball" of every cue-sports game: the spot a disc
  /// must occupy at the moment of contact for the ball to leave along the line
  /// to the goal. Aiming at the ball itself — the second entry — is the naive
  /// shot, and it is second rather than absent because it is the right answer
  /// when the ball is already lined up.
  ///
  /// The rest widen the angle: two ghosts aimed at the posts rather than the
  /// centre of the goal, and two lateral offsets that cut across the ball to
  /// send it square. All of it is vector arithmetic — a perpendicular is a
  /// component swap and a sign flip, so no angle and no trigonometry enters
  /// the simulation.
  List<Vec2> _aimTargets(Vec2 ball, SoccerSide turn) {
    final goalY = SoccerField.attackGoalY(turn);
    final goalCentre = Vec2(SoccerField.centreX, goalY);
    const inset = SoccerField.goalHalfWidth * 0.6;
    final nearPost = Vec2(SoccerField.centreX - inset, goalY);
    final farPost = Vec2(SoccerField.centreX + inset, goalY);

    Vec2 ghostFor(Vec2 target) {
      final toTarget = (target - ball).normalized;
      if (toTarget == Vec2.zero) return ball;
      return ball -
          toTarget * (SoccerField.ballRadius + SoccerField.discRadius);
    }

    final straight = ghostFor(goalCentre);
    final lateral = Vec2(
      -(goalCentre - ball).normalized.y,
      (goalCentre - ball).normalized.x,
    );

    final targets = <Vec2>[
      straight,
      ball,
      ghostFor(nearPost),
      ghostFor(farPost),
      straight + lateral * 34,
      straight - lateral * 34,
    ];
    return targets.length <= profile.aimsPerDisc
        ? targets
        : targets.sublist(0, profile.aimsPerDisc);
  }

  // --- what it thinks will happen ------------------------------------------

  /// Plays [shot] out on a throwaway copy of the world and scores the result.
  double _rollout(SoccerWorld world, BotShot shot, SoccerSide turn) {
    final trial = world.clone()
      ..flick(shot.discIndex, shot.direction, shot.power);

    const stepSeconds = 1.0 / 120;
    SoccerSide? scorer;
    var ticks = 0;
    while (ticks < profile.rolloutTicks && !trial.atRest) {
      scorer = trial.step(
        stepSeconds,
        emitEvents: false,
        substeps: _rolloutSubsteps,
      );
      ticks++;
      if (scorer != null) break;
    }

    if (scorer == turn) return _goalScore - ticks;
    if (scorer != null) return -_goalScore;
    return _evaluate(trial, turn);
  }

  /// How good a resting position is for [turn].
  ///
  /// Four terms, and the fourth is the one that took measuring. Without the
  /// keeper-discipline penalty the bot happily flicked its own goalkeeper up
  /// the pitch to poke the ball, because a keeper is just another disc to a
  /// search that only reads ball position — and then conceded on the reply
  /// into an empty net.
  double _evaluate(SoccerWorld world, SoccerSide turn) {
    final ball = world.ball.position;
    final theirGoal = Vec2(SoccerField.centreX, SoccerField.attackGoalY(turn));
    final myGoal = Vec2(SoccerField.centreX, SoccerField.defendGoalY(turn));

    var score = -(ball - theirGoal).length;
    score += (ball - myGoal).length * profile.defenceWeight;

    // Who is better placed to play the next ball. Turn order alternates, so
    // leaving the ball under an opponent's disc is how a good flick becomes a
    // conceded goal.
    var mine = double.infinity;
    var theirs = double.infinity;
    for (var i = 0; i < SoccerField.discsPerSide * 2; i++) {
      final distance = (world.bodies[i].position - ball).length;
      if (SoccerWorld.indexBelongsTo(i, turn)) {
        if (distance < mine) mine = distance;
      } else if (distance < theirs) {
        theirs = distance;
      }
    }
    score += (theirs - mine) * 0.5;

    final keeper = world.bodies[SoccerWorld.firstDiscIndex(turn)];
    score -= (keeper.position - myGoal).length * 0.55;

    return score;
  }

  // --- what its thumb actually does ----------------------------------------

  /// Displaces the chosen shot by the profile's execution error.
  BotShot _withExecutionError(BotShot shot) {
    // Triangular: the sum of two uniforms peaks at zero, so the bot is usually
    // about right and occasionally well off, like a person. A flat error
    // swings its full range every time, which reads as a bot that is randomly
    // either perfect or hopeless.
    final aimError =
        (_executionRng.nextDouble() + _executionRng.nextDouble() - 1.0) *
            profile.aimJitter;
    final powerError =
        (_executionRng.nextDouble() + _executionRng.nextDouble() - 1.0) *
            profile.powerJitter;

    final perpendicular = Vec2(-shot.direction.y, shot.direction.x);
    final direction =
        (shot.direction + perpendicular * aimError).normalized;

    return BotShot(
      discIndex: shot.discIndex,
      direction: direction == Vec2.zero ? shot.direction : direction,
      power: clampD(shot.power + powerError, 0.06, 1),
    );
  }
}
