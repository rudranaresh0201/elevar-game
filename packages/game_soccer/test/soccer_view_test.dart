import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:game_soccer/game_soccer.dart';
import 'package:soccer_sim/soccer_sim.dart';

/// Drives the real widget through real frames with a real thumb.
///
/// Unit tests prove the simulation is correct; these prove it is actually
/// wired to a screen and a finger. Between them sits the class of bug that
/// passes every unit test and ships a black rectangle — and, for this game
/// specifically, the class of bug where the gesture is translated into the
/// wrong one of the two meanings the input channels carry.
class Harness {
  Harness(this.tester, this.state, this.outcomeSink);

  final WidgetTester tester;
  final State<SoccerView> state;
  final List<SoccerOutcome> outcomeSink;

  SoccerGame get game => (state as dynamic).gameForTest as SoccerGame;

  SoccerSimulation get simulation => game.simulation;

  /// Where a field point lands on the screen, through the same letterbox the
  /// renderer uses.
  Offset screenOf(Vec2 field) => Offset(
        game.fieldOrigin.dx + field.x * game.fieldScale,
        game.fieldOrigin.dy + field.y * game.fieldScale,
      );

  /// The centre-forward of the side to play — the disc with clear space
  /// around it, which is what a test that wants to see movement needs.
  int get forwardIndex =>
      SoccerWorld.firstDiscIndex(simulation.state.turn) + 3;

  Vec2 discAt(int index) => simulation.state.world.bodies[index].position;

  Future<void> pump([int frames = 1]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> pumpUntil(
    bool Function() done, {
    int maxFrames = 900,
  }) async {
    for (var i = 0; i < maxFrames && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }
}

Future<Harness> boot(
  WidgetTester tester, {
  required SoccerConfig config,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final outcomes = <SoccerOutcome>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SoccerView(
          config: config,
          onQuit: () {},
          onComplete: outcomes.add,
        ),
      ),
    ),
  );
  await tester.pump();

  final state = tester.state<State<SoccerView>>(find.byType(SoccerView));
  final harness = Harness(tester, state, outcomes);
  // Past the kickoff freeze, to a turn that can actually be played.
  await harness.pumpUntil(
    () => harness.simulation.state.phase == SoccerPhase.aiming,
  );
  return harness;
}

const SoccerConfig twoPlayer = SoccerConfig(
  mode: GameMode.local2P,
  seed: 4242,
);

