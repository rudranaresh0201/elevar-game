import 'package:elevar_play/data/points_repository.dart';
import 'package:elevar_play/data/profile_repository.dart';
import 'package:elevar_play/screens/cricket_game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_wallcricket/game_wallcricket.dart';
import 'package:wallcricket_sim/wallcricket_sim.dart';

import 'support/fake_points_repository.dart';
import 'support/fake_profile_repository.dart';

/// PLAY AGAIN on the result screen must start a new match.
///
/// It did nothing on a real phone. Every game screen built the button's
/// callback from its own `BuildContext` — and by the time the button could be
/// pressed, that screen had been replaced by the result screen, so the
/// context was dead and the navigation never happened.
void main() {
  setUp(() {
    pointsRepository = FakePointsRepository(balanceValue: 0, pending: 0);
    profileRepository = FakeProfileRepository();
  });

  testWidgets('play again starts a fresh match', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CricketGameScreen(
                      config: WallCricketConfig(
                        pace: Pace.hard,
                        rules: WallCricketRules.quick,
                        seed: 11,
                      ),
                    ),
                  ),
                ),
                child: const Text('GO'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();

    // Nobody bats: two wickets fall inside a few seconds of match time.
    for (var i = 0; i < 2000 && find.text('PLAY AGAIN').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('PLAY AGAIN'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('PLAY AGAIN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.byType(WallCricketView), findsOneWidget,
        reason: 'PLAY AGAIN should open a new innings');
    expect(find.text('PLAY AGAIN'), findsNothing);
  });
}
