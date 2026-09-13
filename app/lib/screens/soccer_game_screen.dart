import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:game_penalty/game_penalty.dart';

import 'result_screen.dart';

/// Holds the live shootout.
class SoccerGameScreen extends StatelessWidget {
  const SoccerGameScreen({required this.config, super.key});

  final PenaltyConfig config;

  String _headline(GameResult result) => switch (result.outcome) {
        MatchOutcome.p1Win => config.isTwoHuman ? 'RED WINS' : 'YOU WIN',
        MatchOutcome.p2Win => config.isTwoHuman ? 'BLUE WINS' : 'BOT WINS',
        MatchOutcome.draw => 'ALL SQUARE',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PenaltyColors.sky,
      body: PenaltyView(
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
                headlineColor: switch (result.outcome) {
                  MatchOutcome.p1Win => PenaltyColors.p1,
                  MatchOutcome.p2Win => PenaltyColors.p2,
                  MatchOutcome.draw => ElevarColors.muted,
                },
                accent: PenaltyColors.turf,
                stats: <ResultStat>[
                  (label: 'SCORE', value: '${result.p1Score} – ${result.p2Score}'),
                  (label: 'KICKS EACH', value: '${outcome.kicksEach}'),
                  if (!config.isTwoHuman) (label: 'YOUR SAVES', value: '${outcome.saves}'),
                ],
                onPlayAgain: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => SoccerGameScreen(config: config.rematch(result.seed)),
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
