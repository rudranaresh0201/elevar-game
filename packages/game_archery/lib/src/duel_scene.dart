import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:archery_sim/archery_sim.dart';
import 'package:design_system/design_system.dart';
import 'package:flame/components.dart';
import 'package:flutter/widgets.dart';
import 'package:game_core/game_core.dart';

import 'duel_game.dart';
import 'duel_theme.dart';

abstract final class DuelColors {
  static const Color sky = Color(0xFF55B8F0);
  static const Color p1 = ElevarColors.p1;
  static const Color p1Deep = ElevarColors.p1Deep;
  static const Color p2 = Color(0xFF29C7F0);
  static const Color p2Deep = Color(0xFF1189B5);
  static const Color skin = Color(0xFFF1C79E);
  static const Color bow = Color(0xFF8B5A2B);
  static const Color shaft = Color(0xFF6B4423);
  static const Color leather = Color(0xFF7A4B2A);
  static const Color boots = Color(0xFF2B2B33);
}

/// Paints the duel: a layered world, two archers, the arc between them.
///
/// Everything here is decoration over `archery_sim`. The scenery is generated
/// from the match seed with its own random stream, so it is stable for a
/// match and different for the next — and nothing in it can touch a hitbox.
class DuelScene extends Component {
  DuelScene({required this.game});

  final DuelGame game;
  final Map<String, TextPainter> _text = <String, TextPainter>{};

  late final DuelTheme theme = game.theme;
  late final List<double> _peaks = _generatePeaks();
  late final List<({double x, double size, int kind})> _props = _generateProps();

  static Paint _stroke(double width, [Color colour = ElevarColors.ink]) => Paint()
    ..color = colour
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  List<double> _generatePeaks() {
    final rng = math.Random(game.config.seed ^ 0x5EED);
    return List<double>.generate(40, (_) => 0.35 + rng.nextDouble() * 0.65);
  }

  /// Trees, rocks and flowers along the terrain, kept clear of both archers.
  List<({double x, double size, int kind})> _generateProps() {
    final rng = math.Random(game.config.seed ^ 0x7A11);
    final props = <({double x, double size, int kind})>[];
    for (var x = 40.0; x < Terrain.width - 40; x += 70 + rng.nextDouble() * 110) {
      final nearArcher = (x - Terrain.p1X).abs() < 160 || (x - Terrain.p2X).abs() < 160;
      if (nearArcher) continue;
      props.add((x: x, size: 0.7 + rng.nextDouble() * 0.6, kind: rng.nextInt(10)));
    }
    return props;
  }

