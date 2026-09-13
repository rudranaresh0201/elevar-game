import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flame/components.dart';
import 'package:flutter/widgets.dart';
import 'package:fruitdrop_sim/fruitdrop_sim.dart';
import 'package:game_core/game_core.dart';

import 'fruit_art.dart';
import 'fruitdrop_game.dart';

abstract final class FruitDropColors {
  static const Color background = Color(0xFFBFDDBE);
  static const Color backgroundDots = Color(0xFFB2D4B1);
  static const Color jarWall = Color(0xFFC9623F);
  static const Color jarWallDeep = Color(0xFFA84A2C);
  static const Color jarFloor = Color(0xFFFBE3B0);
  static const Color jarCheck = Color(0xFFF6D595);
  static const Color danger = Color(0xFFE07A5F);
  static const Color guide = Color(0xFFD6406A);
  static const Color pill = Color(0xFF3F4A3E);
  static const Color accent = Color(0xFFFF7EA8);
}

class FruitDropScene extends Component {
  FruitDropScene({required this.game});

  final FruitDropGame game;
  final Map<String, TextPainter> _text = <String, TextPainter>{};
  double _time = 0;

  @override
  void update(double dt) => _time += dt;

  @override
  void render(Canvas canvas) {
    final size = Size(game.size.x, game.size.y);
    if (size.isEmpty) return;
    _paintBackground(canvas, size);

    canvas.save();
    canvas.translate(game.shakeOffset.dx, game.shakeOffset.dy);
    _paintJar(canvas);
    _paintDangerLine(canvas);
    _paintGuideAndHeld(canvas);
    _paintFruits(canvas);
    _paintJuice(canvas);
    _paintPops(canvas);
    canvas.restore();

    _paintEvolutionBar(canvas, size);

    if (game.flash > 0.01) {
      canvas.drawRect(Offset.zero & size,
          Paint()..color = ElevarColors.white.withValues(alpha: game.flash * 0.4));
    }
  }

