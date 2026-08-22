import 'package:game_core/game_core.dart';
import 'package:pingpong_sim/pingpong_sim.dart';
import 'package:test/test.dart';

/// Plays a whole match against the bot with a scripted human, the way the app
/// would: through [PongMatchRunner], so input is quantised and recorded.
({PingPongSimulation sim, List<int> replay}) playRecordedMatch({
  required int seed,
  BotDifficulty difficulty = BotDifficulty.medium,
  GameMode mode = GameMode.vsBot,
  PongRules rules = PongRules.quick,
  double skill = 0.8,
}) {
  final sim = PingPongSimulation(
    seed: seed,
    mode: mode,
    botDifficulty: mode == GameMode.vsBot ? difficulty : null,
    rules: rules,
  );
  final runner = PongMatchRunner(simulation: sim);
  final p1 = proxyHuman(side: PongSide.p1, skill: skill);
  final p2 = proxyHuman(side: PongSide.p2, skill: skill);

  var guard = 0;
  while (!sim.isComplete && guard < 120 * 60 * 8) {
    runner.setP1Target(p1(sim.state, sim.tick));
    if (mode == GameMode.local2P) runner.setP2Target(p2(sim.state, sim.tick));
    runner.tick();
    guard++;
  }
  return (sim: sim, replay: runner.finishRecording());
}

