import 'dart:math';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_archery/game_archery.dart';
import 'package:game_core/game_core.dart';

import 'result_screen.dart';
import 'setup_scaffold.dart';

/// Archery duel: pick the opponent.
class ShootingModeSelectScreen extends StatefulWidget {
  const ShootingModeSelectScreen({super.key});

  @override
  State<ShootingModeSelectScreen> createState() => _ShootingModeSelectScreenState();
}

class _ShootingModeSelectScreenState extends State<ShootingModeSelectScreen> {
  GameMode _mode = GameMode.vsBot;
  BotDifficulty _difficulty = BotDifficulty.medium;

  void _start() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShootingGameScreen(
          config: DuelConfig(
            mode: _mode,
            botDifficulty: _mode == GameMode.vsBot ? _difficulty : null,
            seed: Random().nextInt(0x7FFFFFFF),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      title: 'SHOOTING',
      accent: DuelColors.p2,
      startLabel: 'START DUEL',
      onStart: _start,
      howTo: const <(IconData, String)>[
        (Icons.open_with_rounded, 'Drag back anywhere to aim. Further is more force.'),
        (Icons.air_rounded, 'Check the wind. It changes every turn.'),
        (Icons.adjust_rounded, 'Headshot 55, body 34. First to drop loses.'),
      ],
      children: <Widget>[
        SetupSection(
          label: 'OPPONENT',
          caption: _mode == GameMode.vsBot
              ? 'Take turns with the bot. It finds its range as it goes.'
              : 'Pass the phone each turn.',
          child: ChunkySegmented<GameMode>(
            options: const <GameMode, String>{
              GameMode.vsBot: 'VS BOT',
              GameMode.local2P: '2 PLAYERS',
            },
            selected: _mode,
            color: DuelColors.p2,
            onChanged: (m) => setState(() => _mode = m),
          ),
        ),
        if (_mode == GameMode.vsBot)
          SetupSection(
            label: 'DIFFICULTY',
            caption: switch (_difficulty) {
              BotDifficulty.easy => 'Sprays it about. Rarely lands two in a row.',
              BotDifficulty.medium => 'Brackets you in a few shots.',
              BotDifficulty.hard => 'Two shots to find you. Then it doesn\'t miss much.',
            },
            child: ChunkySegmented<BotDifficulty>(
              options: const <BotDifficulty, String>{
                BotDifficulty.easy: 'EASY',
                BotDifficulty.medium: 'MEDIUM',
                BotDifficulty.hard: 'HARD',
              },
              selected: _difficulty,
              color: ElevarColors.p1,
              onChanged: (d) => setState(() => _difficulty = d),
            ),
          ),
      ],
    );
  }
}

class ShootingGameScreen extends StatelessWidget {
  const ShootingGameScreen({required this.config, super.key});

  final DuelConfig config;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DuelColors.sky,
      body: DuelView(
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
                headline: switch (result.outcome) {
                  MatchOutcome.p1Win => config.isTwoHuman ? 'RED WINS' : 'YOU WIN',
                  MatchOutcome.p2Win => config.isTwoHuman ? 'BLUE WINS' : 'BOT WINS',
                  MatchOutcome.draw => 'STANDOFF',
                },
                headlineColor: switch (result.outcome) {
                  MatchOutcome.p1Win => DuelColors.p1,
                  MatchOutcome.p2Win => DuelColors.p2,
                  MatchOutcome.draw => ElevarColors.muted,
                },
                accent: DuelColors.p2Deep,
                stats: <ResultStat>[
                  (label: 'HEALTH LEFT', value: '${result.p1Score} – ${result.p2Score}'),
                  (label: 'HITS · HEADSHOTS', value: '${outcome.hits} · ${outcome.headshots}'),
                  (label: 'TURNS', value: '${outcome.turns}'),
                ],
                onPlayAgain: () => navigator.pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => ShootingGameScreen(config: config.rematch(result.seed)),
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
