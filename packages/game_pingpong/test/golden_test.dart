import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:game_pingpong/game_pingpong.dart';
import 'package:pingpong_sim/pingpong_sim.dart';

/// Loads the bundled fonts into the test binding.
///
/// Without this, `flutter test` substitutes a placeholder face and every string
/// renders as boxes — which makes a golden useless for judging a design whose
/// whole character is heavy display type.
Future<void> loadElevarFonts() async {
  const fonts = <String, String>{
    'packages/design_system/Baloo2':
        '../design_system/assets/fonts/Baloo2-ExtraBold.ttf',
    'packages/design_system/Fredoka':
        '../design_system/assets/fonts/Fredoka-SemiBold.ttf',
  };
  for (final entry in fonts.entries) {
    final bytes = File(entry.value).readAsBytesSync();
    await (FontLoader(entry.key)
          ..addFont(Future.value(bytes.buffer.asByteData())))
        .load();
  }
}

Future<void> pumpMatch(
  WidgetTester tester, {
  required PongConfig config,
  required int frames,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PongView(config: config, onQuit: () {}, onComplete: (_) {}),
      ),
    ),
  );
  await tester.pump();

  if (frames == 0) return;
  final thumb = await tester.startGesture(const Offset(195, 700));
  for (var frame = 0; frame < frames; frame++) {
    await thumb.moveTo(Offset(120 + 150 * ((frame % 50) / 50), 700));
    await tester.pump(const Duration(milliseconds: 16));
  }
  addTearDown(() async => thumb.up());
}

void main() {
  setUpAll(loadElevarFonts);

  const config = PongConfig(
    mode: GameMode.vsBot,
    botDifficulty: BotDifficulty.medium,
    seed: 31415,
    rules: PongRules.standard,
  );

  testWidgets('the serve, with the banner up', (tester) async {
    await pumpMatch(tester, config: config, frames: 12);
    await expectLater(
      find.byType(PongView),
      matchesGoldenFile('goldens/pong_serve.png'),
    );
  });

  testWidgets('mid-rally, with the banner gone', (tester) async {
    await pumpMatch(tester, config: config, frames: 150);
    await expectLater(
      find.byType(PongView),
      matchesGoldenFile('goldens/pong_rally.png'),
    );
  });
}
