import 'package:game_core/game_core.dart';
import 'package:soccer_sim/soccer_sim.dart';
import 'package:test/test.dart';

/// The properties the difficulty ladder has to keep, checked cheaply enough to
/// run on every commit.
///
/// The full table lives in `tool/balance.dart` and takes minutes; this is the
/// subset that catches a retune going wrong. Sample sizes are small on
/// purpose, so the thresholds are deliberately loose — this asks "is the ladder
/// still a slope", not "is it still exactly these numbers".
void main() {
  group('every match terminates', () {
    for (final difficulty in BotDifficulty.values) {
      test('against a ${difficulty.name} bot', () {
        for (var i = 0; i < 4; i++) {
          final simulation = simulateSoccerHeadless(
            seed: 500 + i * 991,
            mode: GameMode.vsBot,
            botDifficulty: difficulty,
            p1Controller: proxyHuman(side: SoccerSide.p1, skill: 0.7, seed: i),
          );
          expect(
            simulation.isComplete,
            isTrue,
            reason: 'a match that never ends has no duration for the '
                "server's plausibility rules to check",
          );
          expect(simulation.state.turnsTaken,
              lessThanOrEqualTo(SoccerRules.standard.maxTurns));
          // Ten minutes would be a broken match, not a long one.
          expect(simulation.durationMs, lessThan(10 * 60 * 1000));
        }
      });
    }

    test('with nobody touching the screen at all', () {
      // Every turn times out. This is the shot-clock's real job: an abandoned
      // phone still produces a finished, submittable match rather than a
      // session that runs until the battery does.
      final simulation = simulateSoccerHeadless(
        seed: 4,
        mode: GameMode.local2P,
        rules: const SoccerRules(aimTicks: 120, maxTurns: 8),
      );
      expect(simulation.isComplete, isTrue);
      expect(simulation.outcome, MatchOutcome.draw);
    });
  });

  group('the ladder is a slope', () {
    /// Goal difference from P1's point of view, averaged over a few seeds.
    /// A finer signal than win rate at this sample size — a 0-3 and a 2-3 are
    /// both a loss, and the difference between them is the whole ladder.
    double margin(BotDifficulty difficulty, double skill) {
      var total = 0;
      const matches = 5;
      for (var i = 0; i < matches; i++) {
        final simulation = simulateSoccerHeadless(
          seed: 20000 + i * 7817 + difficulty.index * 13,
          mode: GameMode.vsBot,
          botDifficulty: difficulty,
          p1Controller:
              proxyHuman(side: SoccerSide.p1, skill: skill, seed: i * 3),
        );
        total += simulation.state.p1Goals - simulation.state.p2Goals;
      }
      return total / matches;
    }

    test('a harder bot concedes fewer goals to the same human', () {
      final easy = margin(BotDifficulty.easy, 0.8);
      final medium = margin(BotDifficulty.medium, 0.8);
      final hard = margin(BotDifficulty.hard, 0.8);
      expect(easy, greaterThan(medium));
      expect(medium, greaterThan(hard));
    });

    test('a better human does better against the same bot', () {
      expect(
        margin(BotDifficulty.medium, 0.95),
        greaterThan(margin(BotDifficulty.medium, 0.3)),
      );
    });
  });

  group('the payout input behaves', () {
    test('skill stays inside 0..1 across the whole ladder', () {
      for (final difficulty in BotDifficulty.values) {
        for (final skill in <double>[0.1, 0.5, 1.0]) {
          final simulation = simulateSoccerHeadless(
            seed: 31 + difficulty.index,
            mode: GameMode.vsBot,
            botDifficulty: difficulty,
            p1Controller:
                proxyHuman(side: SoccerSide.p1, skill: skill, seed: 9),
          );
          expect(simulation.normalizedSkill, inInclusiveRange(0, 1));
        }
      }
    });

    test('a player who never touches the screen scores near zero', () {
      final simulation = simulateSoccerHeadless(
        seed: 88,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.medium,
      );
      // Losing every goal and never connecting with the ball: the floor of the
      // scale, so an idle session cannot farm points.
      expect(simulation.normalizedSkill, lessThan(0.1));
    });
  });
}
