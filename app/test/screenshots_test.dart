@Tags(<String>['screenshots'])
library;

import 'dart:io';

import 'package:archery_sim/archery_sim.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruitdrop_sim/fruitdrop_sim.dart';
import 'package:game_archery/game_archery.dart';
import 'package:game_core/game_core.dart';
import 'package:game_fruitdrop/game_fruitdrop.dart';
import 'package:game_penalty/game_penalty.dart';
import 'package:game_pingpong/game_pingpong.dart';
import 'package:game_racing/game_racing.dart';
import 'package:game_wallcricket/game_wallcricket.dart';
import 'package:penalty_sim/penalty_sim.dart';
import 'package:pingpong_sim/pingpong_sim.dart' show PongRules;
import 'package:wallcricket_sim/wallcricket_sim.dart';

/// Renders frames of each game to PNG for a human to look at. Not a golden
/// test — nothing is compared. Run with `--tags screenshots` and set
/// `ELEVAR_SHOTS` to a directory.
final String? outDir = Platform.environment['ELEVAR_SHOTS'];

Future<void> loadFonts() async {
  for (final (family, file) in <(String, String)>[
    ('packages/design_system/Baloo2', 'Baloo2-ExtraBold.ttf'),
    ('packages/design_system/Fredoka', 'Fredoka-SemiBold.ttf'),
  ]) {
    final bytes = File('../packages/design_system/assets/fonts/$file').readAsBytesSync();
    final loader = FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
  // Without this every Icon renders as an empty box — fine for checking a
  // layout, not for the frames that end up on the landing page.
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  if (flutterRoot != null && icons.existsSync()) {
    final bytes = icons.readAsBytesSync();
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
  }
}

Future<void> shoot(WidgetTester tester, String name) async {
  if (outDir == null) return;
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile(Uri.file('$outDir/$name.png')),
  );
}

Future<dynamic> start(WidgetTester tester, Widget view) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, home: Scaffold(body: view)));
  await tester.pump();
  return (tester.state(find.byWidget(view)) as dynamic).gameForTest;
}

Future<void> frames(WidgetTester tester, int n, [int ms = 16]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(Duration(milliseconds: ms));
  }
}

