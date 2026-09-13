import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:game_wallcricket/game_wallcricket.dart';

import 'result_screen.dart';

/// Holds the live innings and hands the result to the shared result screen.
class CricketGameScreen extends StatelessWidget {
  const CricketGameScreen({required this.config, super.key});

  final WallCricketConfig config;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ElevarColors.surface,
      body: WallCricketView(
        config: config,
        onQuit: () => Navigator.of(context).pop(),
        onComplete: (outcome) {
          final result = outcome.result;
          final won = result.outcome == MatchOutcome.p1Win;
          // Held now, while this screen is still mounted. PLAY AGAIN runs
          // after the result screen has replaced this one, and looking the
          // navigator up from this context then throws.
          final navigator = Navigator.of(context);
          navigator.pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => ResultScreen(
                result: result,
                replay: outcome.replay,
                headline: won ? 'TARGET SMASHED' : 'FELL SHORT',
                headlineColor: won ? const Color(0xFF3DFF6E) : ElevarColors.p1,
                accent: WallCricketColors.shirt,
                stats: <ResultStat>[
                  (label: 'FORMAT', value: '${config.formatName} · ${config.pace.name.toUpperCase()}'),
                  (label: 'INNINGS', value: '${outcome.runs}/${outcome.wickets} from ${outcome.balls}'),
                  (label: 'TARGET', value: '${outcome.target}'),
                  (label: 'FOURS · SIXES', value: '${outcome.fours} · ${outcome.sixes}'),
                ],
                onPlayAgain: () => navigator.pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => CricketGameScreen(config: config.rematch(result.seed)),
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
