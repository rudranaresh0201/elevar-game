import 'dart:math' as math;

import 'package:archery_sim/archery_sim.dart';
import 'package:design_system/design_system.dart';
import 'package:flame/components.dart';
import 'package:flutter/widgets.dart';
import 'package:game_core/game_core.dart';

import 'duel_game.dart';

abstract final class DuelColors {
  static const Color sky = Color(0xFF55B8F0);
  static const Color skyHigh = Color(0xFF3FA3E3);
  static const Color sun = Color(0xFFFFF3B0);
  static const Color cloud = Color(0xFFE8F6FF);
  static const Color farHills = Color(0xFF7FC6EE);
  static const Color nearHills = Color(0xFF63B3E4);
  static const Color grass = Color(0xFF58C43A);
  static const Color grassDeep = Color(0xFF3F9A2C);
  static const Color dirt = Color(0xFF8C5A34);
  static const Color p1 = ElevarColors.p1;
  static const Color p1Deep = ElevarColors.p1Deep;
  static const Color p2 = Color(0xFF29C7F0);
  static const Color p2Deep = Color(0xFF1189B5);
  static const Color skin = Color(0xFFF1C79E);
  static const Color bow = Color(0xFF8B5A2B);
  static const Color shaft = Color(0xFF6B4423);
}

class DuelScene extends Component {
  DuelScene({required this.game});

  final DuelGame game;
  final Map<String, TextPainter> _text = <String, TextPainter>{};
  double _time = 0;

  static Paint _stroke(double width, [Color colour = ElevarColors.ink]) => Paint()
    ..color = colour
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void update(double dt) => _time += dt;

  @override
  void render(Canvas canvas) {
    final size = Size(game.size.x, game.size.y);
    if (size.isEmpty) return;
    canvas.save();
    canvas.translate(game.shakeOffset.dx, game.shakeOffset.dy);
    _paintSky(canvas, size);
    _paintTerrain(canvas, size);
    _paintStuck(canvas);
    for (final side in ArcherSide.values) {
      _paintArcher(canvas, side);
    }
    _paintPreview(canvas);
    _paintArrow(canvas);
    _paintParticles(canvas);
    _paintFloaters(canvas);
    _paintOffscreen(canvas, size);
    canvas.restore();

    if (game.flash > 0.01) {
      canvas.drawRect(Offset.zero & size,
          Paint()..color = ElevarColors.white.withValues(alpha: game.flash * 0.35));
    }
  }