void main() {
  setUpAll(loadFonts);

  testWidgets('cricket', (tester) async {

    final game = await start(tester, WallCricketView(
      config: const WallCricketConfig(pace: Pace.easy, seed: 7),
      onComplete: (_) {},
      onQuit: () {},
    )) as WallCricketGame;
    await frames(tester, 70);
    await shoot(tester, 'cricket_1_ready');
    var shotTaken = false;
    for (var f = 0; f < 600 && !shotTaken; f++) {
      final sim = game.simulation;
      if (sim.phase == WallCricketPhase.live && sim.ballVelocity.x < 0) {
        final away = (sim.ballPosition.x - WallCricketSimulation.hitX) / -sim.ballVelocity.x;
        if (away <= WallCricketSimulation.contactDelayTicks / WallCricketRules.tickHz) {
          final g = await tester.startGesture(const Offset(200, 500));
          await g.moveTo(const Offset(220, 440));
          await g.up();
          await frames(tester, 12, 8);
          await shoot(tester, 'cricket_2_contact');
          await frames(tester, 14, 16);
          await shoot(tester, 'cricket_3_flight');
          shotTaken = true;
        }
      }
      await tester.pump(const Duration(milliseconds: 8));
    }
    await frames(tester, 30);
    await shoot(tester, 'cricket_4_result');
  });

  testWidgets('penalty', (tester) async {

    final game = await start(tester, PenaltyView(
      config: const PenaltyConfig(mode: GameMode.vsBot, botDifficulty: BotDifficulty.medium, seed: 12),
      onComplete: (_) {},
      onQuit: () {},
    )) as PenaltyGame;
    await frames(tester, 20);
    await shoot(tester, 'penalty_1_aim');
    final ball = game.ballScreen;
    final gesture = await tester.startGesture(ball);
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(ball + Offset(12.0 * i + (i < 5 ? 10.0 * i : 40), -46.0 * i));
      await tester.pump(const Duration(milliseconds: 10));
    }
    await shoot(tester, 'penalty_2_swipe');
    await gesture.up();
    await frames(tester, 18);
    await shoot(tester, 'penalty_3_flight');
    await frames(tester, 30);
    await shoot(tester, 'penalty_4_outcome');
    // Wait for the bot's run-up, then dive during it.
    for (var i = 0; i < 400 && game.simulation.phase != PenaltyPhase.runUp; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await frames(tester, 40);
    await shoot(tester, 'penalty_5_keeper');
    await tester.tapAt(game.camera3d.at(2.6, 1.2, Goal.keeperZ));
    await frames(tester, 25);
    await shoot(tester, 'penalty_6_dive');
  });

  for (final seed in <int>[3, 4, 5]) {
    testWidgets('shooting $seed', (tester) async {
      final game = await start(tester, DuelView(
        config: DuelConfig(mode: GameMode.vsBot, botDifficulty: BotDifficulty.medium, seed: seed),
        onComplete: (_) {},
        onQuit: () {},
      )) as DuelGame;
      final name = game.theme.name.toLowerCase();
      await frames(tester, 90);
      final shot = solveShot(game.simulation, from: ArcherSide.p1, at: ArcherSide.p2);
      const origin = Offset(200, 500);
      final pull = Offset(-shot.direction.x, shot.direction.y) * (shot.power * 390 * 0.42);
      final gesture = await tester.startGesture(origin);
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(origin + pull * (i / 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await shoot(tester, 'shooting_${name}_1_aim');
      await gesture.up();
      await frames(tester, 40);
      await shoot(tester, 'shooting_${name}_2_flight');
      await frames(tester, 150);
      await shoot(tester, 'shooting_${name}_3_impact');
    });
  }

  testWidgets('fruit drop', (tester) async {

    final game = await start(tester, FruitDropView(
      config: const FruitDropConfig(jar: JarSize.standard, seed: 9),
      onComplete: (_) {},
      onQuit: () {},
    )) as FruitDropGame;
    await frames(tester, 10);
    await shoot(tester, 'fruit_1_empty');
    final dropper = ProxyDropper(skill: 0.8, seed: 3);
    for (var i = 0; i < 40; i++) {
      double? aim;
      for (var w = 0; w < 80 && aim == null; w++) {
        aim = dropper.dropFor(game.simulation);
        if (aim == null) await tester.pump(const Duration(milliseconds: 16));
      }
      if (aim == null) break;
      final x = game.jarOrigin.dx + aim * game.simulation.width * game.jarScale;
      final gesture = await tester.startGesture(Offset(x, 400));
      await tester.pump(const Duration(milliseconds: 16));
      if (i == 39) await shoot(tester, 'fruit_2_aiming');
      await gesture.up();
      await frames(tester, 4);
    }
    await frames(tester, 60);
    await shoot(tester, 'fruit_3_pile');
  });

  testWidgets('racing', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: RaceView(
        config: const RaceConfig(
          mode: GameMode.vsBot,
          botDifficulty: BotDifficulty.medium,
          trackName: 'DUSTBOWL',
          seed: 4242,
        ),
        onQuit: () {},
        onComplete: (_) {},
      )),
    ));
    await tester.pump();
    final gas = await tester.startGesture(tester.getCenter(find.text('GAS')));
    await frames(tester, 460);
    await shoot(tester, 'racing_1_running');
    await gas.up();
  });

  testWidgets('ping pong', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: PongView(
        config: const PongConfig(
          mode: GameMode.vsBot,
          botDifficulty: BotDifficulty.medium,
          seed: 31415,
          rules: PongRules.standard,
        ),
        onQuit: () {},
        onComplete: (_) {},
      )),
    ));
    await tester.pump();
    final thumb = await tester.startGesture(const Offset(195, 700));
    for (var frame = 0; frame < 150; frame++) {
      await thumb.moveTo(Offset(120 + 150 * ((frame % 50) / 50), 700));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await shoot(tester, 'pingpong_1_rally');
    await thumb.up();
  });
}
