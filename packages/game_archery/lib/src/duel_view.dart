import 'package:archery_sim/archery_sim.dart';
import 'package:design_system/design_system.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'duel_game.dart';
import 'duel_scene.dart';
import 'game_config.dart';

class DuelView extends StatefulWidget {
  const DuelView({
    required this.config,
    required this.onComplete,
    required this.onQuit,
    super.key,
  });

  final DuelConfig config;
  final void Function(DuelOutcome outcome) onComplete;
  final VoidCallback onQuit;

  @override
  State<DuelView> createState() => _DuelViewState();
}

class _DuelViewState extends State<DuelView> {
  late final DuelGame _game;
  int? _pointer;

  @visibleForTesting
  DuelGame get gameForTest => _game;

  @override
  void initState() {
    super.initState();
    _game = DuelGame(
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
        if (_pointer != null || !_game.simulation.acceptsAim) return;
        _pointer = e.pointer;
        _game.beginAim(e.localPosition);
      },
      onPointerMove: (e) {
        if (e.pointer == _pointer) _game.moveAim(e.localPosition);
      },
      onPointerUp: (e) {
        if (e.pointer != _pointer) return;
        _pointer = null;
        _game.endAim();
      },
      onPointerCancel: (e) {
        if (e.pointer != _pointer) return;
        _pointer = null;
        _game.cancelAim();
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

  final DuelGame game;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: game.hudRevision,
      builder: (context, _, __) {
        final sim = game.simulation;
        final vsBot = !sim.isTwoHuman;
        return SafeArea(
          child: Stack(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _HealthBar(
                            label: vsBot ? 'YOU' : 'RED',
                            hp: game.shownHp[ArcherSide.p1]!,
                            colour: DuelColors.p1,
                            active: sim.turn == ArcherSide.p1,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _HealthBar(
                            label: vsBot
                                ? 'BOT · ${sim.botDifficulty!.name.toUpperCase()}'
                                : 'BLUE',
                            hp: game.shownHp[ArcherSide.p2]!,
                            colour: DuelColors.p2,
                            active: sim.turn == ArcherSide.p2,
                            mirrored: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
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
                        const Spacer(),
                        _Wind(wind: sim.wind),
                      ],
                    ),
                  ],
                ),
              ),
              if (game.bannerAge < 1.2)
                Align(
                  alignment: const Alignment(0, -0.3),
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey<int>(game.bannerSerial),
                    tween: Tween<double>(begin: 0.3, end: 1),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.elasticOut,
                    builder: (context, s, child) => Transform.scale(scale: s, child: child),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: game.bannerColour,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: ElevarColors.ink, width: 4),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(color: ElevarColors.ink, offset: Offset(0, 5)),
                        ],
                      ),
                      child: Text(game.bannerText,
                          style: ElevarType.display(32, color: ElevarColors.ink)),
                    ),
                  ),
                ),
              if (sim.acceptsAim && sim.turnsTaken < 2)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    margin: const EdgeInsets.all(18),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: ElevarColors.ink.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Drag back anywhere to aim · pull further for more force\n'
                      'Let go to shoot · the head is worth more',
                      textAlign: TextAlign.center,
                      style: ElevarType.body(14),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HealthBar extends StatelessWidget {
  const _HealthBar({
    required this.label,
    required this.hp,
    required this.colour,
    required this.active,
    this.mirrored = false,
  });

  final String label;
  final double hp;
  final Color colour;
  final bool active;
  final bool mirrored;

  @override
  Widget build(BuildContext context) {
    final fraction = (hp / DuelSimulation.maxHp).clamp(0.0, 1.0);
    final avatar = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? const Color(0xFFFFF200) : ElevarColors.ink,
          width: active ? 4 : 3,
        ),
      ),
      child: const Icon(Icons.person_rounded, color: ElevarColors.white, size: 26),
    );
    final bar = Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: mirrored ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: <Widget>[
          FittedBox(child: Text(label, style: ElevarType.label(10, color: ElevarColors.ink))),
          const SizedBox(height: 2),
          Container(
            height: 16,
            decoration: BoxDecoration(
              color: ElevarColors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ElevarColors.ink, width: 3),
            ),
            child: Align(
              alignment: mirrored ? Alignment.centerRight : Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction,
                child: Container(
                  decoration: BoxDecoration(
                    color: colour,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Row(
      children: mirrored
          ? <Widget>[bar, const SizedBox(width: 6), avatar]
          : <Widget>[avatar, const SizedBox(width: 6), bar],
    );
  }
}

class _Wind extends StatelessWidget {
  const _Wind({required this.wind});

  final double wind;

  @override
  Widget build(BuildContext context) {
    final strength = (wind.abs() / DuelSimulation.maxWind * 10).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: ElevarColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ElevarColors.ink, width: 3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('WIND', style: ElevarType.label(10, color: ElevarColors.ink)),
          const SizedBox(width: 6),
          if (strength == 0)
            Text('CALM', style: ElevarType.display(16, color: ElevarColors.ink))
          else ...<Widget>[
            Icon(
              wind < 0 ? Icons.west_rounded : Icons.east_rounded,
              color: ElevarColors.ink,
              size: 20,
            ),
            const SizedBox(width: 2),
            Text('$strength', style: ElevarType.display(18, color: ElevarColors.ink)),
          ],
        ],
      ),
    );
  }
}
