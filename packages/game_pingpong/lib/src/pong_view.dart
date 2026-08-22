import 'package:design_system/design_system.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'package:pingpong_sim/pingpong_sim.dart';

import 'game_config.dart';
import 'pingpong_game.dart';

/// The playable widget: the rendered game, the touch layer, and the HUD.
class PongView extends StatefulWidget {
  const PongView({
    required this.config,
    required this.onComplete,
    required this.onQuit,
    super.key,
  });

  final PongConfig config;
  final void Function(PongOutcome outcome) onComplete;
  final VoidCallback onQuit;

  @override
  State<PongView> createState() => _PongViewState();
}

class _PongViewState extends State<PongView> {
  late final PingPongGame _game;

  /// Exposed so widget tests can assert on simulation state after driving the
  /// real touch layer, rather than re-implementing input to poke at it.
  @visibleForTesting
  PingPongGame get gameForTest => _game;

  /// Which player each active finger belongs to.
  ///
  /// Ownership is decided by which half the finger *started* in and then held
  /// for the life of that touch. Deciding per-frame instead would let a player
  /// steal the other's paddle by dragging across the net — which is exactly
  /// what happens in a real game of two people elbowing each other over one
  /// phone.
  final Map<int, PongSide> _pointerOwners = <int, PongSide>{};

  @override
  void initState() {
    super.initState();
    _game = PingPongGame(
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

  void _claim(PointerDownEvent event) {
    final normalised = _game.screenToNormalised(event.localPosition);
    final side = _game.sideForTouch(normalised);
    // Against the bot, the top half is not yours to touch.
    if (!widget.config.isTwoHuman && side == PongSide.p2) return;
    _pointerOwners[event.pointer] = side;
    _game.setTarget(side, normalised);
  }

  void _drag(PointerMoveEvent event) {
    final side = _pointerOwners[event.pointer];
    if (side == null) return;
    _game.setTarget(side, _game.screenToNormalised(event.localPosition));
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _claim,
      onPointerMove: _drag,
      onPointerUp: (e) => _pointerOwners.remove(e.pointer),
      onPointerCancel: (e) => _pointerOwners.remove(e.pointer),
      child: Stack(
        fit: StackFit.expand,
        children: [
          GameWidget(game: _game),
          _Hud(game: _game, onQuit: widget.onQuit),
        ],
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.game, required this.onQuit});

  final PingPongGame game;
  final VoidCallback onQuit;

  String get _opponentLabel => game.config.isTwoHuman
      ? 'PLAYER 2'
      : 'BOT · ${game.config.botDifficulty!.name.toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: game.hudRevision,
      builder: (context, _, __) {
        final state = game.simulation.state;
        return SafeArea(
          child: Stack(
            children: [
              // P2 sits at the far end of the phone, so their score is upside
              // down from the reader's point of view and right way up from
              // theirs.
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ScorePill(
                    score: state.p2Score,
                    color: ElevarColors.p2,
                    upsideDown: true,
                    label: _opponentLabel,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ScorePill(
                    score: state.p1Score,
                    color: ElevarColors.p1,
                    label: 'YOU',
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: _IconChip(icon: Icons.close_rounded, onTap: onQuit),
                ),
              ),
              if (state.phase == PongPhase.serving)
                const Align(
                  alignment: Alignment(0, -0.22),
                  child: _ServeBanner(),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ServeBanner extends StatelessWidget {
  const _ServeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      decoration: BoxDecoration(
        color: ElevarColors.ink,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text('GET READY', style: ElevarType.display(22)),
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
