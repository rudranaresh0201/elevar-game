import 'dart:math';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:game_racing/game_racing.dart';
import 'package:racing_sim/racing_sim.dart';

import 'racing_game_screen.dart';

/// Choose who you're racing, where, and for how long.
class RacingModeSelectScreen extends StatefulWidget {
  const RacingModeSelectScreen({super.key});

  @override
  State<RacingModeSelectScreen> createState() => _RacingModeSelectScreenState();
}

class _RacingModeSelectScreenState extends State<RacingModeSelectScreen> {
  GameMode _mode = GameMode.vsBot;
  BotDifficulty _difficulty = BotDifficulty.medium;
  String _track = Tracks.names.first;
  RaceRules _rules = RaceRules.standard;
  bool _autoGas = true;

  void _start() {
    final config = RaceConfig(
      mode: _mode,
      botDifficulty: _mode == GameMode.vsBot ? _difficulty : null,
      trackName: _track,
      rules: _rules,
      autoGas: _autoGas,
      // Offline, the seed is drawn locally and the race will submit as
      // unverified. Phase 2 replaces this with a server-issued session token
      // drawn from the pre-fetched pool.
      seed: Random().nextInt(0x7FFFFFFF),
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RacingGameScreen(config: config)),
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
                      child: Text('CAR RACING', style: ElevarType.display(24)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text('OPPONENT', style: ElevarType.label(11)),
                      const SizedBox(height: 10),
                      ChunkySegmented<GameMode>(
                        options: const <GameMode, String>{
                          GameMode.vsBot: 'VS BOT',
                          GameMode.local2P: '2 PLAYERS',
                        },
                        selected: _mode,
                        color: RacingColors.carP1,
                        onChanged: (m) => setState(() => _mode = m),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _mode == GameMode.vsBot
                            ? 'One phone, one driver, one machine.'
                            : 'Two drivers, one phone. Sit facing each other — '
                                'your controls are the pair nearest you.',
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
                          color: RacingColors.carP2,
                          onChanged: (d) => setState(() => _difficulty = d),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          switch (_difficulty) {
                            BotDifficulty.easy =>
                              'Lifts far too early and runs wide. Beatable by '
                                  'anyone.',
                            BotDifficulty.medium =>
                              'Tidy, quick, and fluffs the odd corner.',
                            BotDifficulty.hard =>
                              'Carries speed to the limit. Wins about two '
                                  'races in three.',
                          },
                          style: ElevarType.body(14, color: ElevarColors.muted),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text('CIRCUIT', style: ElevarType.label(11)),
                      const SizedBox(height: 10),
                      ChunkySegmented<String>(
                        options: <String, String>{
                          for (final name in Tracks.names) name: name,
                        },
                        selected: _track,
                        color: RacingColors.rim,
                        onChanged: (t) => setState(() => _track = t),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _track == 'DUSTBOWL'
                            ? 'Pinched in the middle, with a tyre wall between '
                                'the straights. Hard on the brakes.'
                            : 'Wider and faster, with an S through the middle. '
                                'The one to learn on.',
                        style: ElevarType.body(14, color: ElevarColors.muted),
                      ),
                      const SizedBox(height: 24),
                      Text('DISTANCE', style: ElevarType.label(11)),
                      const SizedBox(height: 10),
                      ChunkySegmented<int>(
                        options: const <int, String>{
                          2: 'QUICK · 2',
                          3: '3 LAPS',
                          5: '5 LAPS',
                        },
                        selected: _rules.laps,
                        color: ElevarColors.table,
                        onChanged: (laps) => setState(() {
                          _rules = switch (laps) {
                            2 => RaceRules.quick,
                            5 => RaceRules.endurance,
                            _ => RaceRules.standard,
                          };
                        }),
                      ),
                      const SizedBox(height: 24),
                      _AutoGasToggle(
                        value: _autoGas,
                        onChanged: (v) => setState(() => _autoGas = v),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ChunkyButton(
                label: 'START RACE',
                color: RacingColors.carP1,
                textColor: ElevarColors.white,
                onPressed: _start,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutoGasToggle extends StatelessWidget {
  const _AutoGasToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ElevarColors.surfaceRaised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ElevarColors.ink, width: 3),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('AUTO GAS', style: ElevarType.display(18)),
                  const SizedBox(height: 3),
                  Text(
                    'Holds the throttle for you. Steer and brake only.',
                    style: ElevarType.body(13, color: ElevarColors.muted),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: RacingColors.carP1,
            ),
          ],
        ),
      ),
    );
  }
}
