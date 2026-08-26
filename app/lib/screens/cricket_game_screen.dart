import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:game_cricket/game_cricket.dart';

import 'result_screen.dart';

/// Holds the live match.
///
/// Exactly the same shape as the racing screen: host the game's view, take the
/// outcome it hands back, and pour it into the shared [ResultScreen]. The
/// points formula, the ledger write and the payout card are untouched by
/// cricket existing — which is the property the plugin contract was for.
class CricketGameScreen extends StatelessWidget {
  const CricketGameScreen({required this.config, super.key});

  final CricketConfig config;

  String _headline(GameResult result) => switch (result.outcome) {
        MatchOutcome.p1Win => 'YOU WIN',
        MatchOutcome.p2Win => 'BOT WINS',
        MatchOutcome.draw => 'TIED',
      };

  Color _headlineColor(GameResult result) => switch (result.outcome) {
        MatchOutcome.p1Win => CricketColors.batterShirt,
        MatchOutcome.p2Win => CricketColors.bowlerShirt,
        MatchOutcome.draw => ElevarColors.muted,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ElevarColors.surface,
      body: CricketView(
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
                accent: CricketColors.batterShirt,
                stats: <ResultStat>[
                  (label: 'FORMAT', value: config.formatName),
                  (
                    label: 'YOUR INNINGS',
                    value: '${outcome.runs}-${outcome.wickets} '
                        'from ${outcome.balls}'
                  ),
                  (label: 'FOURS & SIXES', value: '${outcome.boundaries}'),
                ],
                onPlayAgain: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => CricketGameScreen(
                      config: CricketConfig(
                        mode: config.mode,
                        botDifficulty: config.botDifficulty,
                        rules: config.rules,
                        fieldSetting: config.fieldSetting,
                        assistedTiming: config.assistedTiming,
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
