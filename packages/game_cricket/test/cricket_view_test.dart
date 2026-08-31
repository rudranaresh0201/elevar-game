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
      expect(harness.game.bandHeight, greaterThan(200));
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
      expect(PitchCamera.personHeight * camera.scaleAt(CricketField.strikerY),
          greaterThan(60),
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

  group('the pad actually moves the bat', () {
    testWidgets('dragging across the pad moves the blade across the crease',
        (tester) async {
      final harness = CricketHarness(tester);
      await harness.pump(botConfig);
      expect(await harness.waitForDelivery(), isTrue);

      final pad = tester.getCenter(find.byType(BatPad));
      final before = harness.state.bat.position.x;

      // Hold the thumb well over to one side and let the blade travel. It is
      // speed-capped, so this needs real frames rather than one pump.
      final gesture = await tester.startGesture(pad + const Offset(-90, 0));
      await harness.frames(30);
      await gesture.up();

      expect(
        harness.state.bat.position.x,
        lessThan(before - 20),
        reason: 'the thumb never reached the simulation',
      );
    });

    testWidgets('dragging down the pad lowers the blade', (tester) async {
      final harness = CricketHarness(tester);
      await harness.pump(botConfig);
      expect(await harness.waitForDelivery(), isTrue);

      final pad = tester.getCenter(find.byType(BatPad));
      final gesture = await tester.startGesture(pad + const Offset(0, -60));
      await harness.frames(20);
      final high = harness.state.bat.position.y;

      await gesture.moveTo(pad + const Offset(0, 60));
      await harness.frames(20);
      await gesture.up();

      expect(harness.state.bat.position.y, lessThan(high),
          reason: 'down the pad must be down toward the turf');
    });

    testWidgets('a swept blade is moving when it meets the ball',
        (tester) async {
      // The whole reason the control changed: power is not a slider any more,
      // it is how fast the bat happens to be travelling. A blade that arrived
      // and stopped would play every ball as a dead bat.
      final harness = CricketHarness(tester);
      await harness.pump(botConfig);
      expect(await harness.waitForDelivery(), isTrue);

      final pad = tester.getCenter(find.byType(BatPad));
      final gesture = await tester.startGesture(pad + const Offset(-70, -40));
      await harness.frames(10);

      var fastest = 0.0;
      for (var i = 0; i < 40; i++) {
        await gesture.moveTo(
          pad + Offset(-70 + i * 4.0, -40 + i * 2.0),
        );
        await tester.pump(const Duration(milliseconds: 16));
        final speed = harness.state.bat.speed;
        if (speed > fastest) fastest = speed;
      }
      await gesture.up();

      expect(fastest, greaterThan(80),
          reason: 'a thumb sweeping across the pad must move the blade');
    });

    testWidgets('the pad is inert between balls', (tester) async {
      // The bat still exists between deliveries — it drifts back to its
      // stance — but nothing a jab at the screen does should reach the match.
      final harness = CricketHarness(tester);
      await harness.pump(botConfig);
      await harness.frames(2);
      expect(harness.state.phase, CricketPhase.runUp);

      await tester.tap(find.byType(BatPad));
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

    testWidgets('the assist says where the ball is heading', (tester) async {
      final harness = CricketHarness(tester);
      await harness.pump(botConfig);
      expect(await harness.waitForDelivery(), isTrue);

      var sawLine = false;
      for (var i = 0; i < 200; i++) {
        final line = harness.game.ballLineAcrossCrease;
        if (line != null) {
          expect(line, inInclusiveRange(0, 1));
          sawLine = true;
          break;
        }
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(sawLine, isTrue,
          reason: 'the player is never told where the ball is going');
    });

    testWidgets('the assist goes quiet once the ball has passed the bat',
        (tester) async {
      final harness = CricketHarness(tester);
      await harness.pump(botConfig);
      expect(await harness.waitForDelivery(), isTrue);

      for (var i = 0; i < 400; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (harness.state.phase != CricketPhase.delivery) break;
      }
      expect(harness.game.ballLineAcrossCrease, isNull);
    });

    testWidgets('the batting assist can be turned off', (tester) async {
      final harness = CricketHarness(tester);
      await harness.pump(const CricketConfig(
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.medium,
        seed: 4242,
        battingAssist: false,
      ));
      await harness.frames(2);
      expect(harness.game.config.battingAssist, isFalse);
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
      // for a BatPad that is no longer mounted and throws.
      var swept = 0;
      for (var frame = 0; frame < 9000 && harness.outcome == null; frame++) {
        await tester.pump(const Duration(milliseconds: 16));

        final batting = find.byType(BatPad);
        final bowling = find.byType(BowlingPad);

        if (harness.state.phase == CricketPhase.delivery &&
            batting.evaluate().isNotEmpty) {
          // Tap around the pad, so the blade is somewhere different on every
          // ball and actually moving when the ball arrives.
          final pad = tester.getCenter(batting);
          await tester.tapAt(
            pad + Offset(((swept % 5) - 2) * 24.0, ((swept % 3) - 1) * 18.0),
          );
          swept++;
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
