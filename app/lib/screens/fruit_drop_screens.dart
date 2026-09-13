import 'dart:math';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:fruitdrop_sim/fruitdrop_sim.dart';
import 'package:game_core/game_core.dart';
import 'package:game_fruitdrop/game_fruitdrop.dart';

import 'result_screen.dart';
import 'setup_scaffold.dart';

/// Fruit Drop: pick the jar.
class FruitDropModeSelectScreen extends StatefulWidget {
  const FruitDropModeSelectScreen({super.key});

  @override
  State<FruitDropModeSelectScreen> createState() => _FruitDropModeSelectScreenState();
}

class _FruitDropModeSelectScreenState extends State<FruitDropModeSelectScreen> {
  JarSize _jar = JarSize.standard;

  void _start() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FruitDropGameScreen(
          config: FruitDropConfig(jar: _jar, seed: Random().nextInt(0x7FFFFFFF)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      title: 'FRUIT DROP',
      accent: FruitDropColors.accent,
      startLabel: 'START',
      onStart: _start,
      howTo: const <(IconData, String)>[
        (Icons.swap_horiz_rounded, 'Slide to aim. Let go to drop the fruit.'),
        (Icons.merge_rounded, 'Two of the same merge into the next fruit up.'),
        (Icons.warning_amber_rounded, 'Cross the dashed line for two seconds and it\'s over.'),
        (Icons.local_florist_rounded, 'Two watermelons? They pop. Huge points.'),
      ],
      children: <Widget>[
        SetupSection(
          label: 'JAR',
          caption: 'Target ${_jar.target} points. '
              '${switch (_jar) {
                JarSize.wide => 'Lots of room to learn in.',
                JarSize.standard => 'The classic size.',
                JarSize.narrow => 'Tight. Every drop counts.',
              }}',
          child: ChunkySegmented<JarSize>(
            options: const <JarSize, String>{
              JarSize.wide: 'EASY',
              JarSize.standard: 'MEDIUM',
              JarSize.narrow: 'HARD',
            },
            selected: _jar,
            color: FruitDropColors.accent,
            onChanged: (j) => setState(() => _jar = j),
          ),
        ),
      ],
    );
  }
}

class FruitDropGameScreen extends StatelessWidget {
  const FruitDropGameScreen({required this.config, super.key});

  final FruitDropConfig config;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FruitDropColors.background,
      body: FruitDropView(
        config: config,
        onQuit: () => Navigator.of(context).pop(),
        onComplete: (outcome) {
          final result = outcome.result;
          final won = result.outcome == MatchOutcome.p1Win;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => ResultScreen(
                result: result,
                replay: outcome.replay,
                headline: won ? 'SWEET!' : 'JAR FULL',
                headlineColor: won ? const Color(0xFF3DFF6E) : FruitDropColors.accent,
                accent: FruitDropColors.accent,
                stats: <ResultStat>[
                  (label: 'SCORE', value: '${outcome.score}'),
                  (label: 'TARGET', value: '${config.jar.target}'),
                  (label: 'BIGGEST FRUIT', value: FruitArt.palette[outcome.biggestTier].name.toUpperCase()),
                  (label: 'MERGES · DROPS', value: '${outcome.merges} · ${outcome.drops}'),
                ],
                onPlayAgain: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => FruitDropGameScreen(config: config.rematch(result.seed)),
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
