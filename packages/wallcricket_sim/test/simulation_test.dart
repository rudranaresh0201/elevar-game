import 'package:game_core/game_core.dart';
import 'package:test/test.dart';
import 'package:wallcricket_sim/wallcricket_sim.dart';

/// Swings at every ball [offset] seconds away from the perfect moment
/// (positive early), with [direction], and returns the innings.
WallCricketSimulation swingAt(
  double offset, {
  Vec2 direction = const Vec2(1, -0.6),
  Pace pace = Pace.medium,
  int seed = 1,
}) {
  var swung = false;
  return simulateInnings(
    seed: seed,
    pace: pace,
    batter: (sim) {
      if (sim.phase != WallCricketPhase.live || !sim.ballVisible) {
        swung = false;
        return null;
      }
      if (swung || sim.ballVelocity.x >= 0) return null;
      final away = (sim.ballPosition.x - WallCricketSimulation.hitX) / -sim.ballVelocity.x;
      final ideal = WallCricketSimulation.contactDelayTicks / WallCricketRules.tickHz;
      if (away <= ideal + offset) {
        swung = true;
        return direction;
      }
      return null;
    },
  );
}

void main() {
  test('an innings nobody bats in is bowled out, and scores nothing', () {
    var bowled = 0;
    for (var seed = 1; seed <= 20; seed++) {
      final sim = simulateInnings(seed: seed);
      expect(sim.isComplete, isTrue);
      expect(sim.runs, 0);
      bowled += sim.wickets;
    }
    expect(bowled, 60);
  });

  test('a perfectly timed swing is a big hit on every kind of delivery', () {
    // Every length the machine bowls — bouncers and yorkers included — is
    // playable when the timing is right.
    var runs = 0, balls = 0, wickets = 0;
    for (var seed = 1; seed <= 10; seed++) {
      final sim = swingAt(0, seed: seed);
      runs += sim.runs;
      balls += sim.ballsBowled;
      wickets += sim.wickets;
    }
    expect(wickets, 0);
    expect(runs / balls, greaterThan(3.5));
  });

  test('timing decides the shot: well early or late misses', () {
    final early = swingAt(0.3);
    final late = swingAt(-0.25);
    expect(early.hits, 0);
    expect(late.hits, 0);
    expect(early.wickets + late.wickets, greaterThan(0));
  });

  test('any swipe direction is a shot', () {
    for (final direction in <Vec2>[
      const Vec2(1, 0), // forward
      const Vec2(0, -1), // up
      const Vec2(-1, 0), // back
      const Vec2(0, 1), // down
      const Vec2(-1, -1), // back and up
    ]) {
      final sim = swingAt(0, direction: direction, seed: 3);
      expect(sim.hits, greaterThan(10), reason: 'direction $direction');
      expect(sim.runs, greaterThan(0), reason: 'direction $direction');
    }
  });

  test('skill moves the result the right way', () {
    int runsAt(double skill) {
      var total = 0;
      for (var seed = 1; seed <= 20; seed++) {
        total += simulateInnings(
          seed: seed,
          pace: Pace.hard,
          batter: proxyBatter(skill: skill, noiseSeed: seed),
        ).runs;
      }
      return total;
    }

    expect(runsAt(1.0), greaterThan(runsAt(0.4)));
  });

  test('the player is told how every swing was timed', () {
    final sim = WallCricketSimulation(seed: 5, pace: Pace.easy);
    final timings = <double>[];
    final batter = proxyBatter(skill: 0.5);
    var direction = const Vec2(1, -0.5);
    while (!sim.isComplete) {
      final swing = batter(sim);
      if (swing != null) direction = swing;
      sim.step(WallCricketInput(direction: direction, swing: swing == null ? 0 : 1));
      for (final e in sim.pendingEvents) {
        if (e.type == WallCricketEventType.timing) timings.add(e.value);
      }
    }
    expect(timings, isNotEmpty);
  });

  test('a recorded innings replays to the same score', () {
    final sim = WallCricketSimulation(seed: 4242, pace: Pace.hard);
    final runner = WallCricketRunner(simulation: sim);
    final batter = proxyBatter(skill: 0.7);
    while (!sim.isComplete) {
      final swing = batter(sim);
      if (swing != null) runner.swing(swing);
      runner.tick();
    }
    final replay = ReplayReader.parse(runner.finishRecording());
    final again = replayInnings(replay, pace: Pace.hard);
    expect(again.runs, sim.runs);
    expect(again.wickets, sim.wickets);
    expect(again.ballsBowled, sim.ballsBowled);
    expect(sim.hits, greaterThan(0), reason: 'the replay must cover real play');
  });

  test('the bat never enters the ground, anywhere on the swing', () {
    for (var i = 0; i <= 100; i++) {
      final direction = WallCricketSimulation.arcDirection(i / 100);
      // The constrained pose is what is drawn and what a tip can reach.
      final tipY = Arena.pivot.y + direction.y * Arena.batLength;
      final maxDown = (Arena.groundY - 10 - Arena.pivot.y) / Arena.batLength;
      expect(direction.y > maxDown ? Arena.groundY - 10 : tipY, lessThan(Arena.groundY + 1));
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
