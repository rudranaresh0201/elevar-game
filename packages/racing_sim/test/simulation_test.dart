import 'package:game_core/game_core.dart';
import 'package:racing_sim/racing_sim.dart';
import 'package:test/test.dart';

/// Runs a race through the recording runner, exactly as the live game does.
({RaceSimulation simulation, List<int> replay}) recordRace({
  required int seed,
  required GameMode mode,
  required RaceTrack track,
  BotDifficulty? botDifficulty,
  RaceRules rules = RaceRules.standard,
  double p1Skill = 0.75,
  double p2Skill = 0.60,
}) {
  final simulation = RaceSimulation(
    seed: seed,
    mode: mode,
    track: track,
    botDifficulty: botDifficulty,
    rules: rules,
  );
  final runner = RaceMatchRunner(simulation: simulation);

  final p1 = proxyDriver(
    side: RacerSide.p1,
    track: track,
    skill: p1Skill,
    seed: 0xA11CE,
  );
  final p2 = proxyDriver(
    side: RacerSide.p2,
    track: track,
    skill: p2Skill,
    seed: 0xB0B,
  );

  while (!simulation.isComplete && simulation.tick < rules.maxTicks) {
    runner.setP1Input(p1(simulation.state, simulation.tick));
    if (mode == GameMode.local2P) {
      runner.setP2Input(p2(simulation.state, simulation.tick));
    }
    runner.tick();
  }

  return (simulation: simulation, replay: runner.finishRecording());
}

