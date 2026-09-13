import 'package:design_system/design_system.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:fruitdrop_sim/fruitdrop_sim.dart';

import 'fruit_art.dart';
import 'fruitdrop_game.dart';
import 'fruitdrop_scene.dart';
import 'game_config.dart';

class FruitDropView extends StatefulWidget {
  const FruitDropView({
    required this.config,
    required this.onComplete,
    required this.onQuit,
    super.key,
  });

  final FruitDropConfig config;
  final void Function(FruitDropOutcome outcome) onComplete;
  final VoidCallback onQuit;

  @override
  State<FruitDropView> createState() => _FruitDropViewState();
}

class _FruitDropViewState extends State<FruitDropView> {
  late final FruitDropGame _game;
  int? _pointer;

  @visibleForTesting
  FruitDropGame get gameForTest => _game;

  @override
  void initState() {
    super.initState();
    _game = FruitDropGame(
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
        // The HUD row is buttons, not the jar.
        if (_pointer != null || e.localPosition.dy < 110) return;
        _pointer = e.pointer;
        _game.press(e.localPosition);
      },
      onPointerMove: (e) {
        if (e.pointer == _pointer) _game.drag(e.localPosition);
      },
      onPointerUp: (e) {
        if (e.pointer != _pointer) return;
        _pointer = null;
        _game.release(e.localPosition);
      },
      onPointerCancel: (e) {
        if (e.pointer != _pointer) return;
        _pointer = null;
        _game.touching = false;
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

  final FruitDropGame game;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: game.hudRevision,
      builder: (context, _, __) {
        final sim = game.simulation;
        final won = sim.targetReached;
        return SafeArea(
          child: Stack(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    GestureDetector(
                      onTap: onQuit,
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: const BoxDecoration(
                          color: ElevarColors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: FruitDropColors.accent, size: 24),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: _Pill(
                        label: won
                            ? '${'★' * sim.stars}${'☆' * (3 - sim.stars)} · ${sim.stars < 3 ? 'NEXT ${(sim.target * (sim.stars == 1 ? 1.25 : 1.5)).round()}' : 'MAX'}'
                            : 'SCORE / ${sim.target}',
                        value: '${sim.score}',
                        valueColour: won ? const Color(0xFF3DFF6E) : ElevarColors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _Pill(
                        label: 'DROPS',
                        value: '${sim.dropsLeft}',
                        // The last few drops are where a round is won or lost,
                        // so the count turns red while there is still time to
                        // play them carefully.
                        valueColour: sim.dropsLeft <= 5
                            ? const Color(0xFFFF4D4D)
                            : FruitDropColors.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _NextBubble(tier: sim.next),
                  ],
                ),
              ),
              if (game.comboAge < 1.1)
                Align(
                  alignment: const Alignment(0, -0.55),
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey<int>(game.comboSerial),
                    tween: Tween<double>(begin: 0.3, end: 1),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.elasticOut,
                    builder: (context, s, child) => Transform.scale(scale: s, child: child),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                      decoration: BoxDecoration(
                        color: FruitDropColors.accent,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: ElevarColors.ink, width: 3),
                      ),
                      child: Text(game.comboText,
                          style: ElevarType.display(26, color: ElevarColors.white)),
                    ),
                  ),
                ),
              if (sim.drops == 0)
                Align(
                  alignment: const Alignment(0, 0.2),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: FruitDropColors.pill.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Slide to aim, let go to drop.\n'
                      'Merge matching fruit to score ${sim.target}\n'
                      'in ${sim.dropBudget} drops. Keep below the dashed line!',
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

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.value, required this.valueColour});

  final String label;
  final String value;
  final Color valueColour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: FruitDropColors.pill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FittedBox(child: Text(label, style: ElevarType.label(10, color: ElevarColors.white))),
          FittedBox(child: Text(value, style: ElevarType.display(26, color: valueColour))),
        ],
      ),
    );
  }
}

class _NextBubble extends StatelessWidget {
  const _NextBubble({required this.tier});

  final int tier;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: const Color(0xFFCFE6CE),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFAFCFAE), width: 5),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CustomPaint(
            size: const Size(40, 40),
            painter: _FruitPainter(tier),
          ),
          Positioned(
            top: 2,
            child: Text('NEXT', style: ElevarType.label(7, color: FruitDropColors.pill)),
          ),
        ],
      ),
    );
  }
}

class _FruitPainter extends CustomPainter {
  _FruitPainter(this.tier);

  final int tier;

  @override
  void paint(Canvas canvas, Size size) {
    final r = 10 + (Fruits.radii[tier] - 22) / (57 - 22) * 8;
    FruitArt.instance.draw(canvas, tier, size.center(Offset.zero), r);
  }

  @override
  bool shouldRepaint(_FruitPainter old) => old.tier != tier;
}
