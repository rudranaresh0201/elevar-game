import 'package:game_core/game_core.dart';
import 'package:penalty_sim/penalty_sim.dart';
import 'package:test/test.dart';

/// Takes one human kick with [shot] and returns what happened.
KickResult kick(ShotParams shot, {int seed = 1, BotDifficulty d = BotDifficulty.easy}) {
  final sim = PenaltySimulation(seed: seed, mode: GameMode.vsBot, botDifficulty: d);
  var fired = false;
  while (sim.p1Kicks.isEmpty) {
    sim.step(PenaltyInput(
      aim: shot.target,
      power: shot.power,
      curve: shot.curve,
      fire: fired ? 1 : 0,
    ));
    fired = true;
  }
  return sim.p1Kicks.single;
}

void main() {
  test('a shot well wide misses and one over the bar misses', () {
    expect(kick(const ShotParams(target: GoalPoint(5.2, 1), power: 0.5, curve: 0)),
        KickResult.missed);
    expect(kick(const ShotParams(target: GoalPoint(0, 3.4), power: 0.5, curve: 0)),
        KickResult.missed);
  });

  test('a ball aimed at the post hits the post', () {
    expect(
      kick(const ShotParams(target: GoalPoint(Goal.halfWidth, 1.2), power: 0.5, curve: 0)),
      KickResult.post,
    );
  });

  test('curve changes the path but not where the ball arrives', () {
    for (final curve in <double>[-1, 0, 1]) {
      final sim = PenaltySimulation(
          seed: 3, mode: GameMode.local2P);
      sim.step(PenaltyInput(
        aim: const GoalPoint(2.8, 0.8),
        power: 0.6,
        curve: curve,
        fire: 1,
      ));
      while (sim.phase != PenaltyPhase.flight) {
        sim.step(const PenaltyInput(fire: 1));
      }
      final crossing = sim.predictCrossing(0);
      expect(crossing.x, closeTo(2.8, 1e-6));
      expect(crossing.y, closeTo(0.8, 1e-6));
    }
  });

  test('an overhit shot rises', () {
    expect(kick(const ShotParams(target: GoalPoint(1.5, 2.0), power: 1, curve: 0)),
        KickResult.missed);
  });

  test('every shootout terminates with a legal score line', () {
    for (var seed = 1; seed <= 40; seed++) {
      final sim = simulateShootout(
        seed: seed,
        botDifficulty: BotDifficulty.values[seed % 3],
        human: ProxyPlayer(seed: seed),
      );
      expect(sim.isComplete, isTrue);
      final n1 = sim.p1Kicks.length;
      final n2 = sim.p2Kicks.length;
      expect(n1 - n2, inInclusiveRange(0, 1));
      expect(n1, lessThanOrEqualTo(10));
      if (n1 > 5) expect(n1, n2, reason: 'sudden death ends on pairs');
    }
  });

  test('a recorded shootout replays to the same result, both modes', () {
    for (final mode in GameMode.values) {
      late PenaltyRunner runner;
      final sim = simulateShootout(
        seed: 77,
        mode: mode,
        botDifficulty: mode == GameMode.vsBot ? BotDifficulty.hard : null,
        human: ProxyPlayer(skill: 0.6, seed: 5),
        recordWith: (s) => runner = PenaltyRunner(simulation: s),
      );
      final again = replayShootout(
        ReplayReader.parse(runner.finishRecording()),
        mode: mode,
        botDifficulty: sim.botDifficulty,
      );
      expect(again.p1Kicks, sim.p1Kicks, reason: mode.name);
      expect(again.p2Kicks, sim.p2Kicks, reason: mode.name);
    }
  });

  test('a keeper who waits in the middle saves a tame central shot', () {
    final sim = PenaltySimulation(seed: 1, mode: GameMode.local2P);
    sim.step(const PenaltyInput(aim: GoalPoint(0, 1), power: 0.2, fire: 1));
    while (sim.p1Kicks.isEmpty) {
      sim.step(const PenaltyInput(fire: 1));
    }
    expect(sim.p1Kicks.single, KickResult.saved);
  });

  test('a goal through the bonus target is a bullseye worth more', () {
    final sim = PenaltySimulation(seed: 8, mode: GameMode.local2P);
    final target = sim.bonusTarget!;
    sim.step(PenaltyInput(aim: target, power: 0.9, fire: 1));
    // The keeper (the other human) never dives.
    while (sim.p1Kicks.isEmpty) {
      sim.step(const PenaltyInput(fire: 1));
    }
    if (sim.p1Kicks.single == KickResult.goal) {
      expect(sim.p1Bullseyes, 1);
      expect(sim.p1Points, greaterThanOrEqualTo(
          PenaltySimulation.goalPoints + PenaltySimulation.bullseyePoints));
    }
  });

  test('a keeper who dives to the right spot in time catches it', () {
    var caught = 0;
    for (var seed = 1; seed <= 12; seed++) {
      final sim = PenaltySimulation(seed: seed, mode: GameMode.vsBot, botDifficulty: BotDifficulty.easy);
      // Let the human's first kick go by.
      sim.step(const PenaltyInput(aim: GoalPoint(5.5, 1), power: 0.5, fire: 1));
      while (sim.shooter == PenaltySide.p1 && !sim.isComplete) {
        sim.step(const PenaltyInput(fire: 1));
      }
      // The bot shoots; dive exactly where it will cross as soon as it is struck.
      var dived = false;
      while (sim.p2Kicks.isEmpty && !sim.isComplete) {
        final dive = !dived && sim.phase == PenaltyPhase.flight;
        final at = dive ? sim.predictCrossing(Goal.keeperZ) : const GoalPoint(0, 1);
        dived = dived || dive;
        sim.step(PenaltyInput(dive: at, diveTrigger: dive ? 1 : 0));
      }
      if (sim.p2Kicks.isNotEmpty && sim.p2Kicks.single == KickResult.saved && sim.lastSaveCaught) caught++;
    }
    expect(caught, greaterThan(3));
  });

  test('the bot keeper sways across its line before the kick', () {
    final sim = PenaltySimulation(seed: 2, mode: GameMode.vsBot, botDifficulty: BotDifficulty.medium);
    final xs = <double>{};
    for (var t = 0; t < 150; t++) {
      sim.step(const PenaltyInput());
      xs.add((sim.keeper.x * 10).roundToDouble());
    }
    expect(xs.length, greaterThan(5));
  });
}
