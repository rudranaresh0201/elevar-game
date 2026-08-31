import 'package:game_core/game_core.dart';
import 'package:soccer_sim/soccer_sim.dart';
import 'package:test/test.dart';

/// Plays a whole match through [SoccerMatchRunner] — the live path, including
/// input quantisation — and hands back both the simulation and the sealed
/// recording.
({SoccerSimulation simulation, List<int> replay}) playAndRecord({
  required int seed,
  required GameMode mode,
  BotDifficulty? botDifficulty,
  double skill = 0.75,
  SoccerRules rules = SoccerRules.standard,
}) {
  final simulation = SoccerSimulation(
    seed: seed,
    mode: mode,
    botDifficulty: botDifficulty,
    rules: rules,
  );
  final runner = SoccerMatchRunner(simulation: simulation);
  final p1 = proxyHuman(side: SoccerSide.p1, skill: skill, seed: seed);
  final p2 = proxyHuman(side: SoccerSide.p2, skill: skill, seed: seed + 1);

  var guard = 0;
  while (!simulation.isComplete && guard < 120 * 60 * 12) {
    final state = simulation.state;
    runner.setInput(
      state.turn == SoccerSide.p1
          ? p1(state, guard)
          : (mode == GameMode.local2P ? p2(state, guard) : SoccerInput.idle),
    );
    runner.tick();
    guard++;
  }
  return (simulation: simulation, replay: runner.finishRecording());
}

