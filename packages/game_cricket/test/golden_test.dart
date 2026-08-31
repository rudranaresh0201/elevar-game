
import 'package:cricket_sim/cricket_sim.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:game_cricket/game_cricket.dart';

/// Renders real frames to PNG.
///
/// Not really an assertion suite — it is a way to *look* at the game without a
/// phone, and in this repo that has repeatedly found things no assertion did:
/// racing's start line turned out to be drawn diagonally across the track and
/// nothing but the picture showed it. Regenerate with
/// `flutter test --update-goldens` and open `test/goldens/*.png`.
///
/// Goldens are platform-specific: these were generated on Windows and will not
/// match on Linux. See `docs/SETUP.md`.
Future<void> renderMatch(
  WidgetTester tester, {
  required CricketConfig config,
  required int frames,
  bool swing = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CricketView(
          config: config,
          onQuit: () {},
          onComplete: (_) {},
        ),
      ),
    ),
  );
  await tester.pump();

  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (swing) {
      final pad = find.byType(BatPad);
      if (pad.evaluate().isNotEmpty) {
        await tester.tap(pad);
        swing = false;
      }
    }
  }
}

void main() {
  const config = CricketConfig(
    mode: GameMode.vsBot,
    botDifficulty: BotDifficulty.medium,
    seed: 4242,
  );

  testWidgets('the field set, bowler running in', (tester) async {
    await renderMatch(tester, config: config, frames: 30);
    await expectLater(
      find.byType(CricketView),
      matchesGoldenFile('goldens/cricket_runup.png'),
    );
  });

  testWidgets('mid-delivery, the blade on the crease', (tester) async {
    await renderMatch(tester, config: config, frames: 130);
    await expectLater(
      find.byType(CricketView),
      matchesGoldenFile('goldens/cricket_delivery.png'),
    );
  });

  testWidgets('a shot played, ball in the outfield', (tester) async {
    await renderMatch(tester, config: config, frames: 200, swing: true);
    await expectLater(
      find.byType(CricketView),
      matchesGoldenFile('goldens/cricket_shot.png'),
    );
  });

  testWidgets('the bowling innings, seen from the other end', (tester) async {
    // Half the match is played from this camera and until this existed nothing
    // had ever drawn it. A view that is only wrong in the second innings is a
    // view nobody finds until a player does.
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
            config: const CricketConfig(
              mode: GameMode.vsBot,
              botDifficulty: BotDifficulty.easy,
              rules: CricketRules.superOver,
              seed: 31415,
            ),
            onQuit: () {},
            onComplete: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    // Bat out the first innings by swinging at whatever arrives, then stop as
    // soon as the ends swap.
    // ignore: avoid_dynamic_calls
    final game = (key.currentState! as dynamic).gameForTest as CricketGame;

    for (var frame = 0; frame < 6000; frame++) {
      if (game.pitchCamera.facing == 1) break;
      await tester.pump(const Duration(milliseconds: 16));
      final pad = find.byType(BatPad);
      if (pad.evaluate().isNotEmpty &&
          game.simulation.state.phase == CricketPhase.delivery &&
          !game.simulation.state.ball.swung) {
        await tester.tap(pad);
      }
    }
    expect(game.pitchCamera.facing, 1,
        reason: 'never reached the bowling innings');

    // Far enough into the over that somebody is running in.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    await expectLater(
      find.byType(CricketView),
      matchesGoldenFile('goldens/cricket_bowling.png'),
    );
  });
}