void main() {
  group('determinism', () {
    test('the same seed and input produce a bit-identical match', () {
      // The foundation of everything: if this fails, no score the server
      // receives can ever be verified.
      for (final seed in [1, 7777, 123456789]) {
        final a = playRecordedMatch(seed: seed);
        final b = playRecordedMatch(seed: seed);

        expect(a.sim.state.p1Score, b.sim.state.p1Score);
        expect(a.sim.state.p2Score, b.sim.state.p2Score);
        expect(a.sim.tick, b.sim.tick);
        expect(a.sim.normalizedSkill, b.sim.normalizedSkill);
        expect(a.sim.state.longestRally, b.sim.state.longestRally);
        expect(a.replay, equals(b.replay), reason: 'replay bytes must match');
      }
    });

    test('different seeds produce different matches', () {
      final a = playRecordedMatch(seed: 11);
      final b = playRecordedMatch(seed: 22);
      expect(a.sim.tick, isNot(equals(b.sim.tick)));
    });

    test('the simulation is free of wall-clock dependence', () {
      // Stepping 600 times directly must equal stepping via a FixedLoop fed
      // wildly uneven frame times totalling the same duration.
      final direct = PingPongSimulation(
        seed: 4242,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.hard,
      );
      final held = Vec2(quantiseNormalised(0.5), quantiseNormalised(0.9));
      for (var i = 0; i < 600; i++) {
        direct.step(PongInput(p1: held));
      }

      final viaLoop = PingPongSimulation(
        seed: 4242,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.hard,
      );
      final loop = FixedLoop(tickHz: 120);
      final jitter = [0.016, 0.033, 0.008, 0.021, 0.011];
      var ticked = 0;
      var frame = 0;
      while (ticked < 600) {
        final dt = jitter[frame % jitter.length];
        frame++;
        ticked += loop.advance(dt, (_) {
          if (viaLoop.tick < 600) viaLoop.step(PongInput(p1: held));
        });
      }

      expect(viaLoop.state.p1Score, direct.state.p1Score);
      expect(viaLoop.state.p2Score, direct.state.p2Score);
      expect(viaLoop.state.ball.position.x,
          closeTo(direct.state.ball.position.x, 1e-9));
      expect(viaLoop.state.ball.position.y,
          closeTo(direct.state.ball.position.y, 1e-9));
    });
  });

  group('replay verification', () {
    test('replaying a recorded match reproduces the exact score', () {
      // This is the Phase 5 server check, running today.
      for (final seed in [3, 999, 20260821]) {
        final played = playRecordedMatch(seed: seed);
        final reader = ReplayReader.parse(played.replay);

        expect(reader.seed, seed);

        final verified = replayMatch(
          reader,
          mode: GameMode.vsBot,
          botDifficulty: BotDifficulty.medium,
          rules: PongRules.quick,
        );

        expect(verified.state.p1Score, played.sim.state.p1Score);
        expect(verified.state.p2Score, played.sim.state.p2Score);
        expect(verified.tick, played.sim.tick);
        expect(verified.normalizedSkill,
            closeTo(played.sim.normalizedSkill, 1e-12));
      }
    });

    test('a two-human match replays exactly too', () {
      final played = playRecordedMatch(seed: 555, mode: GameMode.local2P);
      final reader = ReplayReader.parse(played.replay);
      expect(reader.channelCount, 4);

      final verified = replayMatch(
        reader,
        mode: GameMode.local2P,
        rules: PongRules.quick,
      );
      expect(verified.state.p1Score, played.sim.state.p1Score);
      expect(verified.state.p2Score, played.sim.state.p2Score);
    });

    test('a forged score does not survive replay', () {
      // The attack the whole design exists to stop: claim 11-0, submit a
      // replay of the match you actually played.
      final played = playRecordedMatch(seed: 31337);
      final claimed = played.sim.buildResult().toJson();
      final forged = Map<String, Object?>.from(claimed)
        ..['p1Score'] = 11
        ..['p2Score'] = 0;

      final verified = replayMatch(
        ReplayReader.parse(played.replay),
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.medium,
        rules: PongRules.quick,
      );

      expect(verified.state.p1Score, isNot(forged['p1Score']));
    });

    test('a replay is small enough to always upload', () {
      final played = playRecordedMatch(seed: 8, rules: PongRules.standard);
      // Uncompressed, before gzip on the wire.
      expect(played.replay.length, lessThan(40 * 1024));
    });
  });

  group('rules', () {
    test('a match is won by two clear points', () {
      final played = playRecordedMatch(seed: 61, rules: PongRules.standard);
      final s = played.sim.state;
      expect(played.sim.isComplete, isTrue);
      final leader = s.p1Score > s.p2Score ? s.p1Score : s.p2Score;
      final trailer = s.p1Score > s.p2Score ? s.p2Score : s.p1Score;
      expect(leader, greaterThanOrEqualTo(11));
      expect(leader - trailer >= 2 || leader >= 21, isTrue);
    });

    test('deuce cannot run forever', () {
      const rules = PongRules(targetScore: 11, hardCeiling: 13);
      expect(rules.isMatchOver(12, 12), isFalse);
      expect(rules.isMatchOver(13, 12), isTrue, reason: 'ceiling ends it');
      expect(rules.isMatchOver(11, 10), isFalse);
      expect(rules.isMatchOver(11, 9), isTrue);
    });

    test('the player who concedes receives the next serve', () {
      final sim = PingPongSimulation(
        seed: 5,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.easy,
      );
      final held = Vec2(quantiseNormalised(0.02), quantiseNormalised(0.93));
      var sawPoint = false;
      for (var i = 0; i < 120 * 30 && !sawPoint; i++) {
        sim.step(PongInput(p1: held));
        for (final event in sim.pendingEvents) {
          if (event.type == PongEventType.point) {
            sawPoint = true;
            expect(sim.state.serveToward, isNot(event.side));
          }
        }
      }
      expect(sawPoint, isTrue, reason: 'a corner-parked paddle must concede');
    });

    test('a completed match ignores further input', () {
      final played = playRecordedMatch(seed: 77);
      final before = played.sim.tick;
      played.sim.step(const PongInput(p1: Vec2(0.5, 0.9)));
      expect(played.sim.tick, before);
    });
  });

  group('physics invariants', () {
    test('the ball never escapes the side walls, at any speed', () {
      final sim = PingPongSimulation(
        seed: 2024,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.hard,
        rules: PongRules.standard,
      );
      final human = proxyHuman(side: PongSide.p1);
      var guard = 0;
      while (!sim.isComplete && guard < 120 * 60 * 8) {
        sim.step(PongInput(p1: human(sim.state, sim.tick)));
        final x = sim.state.ball.position.x;
        expect(x, greaterThanOrEqualTo(PongField.ballRadius - 1e-6));
        expect(x, lessThanOrEqualTo(PongField.width - PongField.ballRadius + 1e-6));
        guard++;
      }
      expect(sim.isComplete, isTrue);
    });

    test('a paddle cannot teleport, however fast the input jumps', () {
      // A tampered client that snaps the paddle onto the ball would otherwise
      // be unbeatable. The speed cap is enforced by the simulation, not the UI.
      final sim = PingPongSimulation(
        seed: 9,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.easy,
      );
      final maxStep = PongField.humanPaddleMaxSpeed * sim.rules.stepSeconds;
      for (var i = 0; i < 1200; i++) {
        // Slam the target corner to corner every single tick.
        final target = i.isEven ? const Vec2(0, 1) : const Vec2(1, 0.55);
        sim.step(PongInput(p1: target));
        final moved =
            (sim.state.p1.position - sim.state.p1.previousPosition).length;
        expect(moved, lessThanOrEqualTo(maxStep + 1e-9));
      }
    });

    test('paddles stay inside their own half', () {
      final sim = PingPongSimulation(
        seed: 12,
        mode: GameMode.local2P,
        rules: PongRules.quick,
      );
      for (var i = 0; i < 4000 && !sim.isComplete; i++) {
        // Both players try to invade the other half and leave the field.
        sim.step(const PongInput(p1: Vec2(2, -1), p2: Vec2(-1, 2)));
        expect(sim.state.p1.position.y, greaterThanOrEqualTo(PongField.netY));
        expect(sim.state.p2.position.y, lessThanOrEqualTo(PongField.netY));
        expect(sim.state.p1.position.x,
            inInclusiveRange(PongField.minPaddleX(), PongField.maxPaddleX()));
      }
    });

    test('rally speed rises but is capped', () {
      final sim = PingPongSimulation(
        seed: 4,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.hard,
        rules: PongRules.standard,
      );
      final human = proxyHuman(side: PongSide.p1, skill: 1);
      var peak = 0.0;
      for (var i = 0; i < 120 * 60 * 3 && !sim.isComplete; i++) {
        sim.step(PongInput(p1: human(sim.state, sim.tick)));
        final speed = sim.state.ball.speed;
        if (speed > peak) peak = speed;
        expect(speed, lessThanOrEqualTo(PongField.ballMaxSpeed + 1e-6));
      }
      expect(peak, greaterThan(PongField.ballInitialSpeed));
    });

    test('the ball is never left stalled horizontally', () {
      // A near-flat return would rally forever and never end the match.
      final sim = PingPongSimulation(
        seed: 606,
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.medium,
        rules: PongRules.standard,
      );
      final human = proxyHuman(side: PongSide.p1);
      for (var i = 0; i < 120 * 60 * 5 && !sim.isComplete; i++) {
        sim.step(PongInput(p1: human(sim.state, sim.tick)));
        if (sim.state.phase == PongPhase.rally) {
          final v = sim.state.ball.velocity;
          if (v.length > 0) {
            expect(v.normalized.y.abs(),
                greaterThan(PongField.minVerticalDirection - 0.05));
          }
        }
      }
    });
  });

  group('scoring contract', () {
    test('normalizedSkill stays inside 0..1', () {
      for (final seed in [1, 2, 3, 4, 5]) {
        for (final skill in [0.0, 0.5, 1.0]) {
          final played = playRecordedMatch(seed: seed, skill: skill);
          expect(played.sim.normalizedSkill, inInclusiveRange(0, 1));
        }
      }
    });

    test('playing better scores higher', () {
      var weakTotal = 0.0;
      var strongTotal = 0.0;
      for (var seed = 0; seed < 12; seed++) {
        weakTotal += playRecordedMatch(seed: seed, skill: 0.0).sim.normalizedSkill;
        strongTotal += playRecordedMatch(seed: seed, skill: 1.0).sim.normalizedSkill;
      }
      expect(strongTotal, greaterThan(weakTotal));
    });

    test('the result carries everything the server needs', () {
      final played = playRecordedMatch(seed: 90210);
      final result = played.sim.buildResult(
        sessionToken: 'signed.jwt.here',
        replay: played.replay,
      );
      expect(result.gameSlug, 'ping_pong');
      expect(result.mode, GameMode.vsBot);
      expect(result.botDifficulty, BotDifficulty.medium);
      expect(result.seed, 90210);
      expect(result.tickCount, played.sim.tick);
      expect(result.durationMs, greaterThan(0));
      expect(result.sessionToken, 'signed.jwt.here');

      final json = result.toJson();
      expect(json['gameSlug'], 'ping_pong');
      expect(json['seed'], 90210);
      // The replay never travels inside the JSON body; it is uploaded
      // separately to object storage.
      expect(json.containsKey('replay'), isFalse);
    });
  });
}
