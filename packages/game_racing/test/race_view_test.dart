import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:game_racing/game_racing.dart';
import 'package:racing_sim/racing_sim.dart';

/// Drives the real widget through real frames with real thumbs.
///
/// The unit tests prove the simulation is correct; these prove it is wired to a
/// screen and to fingers. Between them sits the class of bug that passes every
/// unit test and ships a black rectangle — or, here, a car that never moves
/// because a button reports its presses to nothing.
class RaceHarness {
  RaceHarness(this.tester);

  final WidgetTester tester;

  RaceOutcome? outcome;
  late RacingGame game;

  Future<void> pump(RaceConfig config) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final key = GlobalKey<State<RaceView>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RaceView(
            key: key,
            config: config,
            onQuit: () {},
            onComplete: (o) => outcome = o,
          ),
        ),
      ),
    );
    await tester.pump();
    // ignore: avoid_dynamic_calls
    game = (key.currentState! as dynamic).gameForTest as RacingGame;
  }

  Future<void> frames(int count) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (outcome != null) return;
    }
  }

  CarState get p1 => game.simulation.state.p1;
  CarState get p2 => game.simulation.state.p2;
}

/// P1's controls sit in the bottom band; there are two of every glyph on a
/// two-player screen, so the lower one is the one to press.
Finder lowerMost(Finder finder, WidgetTester tester) {
  final elements = finder.evaluate().toList();
  elements.sort((a, b) {
    final ay = tester.getCenter(find.byWidget(a.widget)).dy;
    final by = tester.getCenter(find.byWidget(b.widget)).dy;
    return by.compareTo(ay);
  });
  return find.byWidget(elements.first.widget);
}

