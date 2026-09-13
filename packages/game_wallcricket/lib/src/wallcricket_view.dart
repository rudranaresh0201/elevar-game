import 'package:design_system/design_system.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:wallcricket_sim/wallcricket_sim.dart';

import 'game_config.dart';
import 'wallcricket_game.dart';

/// The playable widget: the room, the finger, and the scoreboard.
class WallCricketView extends StatefulWidget {
  const WallCricketView({
    required this.config,
    required this.onComplete,
    required this.onQuit,
    super.key,
  });

  final WallCricketConfig config;
  final void Function(WallCricketOutcome outcome) onComplete;
  final VoidCallback onQuit;

  @override
  State<WallCricketView> createState() => _WallCricketViewState();
}

class _WallCricketViewState extends State<WallCricketView> {
  late final WallCricketGame _game;
  int? _pointer;

  @visibleForTesting
  WallCricketGame get gameForTest => _game;

  @override
  void initState() {
    super.initState();
    _game = WallCricketGame(
      config: widget.config,
      onComplete: (outcome) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onComplete(outcome);
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (_pointer != null) return;
        _pointer = e.pointer;
        _game.beginSwing(e.localPosition);
      },
      onPointerMove: (e) {
        if (e.pointer == _pointer) _game.moveSwing(e.localPosition);
      },
      onPointerUp: (e) {
        if (e.pointer != _pointer) return;
        _pointer = null;
        _game.endSwing();
      },
      onPointerCancel: (e) {
        if (e.pointer != _pointer) return;
        _pointer = null;
        _game.endSwing();
      },
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          GameWidget(game: _game),
          _Hud(game: _game, onQuit: widget.onQuit),
        ],
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.game, required this.onQuit});

  final WallCricketGame game;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: game.hudRevision,
      builder: (context, _, __) {
        final sim = game.simulation;
        final needed = sim.target - sim.runs;
        return SafeArea(
          child: Stack(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _IconChip(icon: Icons.close_rounded, onTap: onQuit),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                        decoration: BoxDecoration(
                          color: ElevarColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: ElevarColors.ink, width: 3),
                        ),
                        child: Row(
                          children: <Widget>[
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text('RUNS', style: ElevarType.label(9)),
                                FittedBox(
                                  child: Text(
                                    '${sim.runs}/${sim.wickets}',
                                    style: ElevarType.display(34),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: <Widget>[
                                  FittedBox(
                                    child: Text(
                                      needed > 0
                                          ? 'NEED $needed · ${sim.ballsLeft} BALLS'
                                          : 'TARGET SMASHED',
                                      style: ElevarType.display(
                                        15,
                                        color: needed > 0
                                            ? ElevarColors.white
                                            : const Color(0xFF3DFF6E),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: _OverDots(outcomes: game.thisOver),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (game.bannerAge < 1.3)
                Align(
                  alignment: const Alignment(0, -0.35),
                  child: _Banner(
                    text: game.bannerText,
                    colour: game.bannerColour,
                    serial: game.bannerSerial,
                  ),
                ),
              if (sim.ballsBowled == 0 && sim.phase != WallCricketPhase.live)
                const Align(
                  alignment: Alignment(0, -0.05),
                  child: _Tip(),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _OverDots extends StatelessWidget {
  const _OverDots({required this.outcomes});

  final List<BallOutcome> outcomes;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        for (var i = 0; i < 6; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 4),
          _dot(i < outcomes.length ? outcomes[i] : null),
        ],
      ],
    );
  }

  Widget _dot(BallOutcome? outcome) {
    final (String text, Color colour) = switch (outcome?.kind) {
      null => ('', ElevarColors.surface),
      BallOutcomeKind.dot => ('•', ElevarColors.muted),
      BallOutcomeKind.out => ('W', ElevarColors.p1),
      BallOutcomeKind.runs => ('${outcome!.runs}', switch (outcome.runs) {
          >= 6 => const Color(0xFFFF3DA6),
          >= 4 => const Color(0xFF29C7F0),
          _ => const Color(0xFF27D6A2),
        }),
    };
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colour,
        shape: BoxShape.circle,
        border: Border.all(color: ElevarColors.ink, width: 2),
      ),
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Text(text, style: ElevarType.display(13, color: ElevarColors.ink)),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.colour, required this.serial});

  final String text;
  final Color colour;
  final int serial;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(serial),
      tween: Tween<double>(begin: 0.4, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.elasticOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ElevarColors.ink, width: 4),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: ElevarColors.ink, offset: Offset(0, 5)),
          ],
        ),
        child: Text(text, style: ElevarType.display(30, color: ElevarColors.ink)),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 30),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ElevarColors.ink.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        'Swipe anywhere to swing the bat.\n'
        'Time it as the ball arrives: early or late and you edge it.',
        textAlign: TextAlign.center,
        style: ElevarType.body(14),
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: ElevarColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ElevarColors.ink, width: 3),
        ),
        child: Icon(icon, color: ElevarColors.ink, size: 22),
      ),
    );
  }
}