  @override
  void render(Canvas canvas) {
    final size = Size(game.size.x, game.size.y);
    if (size.isEmpty) return;
    canvas.save();
    canvas.translate(game.shakeOffset.dx, game.shakeOffset.dy);
    _paintSky(canvas, size);
    _paintFarMountains(canvas, size);
    _paintMidHills(canvas, size);
    _paintTerrain(canvas, size);
    _paintProps(canvas, size, background: true);
    _paintStuck(canvas);
    for (final side in ArcherSide.values) {
      _paintArcher(canvas, side);
    }
    _paintProps(canvas, size, background: false);
    _paintPreview(canvas);
    _paintArrow(canvas);
    _paintParticles(canvas);
    _paintWind(canvas, size);
    _paintFloaters(canvas);
    _paintOffscreen(canvas, size);
    canvas.restore();

    if (game.slowMo > 0) {
      // Letterbox bars during the headshot slow-motion.
      final bar = size.height * 0.07 * (game.slowMo / 0.7).clamp(0.0, 1.0);
      final paint = Paint()..color = ElevarColors.ink;
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, bar), paint);
      canvas.drawRect(Rect.fromLTWH(0, size.height - bar, size.width, bar), paint);
    }
    if (game.flash > 0.01) {
      canvas.drawRect(Offset.zero & size,
          Paint()..color = ElevarColors.white.withValues(alpha: game.flash * 0.35));
    }
  }

  // --- world ---------------------------------------------------------------

  void _paintSky(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height * 0.75),
          <Color>[theme.skyTop, theme.skyBottom],
        ),
    );
    // Sun with soft rings, drifting slightly with the camera.
    final sun = Offset(size.width * 0.72 - game.camX * 0.015, size.height * 0.15);
    for (final (r, a) in <(double, double)>[(110, 0.08), (78, 0.14), (54, 0.25)]) {
      canvas.drawCircle(sun, r, Paint()..color = theme.sun.withValues(alpha: a));
    }
    canvas.drawCircle(sun, 40, Paint()..color = theme.sun);

    // Clouds drift with the wind as well as the camera.
    final drift = game.clock * (8 + game.simulation.wind * 0.4);
    for (var i = 0; i < 7; i++) {
      final span = size.width + 360;
      final raw = i * 260.0 + drift - game.camX * (0.12 + 0.03 * (i % 3));
      final x = (raw % span + span) % span - 180;
      final y = size.height * (0.07 + 0.06 * (i % 4));
      final scale = 0.7 + 0.15 * (i % 3);
      final cloud = Paint()..color = theme.cloud.withValues(alpha: 0.92);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, 170 * scale, 42 * scale), Radius.circular(21 * scale)),
        cloud,
      );
      canvas.drawCircle(Offset(x + 60 * scale, y + 2), 34 * scale, cloud);
      canvas.drawCircle(Offset(x + 108 * scale, y + 8), 25 * scale, cloud);
    }
  }

  void _paintFarMountains(Canvas canvas, Size size) {
    const factor = 0.18;
    final base = size.height * 0.5 + (game.camY - 250) * game.scale * 0.12;
    final path = Path()..moveTo(-10, size.height);
    const spacing = 180.0;
    final offset = game.camX * factor;
    final first = (offset / spacing).floor() - 1;
    for (var i = first; i < first + size.width / spacing + 3; i++) {
      final peak = _peaks[i % _peaks.length];
      final x = i * spacing - offset;
      path
        ..lineTo(x, base)
        ..lineTo(x + spacing / 2, base - 150 * peak)
        ..lineTo(x + spacing, base);
    }
    path
      ..lineTo(size.width + 10, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = theme.farHills);
    if (theme.snowing || theme.decoration == GroundDecor.flowers) {
      // Snow caps on the far peaks.
      final caps = Paint()..color = const Color(0xFFF7FBFF).withValues(alpha: 0.85);
      for (var i = first; i < first + size.width / spacing + 3; i++) {
        final peak = _peaks[i % _peaks.length];
        if (peak < 0.6) continue;
        final x = i * spacing - offset + spacing / 2;
        final top = base - 150 * peak;
        canvas.drawPath(
          Path()
            ..moveTo(x, top)
            ..lineTo(x - 26, top + 34)
            ..lineTo(x - 8, top + 26)
            ..lineTo(x + 6, top + 36)
            ..lineTo(x + 26, top + 34)
            ..close(),
          caps,
        );
      }
    }
  }

  void _paintMidHills(Canvas canvas, Size size) {
    const factor = 0.42;
    final base = size.height * 0.57 + (game.camY - 250) * game.scale * 0.25;
    final offset = game.camX * factor;
    final path = Path()..moveTo(0, size.height);
    for (var sx = 0.0; sx <= size.width + 20; sx += 16) {
      final wx = sx + offset;
      final y = base -
          (math.sin(wx / 160) * 0.55 + math.sin(wx / 71 + 1.3) * 0.25) * 46;
      path.lineTo(sx, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = theme.midHills);

    // A row of silhouette trees on the ridge.
    final treePaint = Paint()..color = Color.lerp(theme.midHills, theme.leafDeep, 0.5)!;
    for (var i = -1; i < size.width / 90 + 2; i++) {
      final wx = ((offset / 90).floor() + i) * 90.0;
      final sx = wx - offset;
      final hash = (wx * 7919).floor() % 7;
      if (hash > 3) continue;
      final y = base - (math.sin(wx / 160) * 0.55 + math.sin(wx / 71 + 1.3) * 0.25) * 46;
      final h = 34.0 + hash * 8;
      if (theme.decoration == GroundDecor.cactus) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(sx - 5, y - h, 10, h), const Radius.circular(5)),
          treePaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(sx - 16, y - h * 0.7, 8, h * 0.35), const Radius.circular(4)),
          treePaint,
        );
      } else {
        canvas.drawPath(
          Path()
            ..moveTo(sx, y - h)
            ..lineTo(sx - h * 0.32, y + 2)
            ..lineTo(sx + h * 0.32, y + 2)
            ..close(),
          treePaint,
        );
      }
    }
  }

  void _paintTerrain(Canvas canvas, Size size) {
    final terrain = game.simulation.terrain;
    final s = game.scale;
    // Drawn across the whole view, not just the world: past either end the
    // ground carries on level (heightAt clamps), rather than stopping in
    // mid-air with sky underneath when the camera looks over the edge.
    final left = game.camX - size.width / 2 / s - 60;
    final right = game.camX + size.width / 2 / s + 60;

    final top = <Offset>[];
    for (var x = left; x <= right + 10; x += 10) {
      top.add(game.toScreen(Vec2(x, terrain.heightAt(x))));
    }
    final body = Path()..moveTo(top.first.dx, size.height + 40);
    for (final p in top) {
      body.lineTo(p.dx, p.dy);
    }
    body
      ..lineTo(top.last.dx, size.height + 40)
      ..close();

    final bottom = game.toScreen(Vec2(game.camX, terrain.heightAt(game.camX) - 400));
    canvas.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, top.map((p) => p.dy).reduce(math.min)),
          Offset(0, math.max(bottom.dy, size.height)),
          <Color>[theme.dirt, theme.dirtDeep],
        ),
    );

    // Strata: faint bands following the surface, deeper down.
    canvas.save();
    canvas.clipPath(body);
    for (final depth in <double>[70, 150, 250]) {
      final band = Path();
      for (var i = 0; i < top.length; i++) {
        final p = top[i] + Offset(0, depth * s);
        i == 0 ? band.moveTo(p.dx, p.dy) : band.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(band, _stroke(10 * s, theme.dirtDeep.withValues(alpha: 0.45)));
    }
    // Pebbles.
    final rng = math.Random(game.config.seed);
    for (var i = 0; i < 40; i++) {
      final wx = rng.nextDouble() * Terrain.width;
      final depth = 40 + rng.nextDouble() * 300;
      final p = game.toScreen(Vec2(wx, terrain.heightAt(wx) - depth));
      if (p.dx < -20 || p.dx > size.width + 20) continue;
      canvas.drawOval(
        Rect.fromCenter(center: p, width: 18 * s, height: 11 * s),
        Paint()..color = theme.rock.withValues(alpha: 0.5),
      );
    }
    canvas.restore();

    // Grass (or sand, or snow) cap with a darker lip and tufts on top.
    final surface = Path()..moveTo(top.first.dx, top.first.dy);
    for (final p in top.skip(1)) {
      surface.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(surface.shift(Offset(0, 16 * s)), _stroke(14 * s, theme.grassDeep));
    canvas.drawPath(surface.shift(Offset(0, 6 * s)), _stroke(22 * s, theme.grass));
    canvas.drawPath(surface.shift(Offset(0, -5 * s)), _stroke(5, ElevarColors.ink));

    final tuft = Paint()..color = theme.grassDeep;
    for (var i = 0; i < top.length; i += 3) {
      final p = top[i];
      final h = (6 + (i * 37 % 7)) * s * 1.6;
      canvas.drawPath(
        Path()
          ..moveTo(p.dx - 5 * s, p.dy - 3 * s)
          ..lineTo(p.dx - 1 * s, p.dy - 3 * s - h)
          ..lineTo(p.dx + 2 * s, p.dy - 3 * s)
          ..lineTo(p.dx + 6 * s, p.dy - 3 * s - h * 0.7)
          ..lineTo(p.dx + 9 * s, p.dy - 3 * s)
          ..close(),
        tuft,
      );
    }
  }

  /// Trees and rocks behind the archers; flowers, cacti and snowdrifts in
  /// front of their feet.
  void _paintProps(Canvas canvas, Size size, {required bool background}) {
    final terrain = game.simulation.terrain;
    final s = game.scale;
    for (final prop in _props) {
      // Kinds 0-5 are trees and rocks, behind the archers; 6-9 are the small
      // things at ground level, in front of their feet.
      final inFront = prop.kind >= 6;
      if (inFront == background) continue;
      final ground = game.toScreen(Vec2(prop.x, terrain.heightAt(prop.x)));
      if (ground.dx < -120 || ground.dx > size.width + 120) continue;
      final k = prop.size * s;
      switch (prop.kind) {
        case 0 || 1 || 2:
          _tree(canvas, ground, k);
        case 3 || 4 || 5:
          _rock(canvas, ground, k);
        default:
          _groundDecoration(canvas, ground, k, prop.kind);
      }
    }
  }

  void _tree(Canvas canvas, Offset ground, double k) {
    if (theme.decoration == GroundDecor.cactus) {
      final body = Paint()..color = theme.leaf;
      final outline = _stroke(4);
      final trunk = RRect.fromRectAndRadius(
        Rect.fromLTWH(ground.dx - 14 * k, ground.dy - 130 * k, 28 * k, 132 * k),
        Radius.circular(14 * k),
      );
      final armL = RRect.fromRectAndRadius(
        Rect.fromLTWH(ground.dx - 44 * k, ground.dy - 100 * k, 18 * k, 50 * k),
        Radius.circular(9 * k),
      );
      final armR = RRect.fromRectAndRadius(
        Rect.fromLTWH(ground.dx + 26 * k, ground.dy - 118 * k, 18 * k, 56 * k),
        Radius.circular(9 * k),
      );
      for (final r in <RRect>[armL, armR, trunk]) {
        canvas.drawRRect(r, body);
        canvas.drawRRect(r, outline);
      }
      canvas.drawRect(Rect.fromLTWH(ground.dx - 30 * k, ground.dy - 66 * k, 18 * k, 12 * k), body);
      canvas.drawRect(Rect.fromLTWH(ground.dx + 12 * k, ground.dy - 72 * k, 18 * k, 12 * k), body);
      return;
    }
    final trunk = Rect.fromLTWH(ground.dx - 9 * k, ground.dy - 70 * k, 18 * k, 74 * k);
    canvas.drawRect(trunk, Paint()..color = theme.trunk);
    canvas.drawRect(trunk, _stroke(4));
    if (theme.snowing) {
      // Pines, with snow on each tier.
      for (var tier = 0; tier < 3; tier++) {
        final w = (110 - tier * 26) * k;
        final y = ground.dy - (60 + tier * 48) * k;
        final tri = Path()
          ..moveTo(ground.dx, y - 70 * k)
          ..lineTo(ground.dx - w / 2, y)
          ..lineTo(ground.dx + w / 2, y)
          ..close();
        canvas.drawPath(tri, Paint()..color = theme.leaf);
        canvas.drawPath(tri, _stroke(4));
        canvas.drawPath(
          Path()
            ..moveTo(ground.dx, y - 70 * k)
            ..lineTo(ground.dx - w * 0.2, y - 42 * k)
            ..lineTo(ground.dx + w * 0.2, y - 42 * k)
            ..close(),
          Paint()..color = const Color(0xFFF7FBFF),
        );
      }
      return;
    }
    final crown = Paint()..color = theme.leaf;
    final deep = Paint()..color = theme.leafDeep;
    final centre = Offset(ground.dx, ground.dy - 110 * k);
    canvas.drawCircle(centre + Offset(0, 8 * k), 58 * k, deep);
    canvas.drawCircle(centre + Offset(-30 * k, 10 * k), 36 * k, crown);
    canvas.drawCircle(centre + Offset(28 * k, 6 * k), 40 * k, crown);
    canvas.drawCircle(centre + Offset(0, -18 * k), 42 * k, crown);
    canvas.drawCircle(centre + Offset(-14 * k, -30 * k), 12 * k,
        Paint()..color = ElevarColors.white.withValues(alpha: 0.25));
  }

  void _rock(Canvas canvas, Offset ground, double k) {
    final rock = Path()
      ..moveTo(ground.dx - 34 * k, ground.dy + 4)
      ..lineTo(ground.dx - 26 * k, ground.dy - 24 * k)
      ..lineTo(ground.dx - 4 * k, ground.dy - 36 * k)
      ..lineTo(ground.dx + 24 * k, ground.dy - 26 * k)
      ..lineTo(ground.dx + 36 * k, ground.dy + 4)
      ..close();
    canvas.drawPath(rock, Paint()..color = theme.rock);
    canvas.drawPath(
      Path()
        ..moveTo(ground.dx - 20 * k, ground.dy - 22 * k)
        ..lineTo(ground.dx - 4 * k, ground.dy - 32 * k)
        ..lineTo(ground.dx + 10 * k, ground.dy - 26 * k)
        ..close(),
      Paint()..color = ElevarColors.white.withValues(alpha: 0.35),
    );
    canvas.drawPath(rock, _stroke(4));
  }

  void _groundDecoration(Canvas canvas, Offset ground, double k, int kind) {
    switch (theme.decoration) {
      case GroundDecor.flowers:
        const petals = <Color>[Color(0xFFFF6B9A), Color(0xFFFFE14D), Color(0xFFFFFFFF), Color(0xFFB58CFF)];
        final colour = petals[kind % petals.length];
        for (var i = 0; i < 3; i++) {
          final stem = Offset(ground.dx + (i - 1) * 14 * k, ground.dy);
          final head = stem - Offset(0, (22 + i * 5) * k);
          canvas.drawLine(stem, head, _stroke(3 * k + 1, theme.grassDeep));
          for (var p = 0; p < 5; p++) {
            final a = p * math.pi * 2 / 5;
            canvas.drawCircle(head + Offset(math.cos(a) * 6 * k, math.sin(a) * 6 * k),
                4.5 * k, Paint()..color = colour);
          }
          canvas.drawCircle(head, 3.5 * k, Paint()..color = const Color(0xFFFF9F1C));
        }
      case GroundDecor.cactus:
        final bush = Paint()..color = theme.grassDeep;
        canvas.drawCircle(ground - Offset(0, 8 * k), 14 * k, bush);
        canvas.drawCircle(ground - Offset(14 * k, 5 * k), 10 * k, bush);
        canvas.drawCircle(ground - Offset(-13 * k, 4 * k), 9 * k, bush);
      case GroundDecor.snow:
        canvas.drawOval(
          Rect.fromCenter(center: ground - Offset(0, 4 * k), width: 70 * k, height: 20 * k),
          Paint()..color = const Color(0xFFFFFFFF),
        );
    }
  }

  // --- archers -------------------------------------------------------------

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
    final tint = game.hitTint[side]!;
    final down = hp <= 0;
    final active = sim.turn == side && sim.phase == DuelPhase.aim;

    // Shadow and the active player's ring.
    canvas.drawOval(
      Rect.fromCenter(center: feet + Offset(0, 4 * s), width: 90 * s, height: 18 * s),
      Paint()..color = ElevarColors.ink.withValues(alpha: 0.25),
    );
    if (active && !down) {
      final pulse = 0.5 + 0.5 * math.sin(game.clock * 5);
      canvas.drawOval(
        Rect.fromCenter(center: feet + Offset(0, 4 * s), width: 110 * s, height: 26 * s),
        _stroke(4, const Color(0xFFFFF200).withValues(alpha: 0.4 + 0.5 * pulse)),
      );
    }

    canvas.save();
    canvas.translate(feet.dx, feet.dy);
    if (down) {
      canvas.rotate(-facing * math.pi / 2 * 0.92);
    } else if (flinch > 0) {
      canvas.rotate(-facing * 0.35 * math.sin(flinch * math.pi));
    }
    Offset p(double wx, double wy) => Offset(wx * s * facing, -wy * s);
    final breathe = math.sin(game.clock * 3 + side.index * 2) * 2;

    // Scarf, streaming downwind and fluttering.
    final windDir = sim.wind >= 0 ? 1.0 : -1.0;
    final windPower = 0.35 + (sim.wind.abs() / DuelSimulation.maxWind) * 0.65;
    final neck = p(0, 132 + breathe);
    final scarf = Path()..moveTo(neck.dx, neck.dy);
    for (var i = 1; i <= 4; i++) {
      final t = i / 4;
      final flutter = math.sin(game.clock * 9 + i * 1.3) * 7 * s * t;
      scarf.lineTo(
        neck.dx + windDir * 22 * s * i * windPower,
        neck.dy + 6 * s * i * (1.2 - windPower) + flutter,
      );
    }
    canvas.drawPath(scarf, _stroke(13 * s + 5));
    canvas.drawPath(scarf, _stroke(13 * s, shirtDeep));

    // Quiver on the back, with fletchings showing.
    final quiverTop = p(-24, 150);
    final quiverBottom = p(-10, 84);
    canvas.drawLine(quiverTop, quiverBottom, _stroke(22 * s + 5));
    canvas.drawLine(quiverTop, quiverBottom, _stroke(22 * s, DuelColors.leather));
    for (var i = 0; i < 3; i++) {
      final base = quiverTop + Offset((i - 1) * 6 * s, 0);
      canvas.drawLine(base, base + p(-4 + i * 5.0, 12), _stroke(5 * s, const Color(0xFFFF3DA6)));
    }

    // Legs and boots.
    for (final dx in <double>[-13, 13]) {
      canvas.drawLine(p(dx * 0.6, 64), p(dx, 10), _stroke(19 * s + 6));
      canvas.drawLine(p(dx * 0.6, 64), p(dx, 10), _stroke(19 * s, const Color(0xFF3A3F52)));
      final boot = RRect.fromRectAndRadius(
        Rect.fromCenter(center: p(dx + 5, 6), width: 32 * s, height: 16 * s),
        Radius.circular(7 * s),
      );
      canvas.drawRRect(boot, Paint()..color = DuelColors.boots);
    }

    // Body: hoodie with a belt.
    final body = RRect.fromRectAndRadius(
      Rect.fromPoints(p(-30, 138 + breathe), p(30, 58)),
      Radius.circular(24 * s),
    );
    canvas.drawRRect(body.shift(Offset(0, 5 * s)), Paint()..color = shirtDeep);
    canvas.drawRRect(body, Paint()..color = shirt);
    canvas.drawRect(Rect.fromPoints(p(-30, 78), p(30, 68)), Paint()..color = DuelColors.leather);
    canvas.drawRect(Rect.fromCenter(center: p(0, 73), width: 12 * s, height: 10 * s),
        Paint()..color = const Color(0xFFFFD23F));
    canvas.drawRRect(body, _stroke(5));
    // A chevron on the chest, the team mark.
    canvas.drawPath(
      Path()
        ..moveTo(p(-12, 118).dx, p(-12, 118).dy)
        ..lineTo(p(0, 106).dx, p(0, 106).dy)
        ..lineTo(p(12, 118).dx, p(12, 118).dy),
      _stroke(5 * s, ElevarColors.white.withValues(alpha: 0.8)),
    );

    // Bow arm follows the aim.
    final aim = _aimFor(side);
    final shoulder = p(4, 116 + breathe);
    final dir = Offset(aim.direction.x, -aim.direction.y);
    final hand = shoulder + dir * (50 * s);
    canvas.drawLine(shoulder, hand, _stroke(15 * s + 5));
    canvas.drawLine(shoulder, hand, _stroke(15 * s, shirt));
    canvas.drawCircle(hand, 7 * s, Paint()..color = DuelColors.skin);
    _paintBow(canvas, hand, dir, aim.power, s, nocked: aim.power > 0);

    // Head: face, hood, eyes that look along the aim.
    final head = p(0, DuelSimulation.headHeight + breathe);
    final r = DuelSimulation.headRadius * s;
    canvas.drawCircle(head, r + 4, Paint()..color = ElevarColors.ink);
    canvas.drawCircle(head, r, Paint()..color = DuelColors.skin);
    canvas.drawPath(
      Path()..addArc(Rect.fromCircle(center: head, radius: r + 5), math.pi * 1.02, math.pi * 0.96),
      Paint()..color = ElevarColors.white,
    );
    canvas.drawRect(
      Rect.fromCenter(center: head - Offset(0, r * 0.3), width: r * 2.15, height: r * 0.34),
      Paint()..color = shirt,
    );
    canvas.drawCircle(head, r + 1, _stroke(4));
    final look = Offset(dir.dx * r * 0.12, dir.dy * r * 0.12);
    final eyeA = head + Offset(r * 0.38 * facing, r * 0.12) + look;
    final eyeB = head + Offset(r * -0.05 * facing, r * 0.12) + look;
    if (down) {
      for (final e in <Offset>[eyeA, eyeB]) {
        canvas.drawLine(e - Offset(4 * s, 4 * s), e + Offset(4 * s, 4 * s), _stroke(3));
        canvas.drawLine(e - Offset(-4 * s, 4 * s), e + Offset(-4 * s, 4 * s), _stroke(3));
      }
    } else {
      for (final e in <Offset>[eyeA, eyeB]) {
        canvas.drawCircle(e, r * 0.13, Paint()..color = ElevarColors.ink);
        canvas.drawCircle(e - Offset(r * 0.04, r * 0.04), r * 0.04,
            Paint()..color = ElevarColors.white);
      }
      // Brows: focused while drawing the bow.
      final frown = active ? 3.0 * s : 0.0;
      canvas.drawLine(eyeA + Offset(-6 * s, -9 * s), eyeA + Offset(6 * s, -9 * s + frown * facing), _stroke(3));
      canvas.drawLine(eyeB + Offset(-6 * s, -9 * s - frown * facing), eyeB + Offset(6 * s, -9 * s), _stroke(3));
      // Cheeks.
      canvas.drawCircle(head + Offset(r * 0.55 * facing, r * 0.45), r * 0.16,
          Paint()..color = const Color(0x55FF6B8A));
    }

    if (tint > 0.02) {
      // The hit flash: a white silhouette over the body for a beat.
      canvas.drawRRect(body, Paint()..color = ElevarColors.white.withValues(alpha: tint * 0.7));
      canvas.drawCircle(head, r, Paint()..color = ElevarColors.white.withValues(alpha: tint * 0.7));
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
    final half = 48 * s;
    final tipA = hand + normal * half - dir * (8 * s);
    final tipB = hand - normal * half - dir * (8 * s);
    final grip = hand + dir * (14 * s);
    final bow = Path()
      ..moveTo(tipA.dx, tipA.dy)
      ..quadraticBezierTo(grip.dx + dir.dx * 24 * s, grip.dy + dir.dy * 24 * s, tipB.dx, tipB.dy);
    canvas.drawPath(bow, _stroke(10 * s + 4));
    canvas.drawPath(bow, _stroke(10 * s, DuelColors.bow));
    canvas.drawPath(bow, _stroke(3 * s, const Color(0xFFC08552)));
    final pull = hand - dir * (10 * s + 36 * s * power);
    canvas.drawLine(tipA, pull, _stroke(2.2, ElevarColors.white));
    canvas.drawLine(tipB, pull, _stroke(2.2, ElevarColors.white));
    if (nocked) _paintArrowShape(canvas, pull, dir, 82 * s);
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
      final a = tail + dir * length * 0.16;
      final b = tail - dir * length * 0.02 + normal * length * 0.1 * side;
      canvas.drawLine(a, b, _stroke(length * 0.06, const Color(0xFFFF3DA6)));
    }
  }

  // --- aiming, flight, effects ---------------------------------------------

  void _paintPreview(Canvas canvas) {
    final sim = game.simulation;
    final aim = game.liveAim;
    if (aim == null) return;
    // Only the opening of the arc: enough to judge an angle, not enough to
    // solve the shot. Wind is included, because the wind is on the screen.
    var pos = sim.launchPoint(sim.turn);
    var v = aim.direction * (aim.power * DuelSimulation.maxSpeed);
    const dt = 1 / 30;
    for (var i = 0; i < 16; i++) {
      v = Vec2(v.x + sim.wind * dt, v.y - DuelSimulation.gravity * dt);
      pos = pos + v * dt;
      if (pos.y < sim.terrain.heightAt(pos.x)) break;
      final screen = game.toScreen(pos);
      final fade = 1 - i / 16;
      canvas.drawCircle(screen, 6 + 3 * fade, Paint()..color = ElevarColors.ink.withValues(alpha: 0.25 * fade));
      canvas.drawCircle(screen, 5 + 3 * fade, Paint()..color = ElevarColors.white.withValues(alpha: 0.95 * fade));
    }

    // A force gauge arcing around the archer, green to red.
    final centre = game.toScreen(Vec2(DuelSimulation.xOf(sim.turn), sim.groundOf(sim.turn) + 100));
    final radius = 118 * game.scale;
    final rect = Rect.fromCircle(center: centre, radius: radius);
    canvas.drawArc(rect, math.pi * 0.75, math.pi * 1.5, false,
        _stroke(12, ElevarColors.ink.withValues(alpha: 0.35)));
    final colour = Color.lerp(
      const Color(0xFF3DFF6E),
      aim.power < 0.7 ? const Color(0xFFFFE14D) : const Color(0xFFFF4D4D),
      aim.power < 0.7 ? aim.power / 0.7 : (aim.power - 0.7) / 0.3,
    )!;
    canvas.drawArc(rect, math.pi * 0.75, math.pi * 1.5 * aim.power, false, _stroke(8, colour));

    final angle = (math.atan2(aim.direction.y, aim.direction.x.abs()) * 180 / math.pi).round();
    final at = game.toScreen(sim.headCentre(sim.turn)) + Offset(0, -70 * game.scale - 44);
    _pill(canvas, '${(aim.power * 100).round()}%  FORCE   $angle°  ANGLE', at);
  }

  void _paintArrow(Canvas canvas) {
    final sim = game.simulation;
    if (!sim.arrowFlying) return;
    // A tapering streak rather than dots.
    final trail = game.arrowTrail;
    for (var i = 1; i < trail.length; i++) {
      final t = i / trail.length;
      canvas.drawLine(
        game.toScreen(trail[i - 1]),
        game.toScreen(trail[i]),
        _stroke(1 + 5 * t, ElevarColors.white.withValues(alpha: 0.55 * t)),
      );
    }
    final at = sim.arrowPrevious + (sim.arrow - sim.arrowPrevious) * game.interpolation;
    final v = sim.arrowVelocity.normalized;
    final dir = Offset(v.x, -v.y);
    final length = 92 * game.scale;
    _paintArrowShape(canvas, game.toScreen(at) - dir * length, dir, length);
  }

  void _paintStuck(Canvas canvas) {
    for (final arrow in game.simulation.stuck) {
      var dir = Offset(arrow.direction.x, -arrow.direction.y);
      final quiver = game.wobble[arrow] ?? 0;
      if (quiver > 0.01) {
        // Twang: a fast, decaying rotation about the buried tip.
        final a = math.sin(game.clock * 55) * 0.18 * quiver;
        dir = Offset(dir.dx * math.cos(a) - dir.dy * math.sin(a),
            dir.dx * math.sin(a) + dir.dy * math.cos(a));
      }
      final length = 92 * game.scale;
      final tipScreen = game.toScreen(arrow.at) + dir * (length * 0.3);
      _paintArrowShape(canvas, tipScreen - dir * length, dir, length);
    }
  }

  void _paintParticles(Canvas canvas) {
    for (final part in game.particles) {
      final fade = clampD(part.life / part.maxLife, 0, 1);
      canvas.drawCircle(game.toScreen(part.position), part.size * fade,
          Paint()..color = part.colour.withValues(alpha: fade));
    }
  }

  void _paintWind(Canvas canvas, Size size) {
    final snow = theme.snowing;
    for (final bit in game.windBits) {
      final at = Offset(bit.x * size.width, bit.y * size.height);
      if (snow) {
        canvas.drawCircle(at, 3.2 * bit.size + 1, Paint()..color = theme.windBits.withValues(alpha: 0.85));
      } else {
        canvas.save();
        canvas.translate(at.dx, at.dy);
        canvas.rotate(bit.phase);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 12 * bit.size, height: 5 * bit.size),
          Paint()..color = theme.windBits.withValues(alpha: 0.8),
        );
        canvas.restore();
      }
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
  /// the distance — the reference does exactly this.
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
      canvas.drawRRect(rect.shift(const Offset(0, 4)), Paint()..color = ElevarColors.ink);
      canvas.drawRRect(rect, Paint()..color = ElevarColors.white);
      canvas.drawRRect(rect, _stroke(4));
      canvas.drawCircle(Offset(x, y - 8), 14, Paint()..color = colour);
      canvas.drawCircle(Offset(x, y - 8), 14, _stroke(3));
      final label = _painter('${metres}m', 13, ElevarColors.ink);
      label.paint(canvas, Offset(x - label.width / 2, y + 10));
      // A pointer toward the archer.
      final tip = Offset(left ? x - 38 : x + 38, y);
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(left ? x - 26 : x + 26, y - 9)
          ..lineTo(left ? x - 26 : x + 26, y + 9)
          ..close(),
        Paint()..color = ElevarColors.white,
      );
    }
  }

  void _pill(Canvas canvas, String text, Offset center) {
    final painter = _painter(text, 16, ElevarColors.ink);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: painter.width + 26, height: painter.height + 14),
      const Radius.circular(14),
    );
    canvas.drawRRect(rect.shift(const Offset(0, 4)), Paint()..color = ElevarColors.ink);
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
