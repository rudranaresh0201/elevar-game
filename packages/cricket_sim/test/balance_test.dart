import 'package:cricket_sim/cricket_sim.dart';
import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// The tripwires for a game that still runs but has stopped being cricket.
///
/// Everything here has been wrong at some point, and each assertion is the
/// residue of a specific way the balance collapsed. `tool/diagnose.dart` prints
/// the full picture these check the corners of.
void main() {
  ({int human, int bot, bool humanWon}) play({
    required BotDifficulty difficulty,
    required double skill,
    required int seed,
  }) {
    final simulation = simulateHeadless(
      seed: seed,
      mode: GameMode.vsBot,
      botDifficulty: difficulty,
      striker: proxyBatter(skill: skill, seed: seed + 1),
      // The bot's innings is bowled by the human. Leaving this out makes the
      // bot face an identical delivery every ball and measures nothing.
      bowler: proxyBowler(skill: skill, seed: seed + 2),
    );
    final state = simulation.state;
    return (
      human: state.runsFor(CricketSide.p1),
      bot: state.runsFor(CricketSide.p2),
      humanWon: state.winner == CricketSide.p1,
    );
  }

  /// 60 matches, not 30.
  ///
  /// A win rate off 30 samples carries about nine points of standard error,
  /// and the gaps between adjacent difficulties are only ten to fifteen points
  /// wide — so a monotonicity assertion on 30 matches fails on noise perhaps
  /// one run in five while the ladder underneath it is perfectly ordered.
  double winRate({
    required BotDifficulty difficulty,
    required double skill,
    int matches = 60,
  }) {
    var won = 0;
    for (var i = 0; i < matches; i++) {
      if (play(difficulty: difficulty, skill: skill, seed: 1000 + i * 37)
          .humanWon) {
        won++;
      }
    }
    return won / matches;
  }

  double averageRuns({required double skill, int matches = 30}) {
    var total = 0;
    for (var i = 0; i < matches; i++) {
      total += play(
        difficulty: BotDifficulty.medium,
        skill: skill,
        seed: 2000 + i * 31,
      ).human;
    }
    return total / matches;
  }

  group('batting better scores more', () {
    test('runs rise with skill', () {
      // This has been *inverted* twice, and both times for a structural reason
      // rather than a tuning one: first because runs were counted from time
      // until fielded, so a well-struck ball reached a fielder sooner and
      // scored less; then because the scripted batter's aggression was tied to
      // its skill, so the better player slogged more and holed out more.
      final weak = averageRuns(skill: 0.3);
      final fair = averageRuns(skill: 0.6);
      final strong = averageRuns(skill: 0.9);

      expect(fair, greaterThan(weak), reason: 'skill must pay off');
      expect(strong, greaterThan(fair), reason: 'skill must keep paying off');
    });

    test('scores look like a two-over innings', () {
      // Both ends of this have been breached. Everything was out for 3 when
      // the contact window was one-sided; everything scored 30-plus when a
      // gentle push travelled far enough to beat the field every ball.
      //
      // The ceiling moved from 30 to 45 deliberately. When the field was ten
      // players all sprinting at the landing point, a two-over innings was
      // twelve singles and four and a half wickets — correct-looking numbers
      // for a game nobody wanted to play twice. One chaser and a human
      // fielding speed put boundaries back in, and 20-34 off twelve balls is
      // what a real powerplay looks like.
      for (final skill in <double>[0.3, 0.6, 0.9]) {
        final runs = averageRuns(skill: skill);
        expect(runs, greaterThan(3),
            reason: 'skill $skill is being bowled out for nothing');
        expect(runs, lessThan(45),
            reason: 'skill $skill is scoring more than twelve balls allows');
      }
    });

    test('a real share of the innings comes in boundaries', () {
      // The thing the whole rebalance was for, asserted rather than left to
      // the eye. Twelve singles is technically a cricket score and it is not
      // a game: nobody opens a shoe brand's app twice to nurdle.
      var fours = 0;
      var sixes = 0;
      var scoring = 0;

      for (var i = 0; i < 40; i++) {
        final simulation = simulateHeadless(
          seed: 4000 + i * 13,
          mode: GameMode.vsBot,
          botDifficulty: BotDifficulty.medium,
          striker: proxyBatter(skill: 0.7, seed: 900 + i),
          bowler: proxyBowler(skill: 0.7, seed: 950 + i),
        );
        for (final innings in <InningsState?>[
          simulation.state.first,
          simulation.state.second,
        ]) {
          if (innings == null) continue;
          for (final ball in innings.timeline) {
            if (ball <= 0) continue;
            scoring++;
            if (ball == 4) fours++;
            if (ball == 6) sixes++;
          }
        }
      }

      expect(scoring, greaterThan(100), reason: 'not enough sample');
      final boundaryShare = (fours + sixes) / scoring;
      expect(boundaryShare, greaterThan(0.25),
          reason: 'a scoring shot is almost never a boundary');
      expect(sixes, greaterThan(0), reason: 'nobody can clear the rope');
    });
  });

  group('the difficulty ladder is a slope, not a cliff', () {
    test('a given player does worse against a harder bot', () {
      const skill = 0.6;
      final vsEasy = winRate(difficulty: BotDifficulty.easy, skill: skill);
      final vsMedium = winRate(difficulty: BotDifficulty.medium, skill: skill);
      final vsHard = winRate(difficulty: BotDifficulty.hard, skill: skill);

      expect(vsEasy, greaterThanOrEqualTo(vsMedium));
      expect(vsMedium, greaterThanOrEqualTo(vsHard));
    });

    test('easy is beatable by a weak player', () {
      expect(winRate(difficulty: BotDifficulty.easy, skill: 0.35),
          greaterThan(0.3));
    });

    test('hard is not a formality for a strong one', () {
      final rate = winRate(difficulty: BotDifficulty.hard, skill: 0.9);
      expect(rate, lessThan(0.75), reason: 'hard should still hurt');
    });
  });

  group('bowling is worth doing', () {
    test('bowling well takes wickets', () {
      // The bot used to bat exactly as well against a filthy ball as a good
      // one, which made the innings the player *bowls* a cutscene.
      int wicketsWith({required double bowlingSkill}) {
        var wickets = 0;
        for (var i = 0; i < 24; i++) {
          final simulation = simulateHeadless(
            seed: 3000 + i * 13,
            mode: GameMode.vsBot,
            botDifficulty: BotDifficulty.medium,
            striker: proxyBatter(skill: 0.6, seed: i),
            bowler: proxyBowler(skill: bowlingSkill, seed: i + 500),
          );
          wickets += simulation.state.wicketsFor(CricketSide.p2);
        }
        return wickets;
      }

      expect(wicketsWith(bowlingSkill: 0.9),
          greaterThan(wicketsWith(bowlingSkill: 0.2)));
    });
  });

  group('every format terminates', () {
    test('across all three formats and all three difficulties', () {
      for (final rules in <CricketRules>[
        CricketRules.superOver,
        CricketRules.powerplay,
        CricketRules.chase,
      ]) {
        for (final difficulty in BotDifficulty.values) {
          final simulation = simulateHeadless(
            seed: 11,
            mode: GameMode.vsBot,
            botDifficulty: difficulty,
            rules: rules,
            striker: proxyBatter(skill: 0.6),
            bowler: proxyBowler(skill: 0.6),
          );
          expect(simulation.isComplete, isTrue,
              reason: '${rules.overs} overs vs ${difficulty.name} hung');
          expect(simulation.durationMs, greaterThan(0));
        }
      }
    });

    test('both field settings play', () {
      for (final setting in FieldSetting.all) {
        final simulation = simulateHeadless(
          seed: 21,
          mode: GameMode.vsBot,
          botDifficulty: BotDifficulty.medium,
          fieldSetting: setting,
          striker: proxyBatter(skill: 0.6),
          bowler: proxyBowler(skill: 0.6),
        );
        expect(simulation.isComplete, isTrue, reason: '${setting.name} hung');
      }
    });
  });

  group('the ground is fair', () {
    test('no fielder starts outside the rope', () {
      for (final setting in FieldSetting.all) {
        for (final position in setting.positions) {
          expect(Ground.isOverBoundary(position.home), isFalse,
              reason: '${position.name} in ${setting.name} is over the rope');
        }
      }
    });

    test('the straight boundary is longer than the square one, but not by a '
        'lot', () {
      // The first geometry ran an 820-unit pitch through a 1312-unit ground,
      // which put the square rope 362 units from the bat against 1072 straight.
      // A 3:1 asymmetry makes slogging square strictly dominant and silently
      // decided every balance table.
      const bat = Vec2(CricketField.pitchCentreX, CricketField.strikerY);

      double ropeDistance(Vec2 direction) {
        var distance = 0.0;
        while (distance < 2000) {
          if (Ground.isOverBoundary(bat + direction * distance)) return distance;
          distance += 1;
        }
        return distance;
      }

      final straight = ropeDistance(const Vec2(0, -1));
      final square = ropeDistance(const Vec2(-1, 0));

      expect(straight, greaterThan(square), reason: 'straight is the long one');
      expect(straight / square, lessThan(2.4),
          reason: 'square must not be a free boundary');
    });
  });
}
