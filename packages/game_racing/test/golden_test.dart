import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:game_racing/game_racing.dart';

/// Renders real frames to PNG.
///
/// Not really an assertion suite — it is a way to *look* at the game without a
/// phone. Regenerate with `flutter test --update-goldens` and open
/// `test/goldens/*.png`. This is how the circuit's proportions and the control
/// bands were checked against the reference art.
///
/// Goldens are platform-specific: these were generated on Windows and will not
/// match on Linux. See `docs/SETUP.md`.
Future<void> renderRace(
  WidgetTester tester, {
  required RaceConfig config,
  required int frames,
  bool holdGas = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RaceView(
          config: config,
          onQuit: () {},
          onComplete: (_) {},
        ),
      ),
    ),
  );
  await tester.pump();

  TestGesture? gas;
  if (holdGas) {
    gas = await tester.startGesture(tester.getCenter(find.text('GAS')));
  }
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gas?.up();
}

void main() {
  testWidgets('the grid, mid-countdown', (tester) async {
    await renderRace(
      tester,
      config: const RaceConfig(
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.medium,
        trackName: 'DUSTBOWL',
        seed: 4242,
      ),
      frames: 60,
    );
    await expectLater(
      find.byType(RaceView),
      matchesGoldenFile('goldens/race_countdown.png'),
    );
  });

  testWidgets('mid-race, both cars running', (tester) async {
    await renderRace(
      tester,
      config: const RaceConfig(
        mode: GameMode.vsBot,
        botDifficulty: BotDifficulty.medium,
        trackName: 'DUSTBOWL',
        seed: 4242,
      ),
      frames: 460,
      holdGas: true,
    );
    await expectLater(
      find.byType(RaceView),
      matchesGoldenFile('goldens/race_running.png'),
    );
  });

  testWidgets('the two-player screen, both control bands live',
      (tester) async {
    await renderRace(
      tester,
      config: const RaceConfig(
        mode: GameMode.local2P,
        trackName: 'SUNSET LOOP',
        seed: 777,
      ),
      frames: 300,
    );
    await expectLater(
      find.byType(RaceView),
      matchesGoldenFile('goldens/race_two_player.png'),
    );
  });
}
