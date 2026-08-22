import 'package:game_core/game_core.dart';
import 'package:pingpong_sim/pingpong_sim.dart';
import 'package:test/test.dart';

/// Win rate for a scripted human of [skill] against [difficulty], as a percent.
double winRate(BotDifficulty difficulty, double skill, {int matches = 40}) {
  var wins = 0;
  for (var i = 0; i < matches; i++) {
    final sim = simulateHeadless(
      seed: i * 7919 + 13,
      mode: GameMode.vsBot,
      botDifficulty: difficulty,
      rules: PongRules.standard,
      p1Controller: proxyHuman(side: PongSide.p1, skill: skill),
    );
    if (sim.state.p1Score > sim.state.p2Score) wins++;
  }
  return wins * 100 / matches;
}

void main() {
  // These bands are deliberately wide. They exist to catch a change that
  // silently inverts or flattens the difficulty curve, not to pin exact
  // percentages — the real numbers only mean something once actual players
  // produce them, and `tool/balance.dart` is the instrument for retuning.
  group('bot difficulty curve', () {
    test('easy is winnable by a weak player', () {
      expect(winRate(BotDifficulty.easy, 0.35), greaterThan(70));
    });

    test('medium is a genuine contest for an average player', () {
      expect(winRate(BotDifficulty.medium, 0.35), lessThan(45));
      expect(winRate(BotDifficulty.medium, 0.85), greaterThan(70));
    });

    test('hard resists a weak player and yields to a strong one', () {
      expect(winRate(BotDifficulty.hard, 0.35), lessThan(15));
      expect(winRate(BotDifficulty.hard, 1.0), greaterThan(50));
    });

    test('difficulty is monotonic — harder is never easier', () {
      for (final skill in <double>[0.35, 0.6, 0.85]) {
        final easy = winRate(BotDifficulty.easy, skill, matches: 24);
        final medium = winRate(BotDifficulty.medium, skill, matches: 24);
        final hard = winRate(BotDifficulty.hard, skill, matches: 24);
        expect(easy, greaterThanOrEqualTo(medium),
            reason: 'easy must not be harder than medium at skill $skill');
        expect(medium, greaterThanOrEqualTo(hard),
            reason: 'medium must not be harder than hard at skill $skill');
      }
    });

    test('a better player beats the same bot more often', () {
      expect(
        winRate(BotDifficulty.medium, 0.85),
        greaterThan(winRate(BotDifficulty.medium, 0.35)),
      );
    });
  });

  group('match pacing', () {
    test('every match ends, and in a plausible amount of time', () {
      // Match duration is not just feel: the server's plausibility rules reject
      // submissions that claim an impossible duration, so the real range has to
      // be known and bounded.
      for (final difficulty in BotDifficulty.values) {
        for (var seed = 0; seed < 12; seed++) {
          final sim = simulateHeadless(
            seed: seed * 104729 + 7,
            mode: GameMode.vsBot,
            botDifficulty: difficulty,
            rules: PongRules.standard,
            p1Controller: proxyHuman(side: PongSide.p1, skill: 0.7),
          );
          expect(sim.isComplete, isTrue,
              reason: '${difficulty.name} seed $seed never finished');
          expect(sim.durationMs, greaterThan(20 * 1000));
          expect(sim.durationMs, lessThan(8 * 60 * 1000));
        }
      }
    });

    test('quick matches really are quicker', () {
      var standardTicks = 0;
      var quickTicks = 0;
      for (var seed = 0; seed < 8; seed++) {
        standardTicks += simulateHeadless(
          seed: seed,
          mode: GameMode.vsBot,
          botDifficulty: BotDifficulty.medium,
          rules: PongRules.standard,
          p1Controller: proxyHuman(side: PongSide.p1, skill: 0.7),
        ).tick;
        quickTicks += simulateHeadless(
          seed: seed,
          mode: GameMode.vsBot,
          botDifficulty: BotDifficulty.medium,
          rules: PongRules.quick,
          p1Controller: proxyHuman(side: PongSide.p1, skill: 0.7),
        ).tick;
      }
      expect(quickTicks, lessThan(standardTicks));
    });

    test('an endless rally is broken rather than allowed to run', () {
      // Two identical, near-perfect players would otherwise rally forever.
      final sim = simulateHeadless(
        seed: 4321,
        mode: GameMode.local2P,
        rules: PongRules.standard,
        p1Controller: proxyHuman(side: PongSide.p1, skill: 1),
        p2Controller: proxyHuman(side: PongSide.p2, skill: 1),
      );
      expect(sim.isComplete, isTrue, reason: 'the stalemate breaker must bite');
      expect(sim.state.longestRally,
          lessThan(PongRules.standard.stalemateAfterHits + 60));
    });

    test('paddles shrink only during a stalemate, and recover after', () {
      const rules = PongRules.standard;
      expect(rules.paddleScaleForRally(0), 1);
      expect(rules.paddleScaleForRally(rules.stalemateAfterHits), 1);
      expect(rules.paddleScaleForRally(rules.stalemateAfterHits + 4),
          lessThan(1));
      expect(rules.paddleScaleForRally(10000), rules.minPaddleScale);
    });
  });
}
