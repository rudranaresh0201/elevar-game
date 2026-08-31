import 'dart:math';

import 'package:cricket_sim/cricket_sim.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:game_cricket/game_cricket.dart';

import 'cricket_game_screen.dart';

/// Choose the format, the opposition and how much help you want.
///
/// Only one mode is offered. Cricket is asymmetric — one player bats while the
/// other bowls — and on a single phone that means handing the device over
/// between every ball, which is a worse experience than either racing or ping
/// pong give. So this is a single-player game: you bat an innings, then you
/// bowl one to defend it.
class CricketModeSelectScreen extends StatefulWidget {
  const CricketModeSelectScreen({super.key});

  @override
  State<CricketModeSelectScreen> createState() =>
      _CricketModeSelectScreenState();
}

class _CricketModeSelectScreenState extends State<CricketModeSelectScreen> {
  BotDifficulty _difficulty = BotDifficulty.medium;
  CricketRules _rules = CricketRules.powerplay;
  FieldSetting _field = FieldSetting.standard;
  bool _battingAssist = true;

  void _start() {
    final config = CricketConfig(
      mode: GameMode.vsBot,
      botDifficulty: _difficulty,
      rules: _rules,
      fieldSetting: _field,
      battingAssist: _battingAssist,
      // Offline, the seed is drawn locally and the match submits as
      // unverified. Phase 2 replaces this with a server-issued session token
      // drawn from the pre-fetched pool.
      seed: Random().nextInt(0x7FFFFFFF),
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CricketGameScreen(config: config),
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
                      child: Text('CRICKET', style: ElevarType.display(24)),
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
                      Text('FORMAT', style: ElevarType.label(11)),
                      const SizedBox(height: 10),
                      ChunkySegmented<int>(
                        options: const <int, String>{
                          1: 'SUPER · 1',
                          2: 'POWER · 2',
                          4: 'CHASE · 4',
                        },
                        selected: _rules.overs,
                        color: CricketColors.batterShirt,
                        onChanged: (overs) => setState(() {
                          _rules = switch (overs) {
                            1 => CricketRules.superOver,
                            4 => CricketRules.chase,
                            _ => CricketRules.powerplay,
                          };
                        }),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        switch (_rules.overs) {
                          1 => 'One over each, two wickets. Under a minute a '
                              'side — the tiebreak format.',
                          4 => 'Four overs, five wickets. An actual match, and '
                              'the one where an innings has room to build.',
                          _ => 'Two overs, three wickets. You bat first, then '
                              'bowl to defend it.',
                        },
                        style: ElevarType.body(14, color: ElevarColors.muted),
                      ),
                      const SizedBox(height: 24),
                      Text('OPPOSITION', style: ElevarType.label(11)),
                      const SizedBox(height: 10),
                      ChunkySegmented<BotDifficulty>(
                        options: const <BotDifficulty, String>{
                          BotDifficulty.easy: 'EASY',
                          BotDifficulty.medium: 'MEDIUM',
                          BotDifficulty.hard: 'HARD',
                        },
                        selected: _difficulty,
                        color: CricketColors.bowlerShirt,
                        onChanged: (d) => setState(() => _difficulty = d),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        switch (_difficulty) {
                          BotDifficulty.easy =>
                            'Swings late and slogs everything. Gives you both '
                                'the wickets and the strike.',
                          BotDifficulty.medium =>
                            'Times it well enough, picks the odd wrong ball.',
                          BotDifficulty.hard =>
                            'Middles nearly everything and puts the bad ball '
                                'away. Bowl straight.',
                        },
                        style: ElevarType.body(14, color: ElevarColors.muted),
                      ),
                      const SizedBox(height: 24),
                      Text('FIELD', style: ElevarType.label(11)),
                      const SizedBox(height: 10),
                      ChunkySegmented<String>(
                        options: <String, String>{
                          for (final setting in FieldSetting.all)
                            setting.name: setting.name,
                        },
                        selected: _field.name,
                        color: ElevarColors.table,
                        onChanged: (name) => setState(() {
                          _field =
                              FieldSetting.all.firstWhere((s) => s.name == name);
                        }),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _field.name == 'SPREAD'
                            ? 'Everyone back. Boundaries are harder to find, '
                                'but nobody is waiting under a top edge.'
                            : 'Catchers in close. Loft it and someone is '
                                'usually there.',
                        style: ElevarType.body(14, color: ElevarColors.muted),
                      ),
                      const SizedBox(height: 24),
                      _TimingToggle(
                        value: _battingAssist,
                        onChanged: (v) => setState(() => _battingAssist = v),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ChunkyButton(
                label: 'START MATCH',
                color: CricketColors.batterShirt,
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

class _TimingToggle extends StatelessWidget {
  const _TimingToggle({required this.value, required this.onChanged});

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
                  Text('TIMING BAR', style: ElevarType.display(18)),
                  const SizedBox(height: 3),
                  Text(
                    'Shows whether you were early or late. Turn it off once '
                    'you can feel it.',
                    style: ElevarType.body(13, color: ElevarColors.muted),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: CricketColors.batterShirt,
            ),
          ],
        ),
      ),
    );
  }
}
