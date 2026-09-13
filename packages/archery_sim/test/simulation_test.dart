import 'package:archery_sim/archery_sim.dart';
import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  test('terrain is deterministic and the archers stand on flat ledges', () {
    final a = Terrain.generate(11);
    final b = Terrain.generate(11);
    expect(a.heights, b.heights);
    for (final x in <double>[Terrain.p1X, Terrain.p2X]) {
      expect((a.heightAt(x - 30) - a.heightAt(x + 30)).abs(), lessThan(12));
    }
  });

  test('the solved shot actually hits, in any wind', () {
    for (var seed = 1; seed <= 12; seed++) {
      final sim = DuelSimulation(seed: seed, mode: GameMode.local2P);
      final shot = solveShot(sim, from: ArcherSide.p1, at: ArcherSide.p2);
      sim.step(DuelInput(direction: shot.direction, power: shot.power, fire: 1));
      while (sim.phase == DuelPhase.flight) {
        sim.step(const DuelInput());
      }
      expect(sim.p2Hp, lessThan(DuelSimulation.maxHp), reason: 'seed $seed, wind ${sim.wind}');
    }
  });

  test('a headshot does more than a body shot', () {
    expect(DuelSimulation.headDamage, greaterThan(DuelSimulation.bodyDamage));
    final sim = DuelSimulation(seed: 1, mode: GameMode.local2P);
    expect(sim.hitTest(ArcherSide.p2, sim.headCentre(ArcherSide.p2)), HitKind.head);
    expect(
      sim.hitTest(ArcherSide.p2,
          Vec2(DuelSimulation.xOf(ArcherSide.p2), sim.groundOf(ArcherSide.p2) + 40)),
      HitKind.body,
    );
  });

  test('every duel terminates', () {
    for (var seed = 1; seed <= 10; seed++) {
      final sim = simulateDuel(
        seed: seed,
        botDifficulty: BotDifficulty.values[seed % 3],
        human: ProxyArcher(seed: seed),
      );
      expect(sim.isComplete, isTrue);
    }
    // Nobody touching anything still ends, on the turn cap.
    expect(simulateDuel(seed: 3).isComplete, isTrue);
  });

  test('a recorded duel replays to the same result, both modes', () {
    for (final mode in GameMode.values) {
      late DuelRunner runner;
      final sim = simulateDuel(
        seed: 21,
        mode: mode,
        botDifficulty: mode == GameMode.vsBot ? BotDifficulty.hard : null,
        human: ProxyArcher(seed: 4),
        recordWith: (s) => runner = DuelRunner(simulation: s),
      );
      final again = replayDuel(
        ReplayReader.parse(runner.finishRecording()),
        mode: mode,
        botDifficulty: sim.botDifficulty,
      );
      expect(again.p1Hp, sim.p1Hp, reason: mode.name);
      expect(again.p2Hp, sim.p2Hp, reason: mode.name);
      expect(again.turnsTaken, sim.turnsTaken, reason: mode.name);
    }
  });
}
