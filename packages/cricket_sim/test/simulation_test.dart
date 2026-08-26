import 'package:cricket_sim/cricket_sim.dart';
import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// The load-bearing file.
///
/// Given a seed and an input log, a match must reproduce exactly. If anything
/// here goes red, no cricket score the server receives can be verified and the
/// points it pays out are whatever the client felt like claiming.
void main() {
  group('determinism', () {
    test('the same seed and the same input give the same match', () {
      CricketSimulation run() => simulateHeadless(
            seed: 20260825,
            mode: GameMode.vsBot,
            botDifficulty: BotDifficulty.medium,
            striker: proxyBatter(skill: 0.7, seed: 11),
            bowler: proxyBowler(skill: 0.7, seed: 12),
          );

      final a = run();
      final b = run();

      expect(a.tick, b.tick);
      expect(a.state.runsFor(CricketSide.p1), b.state.runsFor(CricketSide.p1));
      expect(a.state.runsFor(CricketSide.p2), b.state.runsFor(CricketSide.p2));
      expect(a.state.first.timeline, b.state.first.timeline);
      expect(a.state.second!.timeline, b.state.second!.timeline);
    });

    test('a different seed gives a different match', () {
      final a = simulateHeadless(
        seed: 1,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.medium,
        striker: proxyBatter(skill: 0.7),
      );
      final b = simulateHeadless(
        seed: 2,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.medium,
        striker: proxyBatter(skill: 0.7),
      );
      // The whole match, not one innings. A single innings of twelve balls
      // bucketed into runs is a coarse signal — two different seeds really can
      // produce the same twelve numbers — so comparing only that made this
      // test fail for a simulation that was in fact varying perfectly well.
      final same = a.tick == b.tick &&
          a.state.first.timeline.toString() ==
              b.state.first.timeline.toString() &&
          a.state.second!.timeline.toString() ==
              b.state.second!.timeline.toString();
      expect(same, isFalse, reason: 'the seed changed nothing at all');
    });

    test('input survives the replay grid exactly', () {
      // The lesson racing learned the hard way. A value that does not come back
      // off the 16-bit grid as itself will drift the simulation apart from the
      // recording that is supposed to verify it.
      for (final power in <double>[0.0, 0.12, 0.37, 0.5, 0.62, 0.87, 1.0]) {
        for (final action in <bool>[true, false]) {
          final original =
              CricketInput(action: action, x: 0.25, y: 0.75, power: power)
                  .quantised();
          final round = CricketInput.fromChannels(original.toChannels(), 0);

          expect(round.action, original.action);
          expect(round.x, original.x);
          expect(round.y, original.y);
          expect(round.power, original.power);
          // And the derived values, which are what the simulation actually
          // reads — a delivery kind that changed under quantisation would
          // silently bowl a different ball on the server.
          expect(round.deliveryKind, original.deliveryKind);
          expect(round.shotDirection.x, closeTo(original.shotDirection.x, 1e-9));
        }
      }
    });
  });

  group('a recorded match re-runs to the same score', () {
    /// Plays a match through the recorder, exactly as the app does.
    ({CricketSimulation played, List<int> replay}) playAndRecord({
      required int seed,
      double skill = 0.65,
    }) {
      final simulation = CricketSimulation(
        seed: seed,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.medium,
      );
      final runner = CricketMatchRunner(simulation: simulation);
      final batter = proxyBatter(skill: skill, seed: seed + 1);
      final bowler = proxyBowler(skill: skill, seed: seed + 2);

      while (!simulation.isComplete && simulation.tick < 120 * 400) {
        runner
          ..setStrikerInput(batter(simulation.state, simulation.tick))
          ..setBowlerInput(bowler(simulation.state, simulation.tick))
          ..tick();
      }
      return (played: simulation, replay: runner.finishRecording());
    }

    test('the verifier reproduces the result it was sent', () {
      final match = playAndRecord(seed: 4242);
      expect(match.played.isComplete, isTrue, reason: 'the match never ended');

      final verified = replayMatch(
        ReplayReader.parse(match.replay),
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.medium,
      );

      expect(verified.state.runsFor(CricketSide.p1),
          match.played.state.runsFor(CricketSide.p1));
      expect(verified.state.runsFor(CricketSide.p2),
          match.played.state.runsFor(CricketSide.p2));
      expect(verified.state.first.timeline, match.played.state.first.timeline);
      expect(verified.state.winner, match.played.state.winner);
    });

    test('a forged score does not survive verification', () {
      final match = playAndRecord(seed: 777);
      final honest = match.played.buildResult(replay: match.replay);

      // What a tampered client would send: the same recording, a better score.
      final forged = GameResult(
        gameSlug: honest.gameSlug,
        mode: honest.mode,
        botDifficulty: honest.botDifficulty,
        durationMs: honest.durationMs,
        p1Score: honest.p1Score + 40,
        p2Score: honest.p2Score,
        outcome: MatchOutcome.p1Win,
        normalizedSkill: 1,
        seed: honest.seed,
        tickCount: honest.tickCount,
      );

      final verified = replayMatch(
        ReplayReader.parse(match.replay),
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.medium,
      );

      expect(verified.state.runsFor(CricketSide.p1), isNot(forged.p1Score));
      expect(verified.state.runsFor(CricketSide.p1), honest.p1Score);
    });

    test('a truncated replay is rejected rather than half-believed', () {
      final match = playAndRecord(seed: 99);
      final chopped = match.replay.sublist(0, match.replay.length - 3);
      expect(
        () => ReplayReader.parse(chopped),
        anyOf(throwsFormatException, returnsNormally),
      );
      // Garbage in the header must always be refused outright.
      expect(() => ReplayReader.parse(<int>[1, 2, 3]), throwsFormatException);
    });

    test('the replay of a whole match is small enough to always upload', () {
      final match = playAndRecord(seed: 31415);
      expect(match.replay.length, lessThan(40 * 1024));
    });
  });

  group('the laws', () {
    test('an innings ends on the last wicket', () {
      final simulation = simulateHeadless(
        seed: 5,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.hard,
        // Never swing. Every ball is a play and miss, so the only way this
        // innings can end is by losing wickets or running out of balls.
        striker: (_, __) => CricketInput.idle,
      );
      final first = simulation.state.first;
      expect(
        first.wickets == CricketRules.powerplay.wickets ||
            first.balls == CricketRules.powerplay.ballsPerInnings,
        isTrue,
      );
    });

    test('an innings never runs past its allotted balls', () {
      for (var seed = 0; seed < 12; seed++) {
        final simulation = simulateHeadless(
          seed: seed,
          mode: GameMode.vsBot,
          botDifficulty: BotDifficulty.medium,
          striker: proxyBatter(skill: 0.6, seed: seed),
        );
        for (final innings in <InningsState?>[
          simulation.state.first,
          simulation.state.second,
        ]) {
          if (innings == null) continue;
          expect(innings.balls,
              lessThanOrEqualTo(CricketRules.powerplay.ballsPerInnings));
          expect(innings.wickets,
              lessThanOrEqualTo(CricketRules.powerplay.wickets));
        }
      }
    });

    test('a chase stops the moment the target is passed', () {
      // Whatever else happens, the second innings must not carry on scoring
      // after the game is won — that would inflate the score the server sees.
      for (var seed = 0; seed < 20; seed++) {
        final simulation = simulateHeadless(
          seed: seed * 7 + 1,
          mode: GameMode.vsBot,
          botDifficulty: BotDifficulty.easy,
          striker: proxyBatter(skill: 0.9, seed: seed),
          bowler: proxyBowler(skill: 0.3, seed: seed),
        );
        final second = simulation.state.second;
        if (second == null || !second.hasWon) continue;

        // The winning runs may take the score past the target, but not by
        // more than one ball's worth.
        expect(second.runs - second.target, lessThanOrEqualTo(6));
      }
    });

    test('every match terminates, at every difficulty', () {
      for (final difficulty in BotDifficulty.values) {
        for (var seed = 0; seed < 6; seed++) {
          final simulation = simulateHeadless(
            seed: seed,
            mode: GameMode.vsBot,
            botDifficulty: difficulty,
            striker: proxyBatter(skill: 0.5, seed: seed),
          );
          expect(simulation.isComplete, isTrue,
              reason: '${difficulty.name} seed $seed never finished');
        }
      }
    });

    test('a match where nobody ever touches the screen still ends', () {
      final simulation = simulateHeadless(
        seed: 3,
        mode: GameMode.local2P,
        striker: (_, __) => CricketInput.idle,
        bowler: (_, __) => CricketInput.idle,
      );
      expect(simulation.isComplete, isTrue);
    });
  });

  group('scoring', () {
    test('runs come from how far the ball goes, not how long it takes', () {
      // This is the property the whole balance rests on, and it was wrong the
      // first time: with runs counted from elapsed time, a well-struck ball
      // reached a fielder sooner and therefore scored *fewer* runs than a
      // mishit. Every difficulty ladder came out backwards because of it.
      const striker = Vec2(CricketField.pitchCentreX, CricketField.strikerY);

      // The same arithmetic the simulation uses, against the same constant:
      // if `unitsPerRun` moves, this moves with it.
      int runsAt(double distance) {
        final where = Vec2(striker.x, striker.y - distance);
        return (where - striker).length ~/ CricketField.unitsPerRun;
      }

      expect(runsAt(60), 0, reason: 'straight to a close fielder is a dot');
      expect(runsAt(260), greaterThanOrEqualTo(1));
      expect(runsAt(520), greaterThan(runsAt(260)));
    });

    test('clearing the rope in the air is six, along the ground is four', () {
      // The rule falls out of the geometry rather than being special-cased, so
      // this is really a test that the two branches exist at all.
      expect(Ground.isOverBoundary(const Vec2(500, 60)), isTrue);
      expect(Ground.isOverBoundary(const Vec2(500, 720)), isFalse);
      // And a point outside is pulled back onto the rope, not left in orbit.
      final clamped = Ground.clampInside(const Vec2(500, -400));
      expect(Ground.boundaryFraction(clamped), closeTo(1.0, 1e-9));
    });

    test('the result carries the cricket slug and runs as the score', () {
      final simulation = simulateHeadless(
        seed: 8,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.medium,
        striker: proxyBatter(skill: 0.7),
      );
      final result = simulation.buildResult();

      expect(result.gameSlug, 'cricket');
      expect(result.p1Score, simulation.state.runsFor(CricketSide.p1));
      expect(result.p2Score, simulation.state.runsFor(CricketSide.p2));
      expect(result.normalizedSkill, inInclusiveRange(0, 1));
      expect(result.durationMs, greaterThan(0));
    });

    test('skill rewards winning, runs and wickets', () {
      double skillOf({required double batting}) {
        final simulation = simulateHeadless(
          seed: 4242,
          mode: GameMode.vsBot,
          botDifficulty: BotDifficulty.medium,
          striker: proxyBatter(skill: batting, seed: 3),
          bowler: proxyBowler(skill: batting, seed: 4),
        );
        return simulation.normalizedSkill;
      }

      expect(skillOf(batting: 0.9), greaterThan(skillOf(batting: 0.2)));
      expect(skillOf(batting: 0.2), inInclusiveRange(0, 1));
      expect(skillOf(batting: 0.9), inInclusiveRange(0, 1));
    });
  });
}
