import 'package:design_system/design_system.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:racing_sim/racing_sim.dart';

import 'controls.dart';
import 'game_config.dart';
import 'racing_game.dart';

/// The playable widget: the rendered circuit, both control bands, and the HUD.
class RaceView extends StatefulWidget {
  const RaceView({
    required this.config,
    required this.onComplete,
    required this.onQuit,
    super.key,
  });

  final RaceConfig config;
  final void Function(RaceOutcome outcome) onComplete;
  final VoidCallback onQuit;

  @override
  State<RaceView> createState() => _RaceViewState();
}

class _RaceViewState extends State<RaceView> {
  late final RacingGame _game;

  /// Exposed so widget tests can assert on simulation state after driving the
  /// real controls, rather than re-implementing input to poke at it.
  @visibleForTesting
  RacingGame get gameForTest => _game;

  @override
  void initState() {
    super.initState();
    _game = RacingGame(
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
        _Bands(game: _game, config: widget.config),
        _Hud(game: _game, onQuit: widget.onQuit),
      ],
    );
  }
}

/// The two control bands, pinned to the top and bottom of the screen.
///
/// Their height comes from the game rather than being chosen here, so the
/// circuit's letterbox and the space the thumbs get can never disagree.
class _Bands extends StatelessWidget {
  const _Bands({required this.game, required this.config});

  final RacingGame game;
  final RaceConfig config;

  @override
  Widget build(BuildContext context) {
    final height = game.bandHeight;

    return Column(
      children: <Widget>[
        SizedBox(
          height: height,
          child: config.isTwoHuman
              ? DriverControls(
                  color: RacingColors.carP2,
                  upsideDown: true,
                  autoGas: config.autoGas,
                  onInput: (input) => game.setInput(RacerSide.p2, input),
                )
              : _BotBand(config: config),
        ),
        const Spacer(),
        SizedBox(
          height: height,
          child: DriverControls(
            color: RacingColors.carP1,
            autoGas: config.autoGas,
            onInput: (input) => game.setInput(RacerSide.p1, input),
          ),
        ),
      ],
    );
  }
}

/// What sits in P2's band when P2 is the computer.
class _BotBand extends StatelessWidget {
  const _BotBand({required this.config});

  final RaceConfig config;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: RotatedBox(
        quarterTurns: 2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: ElevarColors.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ElevarColors.ink, width: 3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: RacingColors.carP2,
                  shape: BoxShape.circle,
                  border: Border.all(color: ElevarColors.ink, width: 2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'BOT · ${config.botDifficulty!.name.toUpperCase()}',
                style: ElevarType.display(18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.game, required this.onQuit});

  final RacingGame game;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: game.hudRevision,
      builder: (context, _, __) {
        final state = game.simulation.state;
        final laps = game.config.rules.laps;
        final band = game.bandHeight;

        return IgnorePointer(
          // The HUD must never swallow a thumb meant for a control.
          ignoring: false,
          child: Stack(
            children: <Widget>[
              // P2's lap counter, rotated to read the right way up from the
              // far end of the phone.
              Positioned(
                top: band + 10,
                left: 12,
                child: _LapPill(
                  lap: state.p2.lap,
                  laps: laps,
                  position: state.positionOf(RacerSide.p2),
                  color: RacingColors.carP2,
                  upsideDown: true,
                ),
              ),
              Positioned(
                bottom: band + 10,
                right: 12,
                child: _LapPill(
                  lap: state.p1.lap,
                  laps: laps,
                  position: state.positionOf(RacerSide.p1),
                  color: RacingColors.carP1,
                ),
              ),
              Positioned(
                top: band + 10,
                right: 12,
                child: GestureDetector(
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
              ),
              if (state.phase == RacePhase.countdown)
                Center(child: _Countdown(seconds: game.countdownSeconds)),

              // Tells a first-time player what to do, at the one moment they
              // need telling. Without it the race simply starts and nothing
              // moves, which reads as the game being broken rather than as the
              // game waiting for a thumb — that is exactly the report this
              // came from.
              if (game.showStartHint)
                Align(
                  alignment: Alignment(game.config.autoGas ? 0 : 0.55, 0.52),
                  child: _Banner(
                    game.config.autoGas ? 'STEER WITH ◀ ▶' : 'HOLD GAS',
                    ElevarColors.ball,
                  ),
                ),

              // Off in the scenery and slowing down. Said *before* the pickup
              // happens, so being lifted back onto the circuit reads as help
              // arriving rather than as the screen glitching.
              if (state.p1.awaitingRescue && !state.p1.finished)
                Align(
                  alignment: const Alignment(0, 0.30),
                  child: _Banner(
                    'RECOVERING IN ${_seconds(state.p1.ticksToRescue, game)}',
                    RacingColors.rim,
                  ),
                ),
              if (state.p1.rescueFlashTicks > 0)
                const Align(
                  alignment: Alignment(0, 0.30),
                  child: _Banner('BACK ON TRACK', RacingColors.foliage),
                ),

              if (state.phase == RacePhase.racing && state.winner != null)
                const Align(
                  alignment: Alignment(0, -0.15),
                  child: _Banner('FINAL LAP RUN-IN', ElevarColors.ball),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Whole seconds, rounded up, so a countdown never shows "0" while still
/// counting.
int _seconds(int ticks, RacingGame game) =>
    (ticks + game.config.rules.tickHz - 1) ~/ game.config.rules.tickHz;

class _LapPill extends StatelessWidget {
  const _LapPill({
    required this.lap,
    required this.laps,
    required this.position,
    required this.color,
    this.upsideDown = false,
  });

  final int lap;
  final int laps;
  final int position;
  final Color color;
  final bool upsideDown;

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: upsideDown ? 2 : 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ElevarColors.ink, width: 3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              position == 1 ? '1st' : '2nd',
              style: ElevarType.display(16, color: ElevarColors.white),
            ),
            const SizedBox(width: 10),
            Text(
              // Lap 0 is still lap one as far as a driver is concerned.
              '${lap >= laps ? laps : lap + 1}/$laps',
              style: ElevarType.display(22, color: ElevarColors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final text = seconds <= 0 ? 'GO!' : '$seconds';
    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        color: seconds <= 0 ? RacingColors.foliage : ElevarColors.ink,
        shape: BoxShape.circle,
        border: Border.all(color: ElevarColors.white, width: 6),
      ),
      alignment: Alignment.center,
      child: Text(text, style: ElevarType.display(seconds <= 0 ? 44 : 66)),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ElevarColors.ink, width: 3),
      ),
      child: Text(text, style: ElevarType.display(18, color: ElevarColors.ink)),
    );
  }
}
