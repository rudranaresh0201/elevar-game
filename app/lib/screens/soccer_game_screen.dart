import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:game_soccer/game_soccer.dart';

import 'result_screen.dart';

/// Holds the live soccer match.
class SoccerGameScreen extends StatelessWidget {
  const SoccerGameScreen({required this.config, super.key});

  final SoccerConfig config;

  String _headline(GameResult result) => switch (result.outcome) {
        MatchOutcome.p1Win => config.isTwoHuman ? 'RED WINS' : 'YOU WIN',
        MatchOutcome.p2Win => config.isTwoHuman ? 'BLUE WINS' : 'BOT WINS',
        MatchOutcome.draw => 'DRAW',
      };

  Color _headlineColor(GameResult result) => switch (result.outcome) {
        MatchOutcome.p1Win => SoccerColors.discP1,
        MatchOutcome.p2Win => SoccerColors.discP2,
        MatchOutcome.draw => ElevarColors.muted,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SoccerView(
        config: config,
        onQuit: () => Navigator.of(context).pop(),
        onComplete: (outcome) {
          final result = outcome.result;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => ResultScreen(
                result: result,
                replay: outcome.replay,
                headline: _headline(result),
                headlineColor: _headlineColor(result),
                accent: SoccerColors.turf,
                stats: <ResultStat>[
                  (
                    label: 'MATCH',
                    value: 'FIRST TO ${config.rules.targetGoals}'
                  ),
                  (
                    label: 'FINAL SCORE',
                    value: '${result.p1Score} – ${result.p2Score}'
                  ),
                ],
                onPlayAgain: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => SoccerGameScreen(
                      config: config.rematch(result.seed),
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