void main() {
  // Auto-gas is the shipped default, and these tests are specifically about
  // what the pedals do, so they opt out of it explicitly. The auto-gas path has
  // its own test at the bottom of the file.
  const botConfig = RaceConfig(
    mode: GameMode.vsBot,
    botDifficulty: BotDifficulty.medium,
    trackName: 'DUSTBOWL',
    seed: 4242,
    autoGas: false,
  );

  group('the race renders and runs', () {
    testWidgets('opens on the countdown with both cars on the grid',
        (tester) async {
      final harness = RaceHarness(tester);
      await harness.pump(botConfig);
      await harness.frames(2);

      expect(harness.game.simulation.state.phase, RacePhase.countdown);
      expect(harness.p1.lap, 0);
      // Behind the line, so lap one is a full lap like every other.
      expect(harness.p1.travelled, lessThan(0));
      // The 3-2-1 disc.
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('the countdown ends and the race goes green', (tester) async {
      final harness = RaceHarness(tester);
      await harness.pump(botConfig);
      // The countdown is three seconds at 120 Hz.
      await harness.frames(240);

      expect(harness.game.simulation.state.phase, RacePhase.racing);
    });

    testWidgets('the circuit is letterboxed clear of both control bands',
        (tester) async {
      final harness = RaceHarness(tester);
      await harness.pump(botConfig);
      await harness.frames(2);

      // The whole point of reserving the bands first: no part of the track can
      // sit under a thumb.
      expect(harness.game.bandHeight, greaterThan(100));
      expect(harness.game.fieldOrigin.dy,
          greaterThanOrEqualTo(harness.game.bandHeight));
      final bottom = harness.game.fieldOrigin.dy +
          RaceField.height * harness.game.fieldScale;
      expect(bottom, lessThanOrEqualTo(844 - harness.game.bandHeight + 0.5));
    });
  });

  group('the controls actually drive the car', () {
    testWidgets('holding GAS moves the car forward', (tester) async {
      final harness = RaceHarness(tester);
      await harness.pump(botConfig);
      await harness.frames(240); // through the countdown

      final before = harness.p1.travelled;
      expect(harness.p1.speed, lessThan(1));

      final gas = await tester.startGesture(
        tester.getCenter(find.text('GAS')),
      );
      await harness.frames(120); // one second, foot down

      expect(harness.p1.speed, greaterThan(50));
      expect(harness.p1.travelled, greaterThan(before));

      await gas.up();
      final coasting = harness.p1.speed;
      await harness.frames(180);
      // Drag alone should slow it down again once the thumb comes off.
      expect(harness.p1.speed, lessThan(coasting));
    });

    testWidgets('holding BRAKE stops a moving car', (tester) async {
      final harness = RaceHarness(tester);
      await harness.pump(botConfig);
      await harness.frames(240);

      // Short of the first corner. Holding the throttle much longer than this
      // drives straight off the circuit, and a car bogged down in the grass is
      // not a measurement of the brakes.
      final gas = await tester.startGesture(
        tester.getCenter(find.text('GAS')),
      );
      await harness.frames(100);
      await gas.up();
      final rolling = harness.p1.speed;
      expect(rolling, greaterThan(40));

      final brake = await tester.startGesture(
        tester.getCenter(find.text('BRAKE')),
      );
      await harness.frames(90);
      await brake.up();

      // The brake is stronger than the engine, so this must be decisive.
      expect(harness.p1.speed, lessThan(rolling / 2));
    });

    testWidgets('steering turns the car', (tester) async {
      final harness = RaceHarness(tester);
      await harness.pump(botConfig);
      await harness.frames(240);

      final gas = await tester.startGesture(
        tester.getCenter(find.text('GAS')),
      );
      await harness.frames(90);

      final headingBefore = harness.p1.heading;
      final steer = await tester.startGesture(
        tester.getCenter(find.text('▶')),
      );
      await harness.frames(90);
      await steer.up();
      await gas.up();

      final headingAfter = harness.p1.heading;
      // A turn is a change in direction; the dot product falls below one.
      expect(headingBefore.dot(headingAfter), lessThan(0.98));
      // And the heading is still a unit vector, so the rotation renormalised.
      expect(headingAfter.length, closeTo(1.0, 1e-9));
    });

    testWidgets('a stationary car cannot pirouette', (tester) async {
      final harness = RaceHarness(tester);
      await harness.pump(botConfig);
      await harness.frames(240);

      final headingBefore = harness.p1.heading;
      final steer = await tester.startGesture(
        tester.getCenter(find.text('▶')),
      );
      await harness.frames(120);
      await steer.up();

      // Steering authority ramps with speed, so a parked car barely moves.
      expect(harness.p1.heading.dot(headingBefore), closeTo(1.0, 1e-6));
    });

    testWidgets('both directions at once cancel out', (tester) async {
      final harness = RaceHarness(tester);
      await harness.pump(botConfig);
      await harness.frames(240);

      final gas = await tester.startGesture(
        tester.getCenter(find.text('GAS')),
      );
      await harness.frames(90);
      final headingBefore = harness.p1.heading;

      // Two thumbs on the rocker at once — which is what happens when someone
      // fumbles, and must not send the car one way or the other.
      final left = await tester.startGesture(
        tester.getCenter(find.text('◀')),
      );
      final right = await tester.startGesture(
        tester.getCenter(find.text('▶')),
      );
      await harness.frames(90);
      await left.up();
      await right.up();
      await gas.up();

      expect(harness.p1.heading.dot(headingBefore), closeTo(1.0, 1e-6));
    });
  });

  group('two players on one phone', () {
    const twoPlayer = RaceConfig(
      mode: GameMode.local2P,
      trackName: 'SUNSET LOOP',
      seed: 777,
      autoGas: false,
    );

    testWidgets('both bands are live and independent', (tester) async {
      final harness = RaceHarness(tester);
      await harness.pump(twoPlayer);
      await harness.frames(240);

      // Two of everything now: one cluster per driver.
      expect(find.text('GAS'), findsNWidgets(2));
      expect(find.text('BRAKE'), findsNWidgets(2));

      // Press only P1's pedal — the lower of the two.
      final p1Gas = await tester.startGesture(
        tester.getCenter(lowerMost(find.text('GAS'), tester)),
      );
      await harness.frames(120);
      await p1Gas.up();

      expect(harness.p1.speed, greaterThan(50));
      // P2 never touched anything and must not have moved.
      expect(harness.p2.speed, lessThan(1));
    });

    testWidgets('four thumbs at once all register', (tester) async {
      final harness = RaceHarness(tester);
      await harness.pump(twoPlayer);
      await harness.frames(240);

      final gasFinders = find.text('GAS').evaluate().toList();
      final p1Gas = await tester.startGesture(
        tester.getCenter(find.byWidget(gasFinders[0].widget)),
      );
      final p2Gas = await tester.startGesture(
        tester.getCenter(find.byWidget(gasFinders[1].widget)),
      );
      final steerFinders = find.text('▶').evaluate().toList();
      final p1Steer = await tester.startGesture(
        tester.getCenter(find.byWidget(steerFinders[0].widget)),
      );
      final p2Steer = await tester.startGesture(
        tester.getCenter(find.byWidget(steerFinders[1].widget)),
      );

      await harness.frames(120);

      // Both cars accelerating from four simultaneous touches is the whole
      // reason the buttons are raw pointer listeners rather than gesture
      // detectors — an arena would have arbitrated three of these away.
      expect(harness.p1.speed, greaterThan(50));
      expect(harness.p2.speed, greaterThan(50));

      await p1Gas.up();
      await p2Gas.up();
      await p1Steer.up();
      await p2Steer.up();
    });
  });

  group('a race played through the widget still verifies', () {
    testWidgets('the recording reproduces what was played', (tester) async {
      // The end-to-end claim: a race driven by real touches on real buttons
      // produces a replay that re-runs to the same result. If this passes, the
      // path from thumb to server-verifiable score is intact.
      const config = RaceConfig(
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.easy,
        trackName: 'DUSTBOWL',
        rules: RaceRules(laps: 1, maxSeconds: 90),
        seed: 31415,
        autoGas: false,
      );

      final harness = RaceHarness(tester);
      await harness.pump(config);
      await harness.frames(240);

      // Hold the throttle and lean on the wheel — enough to get round.
      final gas = await tester.startGesture(
        tester.getCenter(find.text('GAS')),
      );
      for (var i = 0; i < 90 && harness.outcome == null; i++) {
        final steer = await tester.startGesture(
          tester.getCenter(find.text('▶')),
        );
        await harness.frames(20);
        await steer.up();
        await harness.frames(20);
      }
      await gas.up();
      await harness.frames(600);

      final outcome = harness.outcome;
      expect(outcome, isNotNull, reason: 'the race never finished');

      final verified = replayRace(
        ReplayReader.parse(outcome!.replay),
        mode: GameMode.vsBot,
        track: Tracks.dustbowl(),
        botDifficulty: BotDifficulty.easy,
        rules: config.rules,
      );

      expect(verified.state.p1.lap, outcome.result.p1Score);
      expect(verified.state.p2.lap, outcome.result.p2Score);
      expect(verified.state.winner, isNotNull);
    });
  });

  group('the friendlier defaults', () {
    testWidgets('auto-gas drives the car without a thumb on the pedal',
        (tester) async {
      // The shipped default. Nothing is pressed at any point in this test.
      const config = RaceConfig(
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.easy,
        trackName: 'DUSTBOWL',
        seed: 4242,
      );
      final harness = RaceHarness(tester);
      await harness.pump(config);

      // Still on the grid: auto-gas must not jump the start.
      await harness.frames(150);
      expect(harness.game.simulation.state.phase, RacePhase.countdown);
      expect(harness.p1.speed, lessThan(1));

      // Lights out, and away it goes on its own.
      await harness.frames(180);
      expect(harness.game.simulation.state.phase, RacePhase.racing);
      expect(harness.p1.speed, greaterThan(50));
    });

    testWidgets('auto-gas leaves only the steering and the brake on screen',
        (tester) async {
      const config = RaceConfig(
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.easy,
        trackName: 'DUSTBOWL',
        seed: 4242,
      );
      final harness = RaceHarness(tester);
      await harness.pump(config);
      await harness.frames(2);

      // The chip still says AUTO / GAS — it is a label, not a target, so the
      // thing to assert is that there is nothing left to press for the
      // throttle: three hold buttons (left, right, brake) rather than four.
      expect(find.text('AUTO'), findsOneWidget);
      expect(find.byType(HoldButton), findsNWidgets(3));
      expect(find.text('BRAKE'), findsOneWidget);
      expect(find.text('◀'), findsOneWidget);
      expect(find.text('▶'), findsOneWidget);
    });

    testWidgets('the start hint appears, then gets out of the way',
        (tester) async {
      const config = RaceConfig(
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.easy,
        trackName: 'DUSTBOWL',
        seed: 4242,
        autoGas: false,
      );
      final harness = RaceHarness(tester);
      await harness.pump(config);

      // Nothing during the countdown — the 3-2-1 disc owns the screen.
      await harness.frames(120);
      expect(find.text('HOLD GAS'), findsNothing);

      // Green flag, car stationary: this is the moment a first-time player
      // decides the game is broken.
      await harness.frames(150);
      expect(find.text('HOLD GAS'), findsOneWidget);

      // And it disappears once they are actually driving.
      final gas = await tester.startGesture(
        tester.getCenter(find.text('GAS')),
      );
      await harness.frames(90);
      await gas.up();
      await harness.frames(2);
      expect(find.text('HOLD GAS'), findsNothing);
    });
  });
}
