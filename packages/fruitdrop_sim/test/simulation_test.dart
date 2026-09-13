import 'package:fruitdrop_sim/fruitdrop_sim.dart';
import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Drops a fruit of [tier] at [x] by rigging the held fruit, then lets it
/// fall for [ticks] — long enough to land from the top of the jar.
void place(FruitDropSimulation sim, int tier, double x, {int ticks = 240}) {
  sim.current = tier;
  sim.step(FruitInput(aimX: x / sim.width, drop: 1));
  for (var i = 0; i < ticks; i++) {
    sim.step(FruitInput(aimX: x / sim.width));
  }
}

void main() {
  test('two of the same fruit merge into the next one and score for it', () {
    final sim = FruitDropSimulation(seed: 1, jar: JarSize.standard);
    place(sim, 2, 320);
    place(sim, 2, 320);
    expect(sim.fruits, hasLength(1));
    expect(sim.fruits.single.tier, 3);
    expect(sim.score, Fruits.pointsFor(3));
  });

  test('different fruits stack without merging', () {
    final sim = FruitDropSimulation(seed: 1, jar: JarSize.standard);
    place(sim, 1, 320);
    place(sim, 3, 320);
    expect(sim.fruits.map((f) => f.tier).toList()..sort(), <int>[1, 3]);
    expect(sim.score, 0);
  });

  test('two watermelons pop and leave nothing', () {
    final sim = FruitDropSimulation(seed: 1, jar: JarSize.standard);
    place(sim, Fruits.watermelon, 250);
    place(sim, Fruits.watermelon, 390, ticks: 400);
    expect(sim.fruits, isEmpty);
    expect(sim.score, Fruits.pointsFor(Fruits.count) + Fruits.watermelonBonus);
  });

  test('fruit stays inside the jar and nothing flies off', () {
    final sim = simulateFruitDrop(
      seed: 5,
      player: ProxyDropper(skill: 0.3, seed: 5),
      maxTicks: FruitDropSimulation.tickHz * 90,
    );
    for (final f in sim.fruits) {
      expect(f.position.x, inInclusiveRange(0, sim.width));
      expect(f.position.y, lessThanOrEqualTo(FruitDropSimulation.height));
      expect(f.position.y, greaterThan(-300), reason: 'launched out of the jar');
    }
  });

  test('dropping carelessly in one place ends the game', () {
    final sim = FruitDropSimulation(seed: 2, jar: JarSize.narrow);
    var t = 0;
    while (!sim.isComplete && t < FruitDropSimulation.tickHz * 240) {
      // Alternate two tiers so nothing merges, always in the same column.
      if (sim.canDrop) sim.current = sim.drops.isEven ? 3 : 4;
      sim.step(FruitInput(aimX: 0.5, drop: t % 2 == 0 ? 1 : 0));
      t++;
    }
    expect(sim.isComplete, isTrue);
  });

  test('running out of drops ends the round', () {
    final sim = FruitDropSimulation(seed: 4, jar: JarSize.wide);
    var t = 0;
    while (!sim.isComplete && t < FruitDropSimulation.tickHz * 600) {
      // Spread the drops so the jar does not overflow first.
      final x = (sim.drops % 7) / 6;
      if (sim.canDrop) sim.current = 0;
      sim.step(FruitInput(aimX: x, drop: t.isEven ? 1 : 0));
      t++;
      if (sim.score >= sim.jar.target) break;
    }
    expect(sim.drops, lessThanOrEqualTo(JarSize.wide.drops));
    if (sim.isComplete && sim.endReason == RoundEnd.outOfDrops) {
      expect(sim.dropsLeft, 0);
    }
  });

  test('reaching the target ends the round and pays for unused drops', () {
    final sim = FruitDropSimulation(seed: 1, jar: JarSize.wide);
    // Two watermelons are 166 points; three pairs clear the 250 target.
    for (var pair = 0; pair < 3 && !sim.targetReached; pair++) {
      place(sim, Fruits.watermelon, 250);
      place(sim, Fruits.watermelon, 390, ticks: 400);
    }
    for (var i = 0; i < 200 && !sim.isComplete; i++) {
      sim.step(const FruitInput());
    }
    expect(sim.isComplete, isTrue);
    expect(sim.endReason, RoundEnd.targetHit);
    expect(sim.dropBonus, (JarSize.wide.drops - sim.drops) * Fruits.dropBonus);
    expect(sim.canDrop, isFalse);
  });

  test('a recorded game replays to the same score', () {
    late FruitDropRunner runner;
    final sim = simulateFruitDrop(
      seed: 33,
      jar: JarSize.wide,
      player: ProxyDropper(skill: 0.6, seed: 2),
      recordWith: (s) => runner = FruitDropRunner(simulation: s),
      maxTicks: FruitDropSimulation.tickHz * 120,
    );
    final replay = ReplayReader.parse(runner.finishRecording());
    final again = replayFruitDrop(replay, jar: JarSize.wide);
    expect(sim.merges, greaterThan(10));
    expect(again.score, sim.score);
    expect(again.fruits.length, sim.fruits.length);
  });
}
