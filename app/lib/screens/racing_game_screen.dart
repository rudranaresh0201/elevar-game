import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:game_racing/game_racing.dart';

import 'result_screen.dart';

/// Holds the live race.
class RacingGameScreen extends StatelessWidget {
  const RacingGameScreen({required this.config, super.key});

  final RaceConfig config;

  String _headline(GameResult result) => switch (result.outcome) {
        MatchOutcome.p1Win => config.isTwoHuman ? 'RED WINS' : 'YOU WIN',
        MatchOutcome.p2Win => config.isTwoHuman ? 'BLUE WINS' : 'BOT WINS',
        MatchOutcome.draw => 'DEAD HEAT',
      };

  Color _headlineColor(GameResult result) => switch (result.outcome) {
        MatchOutcome.p1Win => RacingColors.carP1,
        MatchOutcome.p2Win => RacingColors.carP2,
        MatchOutcome.draw => ElevarColors.muted,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ElevarColors.surface,
      body: RaceView(
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
                accent: RacingColors.carP1,
                stats: <ResultStat>[
                  (label: 'CIRCUIT', value: config.trackName),
                  (
                    label: 'BEST LAP',
                    value: outcome.bestLapMs == null
                        ? '—'
                        : '${(outcome.bestLapMs! / 1000).toStringAsFixed(2)}s'
                  ),
                  (
                    label: 'CLEAN DRIVING',
                    value: '${(outcome.cleanliness * 100).round()}%'
                  ),
                ],
                onPlayAgain: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => RacingGameScreen(
                      config: RaceConfig(
                        mode: config.mode,
                        botDifficulty: config.botDifficulty,
                        trackName: config.trackName,
                        rules: config.rules,
                        autoGas: config.autoGas,
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
