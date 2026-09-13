import 'dart:math';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:game_penalty/game_penalty.dart';

import 'setup_scaffold.dart';
import 'soccer_game_screen.dart';

/// Penalty shootout: pick the opponent.
class SoccerModeSelectScreen extends StatefulWidget {
  const SoccerModeSelectScreen({super.key});

  @override
  State<SoccerModeSelectScreen> createState() => _SoccerModeSelectScreenState();
}

class _SoccerModeSelectScreenState extends State<SoccerModeSelectScreen> {
  GameMode _mode = GameMode.vsBot;
  BotDifficulty _difficulty = BotDifficulty.medium;

  void _start() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SoccerGameScreen(
          config: PenaltyConfig(
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
      title: 'PENALTY SHOOTOUT',
      accent: PenaltyColors.turf,
      startLabel: 'KICK OFF',
      onStart: _start,
      howTo: const <(IconData, String)>[
        (Icons.swipe_up_rounded, 'Swipe the ball at the goal. Curve it round the keeper.'),
        (Icons.adjust_rounded, 'Hit the bullseye target for +150. Top corners +50.'),
        (Icons.sports_handball_rounded, 'In goal, a circle shows the shot. Drag the keeper to it.'),
        (Icons.emoji_events_rounded, 'Five kicks each, then sudden death. Catches score big.'),
      ],
      children: <Widget>[
        SetupSection(
          label: 'OPPONENT',
          caption: _mode == GameMode.vsBot
              ? 'You shoot, then you save. Alternate kicks.'
              : 'Sit side by side. One swipes the ball, the other taps the goal to dive — at the same time.',
          child: ChunkySegmented<GameMode>(
            options: const <GameMode, String>{
              GameMode.vsBot: 'VS BOT',
              GameMode.local2P: '2 PLAYERS',
            },
            selected: _mode,
            color: PenaltyColors.turf,
            onChanged: (m) => setState(() => _mode = m),
          ),
        ),
        if (_mode == GameMode.vsBot)
          SetupSection(
            label: 'DIFFICULTY',
            caption: switch (_difficulty) {
              BotDifficulty.easy => 'Slow keeper, tame penalties.',
              BotDifficulty.medium => 'Reads half your shots. Aims for the corners.',
              BotDifficulty.hard => 'Quick off the line. Punishes an early dive.',
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