void main() {
  group('determinism', () {
    test('the same seed and the same inputs produce the same race', () {
      final a = recordRace(
        seed: 987654321,
        mode: GameMode.vsBot,
        track: Tracks.dustbowl(),
        botDifficulty: BotDifficulty.medium,
      );
      final b = recordRace(
        seed: 987654321,
        mode: GameMode.vsBot,
        track: Tracks.dustbowl(),
        botDifficulty: BotDifficulty.medium,
      );

      expect(a.simulation.tick, b.simulation.tick);
      expect(a.simulation.state.winner, b.simulation.state.winner);
      expect(a.simulation.state.p1.lap, b.simulation.state.p1.lap);
      expect(a.simulation.state.p2.lap, b.simulation.state.p2.lap);

      // Bit-identical, not merely close. Anything less and a server replay
      // would drift away from the race it is checking.
      expect(a.simulation.state.p1.position.x,
          equals(b.simulation.state.p1.position.x));
      expect(a.simulation.state.p1.position.y,
          equals(b.simulation.state.p1.position.y));
      expect(a.simulation.state.p2.position.x,
          equals(b.simulation.state.p2.position.x));
      expect(a.simulation.normalizedSkill,
          equals(b.simulation.normalizedSkill));

      // And the recordings themselves match byte for byte.
      expect(a.replay, equals(b.replay));
    });

    test('a different seed produces a different race', () {
      final a = recordRace(
        seed: 1,
        mode: GameMode.vsBot,
        track: Tracks.dustbowl(),
        botDifficulty: BotDifficulty.medium,
      );
      final b = recordRace(
        seed: 2,
        mode: GameMode.vsBot,
        track: Tracks.dustbowl(),
        botDifficulty: BotDifficulty.medium,
      );
      // Compared on the bot's final position, not on tick count. The seed
      // drives the bot's line noise and its mistakes, so the bot's state is
      // what it must change — whereas two different races can perfectly well
      // last the same number of ticks, and asserting otherwise fails for a
      // reason that has nothing to do with determinism.
      final aP2 = a.simulation.state.p2;
      final bP2 = b.simulation.state.p2;
      expect(
        aP2.position.x != bP2.position.x || aP2.position.y != bP2.position.y,
        isTrue,
        reason: 'the seed did not change how the bot drove',
      );
    });

    test('steering never lets the heading drift off unit length', () {
      // The rotation is a complex multiply followed by a normalise. If the
      // normalise were ever dropped the heading would grow without bound and
      // the car would accelerate for free.
      final race = recordRace(
        seed: 42,
        mode: GameMode.vsBot,
        track: Tracks.sunsetLoop(),
        botDifficulty: BotDifficulty.hard,
      );
      expect(race.simulation.state.p1.heading.length, closeTo(1.0, 1e-9));
      expect(race.simulation.state.p2.heading.length, closeTo(1.0, 1e-9));
    });
  });

  group('replay verification', () {
    test('a recorded race reproduces its own result exactly', () {
      const seed = 24680;
      final race = recordRace(
        seed: seed,
        mode: GameMode.vsBot,
        track: Tracks.dustbowl(),
        botDifficulty: BotDifficulty.medium,
      );
      final claimed = race.simulation.buildResult(replay: race.replay);

      // Everything the server has: the bytes, and what the client says they
      // mean. It rebuilds the track from the slug and re-runs.
      final verified = replayRace(
        ReplayReader.parse(race.replay),
        mode: GameMode.vsBot,
        track: Tracks.dustbowl(),
        botDifficulty: BotDifficulty.medium,
      );

      expect(verified.state.p1.lap, claimed.p1Score);
      expect(verified.state.p2.lap, claimed.p2Score);
      expect(verified.state.winner, race.simulation.state.winner);
      expect(verified.normalizedSkill, closeTo(claimed.normalizedSkill, 1e-9));
    });

    test('a two-human race reproduces both drivers', () {
      final race = recordRace(
        seed: 13579,
        mode: GameMode.local2P,
        track: Tracks.sunsetLoop(),
        p1Skill: 0.8,
        p2Skill: 0.5,
      );
      final claimed = race.simulation.buildResult(replay: race.replay);

      final verified = replayRace(
        ReplayReader.parse(race.replay),
        mode: GameMode.local2P,
        track: Tracks.sunsetLoop(),
      );

      expect(verified.state.p1.lap, claimed.p1Score);
      expect(verified.state.p2.lap, claimed.p2Score);
      expect(verified.state.winner, race.simulation.state.winner);
    });

    test('a forged score does not survive the replay', () {
      final race = recordRace(
        seed: 555,
        mode: GameMode.vsBot,
        track: Tracks.dustbowl(),
        botDifficulty: BotDifficulty.hard,
      );
      final honest = race.simulation.buildResult(replay: race.replay);

      // A tampered client claims a rout and a perfect skill score while
      // uploading the replay of the race it actually drove.
      final forged = GameResult(
        gameSlug: honest.gameSlug,
        mode: honest.mode,
        botDifficulty: honest.botDifficulty,
        durationMs: honest.durationMs,
        p1Score: 99,
        p2Score: 0,
        outcome: MatchOutcome.p1Win,
        normalizedSkill: 1,
        seed: honest.seed,
        tickCount: honest.tickCount,
        replay: race.replay,
      );

      final verified = replayRace(
        ReplayReader.parse(forged.replay!),
        mode: GameMode.vsBot,
        track: Tracks.dustbowl(),
        botDifficulty: BotDifficulty.hard,
      );

      expect(verified.state.p1.lap, isNot(forged.p1Score));
      expect(verified.state.p1.lap, honest.p1Score);
      expect(verified.normalizedSkill, lessThan(forged.normalizedSkill));
    });

    test('the replay of a full race stays small enough to always upload', () {
      final race = recordRace(
        seed: 777,
        mode: GameMode.local2P,
        track: Tracks.dustbowl(),
      );
      // Six channels of held buttons delta-encode to almost nothing.
      expect(race.replay.length, lessThan(40 * 1024));
    });

    test('a truncated replay is rejected rather than half-believed', () {
      final race = recordRace(
        seed: 99,
        mode: GameMode.vsBot,
        track: Tracks.dustbowl(),
        botDifficulty: BotDifficulty.easy,
      );
      final truncated = race.replay.sublist(0, 12);
      expect(
        () => ReplayReader.parse(truncated),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('input quantisation', () {
    test('a steering input survives the replay grid unchanged', () {
      // The whole reason steering is ternary. 0.5 does not survive a 16-bit
      // round trip as 0.5, so a "straight" car would inherit a fractional
      // steering input and curve away over a lap.
      for (final steer in <int>[-1, 0, 1]) {
        for (final throttle in <bool>[false, true]) {
          for (final brake in <bool>[false, true]) {
            final original =
                CarInput(steer: steer, throttle: throttle, brake: brake);
            final round = RaceMatchRunner.snapThroughReplayGrid(original);
            expect(round.steer, original.steer);
            expect(round.throttle, original.throttle);
            expect(round.brake, original.brake);
          }
        }
      }
    });

    test('neutral steering really is neutral after quantisation', () {
      final channels = const CarInput().toChannels().map(quantiseNormalised);
      final decoded = CarInput.fromChannels(channels.toList(), 0);
      expect(decoded.steer, 0);
    });
  });

  group('race rules', () {
    test('a race where nobody drives still ends', () {
      // No natural end otherwise — and a race with no duration is one the
      // server's plausibility rules cannot check and two players could farm.
      const rules = RaceRules(maxSeconds: 20);
      final simulation = simulateHeadless(
        seed: 1,
        mode: GameMode.local2P,
        track: Tracks.dustbowl(),
        rules: rules,
        p1Controller: (_, __) => CarInput.coasting,
        p2Controller: (_, __) => CarInput.coasting,
      );
      expect(simulation.isComplete, isTrue);
      expect(simulation.tick, lessThanOrEqualTo(rules.maxTicks));
      expect(simulation.state.p1.lap, 0);
    });

    test('inputs during the countdown do not move the car', () {
      final track = Tracks.dustbowl();
      final simulation = RaceSimulation(
        seed: 5,
        mode: GameMode.local2P,
        track: track,
      );
      final startPosition = simulation.state.p1.position;

      for (var i = 0; i < 200; i++) {
        simulation.step(
          const RaceInput(
            p1: CarInput(steer: 1, throttle: true),
            p2: CarInput(steer: -1, throttle: true),
          ),
        );
      }
      expect(simulation.state.phase, RacePhase.countdown);
      expect(simulation.state.p1.position.x, startPosition.x);
      expect(simulation.state.p1.position.y, startPosition.y);
    });

    test('the grid is behind the line, so lap one is a full lap', () {
      final track = Tracks.dustbowl();
      final simulation = RaceSimulation(
        seed: 5,
        mode: GameMode.vsBot,
        track: track,
        botDifficulty: BotDifficulty.easy,
      );
      expect(simulation.state.p1.travelled, lessThan(0));
      expect(simulation.state.p1.lap, 0);
    });

    test('reversing over the line does not award a lap', () {
      final track = Tracks.dustbowl();
      // Drive backwards off the grid for a good while. `travelled` should fall,
      // and a falling number can never floor its way to lap one.
      final simulation = simulateHeadless(
        seed: 7,
        mode: GameMode.local2P,
        track: track,
        rules: const RaceRules(maxSeconds: 30),
        p1Controller: (_, __) => const CarInput(brake: true),
        p2Controller: (_, __) => CarInput.coasting,
      );
      expect(simulation.state.p1.lap, 0);
      expect(simulation.state.p1.travelled, lessThan(0));
    });

    test('a quick race is genuinely shorter than a standard one', () {
      final track = Tracks.dustbowl();
      int lengthOf(RaceRules rules) => recordRace(
            seed: 31337,
            mode: GameMode.vsBot,
            track: track,
            botDifficulty: BotDifficulty.medium,
            rules: rules,
          ).simulation.durationMs;

      expect(lengthOf(RaceRules.quick),
          lessThan(lengthOf(RaceRules.standard)));
    });
  });

  group('driving', () {
    test('grass is much slower than dirt', () {
      const dirt = RaceField.engineForce / RaceField.dragOnTrack;
      const grass = RaceField.engineForce / RaceField.dragOnGrass;
      // 331 against 115. This was `dirt / 3` when grass drag was 3.30, which
      // put terminal speed on the grass at 80 units/s — measurably a trap
      // rather than a penalty (see `tool/stuck.dart`). What actually has to
      // hold is that a lap round beats a lap through, and `tool/cutcheck.dart`
      // still measures cutting Dustbowl at ~10.0 s against ~8.1 s racing.
      expect(grass, lessThan(dirt / 2.5));
    });

    test('a beached car is picked up rather than left there', () {
      final track = Tracks.dustbowl();
      // Drive off deliberately, then take both thumbs off — the exact thing a
      // player does when they have given up on a corner.
      final simulation = simulateHeadless(
        seed: 77,
        mode: GameMode.local2P,
        track: track,
        rules: const RaceRules(maxSeconds: 40),
        p1Controller: _driveOffThenGiveUp,
        p2Controller: (_, __) => CarInput.coasting,
      );
      final car = simulation.state.p1;
      expect(car.rescues, greaterThan(0),
          reason: 'a car left beached in the scenery must be recovered');
      expect(car.onTrack, isTrue,
          reason: 'a rescue must put the car back on the racing line');
    });

    test('a rescue never advances a car up the road', () {
      // The recovery drops the car at its own projected distance, so it can
      // never be used as a shortcut — which is what would turn a safety net
      // into an exploit.
      final track = Tracks.dustbowl();
      final simulation = simulateHeadless(
        seed: 91,
        mode: GameMode.local2P,
        track: track,
        rules: const RaceRules(maxSeconds: 40),
        p1Controller: _driveOffThenGiveUp,
        p2Controller: (_, __) => CarInput.coasting,
      );
      final car = simulation.state.p1;
      expect(car.rescues, greaterThan(0));
      // Rescued at least once and still short of a single lap: the pickup did
      // not hand out distance.
      expect(car.travelled, lessThan(track.totalLength));
    });

    test('a car cannot leave the field however hard it tries', () {
      final track = Tracks.dustbowl();
      // Full throttle, full lock, for a whole race: the worst a player can do.
      final simulation = simulateHeadless(
        seed: 3,
        mode: GameMode.local2P,
        track: track,
        rules: const RaceRules(maxSeconds: 45),
        p1Controller: (_, __) => const CarInput(steer: 1, throttle: true),
        p2Controller: (_, __) => const CarInput(steer: -1, throttle: true),
      );
      for (final car in <CarState>[
        simulation.state.p1,
        simulation.state.p2,
      ]) {
        expect(car.position.x, greaterThan(-RaceField.carRadius));
        expect(car.position.x, lessThan(RaceField.width + RaceField.carRadius));
        expect(car.position.y, greaterThan(-RaceField.carRadius));
        expect(
          car.position.y,
          lessThan(RaceField.height + RaceField.carRadius),
        );
      }
    });

    test('two cars never end a tick overlapping', () {
      final track = Tracks.dustbowl();
      final simulation = RaceSimulation(
        seed: 11,
        mode: GameMode.local2P,
        track: track,
        rules: const RaceRules(maxSeconds: 40),
      );
      // Steer them into each other on purpose.
      while (!simulation.isComplete && simulation.tick < 120 * 40) {
        simulation.step(
          const RaceInput(
            p1: CarInput(steer: 1, throttle: true),
            p2: CarInput(steer: -1, throttle: true),
          ),
        );
        final gap =
            (simulation.state.p2.position - simulation.state.p1.position)
                .length;
        expect(
          gap,
          greaterThan(RaceField.carRadius * 2 - 0.5),
          reason: 'cars interpenetrated at tick ${simulation.tick}',
        );
      }
    });
  });

  group('the result the server receives', () {
    test('carries the racing slug and laps as the score', () {
      final race = recordRace(
        seed: 2468,
        mode: GameMode.vsBot,
        track: Tracks.dustbowl(),
        botDifficulty: BotDifficulty.medium,
      );
      final result = race.simulation.buildResult(replay: race.replay);

      expect(result.gameSlug, 'car_racing');
      expect(result.p1Score, race.simulation.state.p1.lap);
      expect(result.tickCount, race.simulation.tick);
      expect(result.durationMs, greaterThan(0));
      expect(result.normalizedSkill, inInclusiveRange(0, 1));
    });

    test('skill rewards winning, pace and clean driving', () {
      final track = Tracks.dustbowl();
      final strong = recordRace(
        seed: 4242,
        mode: GameMode.vsBot,
        track: track,
        botDifficulty: BotDifficulty.easy,
        p1Skill: 0.95,
      ).simulation;
      final weak = recordRace(
        seed: 4242,
        mode: GameMode.vsBot,
        track: track,
        botDifficulty: BotDifficulty.hard,
        p1Skill: 0.2,
      ).simulation;

      expect(strong.normalizedSkill, greaterThan(weak.normalizedSkill));
      expect(strong.normalizedSkill, inInclusiveRange(0, 1));
      expect(weak.normalizedSkill, inInclusiveRange(0, 1));
    });
  });
}

/// Accelerates away from the grid, turns hard off the circuit, and then takes
/// both thumbs off — a player who has given up on the corner.
///
/// The countdown is 360 ticks, so nothing before that moves the car at all;
/// the numbers below are chosen against that offset rather than from zero.
CarInput _driveOffThenGiveUp(RaceState state, int tick) {
  if (tick < 400) return const CarInput(throttle: true);
  if (tick < 660) return const CarInput(throttle: true, steer: -1);
  return CarInput.coasting;
}
