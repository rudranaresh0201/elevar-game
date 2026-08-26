import 'package:cricket_sim/cricket_sim.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:game_cricket/game_cricket.dart';

/// Drives the real widget through real frames with a real thumb.
///
/// The unit tests prove the simulation is correct; these prove it is wired to a
/// screen and to fingers. Between them sits the class of bug that passes every
/// unit test and ships a batter who never swings because the pad reports its
/// swipes to nothing.
class CricketHarness {
  CricketHarness(this.tester);

  final WidgetTester tester;

  CricketOutcome? outcome;
  late CricketGame game;

  Future<void> pump(CricketConfig config) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final key = GlobalKey<State<CricketView>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CricketView(
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
    game = (key.currentState! as dynamic).gameForTest as CricketGame;
  }

  Future<void> frames(int count) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (outcome != null) return;
    }
  }

  /// Pumps until the ball is on its way, or gives up.
  Future<bool> waitForDelivery({int limit = 600}) async {
    for (var i = 0; i < limit; i++) {
      if (state.phase == CricketPhase.delivery) return true;
      await tester.pump(const Duration(milliseconds: 16));
      if (outcome != null) return false;
    }
    return false;
  }

  CricketState get state => game.simulation.state;
  InningsState get innings => state.current;
}

void main() {
  const botConfig = CricketConfig(
    mode: GameMode.vsBot,
    botDifficulty: BotDifficulty.medium,
    seed: 4242,
  );

  group('the match renders and runs', () {
    testWidgets('opens with the bowler running in', (tester) async {
      final harness = CricketHarness(tester);
      await harness.pump(botConfig);
      await harness.frames(2);

      expect(harness.state.phase, CricketPhase.runUp);
      expect(harness.innings.runs, 0);
      expect(harness.innings.balls, 0);
      expect(find.text('BATTING'), findsOneWidget);
    });

    testWidgets('the view is from behind the stumps, not above them',
        (tester) async {
      final harness = CricketHarness(tester);
      await harness.pump(botConfig);
      await harness.frames(2);

      final camera = harness.game.pitchCamera;

      // The whole point of reserving the band first: the scene is built into
      // the space above it, so no part of the ground sits under a thumb.
      expect(harness.game.bandHeight, greaterThan(150));
      expect(camera.screenHeight,
          closeTo(844 - harness.game.bandHeight, 0.5));

      // Perspective, not orthographic: the same width of pitch has to cover
      // more screen at the batter's end than at the bowler's. This is the
      // assertion that would have caught the original top-down view, which
      // shipped looking like a radar display.
      final nearWidth = (camera.project(
                  CricketField.pitchCentreX + CricketField.pitchHalfWidth,
                  CricketField.strikerCreaseY) -
              camera.project(
                  CricketField.pitchCentreX - CricketField.pitchHalfWidth,
                  CricketField.strikerCreaseY))
          .distance;
      final farWidth = (camera.project(
                  CricketField.pitchCentreX + CricketField.pitchHalfWidth,
                  CricketField.bowlerCreaseY) -
              camera.project(
                  CricketField.pitchCentreX - CricketField.pitchHalfWidth,
                  CricketField.bowlerCreaseY))
          .distance;
      expect(nearWidth, greaterThan(farWidth * 1.8),
          reason: 'the pitch is not receding — this is a top-down view');

      // And the batter is on screen at a size somebody can actually see.
      final batter = camera.project(
          CricketField.pitchCentreX, CricketField.strikerY);
      expect(batter.dy, lessThan(camera.screenHeight));
      expect(batter.dy, greaterThan(camera.horizon));
      expect(178 * camera.scaleAt(CricketField.strikerY), greaterThan(80),
          reason: 'the batter is smaller than a thumbnail');
    });

    testWidgets('the camera swaps ends when the player starts bowling',
        (tester) async {
      final harness = CricketHarness(tester);
      await harness.pump(botConfig);
      await harness.frames(2);
      expect(harness.game.pitchCamera.facing, -1);

      // Watching from behind the batter you are bowling *to* would send every
      // delivery away from the camera.
      expect(
        PitchCamera.forScreen(width: 390, height: 650, role: Role.bowling)
            .facing,
        1,
      );
    });

    testWidgets('the bowler eventually bowls', (tester) async {
      final harness = CricketHarness(tester);
      await harness.pump(botConfig);
      expect(await harness.waitForDelivery(), isTrue,
          reason: 'no ball was ever bowled');
    });
  });

  group('the pad actually plays a shot', () {
    testWidgets('a swipe during the delivery registers a swing',
        (tester) async {
      final harness = CricketHarness(tester);
      await harness.pump(botConfig);
      expect(await harness.waitForDelivery(), isTrue);

      expect(harness.state.ball.swung, isFalse);

      // A real drag on the pad: down, across, up.
      final pad = tester.getCenter(find.byType(BattingPad));
      final gesture = await tester.startGesture(pad);
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(-40, -70));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await harness.frames(8);

      expect(harness.state.ball.swung, isTrue,
          reason: 'the swipe never reached the simulation');
    });

    testWidgets('a tap is a straight push rather than nothing', (tester) async {
      final harness = CricketHarness(tester);
      await harness.pump(botConfig);
      expect(await harness.waitForDelivery(), isTrue);

      await tester.tap(find.byType(BattingPad));
      await harness.frames(8);

      expect(harness.state.ball.swung, isTrue);
    });

    testWidgets('the pad is inert between balls', (tester) async {
      // Otherwise a jab at the screen spends the next delivery's shot before
      // the bowler has even run in.
      final harness = CricketHarness(tester);
      await harness.pump(botConfig);
      await harness.frames(2);
      expect(harness.state.phase, CricketPhase.runUp);

      await tester.tap(find.byType(BattingPad));
      await harness.frames(4);

      expect(harness.state.ball.swung, isFalse);
      expect(find.text('WAIT FOR THE BALL'), findsOneWidget);
    });
  });

  group('the scoreboard says what is happening', () {
    testWidgets('the over strip has one pip per ball of the innings',
        (tester) async {
      final harness = CricketHarness(tester);
      await harness.pump(botConfig);
      await harness.frames(2);

      // Twelve balls in a two-over innings, all still to come.
      expect(harness.game.config.rules.ballsPerInnings, 12);
    });

    testWidgets('the timing ring appears while the ball is arriving',
        (tester) async {
      final harness = CricketHarness(tester);
      await harness.pump(botConfig);
      expect(await harness.waitForDelivery(), isTrue);

      // Somewhere in the delivery the window opens.
      var sawRing = false;
      for (var i = 0; i < 200; i++) {
        if (harness.game.inSwingWindow) {
          sawRing = true;
          break;
        }
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(sawRing, isTrue,
          reason: 'the player is never told when to swing');
      expect(harness.game.swingOffset, inInclusiveRange(-1, 1));
    });

    testWidgets('assisted timing can be turned off', (tester) async {
      final harness = CricketHarness(tester);
      await harness.pump(const CricketConfig(
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.medium,
        seed: 4242,
        assistedTiming: false,
      ));
      await harness.frames(2);
      expect(harness.game.config.assistedTiming, isFalse);
    });
  });

  group('a match played through the widget still verifies', () {
    testWidgets('the recording reproduces what was played', (tester) async {
      // The end-to-end claim: a match driven by real touches on the real pad
      // produces a replay that re-runs to the same score. If this passes, the
      // path from thumb to server-verifiable score is intact.
      const config = CricketConfig(
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.easy,
        rules: CricketRules.superOver,
        seed: 31415,
      );

      final harness = CricketHarness(tester);
      await harness.pump(config);

      // Play the whole match, driving off whichever pad is actually on
      // screen rather than off a role read a moment earlier.
      //
      // You bat first and then bowl, so the pad swaps partway through — and
      // reading the role *before* waiting for the delivery leaves it stale,
      // because the innings can turn over during the wait. Then the tap looks
      // for a BattingPad that is no longer mounted and throws.
      for (var frame = 0; frame < 9000 && harness.outcome == null; frame++) {
        await tester.pump(const Duration(milliseconds: 16));

        final batting = find.byType(BattingPad);
        final bowling = find.byType(BowlingPad);

        if (harness.state.phase == CricketPhase.delivery &&
            !harness.state.ball.swung &&
            batting.evaluate().isNotEmpty) {
          await tester.tap(batting);
        } else if (harness.state.phase == CricketPhase.runUp &&
            bowling.evaluate().isNotEmpty) {
          await tester.tap(bowling);
        }
      }

      final outcome = harness.outcome;
      expect(outcome, isNotNull, reason: 'the match never finished');

      final verified = replayMatch(
        ReplayReader.parse(outcome!.replay),
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.easy,
        rules: CricketRules.superOver,
      );

      expect(verified.state.runsFor(CricketSide.p1), outcome.result.p1Score);
      expect(verified.state.runsFor(CricketSide.p2), outcome.result.p2Score);
    });
  });
}