  void _paintSky(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = DuelColors.sky);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height * 0.25),
        Paint()..color = DuelColors.skyHigh);
    // Sun and clouds, barely moving with the camera — distance by parallax.
    final sunX = size.width * 0.75 - game.camX * 0.02;
    canvas.drawCircle(Offset(sunX, size.height * 0.16), 46, Paint()..color = DuelColors.sun);
    for (var i = 0; i < 6; i++) {
      final worldX = i * 520.0 + (_time * 12) % 520;
      final x = (worldX - game.camX * 0.25) % (size.width + 400) - 200;
      final y = size.height * (0.1 + 0.07 * (i % 3));
      final cloud = Paint()..color = DuelColors.cloud.withValues(alpha: 0.9);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, 150, 38), const Radius.circular(19)),
        cloud,
      );
      canvas.drawCircle(Offset(x + 55, y + 4), 30, cloud);
      canvas.drawCircle(Offset(x + 95, y + 10), 22, cloud);
    }
    // Far hills at half parallax.
    for (final (colour, factor, base, amp) in <(Color, double, double, double)>[
      (DuelColors.farHills, 0.3, 0.46, 60),
      (DuelColors.nearHills, 0.55, 0.52, 80),
    ]) {
      final path = Path()..moveTo(0, size.height);
      for (var sx = 0.0; sx <= size.width + 20; sx += 20) {
        final wx = (sx - size.width / 2) / game.scale + game.camX * factor;
        final y = size.height * base -
            (math.sin(wx / 190) * 0.6 + math.sin(wx / 83) * 0.4) * amp +
            (game.camY - 300) * game.scale * factor * 0.3;
        path.lineTo(sx, y);
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = colour);
    }
  }

  void _paintTerrain(Canvas canvas, Size size) {
    final terrain = game.simulation.terrain;
    final path = Path();
    final top = Path();
    var first = true;
    final left = game.camX - size.width / 2 / game.scale - 40;
    final right = game.camX + size.width / 2 / game.scale + 40;
    for (var x = math.max(0.0, left); x <= math.min(Terrain.width, right) + 20; x += 10) {
      final p = game.toScreen(Vec2(x, terrain.heightAt(x)));
      if (first) {
        path.moveTo(p.dx, size.height + 20);
        path.lineTo(p.dx, p.dy);
        top.moveTo(p.dx, p.dy);
        first = false;
      } else {
        path.lineTo(p.dx, p.dy);
        top.lineTo(p.dx, p.dy);
      }
    }
    if (first) return;
    final last = game.toScreen(Vec2(math.min(Terrain.width, right) + 20, 0));
    path
      ..lineTo(last.dx, size.height + 20)
      ..close();
    canvas.drawPath(path, Paint()..color = DuelColors.dirt);
    // Grass band on top of the dirt.
    canvas.drawPath(top, _stroke(34 * game.scale, DuelColors.grass));
    canvas.drawPath(top.shift(Offset(0, 14 * game.scale)),
        _stroke(8 * game.scale, DuelColors.grassDeep));
    canvas.drawPath(top.shift(Offset(0, -17 * game.scale)), _stroke(6, ElevarColors.ink));
  }

  void _paintArcher(Canvas canvas, ArcherSide side) {
    final sim = game.simulation;
    final x = DuelSimulation.xOf(side);
    final ground = sim.groundOf(side);
    final s = game.scale;
    final facing = side == ArcherSide.p1 ? 1.0 : -1.0;
    final hp = side == ArcherSide.p1 ? sim.p1Hp : sim.p2Hp;
    final shirt = side == ArcherSide.p1 ? DuelColors.p1 : DuelColors.p2;
    final shirtDeep = side == ArcherSide.p1 ? DuelColors.p1Deep : DuelColors.p2Deep;
    final feet = game.toScreen(Vec2(x, ground));
    final flinch = game.flinch[side]!;
    final down = hp <= 0;

    canvas.save();
    canvas.translate(feet.dx, feet.dy);
    if (down) {
      canvas.rotate(-facing * math.pi / 2 * 0.92);
    } else if (flinch > 0) {
      canvas.rotate(-facing * 0.35 * math.sin(flinch * math.pi));
    }
    Offset p(double wx, double wy) => Offset(wx * s * facing, -wy * s);

    // Legs.
    final breathe = math.sin(_time * 3 + (side.index * 2)) * 2;
    for (final dx in <double>[-14, 14]) {
      canvas.drawLine(p(dx * 0.6, 64), p(dx, 4), _stroke(20 * s + 6));
      canvas.drawLine(p(dx * 0.6, 64), p(dx, 4), _stroke(20 * s, const Color(0xFF2B2B33)));
      canvas.drawOval(
        Rect.fromCenter(center: p(dx + 6, 3), width: 30 * s, height: 14 * s),
        Paint()..color = ElevarColors.ink,
      );
    }
    // Body.
    final body = RRect.fromRectAndRadius(
      Rect.fromPoints(p(-30, 134 + breathe), p(30, 58)),
      Radius.circular(24 * s),
    );
    canvas.drawRRect(body.shift(Offset(0, 5 * s)), Paint()..color = shirtDeep);
    canvas.drawRRect(body, Paint()..color = shirt);
    canvas.drawRRect(body, _stroke(5));

    // The bow arm follows the aim.
    final aim = _aimFor(side);
    final shoulder = p(4, 114 + breathe);
    final aimScreen = Offset(aim.direction.x * facing, -aim.direction.y);
    // The whole body is drawn facing-mirrored, so un-mirror the aim x.
    final hand = shoulder + Offset(aimScreen.dx * facing, aimScreen.dy) * (48 * s);
    canvas.drawLine(shoulder, hand, _stroke(16 * s + 5));
    canvas.drawLine(shoulder, hand, _stroke(16 * s, shirt));
    _paintBow(canvas, hand, Offset(aimScreen.dx * facing, aimScreen.dy), aim.power, s,
        nocked: aim.power > 0);

    // Head.
    final head = p(0, DuelSimulation.headHeight + breathe);
    final r = DuelSimulation.headRadius * s;
    canvas.drawCircle(head, r + 3, Paint()..color = ElevarColors.ink);
    canvas.drawCircle(head, r, Paint()..color = DuelColors.skin);
    // Hood, like the reference: a white cap with the team colour band.
    final hood = Path()
      ..addArc(Rect.fromCircle(center: head, radius: r + 4), math.pi, math.pi);
    canvas.drawPath(hood, Paint()..color = ElevarColors.white);
    canvas.drawRect(
      Rect.fromCenter(center: head - Offset(0, r * 0.25), width: r * 2.1, height: r * 0.35),
      Paint()..color = shirt,
    );
    canvas.drawCircle(head, r + 1, _stroke(4));
    // Eyes look where the archer faces; crosses when down.
    final eye = head + Offset(r * 0.35 * facing, r * 0.15);
    if (down) {
      final cross = _stroke(3);
      for (final e in <Offset>[eye, eye - Offset(r * 0.45 * facing, 0)]) {
        canvas.drawLine(e - const Offset(4, 4), e + const Offset(4, 4), cross);
        canvas.drawLine(e - const Offset(-4, 4), e + const Offset(-4, 4), cross);
      }
    } else {
      canvas.drawCircle(eye, r * 0.11, Paint()..color = ElevarColors.ink);
      canvas.drawCircle(eye - Offset(r * 0.45 * facing, 0), r * 0.11,
          Paint()..color = ElevarColors.ink);
    }
    canvas.restore();
  }

  ({Vec2 direction, double power}) _aimFor(ArcherSide side) {
    final sim = game.simulation;
    final facing = side == ArcherSide.p1 ? 1.0 : -1.0;
    final rest = Vec2(facing, -0.35).normalized;
    if (sim.turn != side) return (direction: rest, power: 0);
    if (sim.phase == DuelPhase.aim) {
      if (sim.turnIsHuman) {
        final live = game.liveAim;
        return live ?? (direction: Vec2(facing, 0.25).normalized, power: 0);
      }
      return (direction: sim.botAimDirection, power: sim.botAimPower);
    }
    return (direction: sim.lastDirection, power: 0);
  }

  void _paintBow(Canvas canvas, Offset hand, Offset dir, double power, double s,
      {required bool nocked}) {
    final normal = Offset(-dir.dy, dir.dx);
    final half = 46 * s;
    final tipA = hand + normal * half - dir * (8 * s);
    final tipB = hand - normal * half - dir * (8 * s);
    final grip = hand + dir * (12 * s);
    final bow = Path()
      ..moveTo(tipA.dx, tipA.dy)
      ..quadraticBezierTo(grip.dx + dir.dx * 22 * s, grip.dy + dir.dy * 22 * s, tipB.dx, tipB.dy);
    canvas.drawPath(bow, _stroke(9 * s + 4));
    canvas.drawPath(bow, _stroke(9 * s, DuelColors.bow));
    final pull = hand - dir * (10 * s + 34 * s * power);
    canvas.drawLine(tipA, pull, _stroke(2, ElevarColors.white));
    canvas.drawLine(tipB, pull, _stroke(2, ElevarColors.white));
    if (nocked) _paintArrowShape(canvas, pull, dir, 80 * s);
  }

  void _paintArrowShape(Canvas canvas, Offset tail, Offset dir, double length) {
    final tip = tail + dir * length;
    canvas.drawLine(tail, tip, _stroke(length * 0.07 + 3));
    canvas.drawLine(tail, tip, _stroke(length * 0.07, DuelColors.shaft));
    final normal = Offset(-dir.dy, dir.dx);
    final head = Path()
      ..moveTo((tip + dir * length * 0.16).dx, (tip + dir * length * 0.16).dy)
      ..lineTo((tip + normal * length * 0.08).dx, (tip + normal * length * 0.08).dy)
      ..lineTo((tip - normal * length * 0.08).dx, (tip - normal * length * 0.08).dy)
      ..close();
    canvas.drawPath(head, Paint()..color = const Color(0xFFD5D8DC));
    canvas.drawPath(head, _stroke(2.5));
    for (final side in <double>[-1, 1]) {
      final a = tail + dir * length * 0.14;
      final b = tail - dir * length * 0.02 + normal * length * 0.09 * side;
      canvas.drawLine(a, b, _stroke(length * 0.05, const Color(0xFFFF3DA6)));
    }
  }

  void _paintPreview(Canvas canvas) {
    final sim = game.simulation;
    final aim = game.liveAim;
    if (aim == null) return;
    // Only the opening of the arc: enough to judge an angle, not enough to
    // solve the shot. Wind is included, because the wind is on the screen.
    var p = sim.launchPoint(sim.turn);
    var v = aim.direction * (aim.power * DuelSimulation.maxSpeed);
    const dt = 1 / 30;
    for (var i = 0; i < 16; i++) {
      v = Vec2(v.x + sim.wind * dt, v.y - DuelSimulation.gravity * dt);
      p = p + v * dt;
      if (p.y < sim.terrain.heightAt(p.x)) break;
      final screen = game.toScreen(p);
      final fade = 1 - i / 16;
      canvas.drawCircle(screen, 5 + 3 * fade,
          Paint()..color = ElevarColors.white.withValues(alpha: 0.9 * fade));
    }
    // The force and angle, as the reference shows them.
    final angle = (math.atan2(aim.direction.y, aim.direction.x.abs()) * 180 / math.pi).round();
    final at = game.toScreen(sim.headCentre(sim.turn)) + Offset(0, -70 * game.scale - 40);
    _pill(canvas, '${(aim.power * 100).round()}%  FORCE   $angle°  ANGLE', at);
  }

  void _paintArrow(Canvas canvas) {
    final sim = game.simulation;
    if (!sim.arrowFlying) return;
    for (var i = 0; i < game.arrowTrail.length; i += 3) {
      final t = i / game.arrowTrail.length;
      canvas.drawCircle(game.toScreen(game.arrowTrail[i]), 2 + 2 * t,
          Paint()..color = ElevarColors.white.withValues(alpha: 0.5 * t));
    }
    final at = sim.arrowPrevious + (sim.arrow - sim.arrowPrevious) * game.interpolation;
    final v = sim.arrowVelocity.normalized;
    final dir = Offset(v.x, -v.y);
    final length = 90 * game.scale;
    _paintArrowShape(canvas, game.toScreen(at) - dir * length, dir, length);
  }

  void _paintStuck(Canvas canvas) {
    for (final arrow in game.simulation.stuck) {
      final dir = Offset(arrow.direction.x, -arrow.direction.y);
      final length = 90 * game.scale;
      // Buried a third of the way in.
      final tipScreen = game.toScreen(arrow.at) + dir * (length * 0.3);
      _paintArrowShape(canvas, tipScreen - dir * length, dir, length);
    }
  }

  void _paintParticles(Canvas canvas) {
    for (final p in game.particles) {
      final fade = clampD(p.life / p.maxLife, 0, 1);
      canvas.drawCircle(game.toScreen(p.position), p.size * fade,
          Paint()..color = p.colour.withValues(alpha: fade));
    }
  }

  void _paintFloaters(Canvas canvas) {
    for (final f in game.floaters) {
      final t = f.age / 1.4;
      final at = game.toScreen(f.at) - Offset(0, t * 70);
      final painter = _painter(f.text, 30, f.colour);
      final alpha = clampD(1.5 - t * 1.5, 0, 1);
      final scale = t < 0.12 ? 0.5 + t / 0.12 * 0.7 : 1.2 - (t - 0.12) * 0.2;
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.scale(scale);
      if (alpha < 0.99) {
        canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
      }
      final outline = _painter(f.text, 30, ElevarColors.ink);
      for (final o in const <Offset>[Offset(-2, 0), Offset(2, 0), Offset(0, -2), Offset(0, 3)]) {
        outline.paint(canvas, o - Offset(painter.width / 2, painter.height / 2));
      }
      painter.paint(canvas, -Offset(painter.width / 2, painter.height / 2));
      if (alpha < 0.99) canvas.restore();
      canvas.restore();
    }
  }

  /// A chip at the screen edge pointing at an archer who is off screen, with
  /// the distance — the reference does exactly this and it answers "where is
  /// he" without a minimap.
  void _paintOffscreen(Canvas canvas, Size size) {
    final sim = game.simulation;
    for (final side in ArcherSide.values) {
      final head = game.toScreen(sim.headCentre(side));
      if (head.dx > 20 && head.dx < size.width - 20) continue;
      final left = head.dx <= 20;
      final metres = ((DuelSimulation.xOf(side) - game.camX).abs() / 25).round();
      final y = clampD(head.dy, 140, size.height - 140);
      final x = left ? 40.0 : size.width - 40;
      final colour = side == ArcherSide.p1 ? DuelColors.p1 : DuelColors.p2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, y), width: 58, height: 64),
        const Radius.circular(16),
      );
      canvas.drawRRect(rect, Paint()..color = ElevarColors.white);
      canvas.drawRRect(rect, _stroke(4));
      canvas.drawCircle(Offset(x, y - 8), 14, Paint()..color = colour);
      canvas.drawCircle(Offset(x, y - 8), 14, _stroke(3));
      final label = _painter('${metres}m', 13, ElevarColors.ink);
      label.paint(canvas, Offset(x - label.width / 2, y + 10));
    }
  }

  void _pill(Canvas canvas, String text, Offset center) {
    final painter = _painter(text, 16, ElevarColors.ink);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: painter.width + 26, height: painter.height + 14),
      const Radius.circular(14),
    );
    canvas.drawRRect(rect, Paint()..color = ElevarColors.white);
    canvas.drawRRect(rect, _stroke(3));
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
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
