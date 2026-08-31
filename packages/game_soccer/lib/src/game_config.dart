import 'dart:ui';

import 'package:game_core/game_core.dart';
import 'package:soccer_sim/soccer_sim.dart';

/// Everything chosen on the mode-select screen.
class SoccerConfig {
  const SoccerConfig({
    required this.mode,
    required this.seed,
    this.botDifficulty,
    this.rules = SoccerRules.standard,
    this.sessionToken,
  });

  final GameMode mode;
  final BotDifficulty? botDifficulty;
  final SoccerRules rules;

  /// The match seed. In production this comes from a server-issued session
  /// token; offline, it is drawn locally and the match is submitted
  /// unverified.
  final int seed;

  final String? sessionToken;

  bool get isTwoHuman => mode == GameMode.local2P;

  /// A fresh config for a rematch, on the next seed.
  SoccerConfig rematch(int previousSeed) => SoccerConfig(
        mode: mode,
        botDifficulty: botDifficulty,
        rules: rules,
        seed: previousSeed + 1,
      );
}

/// What the game hands back when the match ends.
class SoccerOutcome {
  const SoccerOutcome({required this.result, required this.replay});

  final GameResult result;
  final List<int> replay;
}

/// A drag in progress, as the touch layer sees it.
///
/// Screen coordinates, because that is what a `Listener` reports and what the
/// finger is actually doing. The game converts to field units and the
/// simulation decides what any of it means.
class SoccerGesture {
  const SoccerGesture({
    required this.grabScreen,
    required this.currentScreen,
    this.released = false,
  });

  /// Where the finger went down. The disc is grabbed from here, and every
  /// later position is measured against it — which is what lets the drag run
  /// off the pitch, or off the screen, without losing power.
  final Offset grabScreen;

  final Offset currentScreen;

  /// True once the finger has left the glass. The gesture is kept for a few
  /// more frames so the release survives the gap between a pointer event and
  /// the next simulation sample boundary — see `SoccerGame.feedInput`.
  final bool released;

  SoccerGesture movedTo(Offset to) => SoccerGesture(
        grabScreen: grabScreen,
        currentScreen: to,
        released: released,
      );

  SoccerGesture get lifted => SoccerGesture(
        grabScreen: grabScreen,
        currentScreen: currentScreen,
        released: true,
      );
}
