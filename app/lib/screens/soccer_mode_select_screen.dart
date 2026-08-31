import 'dart:math';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:game_soccer/game_soccer.dart';
import 'package:soccer_sim/soccer_sim.dart';

import 'soccer_game_screen.dart';

/// Choose who you're playing and how many goals it takes.
class SoccerModeSelectScreen extends StatefulWidget {
  const SoccerModeSelectScreen({super.key});

  @override
  State<SoccerModeSelectScreen> createState() => _SoccerModeSelectScreenState();
}

class _SoccerModeSelectScreenState extends State<SoccerModeSelectScreen> {
  GameMode _mode = GameMode.vsBot;
  BotDifficulty _difficulty = BotDifficulty.medium;
  SoccerRules _rules = SoccerRules.standard;

  void _start() {
    final config = SoccerConfig(
      mode: _mode,
      botDifficulty: _mode == GameMode.vsBot ? _difficulty : null,
      rules: _rules,
      // Offline, the seed is drawn locally and the match will submit as
      // unverified. Phase 2 replaces this with a server-issued session token
      // drawn from the pre-fetched pool.
      seed: Random().nextInt(0x7FFFFFFF),
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SoccerGameScreen(config: config),
      ),
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
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: ElevarColors.white,
                  ),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('SOCCER', style: ElevarType.display(24)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const _HowToPlay(),
                      const SizedBox(height: 24),
                      Text('OPPONENT', style: ElevarType.label(11)),
                      const SizedBox(height: 10),
                      ChunkySegmented<GameMode>(
                        options: const <GameMode, String>{
                          GameMode.vsBot: 'VS BOT',
                          GameMode.local2P: '2 PLAYERS',
                        },
                        selected: _mode,
                        color: SoccerColors.turf,
                        onChanged: (m) => setState(() => _mode = m),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _mode == GameMode.vsBot
                            ? 'You are red, at the bottom. Attack the blue goal.'
                            : 'Pass the phone each turn. Sit facing each other.',
                        style: ElevarType.body(14, color: ElevarColors.muted),
                      ),
                      if (_mode == GameMode.vsBot) ...<Widget>[
                        const SizedBox(height: 24),
                        Text('DIFFICULTY', style: ElevarType.label(11)),
                        const SizedBox(height: 10),
                        ChunkySegmented<BotDifficulty>(
                          options: const <BotDifficulty, String>{
                            BotDifficulty.easy: 'EASY',
                            BotDifficulty.medium: 'MEDIUM',
                            BotDifficulty.hard: 'HARD',
                          },
                          selected: _difficulty,
                          color: SoccerColors.discP1,
                          onChanged: (d) => setState(() => _difficulty = d),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          switch (_difficulty) {
                            BotDifficulty.easy =>
                              'Pokes at the nearest counter. Misses a lot.',
                            BotDifficulty.medium =>
                              'Lines up a real shot. Defends its keeper.',
                            BotDifficulty.hard =>
                              'Reads rebounds off your own defenders.',
                          },
                          style: ElevarType.body(14, color: ElevarColors.muted),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text('MATCH LENGTH', style: ElevarType.label(11)),
                      const SizedBox(height: 10),
                      ChunkySegmented<SoccerRules>(
                        options: const <SoccerRules, String>{
                          SoccerRules.quick: 'QUICK · 2',
                          SoccerRules.standard: 'FIRST TO 3',
                          SoccerRules.cup: 'CUP · 5',
                        },
                        selected: _rules,
                        color: SoccerColors.discP2,
                        onChanged: (r) => setState(() => _rules = r),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        switch (_rules.targetGoals) {
                          2 => 'About a minute and a half.',
                          3 => 'About three minutes.',
                          _ => 'The long one. Five or six minutes.',
                        },
                        style: ElevarType.body(14, color: ElevarColors.muted),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ChunkyButton(
                label: 'KICK OFF',
                color: SoccerColors.turf,
                onPressed: _start,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three lines and a picture of the gesture.
///
/// Worth the space: a slingshot is not a gesture people arrive knowing, and
/// the alternative to explaining it here is a first turn spent tapping the
/// screen and watching nothing happen.
class _HowToPlay extends StatelessWidget {
  const _HowToPlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ElevarColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ElevarColors.ink, width: 3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('HOW IT WORKS', style: ElevarType.label(10)),
          const SizedBox(height: 10),
          const _Step(
            icon: Icons.touch_app_rounded,
            text: 'Hold one of your counters.',
          ),
          const _Step(
            icon: Icons.south_east_rounded,
            text: 'Drag back. Further is harder.',
          ),
          const _Step(
            icon: Icons.sports_soccer_rounded,
            text: 'Let go. Then it is their turn.',
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Icon(icon, color: SoccerColors.turf, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: ElevarType.body(14, color: ElevarColors.white),
            ),
          ),
        ],
      ),
    );
  }
}
