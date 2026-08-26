
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
      final pad = find.byType(BattingPad);
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

  testWidgets('mid-delivery, the timing ring up', (tester) async {
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
}