void main() {
  group('determinism', () {
    test('the same seed and the same input produce the same match', () {
      final a = playAndRecord(
        seed: 8812,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.medium,
      );
      final b = playAndRecord(
        seed: 8812,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.medium,
      );

      expect(a.simulation.state.p1Goals, b.simulation.state.p1Goals);
      expect(a.simulation.state.p2Goals, b.simulation.state.p2Goals);
      expect(a.simulation.tick, b.simulation.tick);
      expect(a.replay, b.replay);
      // Not just the score: every body has to land on the same coordinate, or
      // the divergence is there and merely has not reached the scoreboard yet.
      for (var i = 0; i < a.simulation.state.world.bodies.length; i++) {
        expect(
          a.simulation.state.world.bodies[i].position,
          b.simulation.state.world.bodies[i].position,
          reason: 'body $i drifted between two runs of the same seed',
        );
      }
    });

    test('different seeds produce different matches', () {
      final a = playAndRecord(
        seed: 1,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.medium,
      );
      final b = playAndRecord(
        seed: 2,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.medium,
      );
      expect(a.replay, isNot(equals(b.replay)));
    });
  });

  group('replay verification', () {
    // If this group ever goes red, no score the server receives can be
    // verified — a submitted match could claim any result at all.
    test('a recorded match replays to the identical score', () {
      final played = playAndRecord(
        seed: 31337,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.hard,
      );

      final verified = replaySoccerMatch(
        ReplayReader.parse(played.replay),
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.hard,
      );

      expect(verified.state.p1Goals, played.simulation.state.p1Goals);
      expect(verified.state.p2Goals, played.simulation.state.p2Goals);
      expect(verified.state.turnsTaken, played.simulation.state.turnsTaken);
      expect(verified.tick, played.simulation.tick);
      expect(
        verified.normalizedSkill,
        closeTo(played.simulation.normalizedSkill, 1e-12),
      );
    });

    test('a two-human match replays to the identical score', () {
      final played = playAndRecord(seed: 5150, mode: GameMode.local2P);
      final verified = replaySoccerMatch(
        ReplayReader.parse(played.replay),
        mode: GameMode.local2P,
      );
      expect(verified.state.p1Goals, played.simulation.state.p1Goals);
      expect(verified.state.p2Goals, played.simulation.state.p2Goals);
    });

    test('a forged score does not survive the replay', () {
      final played = playAndRecord(
        seed: 909,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.easy,
      );
      final submitted = played.simulation.buildResult(replay: played.replay);

      // What a tampered client would send: the real replay, a better score.
      final forged = GameResult(
        gameSlug: submitted.gameSlug,
        mode: submitted.mode,
        botDifficulty: submitted.botDifficulty,
        durationMs: submitted.durationMs,
        p1Score: submitted.p1Score + 5,
        p2Score: 0,
        outcome: MatchOutcome.p1Win,
        normalizedSkill: 1,
        seed: submitted.seed,
        tickCount: submitted.tickCount,
      );

      final verified = replaySoccerMatch(
        ReplayReader.parse(played.replay),
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.easy,
      );
      expect(verified.state.p1Goals, isNot(forged.p1Score));
      expect(verified.state.p1Goals, submitted.p1Score);
    });

    test('the replay is small enough to always upload', () {
      final played = playAndRecord(
        seed: 4004,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.medium,
      );
      // Three channels at 20 Hz for a ~100 s match, delta-varint encoded.
      expect(played.replay.length, lessThan(12 * 1024));
    });
  });

  group('the flick', () {
    test('a disc leaves along the opposite of the drag', () {
      final simulation = SoccerSimulation(
        seed: 7,
        mode: GameMode.local2P,
      );
      _runTo(simulation, SoccerPhase.aiming);

      final side = simulation.state.turn;
      // The centre-forward, and sent back toward its own goal. Both choices
      // are about clear space rather than about soccer: the keeper is parked
      // against its own goal line with nowhere to travel, and the half in
      // front of a forward is full of the opposition.
      final index = SoccerWorld.firstDiscIndex(side) + 3;
      final disc = simulation.state.world.bodies[index];
      final before = disc.position;
      final home = side == SoccerSide.p1 ? 1.0 : -1.0;

      _hold(simulation, SoccerInput.grab(disc.position), 4);
      expect(simulation.state.aim.isHolding, isTrue);
      expect(simulation.state.aim.discIndex, index);

      // Pull *away* from home; the disc must travel toward it.
      final drag = Vec2(0, -home * 160);
      _hold(simulation, SoccerInput.pull(drag, stillDown: true), 4);
      expect(simulation.state.aim.direction.y * home, greaterThan(0.9));
      expect(simulation.state.aim.power, greaterThan(0.4));

      simulation.step(SoccerInput.pull(drag, stillDown: false));
      expect(simulation.state.phase, SoccerPhase.resolving);
      expect(disc.velocity.y * home, greaterThan(0));

      _runTo(simulation, SoccerPhase.aiming);
      expect((disc.position.y - before.y) * home, greaterThan(100));
    });

    test('a drag shorter than the minimum cancels instead of dribbling', () {
      final simulation = SoccerSimulation(seed: 11, mode: GameMode.local2P);
      _runTo(simulation, SoccerPhase.aiming);

      final index = SoccerWorld.firstDiscIndex(simulation.state.turn);
      final disc = simulation.state.world.bodies[index];

      _hold(simulation, SoccerInput.grab(disc.position), 4);
      _hold(simulation, SoccerInput.pull(const Vec2(0, 8), stillDown: true), 4);
      simulation.step(SoccerInput.pull(const Vec2(0, 8), stillDown: false));

      expect(simulation.state.phase, SoccerPhase.aiming,
          reason: 'a mis-grab should hand the disc back, not burn the turn');
      expect(simulation.state.aim.isHolding, isFalse);
      expect(disc.velocity, Vec2.zero);
    });

    test('you can only grab your own discs', () {
      final simulation = SoccerSimulation(seed: 13, mode: GameMode.local2P);
      _runTo(simulation, SoccerPhase.aiming);

      final opponent = SoccerWorld.firstDiscIndex(simulation.state.turn.other);
      final theirDisc = simulation.state.world.bodies[opponent];

      _hold(simulation, SoccerInput.grab(theirDisc.position), 4);
      expect(simulation.state.aim.isHolding, isFalse);
    });

    test('a grab picks the nearest disc, not the first one listed', () {
      final simulation = SoccerSimulation(seed: 17, mode: GameMode.local2P);
      _runTo(simulation, SoccerPhase.aiming);

      final side = simulation.state.turn;
      final first = SoccerWorld.firstDiscIndex(side);
      // Aim at the fourth disc's centre. It is later in the list than three
      // others, so a first-match grab would return the wrong one.
      final wanted = first + 3;
      _hold(
        simulation,
        SoccerInput.grab(simulation.state.world.bodies[wanted].position),
        4,
      );
      expect(simulation.state.aim.discIndex, wanted);
    });

    test('the shot clock passes the turn when it runs out', () {
      const rules = SoccerRules(aimTicks: 60);
      final simulation = SoccerSimulation(
        seed: 19,
        mode: GameMode.local2P,
        rules: rules,
      );
      _runTo(simulation, SoccerPhase.aiming);
      final was = simulation.state.turn;

      for (var i = 0; i < 61; i++) {
        simulation.step(SoccerInput.idle);
      }
      expect(simulation.state.turn, was.other);
      expect(simulation.state.lastTurnEnd, TurnEnd.timedOut);
    });
  });

  group('the pitch', () {
    test('nothing tunnels out through a touchline at full speed', () {
      final world = SoccerWorld.kickoff();
      // Fire the ball into a corner as hard as the cap allows, from close in.
      world.ball
        ..position = const Vec2(200, 300)
        ..velocity = const Vec2(-SoccerField.speedCap, -SoccerField.speedCap);

      for (var i = 0; i < 400 && !world.atRest; i++) {
        world.step(1 / 120);
      }
      for (final body in world.bodies) {
        expect(
          body.position.x,
          inInclusiveRange(
            SoccerField.left - body.radius,
            SoccerField.right + body.radius,
          ),
        );
      }
    });

    test('a ball into the mouth is a goal; a ball beside it is not', () {
      SoccerSide? scoreFrom(double x) {
        final world = SoccerWorld.kickoff();
        for (var i = 0; i < SoccerWorld.ballIndex; i++) {
          world.bodies[i].position = Vec2(4000 + i * 100.0, 4000);
        }
        world.ball
          ..position = Vec2(x, 400)
          ..velocity = const Vec2(0, -2200);
        SoccerSide? scorer;
        for (var i = 0; i < 200 && scorer == null; i++) {
          scorer = world.step(1 / 120);
        }
        return scorer;
      }

      expect(scoreFrom(SoccerField.centreX), SoccerSide.p1);
      expect(
        scoreFrom(SoccerField.centreX + SoccerField.goalHalfWidth + 60),
        isNull,
        reason: 'outside the mouth the end line is solid',
      );
    });

    test('a disc cannot leave through the goal mouth', () {
      final world = SoccerWorld.kickoff();
      world.bodies[0]
        ..position = const Vec2(SoccerField.centreX, 400)
        ..velocity = const Vec2(0, -SoccerField.speedCap);
      for (var i = 0; i < 300 && !world.atRest; i++) {
        world.step(1 / 120);
      }
      expect(
        world.bodies[0].position.y,
        greaterThanOrEqualTo(SoccerField.topGoalLine),
      );
    });

    test('every turn comes to rest well inside the resolve cap', () {
      final world = SoccerWorld.kickoff()..flick(3, const Vec2(0, -1), 1);
      var ticks = 0;
      while (!world.atRest && ticks < SoccerRules.standard.maxResolveTicks) {
        world.step(1 / 120);
        ticks++;
      }
      expect(world.atRest, isTrue);
      expect(ticks, lessThan(SoccerRules.standard.maxResolveTicks));
    });
  });

  group('the match', () {
    test('the side that conceded restarts, and the formation resets', () {
      final simulation = SoccerSimulation(seed: 23, mode: GameMode.local2P);
      _runTo(simulation, SoccerPhase.aiming);

      // Roll the ball into P1's attacking goal directly, so a goal happens
      // without having to play a whole match for one. P2's keeper is standing
      // on that line and has to be moved aside first — it does its job.
      simulation.state.world.bodies[SoccerWorld.firstDiscIndex(SoccerSide.p2)]
          .position = const Vec2(SoccerField.left + 60, 300);
      simulation.state.world.ball
        ..position = const Vec2(SoccerField.centreX, 300)
        ..velocity = const Vec2(0, -2000);
      simulation.state.phase = SoccerPhase.resolving;

      var guard = 0;
      while (simulation.state.lastScorer == null && guard < 600) {
        simulation.step(SoccerInput.idle);
        guard++;
      }
      expect(simulation.state.lastScorer, SoccerSide.p1);

      _runTo(simulation, SoccerPhase.aiming);
      expect(simulation.state.turn, SoccerSide.p2,
          reason: 'the conceding side kicks off');
      expect(
        simulation.state.world.ball.position,
        const Vec2(SoccerField.centreX, SoccerField.centreSpotY),
      );
      expect(
        simulation.state.world.bodies[0].position,
        Vec2(SoccerField.p1Formation[0].$1, SoccerField.p1Formation[0].$2),
      );
    });

    test('skill is on the 0..1 scale and rewards winning', () {
      final won = simulateSoccerHeadless(
        seed: 606,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.easy,
        p1Controller: proxyHuman(side: SoccerSide.p1, skill: 1),
      );
      final lost = simulateSoccerHeadless(
        seed: 606,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.hard,
        p1Controller: proxyHuman(side: SoccerSide.p1, skill: 0.2),
      );

      for (final simulation in <SoccerSimulation>[won, lost]) {
        expect(simulation.normalizedSkill, inInclusiveRange(0, 1));
      }
      expect(won.normalizedSkill, greaterThan(lost.normalizedSkill));
    });

    test('the result carries the slug the hub keys everything off', () {
      final played = playAndRecord(
        seed: 77,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.easy,
      );
      final result =
          played.simulation.buildResult(replay: played.replay);
      expect(result.gameSlug, 'soccer');
      expect(result.tickCount, played.simulation.tick);
      expect(result.durationMs, greaterThan(0));
    });
  });
}

/// Advances until [phase] is reached, with idle input.
void _runTo(SoccerSimulation simulation, SoccerPhase phase) {
  var guard = 0;
  while (simulation.state.phase != phase && guard < 5000) {
    simulation.step(SoccerInput.idle);
    guard++;
  }
  expect(simulation.state.phase, phase);
}

/// Feeds the same input for [ticks] ticks, as a finger resting still does.
void _hold(SoccerSimulation simulation, SoccerInput input, int ticks) {
  for (var i = 0; i < ticks; i++) {
    simulation.step(input);
  }
}
