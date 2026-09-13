import 'package:game_core/game_core.dart';
import 'package:test/test.dart';
import 'package:wallcricket_sim/wallcricket_sim.dart';

void main() {
  test('an innings nobody bats in is bowled out, and terminates', () {
    var bowled = 0;
    var runs = 0;
    for (var seed = 1; seed <= 20; seed++) {
      final sim = simulateInnings(seed: seed);
      expect(sim.isComplete, isTrue);
      bowled += sim.wickets;
      runs += sim.runs;
    }
    // The raised blade can still clip a lifting ball now and then, but
    // leaving everything must never be a way to score.
    expect(runs, lessThan(40));
    // Most deliveries are aimed at the stumps, so leaving everything alone
    // has to cost wickets on almost every seed.
    expect(bowled, 60);
  });

  test('a batter who swings through the line scores runs', () {
    var total = 0;
    var hits = 0;
    for (var seed = 1; seed <= 20; seed++) {
      final sim = simulateInnings(seed: seed, batter: proxyBatter(skill: 0.9));
      total += sim.runs;
      hits += sim.hits;
    }
    expect(hits, greaterThan(100));
    expect(total, greaterThan(150));
  });

  test('a recorded innings replays to the same score', () {
    final sim = WallCricketSimulation(seed: 4242, pace: Pace.hard);
    final runner = WallCricketRunner(simulation: sim);
    final batter = proxyBatter(skill: 0.85);
    while (!sim.isComplete) {
      runner
        ..setFinger(batter(sim))
        ..tick();
    }
    final replay = ReplayReader.parse(runner.finishRecording());
    final again = replayInnings(replay, pace: Pace.hard);
    expect(again.runs, sim.runs);
    expect(again.wickets, sim.wickets);
    expect(again.ballsBowled, sim.ballsBowled);
    expect(sim.hits, greaterThan(0), reason: 'the replay must cover real play');
  });

  test('the bat never enters the ground', () {
    final sim = WallCricketSimulation(seed: 9, pace: Pace.easy);
    for (var t = 0; t < 2000; t++) {
      sim.step(
        WallCricketInput(
          finger: Vec2((t % 97) / 97, 1.0),
          touching: true,
        ),
      );
      expect(sim.batTip.y, lessThan(Arena.groundY));
    }
  });

  test('the result reports the target as the opposition score', () {
    final sim = simulateInnings(seed: 3, batter: proxyBatter());
    final result = sim.buildResult();
    expect(result.p1Score, sim.runs);
    expect(result.p2Score, sim.target);
    expect(result.outcome,
        sim.runs >= sim.target ? MatchOutcome.p1Win : MatchOutcome.p2Win);
  });
}
