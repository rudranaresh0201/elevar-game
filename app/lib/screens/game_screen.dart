import 'package:flutter/material.dart';
import 'package:game_pingpong/game_pingpong.dart';

import 'result_screen.dart';

/// Holds the live match.
class GameScreen extends StatelessWidget {
  const GameScreen({required this.config, super.key});

  final PongConfig config;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PongView(
        config: config,
        onQuit: () => Navigator.of(context).pop(),
        onComplete: (outcome) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => ResultScreen(outcome: outcome, config: config),
            ),
          );
        },
      ),
    );
  }
}
