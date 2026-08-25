import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';

import '../data/points_repository.dart';
import '../scoring/points_estimate.dart';

/// One line of game-specific detail on the result screen.
typedef ResultStat = ({String label, String value});

/// What a finished match was worth.
///
/// Deliberately knows nothing about ping pong or racing. It is handed a
/// [GameResult] — the one shape every game in the hub reduces to — plus a
/// headline and whatever stat lines the game chose to show. That is the whole
/// point of the plugin contract: the payout, the ledger write and this screen
/// are written once and never grow a branch per game.
class ResultScreen extends StatefulWidget {
  const ResultScreen({
    required this.result,
    required this.replay,
    required this.headline,
    required this.headlineColor,
    required this.accent,
    required this.onPlayAgain,
    this.stats = const <ResultStat>[],
    super.key,
  });

  final GameResult result;
  final List<int> replay;
  final String headline;
  final Color headlineColor;
  final Color accent;
  final VoidCallback onPlayAgain;
  final List<ResultStat> stats;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  PointsEstimate? _estimate;
  int _balance = 0;
  bool _recorded = false;

  @override
  void initState() {
    super.initState();
    _record();
  }

  Future<void> _record() async {
    // The ledger is the authority on how many matches have been played today
    // and what they paid, because both feed the diminishing-returns curve and
    // the daily cap. Asking it rather than an in-memory counter is what makes
    // those limits survive the app being closed and reopened — which is the
    // first thing anyone farming points would try.
    final today = await pointsRepository.todaySoFar();
    final estimate = estimatePoints(
      widget.result,
      matchesAlreadyToday: today.matches,
      pointsAlreadyToday: today.points,
      streakDays: today.streakDays,
    );

    final balance = await pointsRepository.recordMatch(
      result: widget.result,
      estimate: estimate,
      replay: widget.replay,
    );

    if (!mounted) return;
    setState(() {
      _estimate = estimate;
      _balance = balance;
      _recorded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final replayKb = (widget.replay.length / 1024).toStringAsFixed(1);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 10),
              Text(
                widget.headline,
                style: ElevarType.display(44, color: widget.headlineColor),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  ScorePill(score: result.p1Score, color: ElevarColors.p1),
                  const SizedBox(width: 14),
                  ScorePill(score: result.p2Score, color: ElevarColors.p2),
                ],
              ),
              const SizedBox(height: 22),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final stat in widget.stats)
                        _StatRow(label: stat.label, value: stat.value),
                      _StatRow(
                        label: 'DURATION',
                        value: '${(result.durationMs / 1000).round()}s',
                      ),
                      _StatRow(
                        label: 'SKILL',
                        value: '${(result.normalizedSkill * 100).round()}%',
                      ),
                      _StatRow(label: 'REPLAY', value: '$replayKb KB recorded'),
                      const SizedBox(height: 20),
                      if (_estimate != null)
                        _PointsCard(estimate: _estimate!, balance: _balance)
                      else
                        const _PointsPlaceholder(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ChunkyButton(
                label: 'PLAY AGAIN',
                color: widget.accent,
                textColor: ElevarColors.white,
                onPressed: _recorded ? widget.onPlayAgain : null,
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
        children: <Widget>[
          Text(label, style: ElevarType.label(11)),
          Text(value, style: ElevarType.body(15)),
        ],
      ),
    );
  }
}

class _PointsPlaceholder extends StatelessWidget {
  const _PointsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ElevarColors.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ElevarColors.ink, width: 3),
      ),
      child: Text('BANKING POINTS…', style: ElevarType.label(11)),
    );
  }
}

class _PointsCard extends StatelessWidget {
  const _PointsCard({required this.estimate, required this.balance});

  final PointsEstimate estimate;
  final int balance;

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
        children: <Widget>[
          Row(
            children: <Widget>[
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
          if (estimate.cappedByDailyLimit) _Line('Daily cap reached', 'capped'),
          const Divider(color: ElevarColors.muted, height: 22),
          Row(
            children: <Widget>[
              Text('BALANCE', style: ElevarType.label(11)),
              const Spacer(),
              Text('$balance',
                  style: ElevarType.display(22, color: ElevarColors.white)),
              const SizedBox(width: 4),
              Text('EP', style: ElevarType.label(10)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Banked on this device and queued to sync. The server confirms the '
            'final amount when it lands.',
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
        children: <Widget>[
          Text(label, style: ElevarType.body(13, color: ElevarColors.muted)),
          Text(value, style: ElevarType.body(13)),
        ],
      ),
    );
  }
}
