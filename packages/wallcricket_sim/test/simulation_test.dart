import 'package:game_core/game_core.dart';
import 'package:test/test.dart';
import 'package:wallcricket_sim/wallcricket_sim.dart';

/// Plays an innings where every swing starts [lead] seconds before the ball
/// reaches the hitting zone.
WallCricketSimulation swingAt(double lead, {Pace pace = Pace.medium, int seeds = 10}) {
  final total = WallCricketSimulation(seed: 0, pace: pace);
  var runs = 0, hits = 0, wickets = 0, balls = 0;
  for (var seed = 1; seed <= seeds; seed++) {
    var swingTicks = 0;
    final sim = simulateInnings(
      seed: seed,
      pace: pace,
      batter: (sim) {
        if (sim.phase != WallCricketPhase.live) {
          swingTicks = 0;
          return null;
        }
        final hitX = Arena.pivot.x + Arena.batLength * 0.8;
        final away = sim.ballVelocity.x < 0
            ? (sim.ballPosition.x - hitX) / -sim.ballVelocity.x
            : 99.0;
        if (swingTicks > 0 || away < lead) {
          swingTicks++;
          return swingTicks < 40 ? 1.0 : null;
        }
        return 0.0;
      },
    );
    runs += sim.runs;
    hits += sim.hits;
    wickets += sim.wickets;
    balls += sim.ballsBowled;
  }
  return total
    ..runs = runs
    ..hits = hits
    ..wickets = wickets
    ..ballsBowled = balls;
}

void main() {
  test('an innings nobody bats in is bowled out, and scores nothing', () {
    var bowled = 0;
    var runs = 0;
    for (var seed = 1; seed <= 20; seed++) {
      final sim = simulateInnings(seed: seed);
      expect(sim.isComplete, isTrue);
      bowled += sim.wickets;
      runs += sim.runs;
    }
    // The resting blade is up in the backlift, and a blade behind the batter
    // does not play the ball.
    expect(runs, 0);
    expect(bowled, 60);
  });

  test('well-timed swings score and badly-timed ones do not', () {
    final good = swingAt(0.16);
    final late = swingAt(0.04);
    final early = swingAt(0.5);
    expect(good.runs / good.ballsBowled, greaterThan(1.5));
    // Not every ball can be hit: late and early swings are beaten.
    expect(late.hits / late.ballsBowled, lessThan(0.3));
    expect(early.hits / early.ballsBowled, lessThan(0.3));
    expect(good.hits / good.ballsBowled, greaterThan(late.hits / late.ballsBowled + 0.5));
  });

  test('skill moves the result the right way', () {
    int runsAt(double skill) {
      var total = 0;
      for (var seed = 1; seed <= 15; seed++) {
        total += simulateInnings(seed: seed, batter: proxyBatter(skill: skill, noiseSeed: seed)).runs;
      }
      return total;
    }

    expect(runsAt(1.0), greaterThan(runsAt(0.4)));
  });

  test('an edge that carries backwards is caught behind', () {
    var caught = 0;
    for (var seed = 1; seed <= 20; seed++) {
      final sim = WallCricketSimulation(seed: seed, pace: Pace.medium);
      var swingTicks = 0;
      while (!sim.isComplete) {
        double? swing;
        if (sim.phase == WallCricketPhase.live) {
          final away = (sim.ballPosition.x - 446) / -sim.ballVelocity.x;
          if (swingTicks > 0 || away < 0.1) {
            swingTicks++;
            swing = 1;
          } else {
            swing = 0;
          }
        } else {
          swingTicks = 0;
        }
        sim.step(WallCricketInput(swing: swing ?? 0, touching: swing != null));
        for (final e in sim.pendingEvents) {
          if (e.type == WallCricketEventType.out && sim.lastOutcome!.caught) caught++;
        }
      }
    }
    expect(caught, greaterThan(0));
  });

  test('a recorded innings replays to the same score', () {
    final sim = WallCricketSimulation(seed: 4242, pace: Pace.hard);
    final runner = WallCricketRunner(simulation: sim);
    final batter = proxyBatter(skill: 0.85);
    while (!sim.isComplete) {
      runner
        ..setSwing(batter(sim))
        ..tick();
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
      final tip = Arena.pivot +
          WallCricketSimulation.arcDirection(i / 100) * Arena.batLength;
      final sim = WallCricketSimulation(seed: 9, pace: Pace.easy);
      for (var t = 0; t < 60; t++) {
        sim.step(WallCricketInput(swing: i / 100, touching: true));
      }
      expect(sim.batTip.y, lessThan(Arena.groundY), reason: 'swing ${i / 100}, raw tip $tip');
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
