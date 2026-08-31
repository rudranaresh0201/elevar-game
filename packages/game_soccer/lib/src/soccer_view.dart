import 'package:design_system/design_system.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:soccer_sim/soccer_sim.dart';

import 'game_config.dart';
import 'soccer_game.dart';

/// The playable widget: the rendered pitch, the touch layer, and the HUD.
class SoccerView extends StatefulWidget {
  const SoccerView({
    required this.config,
    required this.onComplete,
    required this.onQuit,
    super.key,
  });

  final SoccerConfig config;
  final void Function(SoccerOutcome outcome) onComplete;
  final VoidCallback onQuit;

  @override
  State<SoccerView> createState() => _SoccerViewState();
}

class _SoccerViewState extends State<SoccerView> {
  late final SoccerGame _game;

  /// Exposed so widget tests can assert on simulation state after driving the
  /// real touch layer, rather than re-implementing input to poke at it.
  @visibleForTesting
  SoccerGame get gameForTest => _game;

  /// The one finger that owns the current drag.
  ///
  /// A single pointer, not a map. Unlike ping pong, only one side is ever
  /// allowed to act — a second thumb on the glass during your turn is your
  /// opponent trying to spoil the shot, and it should do nothing.
  int? _activePointer;

  @override
  void initState() {
    super.initState();
    _game = SoccerGame(
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

  void _down(PointerDownEvent event) {
    if (_activePointer != null) return;
    if (!_game.acceptsTouch) return;
    _activePointer = event.pointer;
    _game.beginGesture(event.localPosition);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    _game.updateGesture(event.localPosition);
  }

  void _up(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    // Marked released rather than cleared: the simulation only samples input
    // every sixth tick, so the flick has to stay on the wire until it has been
    // consumed. `SoccerGame` retires it once that has happened.
    _game.releaseGesture(event.localPosition);
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _game.cancelGesture();
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

  final SoccerGame game;
  final VoidCallback onQuit;

  bool get _vsBot => !game.config.isTwoHuman;

  String get _opponentLabel => _vsBot
      ? 'BOT · ${game.config.botDifficulty!.name.toUpperCase()}'
      : 'BLUE';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: game.hudRevision,
      builder: (context, _, __) {
        final state = game.simulation.state;
        return SafeArea(
          child: Stack(
            children: <Widget>[
              // P2 sits at the far end of the phone, so their score is upside
              // down from the reader's point of view and the right way up from
              // theirs.
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ScorePill(
                    score: state.p2Goals,
                    color: SoccerColors.discP2,
                    upsideDown: true,
                    label: _opponentLabel,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ScorePill(
                    score: state.p1Goals,
                    color: SoccerColors.discP1,
                    label: _vsBot ? 'YOU' : 'RED',
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
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: _MatchClock(
                    turnsLeft: game.config.rules.maxTurns - state.turnsTaken,
                    target: game.config.rules.targetGoals,
                  ),
                ),
              ),
              Align(
                alignment: const Alignment(0, 0.02),
                child: _Banner(game: game, state: state),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The line across the middle of the pitch that says what is happening.
///
/// Placed on the halfway line rather than at the top, because that is where
/// the eye already is between turns, and because at the top it would collide
/// with an upside-down score on a shared screen.
class _Banner extends StatelessWidget {
  const _Banner({required this.game, required this.state});

  final SoccerGame game;
  final SoccerState state;

  @override
  Widget build(BuildContext context) {
    final vsBot = !game.config.isTwoHuman;
    final yours = state.turn == SoccerSide.p1;

    final (String text, Color colour, bool flipped) = switch (state.phase) {
      SoccerPhase.goalScored => (
          state.lastScorer == SoccerSide.p1
              ? (vsBot ? 'YOU SCORED' : 'RED SCORES')
              : (vsBot ? 'BOT SCORES' : 'BLUE SCORES'),
          state.lastScorer == SoccerSide.p1
              ? SoccerColors.discP1
              : SoccerColors.discP2,
          false,
        ),
      SoccerPhase.kickoff => ('KICK OFF', ElevarColors.ink, false),
      SoccerPhase.resolving => ('', ElevarColors.ink, false),
      SoccerPhase.complete => ('FULL TIME', ElevarColors.ink, false),
      SoccerPhase.aiming when vsBot && !yours => (
          'BOT IS THINKING',
          SoccerColors.discP2,
          false,
        ),
      SoccerPhase.aiming => (
          vsBot
              ? 'YOUR TURN · DRAG A RED COUNTER'
              : (yours ? 'RED TO PLAY' : 'BLUE TO PLAY'),
          yours ? SoccerColors.discP1 : SoccerColors.discP2,
          // The player at the far end reads the phone upside down. Their
          // prompt is rotated for them; it is the one detail that makes a
          // shared-screen game feel considered rather than tolerated.
          !vsBot && !yours,
        ),
    };

    if (text.isEmpty) return const SizedBox.shrink();

    return RotatedBox(
      quarterTurns: flipped ? 2 : 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ElevarColors.ink, width: 4),
            ),
            child: FittedBox(
              child: Text(text, style: ElevarType.display(20)),
            ),
          ),
          if (state.phase == SoccerPhase.aiming)
            _ShotClock(
              ticksLeft: state.aimTicksLeft,
              total: game.config.rules.aimTicks,
              tickHz: game.config.rules.tickHz,
            ),
        ],
      ),
    );
  }
}

/// The shot clock, as a bar that only appears once it matters.
///
/// Showing twelve seconds of countdown from the moment a turn starts trains
/// people to hurry, which is the opposite of what a thinking game wants. It
/// arrives at five seconds, which is late enough to be information rather than
/// pressure.
class _ShotClock extends StatelessWidget {
  const _ShotClock({
    required this.ticksLeft,
    required this.total,
    required this.tickHz,
  });

  final int ticksLeft;
  final int total;
  final int tickHz;

  static const int _showBelowSeconds = 5;

  @override
  Widget build(BuildContext context) {
    final seconds = ticksLeft / tickHz;
    if (seconds > _showBelowSeconds) return const SizedBox(height: 12);

    final fraction = (seconds / _showBelowSeconds).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        width: 132,
        height: 12,
        decoration: BoxDecoration(
          color: ElevarColors.ink,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fraction,
            child: Container(
              decoration: BoxDecoration(
                color: fraction < 0.35
                    ? SoccerColors.powerHigh
                    : SoccerColors.powerMid,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Turns remaining, and the target. Between them they answer the only two
/// questions a player has about how long this is going to take.
class _MatchClock extends StatelessWidget {
  const _MatchClock({required this.turnsLeft, required this.target});

  final int turnsLeft;
  final int target;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: ElevarColors.ink.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text('FIRST TO $target', style: ElevarType.label(9)),
          const SizedBox(height: 1),
          Text(
            '$turnsLeft TURNS LEFT',
            style: ElevarType.display(13, color: ElevarColors.white),
          ),
        ],
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
