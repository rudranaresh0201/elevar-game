import 'dart:math';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_wallcricket/game_wallcricket.dart';
import 'package:wallcricket_sim/wallcricket_sim.dart';

import 'cricket_game_screen.dart';
import 'setup_scaffold.dart';

/// Pick the pace of the machine and how long the innings is.
///
/// One player, no bowler to control: this is the Top Spinner shape — a bat,
/// a machine and a room full of numbers. Pace sets the target as well as the
/// speed, so "hard" is a real claim rather than just faster balls.
class CricketModeSelectScreen extends StatefulWidget {
  const CricketModeSelectScreen({super.key});

  @override
  State<CricketModeSelectScreen> createState() => _CricketModeSelectScreenState();
}

class _CricketModeSelectScreenState extends State<CricketModeSelectScreen> {
  Pace _pace = Pace.medium;
  WallCricketRules _rules = WallCricketRules.classic;

  void _start() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CricketGameScreen(
          config: WallCricketConfig(
            pace: _pace,
            rules: _rules,
            // Offline, drawn locally; Phase 2 swaps in a server-issued seed.
            seed: Random().nextInt(0x7FFFFFFF),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final target = (_rules.balls * _pace.runsPerBall).round();
    return SetupScaffold(
      title: 'CRICKET',
      accent: WallCricketColors.shirt,
      startLabel: 'START MATCH',
      onStart: _start,
      howTo: const <(IconData, String)>[
        (Icons.touch_app_rounded, 'Tap as the ball reaches the bat. Timing is everything.'),
        (Icons.swipe_rounded, 'Swipe any way to pick the shot: up to loft it, down along the ground.'),
        (Icons.grid_view_rounded, 'Hit the numbered walls for 1, 2, 4 or 6. Hot zone pays double.'),
        (Icons.sports_cricket_rounded, 'Miss one that hits the stumps and you\'re bowled.'),
      ],
      children: <Widget>[
        SetupSection(
          label: 'MACHINE PACE',
          caption: switch (_pace) {
            Pace.easy => 'Gentle. Learn the swing.',
            Pace.medium => 'Proper pace. Most balls hit the stumps if you leave them.',
            Pace.hard => 'Quick and straight. The target is steep.',
          },
          child: ChunkySegmented<Pace>(
            options: const <Pace, String>{
              Pace.easy: 'EASY',
              Pace.medium: 'MEDIUM',
              Pace.hard: 'HARD',
            },
            selected: _pace,
            color: WallCricketColors.shirt,
            onChanged: (p) => setState(() => _pace = p),
          ),
        ),
        SetupSection(
          label: 'FORMAT',
          caption: '${_rules.overs} overs, ${_rules.wickets} wickets. '
              'Score $target to win.',
          child: ChunkySegmented<WallCricketRules>(
            options: const <WallCricketRules, String>{
              WallCricketRules.quick: 'QUICK · 2',
              WallCricketRules.classic: 'CLASSIC · 3',
              WallCricketRules.long: 'LONG · 5',
            },
            selected: _rules,
            color: WallCricketColors.wall,
            onChanged: (r) => setState(() => _rules = r),
          ),
        ),
      ],
    );
  }
}
