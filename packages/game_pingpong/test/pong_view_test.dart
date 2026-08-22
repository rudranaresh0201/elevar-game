import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:game_pingpong/game_pingpong.dart';
import 'package:pingpong_sim/pingpong_sim.dart';

/// Drives the real widget through real frames.
///
/// Unit tests prove the simulation is correct; these prove it is actually
/// wired to a screen and a thumb. Between them sits the class of bug that
/// passes every unit test and ships a black rectangle.
Future<PongOutcome?> playThrough(
  WidgetTester tester, {
  required PongConfig config,
  required int frames,
  bool drag = true,
}) async {
  PongOutcome? outcome;

  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PongView(
          config: config,
          onQuit: () {},
          onComplete: (o) => outcome = o,
        ),
      ),
    ),
  );
  await tester.pump();

  final gesture = drag
      ? await tester.startGesture(const Offset(195, 700))
      : null;

  for (var frame = 0; frame < frames; frame++) {
    if (gesture != null) {
      // Sweep a thumb across the bottom half, as a player would.
      final x = 90 + 210 * ((frame % 60) / 60);
      await gesture.moveTo(Offset(x, 700));
    }
    await tester.pump(const Duration(milliseconds: 16));
    if (outcome != null) break;
  }
  await gesture?.up();
  return outcome;
}

void main() {
  testWidgets('the game renders and the ball comes into play', (tester) async {
    const config = PongConfig(
      mode: GameMode.vsBot,
      botDifficulty: BotDifficulty.medium,
      seed: 4242,
      rules: PongRules.quick,
    );

    await playThrough(tester, config: config, frames: 90);

    // No exceptions from paint or the game loop is the first thing this proves.
    expect(tester.takeException(), isNull);
    expect(find.byType(PongView), findsOneWidget);
    // The HUD is live.
    expect(find.text('YOU'), findsOneWidget);
    expect(find.textContaining('BOT'), findsOneWidget);
  });

  testWidgets('a dragged thumb moves the paddle it started under',
      (tester) async {
    const config = PongConfig(
      mode: GameMode.local2P,
      seed: 77,
      rules: PongRules.quick,
    );

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PongView(
            config: config,
            onQuit: () {},
            onComplete: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final game = _gameOf(tester);
    final startX = game.simulation.state.p1.position.x;

    // Drag in the bottom half — P1's territory.
    final thumb = await tester.startGesture(const Offset(120, 720));
    for (var i = 0; i < 30; i++) {
      await thumb.moveTo(Offset(120 + i * 6, 720));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await thumb.up();

    expect(game.simulation.state.p1.position.x, isNot(closeTo(startX, 1)));
  });

  testWidgets('two thumbs drive two paddles independently', (tester) async {
    // The headline feature of shared-screen play, and the one that a
    // single-pointer test would never catch.
    const config = PongConfig(
      mode: GameMode.local2P,
      seed: 2468,
      rules: PongRules.quick,
    );

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
    await tester.pump(const Duration(milliseconds: 16));

    final game = _gameOf(tester);
    final startP1 = game.simulation.state.p1.position.x;
    final startP2 = game.simulation.state.p2.position.x;

    // One finger low (P1's half), one high (P2's half), moving opposite ways.
    final bottom = await tester.startGesture(const Offset(300, 720));
    final top = await tester.startGesture(const Offset(90, 160));

    for (var i = 0; i < 30; i++) {
      await bottom.moveTo(Offset(300 - i * 6, 720));
      await top.moveTo(Offset(90 + i * 6, 160));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await bottom.up();
    await top.up();

    final endP1 = game.simulation.state.p1.position.x;
    final endP2 = game.simulation.state.p2.position.x;

    expect(endP1, lessThan(startP1), reason: 'bottom thumb dragged left');
    expect(endP2, greaterThan(startP2), reason: 'top thumb dragged right');
  });

  testWidgets('a finger that starts in one half cannot steal the other paddle',
      (tester) async {
    const config = PongConfig(
      mode: GameMode.local2P,
      seed: 1357,
      rules: PongRules.quick,
    );

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
    await tester.pump(const Duration(milliseconds: 16));

    final game = _gameOf(tester);
    final startP2 = game.simulation.state.p2.position.x;

    // Start in P1's half, then drag right across the net into P2's.
    final cheat = await tester.startGesture(const Offset(300, 720));
    for (var i = 0; i < 40; i++) {
      await cheat.moveTo(Offset(300 - i * 5, 720 - i * 16));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await cheat.up();

    // P2's paddle stays where the simulation put it, untouched by that finger.
    expect(game.simulation.state.p2.position.x, closeTo(startP2, 0.01));
  });

  testWidgets('a whole match completes and hands back a replay',
      (tester) async {
    const config = PongConfig(
      mode: GameMode.vsBot,
      botDifficulty: BotDifficulty.easy,
      seed: 909,
      rules: PongRules.quick,
    );

    // 60 fps for 3 simulated minutes is plenty for a quick match against Easy.
    final outcome =
        await playThrough(tester, config: config, frames: 60 * 180);

    expect(outcome, isNotNull);
    expect(outcome!.replay, isNotEmpty);
    expect(outcome.result.gameSlug, 'ping_pong');

    // And the recording verifies — end to end, through the real widget.
    final verified = replayMatch(
      ReplayReader.parse(outcome.replay),
      mode: GameMode.vsBot,
      botDifficulty: BotDifficulty.easy,
      rules: PongRules.quick,
    );
    expect(verified.state.p1Score, outcome.result.p1Score);
    expect(verified.state.p2Score, outcome.result.p2Score);
  });
}

PingPongGame _gameOf(WidgetTester tester) {
  final state = tester.state(find.byType(PongView));
  // ignore: avoid_dynamic_calls
  return (state as dynamic).gameForTest as PingPongGame;
}
