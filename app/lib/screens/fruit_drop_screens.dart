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
          caption: 'Score ${_jar.target} in ${_jar.drops} drops for ★. '
              '${(_jar.target * 1.25).round()} for ★★, ${(_jar.target * 1.5).round()} for ★★★. '
              '${switch (_jar) {
                JarSize.wide => 'A wide jar to learn in.',
                JarSize.standard => 'The classic jar.',
                JarSize.narrow => 'A narrow jar. Every drop counts.',
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
          // Held now, while this screen is still mounted. PLAY AGAIN runs
          // after the result screen has replaced this one, and looking the
          // navigator up from this context then throws.
          final navigator = Navigator.of(context);
          navigator.pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => ResultScreen(
                result: result,
                replay: outcome.replay,
                headline: switch (outcome.stars) {
                  3 => '★★★ PERFECT!',
                  2 => '★★☆ SWEET!',
                  1 => '★☆☆ CLEARED',
                  _ => outcome.endReason == RoundEnd.jarFull ? 'JAR FULL' : 'SO CLOSE',
                },
                headlineColor: won ? const Color(0xFF3DFF6E) : FruitDropColors.accent,
                accent: FruitDropColors.accent,
                stats: <ResultStat>[
                  (label: 'SCORE', value: '${outcome.score}'),
                  (label: 'TARGET', value: '${config.jar.target} in ${config.jar.drops} drops'),
                  (label: 'STARS', value: '${outcome.stars} / 3'),
                  (label: 'BIGGEST FRUIT', value: FruitArt.palette[outcome.biggestTier].name.toUpperCase()),
                  (label: 'MERGES · DROPS', value: '${outcome.merges} · ${outcome.drops}'),
                ],
                onPlayAgain: () => navigator.pushReplacement(
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
