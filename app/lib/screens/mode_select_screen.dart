import 'dart:math';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:game_pingpong/game_pingpong.dart';
import 'package:pingpong_sim/pingpong_sim.dart';

import 'game_screen.dart';

/// Choose who you're playing and how long for.
class ModeSelectScreen extends StatefulWidget {
  const ModeSelectScreen({super.key});

  @override
  State<ModeSelectScreen> createState() => _ModeSelectScreenState();
}

class _ModeSelectScreenState extends State<ModeSelectScreen> {
  GameMode _mode = GameMode.vsBot;
  BotDifficulty _difficulty = BotDifficulty.medium;
  bool _quick = false;

  void _start() {
    final config = PongConfig(
      mode: _mode,
      botDifficulty: _mode == GameMode.vsBot ? _difficulty : null,
      rules: _quick ? PongRules.quick : PongRules.standard,
      // Offline, the seed is drawn locally and the match will submit as
      // unverified. Phase 2 replaces this with a server-issued session token
      // drawn from the pre-fetched pool.
      seed: Random().nextInt(0x7FFFFFFF),
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => GameScreen(config: config)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: ElevarColors.white,
                  ),
                  Text('PING PONG', style: ElevarType.display(24)),
                ],
              ),
              const SizedBox(height: 28),
              Text('OPPONENT', style: ElevarType.label(11)),
              const SizedBox(height: 10),
              ChunkySegmented<GameMode>(
                options: const {
                  GameMode.vsBot: 'VS BOT',
                  GameMode.local2P: '2 PLAYERS',
                },
                selected: _mode,
                onChanged: (m) => setState(() => _mode = m),
              ),
              const SizedBox(height: 10),
              Text(
                _mode == GameMode.vsBot
                    ? 'One phone, one thumb, one machine.'
                    : 'Two thumbs, one phone. Sit facing each other.',
                style: ElevarType.body(14, color: ElevarColors.muted),
              ),
              if (_mode == GameMode.vsBot) ...[
                const SizedBox(height: 26),
                Text('DIFFICULTY', style: ElevarType.label(11)),
                const SizedBox(height: 10),
                ChunkySegmented<BotDifficulty>(
                  options: const {
                    BotDifficulty.easy: 'EASY',
                    BotDifficulty.medium: 'MEDIUM',
                    BotDifficulty.hard: 'HARD',
                  },
                  selected: _difficulty,
                  color: ElevarColors.p1,
                  onChanged: (d) => setState(() => _difficulty = d),
                ),
                const SizedBox(height: 10),
                Text(
                  switch (_difficulty) {
                    BotDifficulty.easy => 'Slow to react. Misses often.',
                    BotDifficulty.medium => 'Reads the bounce. Beatable.',
                    BotDifficulty.hard => 'Reads everything. Rarely misses.',
                  },
                  style: ElevarType.body(14, color: ElevarColors.muted),
                ),
              ],
              const SizedBox(height: 26),
              Text('MATCH LENGTH', style: ElevarType.label(11)),
              const SizedBox(height: 10),
              ChunkySegmented<bool>(
                options: const {false: 'FIRST TO 11', true: 'QUICK · 7'},
                selected: _quick,
                color: ElevarColors.p2,
                onChanged: (q) => setState(() => _quick = q),
              ),
              const Spacer(),
              ChunkyButton(label: 'START MATCH', onPressed: _start),
            ],
          ),
        ),
      ),
    );
  }
}