  void _paintBackground(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = FruitDropColors.background);
    final dot = Paint()..color = FruitDropColors.backgroundDots;
    for (var y = 20.0; y < size.height; y += 44) {
      for (var x = 20.0; x < size.width; x += 44) {
        canvas.drawCircle(Offset(x + ((y / 44).floor().isEven ? 0 : 22), y), 5, dot);
      }
    }
  }

  void _paintJar(Canvas canvas) {
    final sim = game.simulation;
    final s = game.jarScale;
    final origin = game.jarOrigin;
    final inner = Rect.fromLTWH(origin.dx, origin.dy, sim.width * s, FruitDropSimulation.height * s);
    const wall = FruitDropGame.wall;

    // Gingham floor.
    canvas.drawRect(inner, Paint()..color = FruitDropColors.jarFloor);
    canvas.save();
    canvas.clipRect(inner);
    final check = Paint()..color = FruitDropColors.jarCheck.withValues(alpha: 0.7);
    final cell = 40 * s;
    for (var x = inner.left; x < inner.right; x += cell * 2) {
      canvas.drawRect(Rect.fromLTWH(x, inner.top, cell, inner.height), check);
    }
    for (var y = inner.top; y < inner.bottom; y += cell * 2) {
      canvas.drawRect(Rect.fromLTWH(inner.left, y, inner.width, cell), check);
    }
    canvas.restore();

    // The warning glow when the pile nears the line.
    final danger = sim.danger;
    if (danger > 0.05) {
      final pulse = 0.5 + 0.5 * math.sin(_time * (8 + danger * 12));
      canvas.drawRect(
        Rect.fromLTRB(inner.left, inner.top, inner.right,
            inner.top + FruitDropSimulation.dangerY * s),
        Paint()..color = const Color(0xFFFF3B3B).withValues(alpha: 0.12 + 0.2 * danger * pulse),
      );
    }

    // Walls: a U, with rounded top caps like the reference.
    final w = wall * s;
    final path = Path()
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTRB(inner.left - w, inner.top - 10 * s, inner.left, inner.bottom + w),
        topLeft: Radius.circular(w / 2),
        topRight: Radius.circular(w / 2),
        bottomLeft: Radius.circular(w / 2),
      ))
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTRB(inner.right, inner.top - 10 * s, inner.right + w, inner.bottom + w),
        topLeft: Radius.circular(w / 2),
        topRight: Radius.circular(w / 2),
        bottomRight: Radius.circular(w / 2),
      ))
      ..addRect(Rect.fromLTRB(inner.left - w / 2, inner.bottom, inner.right + w / 2, inner.bottom + w));
    canvas.drawPath(path.shift(Offset(0, 5 * s)), Paint()..color = FruitDropColors.jarWallDeep);
    canvas.drawPath(path, Paint()..color = FruitDropColors.jarWall);
  }

  void _paintDangerLine(Canvas canvas) {
    final sim = game.simulation;
    final s = game.jarScale;
    final y = game.jarOrigin.dy + FruitDropSimulation.dangerY * s;
    final danger = sim.danger;
    final colour = Color.lerp(FruitDropColors.danger, const Color(0xFFFF1F1F), danger)!;
    final paint = Paint()
      ..color = colour
      ..strokeWidth = 7 * s + 2
      ..strokeCap = StrokeCap.round;
    final dash = 26 * s;
    for (var x = game.jarOrigin.dx + 10 * s; x < game.jarOrigin.dx + sim.width * s - 10 * s; x += dash * 1.8) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
    }
  }

  void _paintGuideAndHeld(Canvas canvas) {
    final sim = game.simulation;
    if (sim.isComplete) return;
    final s = game.jarScale;
    final tier = sim.current;
    final r = Fruits.radii[tier];
    final x = sim.holdX;

    // Dotted guide down to whatever the fruit would land on first.
    var floor = FruitDropSimulation.height;
    for (final f in sim.fruits) {
      final dx = (f.position.x - x).abs();
      final reach = f.radius + r;
      if (dx < reach) {
        final lift = math.sqrt(reach * reach - dx * dx);
        final top = f.position.y - lift + r;
        if (top < floor) floor = top;
      }
    }
    if (sim.canDrop) {
      final dot = Paint()..color = FruitDropColors.guide.withValues(alpha: game.touching ? 0.95 : 0.6);
      for (var y = FruitDropSimulation.holdY + r + 18; y < floor - 10; y += 34) {
        canvas.drawCircle(game.toScreen(Vec2(x, y)), 6 * s + 1.5, dot);
      }
      final bob = game.touching ? 0.0 : math.sin(_time * 3) * 4;
      FruitArt.instance.draw(
        canvas,
        tier,
        game.toScreen(Vec2(x, FruitDropSimulation.holdY + bob)),
        r * s,
      );
    }
  }

  void _paintFruits(Canvas canvas) {
    final sim = game.simulation;
    final s = game.jarScale;
    final over = sim.danger > 0.05;
    for (final f in sim.fruits) {
      final at = game.toScreen(f.position);
      var radius = f.radius * s;
      final wobble = game.squash[f.id] ?? 0;
      if (over && f.overLineTicks > 0 && (_time * 10).floor().isEven) {
        radius *= 1.04;
      }
      FruitArt.instance.draw(
        canvas,
        f.tier,
        at,
        radius,
        rotation: game.rotation[f.id] ?? 0,
        squash: wobble * math.sin(_time * 30),
      );
    }
  }

  void _paintJuice(Canvas canvas) {
    for (final j in game.juice) {
      final fade = clampD(j.life / j.maxLife, 0, 1);
      canvas.drawCircle(game.toScreen(j.position), j.size * game.jarScale * fade + 1,
          Paint()..color = j.colour.withValues(alpha: fade));
    }
  }

  void _paintPops(Canvas canvas) {
    for (final p in game.pops) {
      final t = p.age / 0.9;
      final at = game.toScreen(p.at) - Offset(0, 50 * t);
      final size = 26 * (t < 0.15 ? 0.6 + t / 0.15 * 0.5 : 1.1 - (t - 0.15) * 0.15);
      final fill = _painter(p.text, size, ElevarColors.white);
      final outline = _painter(p.text, size, ElevarColors.ink);
      final alpha = clampD(1.6 - t * 1.6, 0, 1);
      if (alpha < 0.99) {
        canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
      }
      final origin = at - Offset(fill.width / 2, fill.height / 2);
      for (final o in const <Offset>[Offset(-2, 0), Offset(2, 0), Offset(0, -2), Offset(0, 3)]) {
        outline.paint(canvas, origin + o);
      }
      fill.paint(canvas, origin);
      if (alpha < 0.99) canvas.restore();
    }
  }

  void _paintEvolutionBar(Canvas canvas, Size size) {
    final sim = game.simulation;
    final barHeight = 60.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(14, size.height - barHeight - 22, size.width - 28, barHeight),
      const Radius.circular(30),
    );
    canvas.drawRRect(rect, Paint()..color = const Color(0xFFAFCFAE));
    canvas.drawRRect(rect.deflate(5), Paint()..color = const Color(0xFFCFE6CE));
    final slot = (rect.width - 20) / Fruits.count;
    for (var i = 0; i < Fruits.count; i++) {
      final reached = i <= math.max(sim.biggestTier, 4);
      final centre = Offset(rect.left + 10 + slot * (i + 0.5), rect.center.dy);
      final r = math.min(slot * 0.42, 8 + i * 1.6);
      if (reached) {
        FruitArt.instance.draw(canvas, i, centre, r);
      } else {
        canvas.drawCircle(centre, r, Paint()..color = const Color(0x33000000));
      }
      if (i == sim.biggestTier && sim.biggestTier > 0) {
        canvas.drawCircle(
          centre,
          r + 4,
          Paint()
            ..color = FruitDropColors.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
    }
  }

  TextPainter _painter(String text, double size, Color colour) {
    final key = '$text|${size.round()}|${colour.toARGB32()}';
    return _text.putIfAbsent(key, () {
      if (_text.length > 120) _text.clear();
      return TextPainter(
        text: TextSpan(text: text, style: ElevarType.display(size, color: colour)),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }
}
