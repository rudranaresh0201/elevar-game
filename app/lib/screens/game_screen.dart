import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:game_pingpong/game_pingpong.dart';

import 'result_screen.dart';

/// Holds the live ping pong match.
class GameScreen extends StatelessWidget {
  const GameScreen({required this.config, super.key});

  final PongConfig config;

  String _headline(GameResult result) => switch (result.outcome) {
        MatchOutcome.p1Win => config.isTwoHuman ? 'RED WINS' : 'YOU WIN',
        MatchOutcome.p2Win => config.isTwoHuman ? 'BLUE WINS' : 'BOT WINS',
        MatchOutcome.draw => 'DRAW',
      };

  Color _headlineColor(GameResult result) => switch (result.outcome) {
        MatchOutcome.p1Win => ElevarColors.p1,
        MatchOutcome.p2Win => ElevarColors.p2,
        MatchOutcome.draw => ElevarColors.muted,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PongView(
        config: config,
        onQuit: () => Navigator.of(context).pop(),
        onComplete: (outcome) {
          final result = outcome.result;
          // Held now, while this screen is still mounted. PLAY AGAIN runs
          // after the result screen has replaced this one, and looking the
          // navigator up from this context then throws.
          final navigator = Navigator.of(context);
          navigator.pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => ResultScreen(
                result: result,
                replay: outcome.replay,
                headline: _headline(result),
                headlineColor: _headlineColor(result),
                accent: ElevarColors.table,
                stats: <ResultStat>[
                  (
                    label: 'MATCH',
                    value: 'FIRST TO ${config.rules.targetScore}'
                  ),
                ],
                onPlayAgain: () => navigator.pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => GameScreen(
                      config: PongConfig(
                        mode: config.mode,
                        botDifficulty: config.botDifficulty,
                        rules: config.rules,
                        seed: result.seed + 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