void main() {
  testWidgets('the pitch renders and a turn starts', (tester) async {
    final harness = await boot(tester, config: twoPlayer);

    expect(find.byType(SoccerView), findsOneWidget);
    expect(harness.simulation.state.phase, SoccerPhase.aiming);
    expect(tester.takeException(), isNull);

    // Sixty frames of nothing on screen would still pass a smoke test; this
    // also checks nothing throws while the shot clock runs down.
    await harness.pump(60);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a drag on a counter flicks it, and the turn passes',
      (tester) async {
    final harness = await boot(tester, config: twoPlayer);

    final side = harness.simulation.state.turn;
    final index = harness.forwardIndex;
    final before = harness.discAt(index);

    final gesture = await tester.startGesture(harness.screenOf(before));
    // Held still for a moment: the simulation samples input every sixth tick,
    // so the grab needs a boundary to land on.
    await harness.pump(6);
    expect(harness.simulation.state.aim.isHolding, isTrue);
    expect(harness.simulation.state.aim.discIndex, index);

    // Drag back toward this side's own goal, so the disc goes the other way —
    // up the pitch for P1, down it for P2 — into clear space either way.
    final home = side == SoccerSide.p1 ? 1.0 : -1.0;
    await gesture.moveBy(Offset(0, -home * 62));
    await harness.pump(6);
    expect(harness.simulation.state.aim.power, greaterThan(0.2));
    expect(harness.simulation.state.aim.direction.y * home, greaterThan(0.9));

    await gesture.up();
    await harness.pumpUntil(
      () => harness.simulation.state.phase == SoccerPhase.resolving,
      maxFrames: 30,
    );
    expect(harness.simulation.state.phase, SoccerPhase.resolving);

    await harness.pumpUntil(
      () => harness.simulation.state.phase == SoccerPhase.aiming,
    );
    expect(
      (harness.discAt(index).y - before.y) * home,
      greaterThan(80),
      reason: 'the counter should have travelled away from the drag',
    );
    expect(harness.simulation.state.turn, side.other,
        reason: 'a flick ends your turn');
  });

  testWidgets('a fast flick still registers', (tester) async {
    // The regression this exists for: down, drag and up inside two frames.
    // The simulation has usually not reached a sample boundary by then, so a
    // touch layer that drops the gesture the instant the finger lifts eats the
    // shot — and it eats exactly the shots that felt best to take.
    final harness = await boot(tester, config: twoPlayer);

    final side = harness.simulation.state.turn;
    final index = harness.forwardIndex;
    final before = harness.discAt(index);
    final home = side == SoccerSide.p1 ? 1.0 : -1.0;

    final gesture = await tester.startGesture(harness.screenOf(before));
    await gesture.moveBy(Offset(0, -home * 70));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();

    await harness.pumpUntil(
      () => harness.simulation.state.turn != side,
    );
    expect(
      (harness.discAt(index).y - before.y).abs(),
      greaterThan(60),
      reason: 'the fast flick was dropped before the simulation saw it',
    );
  });

  testWidgets('a tap does not burn the turn', (tester) async {
    final harness = await boot(tester, config: twoPlayer);

    final side = harness.simulation.state.turn;
    final index = harness.forwardIndex;
    final before = harness.discAt(index);

    final gesture = await tester.startGesture(harness.screenOf(before));
    await harness.pump(8);
    await gesture.up();
    await harness.pump(20);

    expect(harness.simulation.state.phase, SoccerPhase.aiming);
    expect(harness.simulation.state.turn, side);
    expect(harness.discAt(index), before);
  });

  testWidgets("you cannot grab the other side's counters", (tester) async {
    final harness = await boot(tester, config: twoPlayer);

    final theirs =
        SoccerWorld.firstDiscIndex(harness.simulation.state.turn.other) + 3;
    final gesture =
        await tester.startGesture(harness.screenOf(harness.discAt(theirs)));
    await harness.pump(10);
    expect(harness.simulation.state.aim.isHolding, isFalse);
    await gesture.up();
  });

  testWidgets('the bot takes its own turn without a finger', (tester) async {
    final harness = await boot(
      tester,
      config: const SoccerConfig(
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.easy,
        seed: 900,
      ),
    );

    // Get to a turn the bot owns, then leave the screen alone entirely.
    await harness.pumpUntil(
      () =>
          harness.simulation.state.turn == SoccerSide.p2 &&
          harness.simulation.state.phase == SoccerPhase.aiming,
    );
    expect(harness.game.acceptsTouch, isFalse,
        reason: 'the pitch must be untouchable while the bot plays');
    // The aim band is populated for the bot too, so you can see what it is
    // about to try.
    expect(harness.simulation.state.aim.isHolding, isTrue);

    await harness.pumpUntil(
      () => harness.simulation.state.turn == SoccerSide.p1,
    );
    expect(harness.simulation.state.turnsTaken, greaterThan(0));
  });

  testWidgets('a match finishes and hands back a verifiable replay',
      (tester) async {
    // Short rules, and nobody touches the screen: every turn times out, which
    // is the fastest legal way to reach full time.
    final harness = await boot(
      tester,
      config: const SoccerConfig(
        mode: GameMode.local2P,
        seed: 55,
        rules: SoccerRules(targetGoals: 1, maxTurns: 4, aimTicks: 90),
      ),
    );

    await harness.pumpUntil(
      () => harness.outcomeSink.isNotEmpty,
      maxFrames: 600,
    );
    expect(harness.outcomeSink, hasLength(1));

    final outcome = harness.outcomeSink.single;
    expect(outcome.result.gameSlug, 'soccer');
    expect(outcome.replay, isNotEmpty);

    final verified = replaySoccerMatch(
      ReplayReader.parse(outcome.replay),
      mode: GameMode.local2P,
      rules: const SoccerRules(targetGoals: 1, maxTurns: 4, aimTicks: 90),
    );
    expect(verified.state.p1Goals, outcome.result.p1Score);
    expect(verified.state.p2Goals, outcome.result.p2Score);
  });
}
