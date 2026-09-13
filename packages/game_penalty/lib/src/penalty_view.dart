import 'package:design_system/design_system.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:penalty_sim/penalty_sim.dart';

import 'game_config.dart';
import 'penalty_game.dart';
import 'penalty_scene.dart';

class PenaltyView extends StatefulWidget {
  const PenaltyView({
    required this.config,
    required this.onComplete,
    required this.onQuit,
    super.key,
  });

  final PenaltyConfig config;
  final void Function(PenaltyOutcome outcome) onComplete;
  final VoidCallback onQuit;

  @override
  State<PenaltyView> createState() => _PenaltyViewState();
}

class _PenaltyViewState extends State<PenaltyView> {
  late final PenaltyGame _game;

  /// Each finger keeps the role it started with.
  final Map<int, PenaltyRole> _roles = <int, PenaltyRole>{};

  @visibleForTesting
  PenaltyGame get gameForTest => _game;

  @override
  void initState() {
    super.initState();
    _game = PenaltyGame(
      config: widget.config,
      onComplete: (outcome) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onComplete(outcome);
        });
      },
    );
  }

  void _down(PointerDownEvent e) {
    final role = _game.roleFor(e.localPosition);
    if (role == null) return;
    if (role == PenaltyRole.shooter) {
      if (_roles.containsValue(PenaltyRole.shooter)) return;
      _roles[e.pointer] = role;
      _game.beginSwipe(e.localPosition);
    } else {
      _game.tapDive(e.localPosition);
    }
  }

  void _move(PointerMoveEvent e) {
    if (_roles[e.pointer] == PenaltyRole.shooter) _game.moveSwipe(e.localPosition);
  }

  void _up(PointerEvent e) {
    final role = _roles.remove(e.pointer);
    if (role == PenaltyRole.shooter) _game.endSwipe(e.localPosition);
  }

  void _cancel(PointerCancelEvent e) {
    if (_roles.remove(e.pointer) == PenaltyRole.shooter) _game.cancelSwipe();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _cancel,
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

  final PenaltyGame game;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: game.hudRevision,
      builder: (context, _, __) {
        final sim = game.simulation;
        final vsBot = !sim.isTwoHuman;
        final p1Name = vsBot ? 'YOU' : 'RED';
        final p2Name = vsBot ? 'BOT' : 'BLUE';
        return SafeArea(
          child: Stack(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    GestureDetector(
                      onTap: onQuit,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: ElevarColors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: ElevarColors.ink, width: 3),
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: ElevarColors.ink, size: 22),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                        decoration: BoxDecoration(
                          color: ElevarColors.ink.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: ElevarColors.ink, width: 3),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _ScoreRow(
                              name: p1Name,
                              colour: PenaltyColors.p1,
                              kicks: sim.p1Kicks,
                              goals: sim.p1Goals,
                              active: sim.shooter == PenaltySide.p1,
                            ),
                            const SizedBox(height: 4),
                            _ScoreRow(
                              name: p2Name,
                              colour: PenaltyColors.p2,
                              kicks: sim.p2Kicks,
                              goals: sim.p2Goals,
                              active: sim.shooter == PenaltySide.p2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (game.bannerAge < 1.4)
                Align(
                  alignment: const Alignment(0, -0.1),
                  child: _Banner(
                    text: game.bannerText,
                    colour: game.bannerColour,
                    serial: game.bannerSerial,
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _Prompt(game: game),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.name,
    required this.colour,
    required this.kicks,
    required this.goals,
    required this.active,
  });

  final String name;
  final Color colour;
  final List<KickResult> kicks;
  final int goals;
  final bool active;

  @override
  Widget build(BuildContext context) {
    // The last five, so sudden death keeps scrolling.
    final shown = kicks.length <= 5 ? kicks : kicks.sublist(kicks.length - 5);
    return Row(
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFFF200) : Colors.transparent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 46,
          child: Text(name, style: ElevarType.display(16, color: colour)),
        ),
        for (var i = 0; i < 5; i++) ...<Widget>[
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(right: 5),
            decoration: BoxDecoration(
              color: i < shown.length
                  ? (shown[i] == KickResult.goal
                      ? const Color(0xFF3DFF6E)
                      : const Color(0xFFFF2B2B))
                  : ElevarColors.surfaceRaised,
              shape: BoxShape.circle,
              border: Border.all(color: ElevarColors.ink, width: 2),
            ),
            child: i < shown.length
                ? Icon(
                    shown[i] == KickResult.goal
                        ? Icons.check_rounded
                        : Icons.close_rounded,
                    size: 13,
                    color: ElevarColors.ink,
                  )
                : null,
          ),
        ],
        const Spacer(),
        Text('$goals', style: ElevarType.display(24)),
      ],
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.game});

  final PenaltyGame game;

  @override
  Widget build(BuildContext context) {
    final sim = game.simulation;
    if (sim.phase == PenaltyPhase.complete || game.bannerAge < 1.4) {
      return const SizedBox.shrink();
    }
    final String text;
    if (game.swipeHintAge < 1.5) {
      text = 'SWIPE UP TOWARDS THE GOAL';
    } else if (sim.isTwoHuman) {
      final shooter = sim.shooter == PenaltySide.p1 ? 'RED' : 'BLUE';
      final keeper = sim.shooter == PenaltySide.p1 ? 'BLUE' : 'RED';
      text = '$shooter: SWIPE THE BALL · $keeper: TAP THE GOAL';
    } else if (sim.shooter == PenaltySide.p1) {
      text = sim.phase == PenaltyPhase.aim
          ? 'YOUR KICK · SWIPE UP · CURVE IT · FLICK HARD'
          : '';
    } else {
      text = sim.keeperCommitted
          ? 'YOU\'RE DIVING!'
          : 'YOU\'RE IN GOAL · TAP WHERE TO DIVE';
    }
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: ElevarColors.ink.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
      ),
      child: FittedBox(
        child: Text(text, style: ElevarType.display(16)),
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
      tween: Tween<double>(begin: 0.3, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.elasticOut,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ElevarColors.ink, width: 4),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: ElevarColors.ink, offset: Offset(0, 6)),
          ],
        ),
        child: Text(text, style: ElevarType.display(44, color: ElevarColors.ink)),
      ),
    );
  }
}
