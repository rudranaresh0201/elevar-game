import 'package:archery_sim/archery_sim.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruitdrop_sim/fruitdrop_sim.dart';
import 'package:game_archery/game_archery.dart';
import 'package:game_core/game_core.dart';
import 'package:game_fruitdrop/game_fruitdrop.dart';
import 'package:game_penalty/game_penalty.dart';
import 'package:game_wallcricket/game_wallcricket.dart';
import 'package:penalty_sim/penalty_sim.dart';
import 'package:wallcricket_sim/wallcricket_sim.dart';

/// The four new games, played through real frames with real gestures, at the
/// smallest phone and a common one.
///
/// A simulation test cannot see a HUD that overflows a 320pt screen or a
/// painter that throws on the first frame. These can: a layout overflow or a
/// paint exception during any pumped frame fails the test.
Future<void> pumpGame(WidgetTester tester, Size size, Widget view) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: view)));
  await tester.pump();
}

Future<void> frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  const sizes = <Size>[Size(320, 640), Size(390, 844)];

  for (final size in sizes) {
    final label = '${size.width.round()}x${size.height.round()}';

    testWidgets('cricket: a held, swung bat hits balls ($label)', (tester) async {
      late WallCricketView view;
      await pumpGame(
        tester,
        size,
        view = WallCricketView(
          config: const WallCricketConfig(pace: Pace.easy, seed: 7),
          onComplete: (_) {},
          onQuit: () {},
        ),
      );
      final state = tester.state(find.byWidget(view));
      final game = (state as dynamic).gameForTest as WallCricketGame;

      // Rest a thumb on the glass, then swipe as the ball comes into the
      // hitting zone — what a player does, through the real touch layer.
      final start = Offset(size.width * 0.6, size.height * 0.45);
      for (var ball = 0; ball < 4; ball++) {
        TestGesture? gesture;
        var swung = false;
        for (var f = 0; f < 400; f++) {
          final sim = game.simulation;
          if (sim.phase == WallCricketPhase.live && !swung) {
            gesture ??= await tester.startGesture(start);
            final hitX = Arena.pivot.x + Arena.batLength * 0.8;
            final seconds = (sim.ballPosition.x - hitX) / -sim.ballVelocity.x;
            if (sim.ballVelocity.x < 0 && seconds < 0.16) {
              swung = true;
              for (var s = 1; s <= 3; s++) {
                await gesture.moveTo(start + Offset(0, size.height * 0.13 * s));
                await tester.pump(const Duration(milliseconds: 8));
              }
            }
          }
          await tester.pump(const Duration(milliseconds: 8));
          if (sim.ballsBowled > ball) break;
        }
        await gesture?.up();
        await frames(tester, 30);
      }
      expect(tester.takeException(), isNull);
      expect(game.simulation.ballsBowled, greaterThan(0));
      expect(game.simulation.hits, greaterThan(0), reason: 'a real swing should connect');
    });

    testWidgets('penalties: a swipe becomes a shot, a tap becomes a dive ($label)',
        (tester) async {
      late PenaltyView view;
      await pumpGame(
        tester,
        size,
        view = PenaltyView(
          config: const PenaltyConfig(mode: GameMode.vsBot, botDifficulty: BotDifficulty.easy, seed: 3),
          onComplete: (_) {},
          onQuit: () {},
        ),
      );
      final game = (tester.state(find.byWidget(view)) as dynamic).gameForTest as PenaltyGame;
      final ball = game.ballScreen;
      await tester.flingFrom(ball, Offset(size.width * 0.25, -(ball.dy - game.goalBaseScreenY) - 30), 1800);
      await frames(tester, 30);
      expect(game.simulation.lastShot, isNotNull, reason: 'the swipe did not shoot');
      await frames(tester, 260);
      expect(game.simulation.shooter, PenaltySide.p2);

      // The bot's kick: dive at the goal.
      await frames(tester, 60);
      await tester.tapAt(game.camera3d.at(-2.5, 1, Goal.keeperZ));
      await frames(tester, 200);
      expect(game.simulation.p2Kicks, isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shooting: drag back and release looses an arrow ($label)', (tester) async {
      late DuelView view;
      await pumpGame(
        tester,
        size,
        view = DuelView(
          config: const DuelConfig(mode: GameMode.vsBot, botDifficulty: BotDifficulty.easy, seed: 5),
          onComplete: (_) {},
          onQuit: () {},
        ),
      );
      final game = (tester.state(find.byWidget(view)) as dynamic).gameForTest as DuelGame;
      await frames(tester, 30);
      final start = Offset(size.width * 0.5, size.height * 0.6);
      final gesture = await tester.startGesture(start);
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(start + Offset(-10.0 * i, 8.0 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await frames(tester, 20);
      expect(game.simulation.phase, isNot(DuelPhase.aim), reason: 'no arrow was loosed');
      // Through the flight, the impact and the bot's whole turn.
      await frames(tester, 700);
      expect(game.simulation.turnsTaken, greaterThanOrEqualTo(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('fruit drop: tap-drops fill the jar and merge ($label)', (tester) async {
      late FruitDropView view;
      await pumpGame(
        tester,
        size,
        view = FruitDropView(
          config: const FruitDropConfig(jar: JarSize.standard, seed: 9),
          onComplete: (_) {},
          onQuit: () {},
        ),
      );
      final game = (tester.state(find.byWidget(view)) as dynamic).gameForTest as FruitDropGame;
      for (var i = 0; i < 24; i++) {
        final x = size.width * (0.3 + 0.4 * ((i % 3) / 2));
        final gesture = await tester.startGesture(Offset(x, size.height * 0.5));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveTo(Offset(x + 4, size.height * 0.5));
        await gesture.up();
        await frames(tester, 45);
      }
      expect(game.simulation.drops, greaterThan(15));
      expect(game.simulation.merges, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  }
}
