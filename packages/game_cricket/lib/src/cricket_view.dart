import 'package:cricket_sim/cricket_sim.dart';
import 'package:design_system/design_system.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'controls.dart';
import 'cricket_game.dart';
import 'cricket_scene.dart';
import 'game_config.dart';

/// The playable widget: the ground, the control band and the scoreboard.
class CricketView extends StatefulWidget {
  const CricketView({
    required this.config,
    required this.onComplete,
    required this.onQuit,
    super.key,
  });

  final CricketConfig config;
  final void Function(CricketOutcome outcome) onComplete;
  final VoidCallback onQuit;

  @override
  State<CricketView> createState() => _CricketViewState();
}

class _CricketViewState extends State<CricketView> {
  late final CricketGame _game;

  /// Exposed so widget tests can assert on simulation state after driving the
  /// real controls, rather than re-implementing input to poke at it.
  @visibleForTesting
  CricketGame get gameForTest => _game;

  @override
  void initState() {
    super.initState();
    _game = CricketGame(
      config: widget.config,
      onComplete: (outcome) {
        // The callback fires mid-update; let the frame finish before the
        // navigator tears this widget down underneath it.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onComplete(outcome);
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        GameWidget(game: _game),
        _Band(game: _game),
        _Hud(game: _game, onQuit: widget.onQuit),
      ],
    );
  }
}

/// The control band, pinned to the bottom.
///
/// Which pad it holds follows the innings: you bat, then you bowl. Its height
/// comes from the game rather than being chosen here, so the ground's letterbox
/// and the space the thumb gets can never disagree.
class _Band extends StatelessWidget {
  const _Band({required this.game});

  final CricketGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: game.hudRevision,
      builder: (context, _, __) {
        final state = game.simulation.state;
        final batting = game.role == Role.batting;

        // Only live while the ball is actually on its way. Swinging between
        // deliveries would otherwise spend the next ball's shot before the
        // bowler had run in.
        final armed = batting
            ? state.phase == CricketPhase.delivery
            : state.phase == CricketPhase.runUp;

        return Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: game.bandHeight,
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ElevarColors.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: ElevarColors.ink, width: 3),
              ),
              child: batting
                  ? BatPad(
                      enabled: armed,
                      onMove: game.setBattingInput,
                      ballLine: game.config.battingAssist
                          ? game.ballLineAcrossCrease
                          : null,
                    )
                  : BowlingPad(
                      enabled: armed,
                      onBowl: game.setBowlingInput,
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.game, required this.onQuit});

  final CricketGame game;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: game.hudRevision,
      builder: (context, _, __) {
        final state = game.simulation.state;
        final innings = state.current;
        final rules = game.config.rules;

        return SafeArea(
          child: Stack(
            children: <Widget>[
              Positioned(
                top: 8,
                left: 12,
                right: 12,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: _Scoreboard(
                        innings: innings,
                        rules: rules,
                        role: game.role,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onQuit,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: ElevarColors.white,
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: ElevarColors.ink, width: 3),
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: ElevarColors.ink, size: 22),
                      ),
                    ),
                  ],
                ),
              ),

              // The over so far, ball by ball. The clearest possible way to
              // show a twelve-ball innings, and it is what everybody already
              // reads on a broadcast.
              Positioned(
                top: 82,
                left: 12,
                right: 12,
                child: _Timeline(timeline: innings.timeline, rules: rules),
              ),

              if (game.bannerText != null)
                Align(
                  alignment: const Alignment(0, -0.12),
                  child: _Banner(game.bannerText!),
                ),

              if (state.phase == CricketPhase.inningsBreak)
                const Align(
                  alignment: Alignment(0, 0.05),
                  child: _Banner('YOUR TURN TO BOWL'),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({
    required this.innings,
    required this.rules,
    required this.role,
  });

  final InningsState innings;
  final CricketRules rules;
  final Role role;

  @override
  Widget build(BuildContext context) {
    final needed = innings.chasing ? innings.target - innings.runs : 0;
    final ballsLeft = rules.ballsPerInnings - innings.balls;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: ElevarColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ElevarColors.ink, width: 3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${innings.runs}-${innings.wickets}',
                    style: ElevarType.display(30),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '(${innings.overs(rules)})',
                style: ElevarType.body(14, color: ElevarColors.muted),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: role == Role.batting
                      ? CricketColors.batterShirt
                      : CricketColors.bowlerShirt,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: ElevarColors.ink, width: 2),
                ),
                child: Text(
                  role == Role.batting ? 'BATTING' : 'BOWLING',
                  style: ElevarType.label(10, color: ElevarColors.white),
                ),
              ),
            ],
          ),
          if (innings.chasing) ...<Widget>[
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                needed <= 0
                    ? 'TARGET PASSED'
                    : 'NEED $needed FROM $ballsLeft',
                style: ElevarType.label(11, color: ElevarColors.ball),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One dot per ball bowled, coloured by what happened.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.timeline, required this.rules});

  final List<int> timeline;
  final CricketRules rules;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = rules.ballsPerInnings;
        // Sized from the width available rather than fixed, so a twelve-ball
        // strip and a twenty-four-ball one both fit a 320pt phone.
        final size =
            ((constraints.maxWidth - (count - 1) * 4) / count).clamp(9.0, 26.0);

        return Row(
          children: <Widget>[
            for (var i = 0; i < count; i++)
              Padding(
                padding: EdgeInsets.only(right: i == count - 1 ? 0 : 4),
                child: _Pip(
                  size: size,
                  value: i < timeline.length ? timeline[i] : null,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Pip extends StatelessWidget {
  const _Pip({required this.size, required this.value});

  final double size;
  final int? value;

  @override
  Widget build(BuildContext context) {
    final (Color fill, String label) = switch (value) {
      null => (ElevarColors.surfaceRaised, ''),
      -1 => (CricketColors.ball, 'W'),
      0 => (ElevarColors.surfaceRaised, '·'),
      6 => (ElevarColors.p1, '6'),
      4 => (ElevarColors.table, '4'),
      final int runs => (CricketColors.bowlerShirt, '$runs'),
    };

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(size / 3),
        border: Border.all(color: ElevarColors.ink, width: 2),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: ElevarType.display(size * 0.6, color: ElevarColors.white),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final big = text == 'SIX!' || text == 'FOUR';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: big ? 28 : 20, vertical: 10),
      decoration: BoxDecoration(
        color: big ? ElevarColors.ball : ElevarColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ElevarColors.ink, width: 4),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          style: ElevarType.display(big ? 34 : 20, color: ElevarColors.ink),
        ),
      ),
    );
  }
}
