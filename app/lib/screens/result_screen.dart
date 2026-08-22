import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:game_pingpong/game_pingpong.dart';

import '../scoring/points_estimate.dart';
import '../state/session.dart';
import 'game_screen.dart';

/// What the match was worth.
class ResultScreen extends StatefulWidget {
  const ResultScreen({required this.outcome, required this.config, super.key});

  final PongOutcome outcome;
  final PongConfig config;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late final PointsEstimate _estimate;

  GameResult get _result => widget.outcome.result;

  @override
  void initState() {
    super.initState();
    _estimate = estimatePoints(
      _result,
      matchesAlreadyToday: sessionPoints.matchesToday,
      pointsAlreadyToday: sessionPoints.pending,
    );
    sessionPoints.record(_estimate.awarded);
  }

  String get _headline => switch (_result.outcome) {
        MatchOutcome.p1Win => widget.config.isTwoHuman ? 'RED WINS' : 'YOU WIN',
        MatchOutcome.p2Win =>
          widget.config.isTwoHuman ? 'BLUE WINS' : 'BOT WINS',
        MatchOutcome.draw => 'DRAW',
      };

  Color get _headlineColor => switch (_result.outcome) {
        MatchOutcome.p1Win => ElevarColors.p1,
        MatchOutcome.p2Win => ElevarColors.p2,
        MatchOutcome.draw => ElevarColors.muted,
      };

  @override
  Widget build(BuildContext context) {
    final replayKb = (widget.outcome.replay.length / 1024).toStringAsFixed(1);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Text(_headline,
                  style: ElevarType.display(44, color: _headlineColor)),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScorePill(score: _result.p1Score, color: ElevarColors.p1),
                  const SizedBox(width: 14),
                  ScorePill(score: _result.p2Score, color: ElevarColors.p2),
                ],
              ),
              const SizedBox(height: 26),
              _StatRow(
                label: 'DURATION',
                value: '${(_result.durationMs / 1000).round()}s',
              ),
              _StatRow(
                label: 'SKILL',
                value: '${(_result.normalizedSkill * 100).round()}%',
              ),
              _StatRow(label: 'REPLAY', value: '$replayKb KB recorded'),
              const SizedBox(height: 22),
              _PointsCard(estimate: _estimate),
              const Spacer(),
              ChunkyButton(
                label: 'PLAY AGAIN',
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => GameScreen(
                      config: PongConfig(
                        mode: widget.config.mode,
                        botDifficulty: widget.config.botDifficulty,
                        rules: widget.config.rules,
                        seed: _result.seed + 1,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ChunkyButton(
                label: 'HOME',
                color: ElevarColors.surfaceRaised,
                textColor: ElevarColors.white,
                fontSize: 20,
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: ElevarType.label(11)),
          Text(value, style: ElevarType.body(15)),
        ],
      ),
    );
  }
}

class _PointsCard extends StatelessWidget {
  const _PointsCard({required this.estimate});

  final PointsEstimate estimate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ElevarColors.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ElevarColors.ink, width: 3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('POINTS EARNED', style: ElevarType.label(11)),
              const Spacer(),
              Text('+${estimate.awarded}',
                  style: ElevarType.display(30, color: ElevarColors.ball)),
              const SizedBox(width: 5),
              Text('EP', style: ElevarType.label(11)),
            ],
          ),
          const SizedBox(height: 12),
          _Line('Completed a match', '+${estimate.completion}'),
          _Line('Result', '+${estimate.outcome}'),
          _Line('Performance', '+${estimate.performance}'),
          if (estimate.streakMultiplier > 1)
            _Line('Streak', '×${estimate.streakMultiplier}'),
          if (estimate.diminishing < 1)
            _Line('Repeat play today', '×${estimate.diminishing}'),
          if (estimate.cappedByDailyLimit)
            _Line('Daily cap reached', 'capped'),
          const SizedBox(height: 12),
          Text(
            'Estimated on device. The server confirms the final amount when '
            'this match syncs.',
            style: ElevarType.body(12, color: ElevarColors.muted),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: ElevarType.body(13, color: ElevarColors.muted)),
          Text(value, style: ElevarType.body(13)),
        ],
      ),
    );
  }
}
