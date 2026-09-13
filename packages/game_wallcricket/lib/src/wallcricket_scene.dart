import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flame/components.dart';
import 'package:flutter/widgets.dart';
import 'package:game_core/game_core.dart';
import 'package:wallcricket_sim/wallcricket_sim.dart';

import 'wallcricket_game.dart';

/// The palette for the nets room.
abstract final class WallCricketColors {
  static const Color backdrop = Color(0xFF14213D);
  static const Color wall = Color(0xFF2E6FD8);
  static const Color wallPanel = Color(0xFF3B7FE6);
  static const Color turf = Color(0xFF4EB537);
  static const Color turfDeep = Color(0xFF3F9A2C);
  static const Color pitch = Color(0xFFE3C58D);
  static const Color crease = Color(0xFFFFFFFF);
  static const Color wood = Color(0xFFF2D7A0);
  static const Color woodDeep = Color(0xFFC99B55);
  static const Color grip = Color(0xFF1B1B1B);
  static const Color shirt = ElevarColors.p1;
  static const Color shirtDeep = ElevarColors.p1Deep;
  static const Color pads = Color(0xFFFFFFFF);
  static const Color helmet = Color(0xFF1D2B53);
  static const Color skin = Color(0xFFE0A878);
  static const Color ball = Color(0xFFD7263D);
  static const Color machine = Color(0xFF9AA5B1);
  static const Color machineDeep = Color(0xFF5F6B78);

  static Color forRuns(int runs) => switch (runs) {
        6 => const Color(0xFFFF3DA6),
        4 => const Color(0xFF29C7F0),
        2 => const Color(0xFF27D6A2),
        _ => const Color(0xFFFFE14D),
      };
}

/// Paints the whole room in one component, in a fixed draw order.
class WallCricketScene extends Component {
  WallCricketScene({required this.game});

  final WallCricketGame game;

  static const double _outline = 7;
  final Map<String, TextPainter> _text = <String, TextPainter>{};
  double _time = 0;

  @override
  void update(double dt) {
    _time += dt;
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      Offset.zero & Size(game.size.x, game.size.y),
      Paint()..color = WallCricketColors.backdrop,
    );

    canvas.save();
    canvas.translate(
      game.fieldOrigin.dx + game.shakeOffset.dx,
      game.fieldOrigin.dy + game.shakeOffset.dy,
    );
    canvas.scale(game.fieldScale);
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-20, -20, Arena.width + 40, Arena.height + 40),
        const Radius.circular(40),
      ),
    );

    _paintRoom(canvas);
    _paintZones(canvas);
    _paintGround(canvas);
    _paintMachine(canvas);
    _paintStumps(canvas);
    _paintBatter(canvas);
    _paintSwoosh(canvas);
    _paintBat(canvas);
    _paintBall(canvas);
    _paintParticles(canvas);
    _paintFloaters(canvas);

    canvas.restore();

    if (game.flash > 0.01) {
      canvas.drawRect(
        Offset.zero & Size(game.size.x, game.size.y),
        Paint()..color = ElevarColors.white.withValues(alpha: game.flash * 0.4),
      );
    }
  }

  void _paintRoom(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, Arena.width, Arena.groundY),
      Paint()..color = WallCricketColors.wall,
    );
    // Big soft panels on the back wall, so the ball has something to be seen
    // moving against.
    final panel = Paint()..color = WallCricketColors.wallPanel;
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(90 + col * 285.0, 110 + row * 400.0, 250, 360),
            const Radius.circular(26),
          ),
          panel,
        );
      }
    }
    // Netting lines, faint.
    final net = Paint()
      ..color = ElevarColors.white.withValues(alpha: 0.06)
      ..strokeWidth = 3;
    for (var x = 0.0; x <= Arena.width; x += 50) {
      canvas.drawLine(Offset(x, 0), Offset(x, Arena.groundY), net);
    }
    for (var y = 0.0; y <= Arena.groundY; y += 50) {
      canvas.drawLine(Offset(0, y), Offset(Arena.width, y), net);
    }
    _label(canvas, 'ELEVAR NETS', const Offset(500, 760), 70,
        ElevarColors.white.withValues(alpha: 0.12));
  }

  void _paintZones(Canvas canvas) {
    const band = 34.0;
    for (var i = 0; i < Arena.zones.length; i++) {
      final zone = Arena.zones[i];
      final hot = i == game.simulation.hotZone;
      final glowing = game.glowZone == i ? game.wallGlow : 0.0;
      final colour = WallCricketColors.forRuns(zone.runs);

      final Rect rect;
      final Offset labelAt;
      switch (zone.wall) {
        case Wall.ceiling:
          rect = Rect.fromLTRB(zone.from, -10, zone.to, band);
          labelAt = Offset((zone.from + zone.to) / 2, band + 62);
        case Wall.right:
          rect = Rect.fromLTRB(Arena.width - band, zone.from, Arena.width + 10,
              zone.to);
          labelAt = Offset(Arena.width - band - 62, (zone.from + zone.to) / 2);
        case Wall.left:
          rect = Rect.fromLTRB(-10, zone.from, band, zone.to);
          labelAt = Offset(band + 50, (zone.from + zone.to) / 2);
        case Wall.machine:
          continue;
      }

      canvas.drawRect(rect, Paint()..color = colour);
      if (glowing > 0.02) {
        canvas.drawRect(
          rect.inflate(40 * glowing),
          Paint()..color = colour.withValues(alpha: 0.45 * glowing),
        );
      }
      canvas.drawRect(
        rect,
        Paint()
          ..color = ElevarColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );

      final pulse = hot ? 1 + 0.12 * math.sin(_time * 7) : 1.0;
      _chip(
        canvas,
        hot ? '${zone.runs}×2' : '${zone.runs}',
        labelAt,
        (hot ? 50 : 44) * pulse,
        hot ? const Color(0xFFFFF200) : colour,
      );
    }

    // Dividers between zones on each wall.
    final divider = Paint()
      ..color = ElevarColors.ink
      ..strokeWidth = 6;
    for (final zone in Arena.zones) {
      if (zone.wall == Wall.ceiling) {
        canvas.drawLine(Offset(zone.from, 0), Offset(zone.from, band), divider);
      } else if (zone.wall == Wall.right) {
        canvas.drawLine(Offset(Arena.width - band, zone.from),
            Offset(Arena.width, zone.from), divider);
      }
    }
  }

  void _paintGround(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, Arena.groundY, Arena.width, Arena.height),
      Paint()..color = WallCricketColors.turf,
    );
    for (var x = 0.0; x < Arena.width; x += 120) {
      canvas.drawRect(
        Rect.fromLTWH(x, Arena.groundY + 40, 60, Arena.height),
        Paint()..color = WallCricketColors.turfDeep,
      );
    }
    // The strip, seen side on: a thin tan edge along the top of the turf.
    canvas.drawRect(
      const Rect.fromLTWH(40, Arena.groundY - 4, 880, 26),
      Paint()..color = WallCricketColors.pitch,
    );
    canvas.drawRect(
      const Rect.fromLTWH(318, Arena.groundY - 4, 8, 26),
      Paint()..color = WallCricketColors.crease,
    );
    canvas.drawLine(
      const Offset(0, Arena.groundY),
      const Offset(Arena.width, Arena.groundY),
      Paint()
        ..color = ElevarColors.ink
        ..strokeWidth = 6,
    );
  }

  void _paintMachine(Canvas canvas) {
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTRB(
          Arena.machineLeft, Arena.machineTop, Arena.width + 20, Arena.machineBottom),
      const Radius.circular(22),
    );
    canvas.drawRRect(body.shift(const Offset(0, 8)),
        Paint()..color = WallCricketColors.machineDeep);
    canvas.drawRRect(body, Paint()..color = WallCricketColors.machine);
    canvas.drawRRect(
      body,
      Paint()
        ..color = ElevarColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = _outline,
    );
    // The mouth.
    canvas.drawCircle(Offset(Arena.machineMouth.x + 20, Arena.machineMouth.y),
        30, Paint()..color = ElevarColors.ink);

    // The light: red while loading, blinking amber in the windup, green on
    // release. This is the only warning a batter gets, so it has to be loud.
    final sim = game.simulation;
    final Color light;
    if (sim.phase == WallCricketPhase.windup) {
      final blink = (sim.windupProgress * 6).floor().isEven;
      light = sim.windupProgress > 0.8
          ? const Color(0xFF3DFF6E)
          : (blink ? const Color(0xFFFFB020) : const Color(0xFF6B4A10));
    } else if (sim.phase == WallCricketPhase.live) {
      light = const Color(0xFF3DFF6E);
    } else {
      light = const Color(0xFFFF3B3B);
    }
    const lightAt = Offset(950, Arena.machineTop - 34);
    canvas.drawCircle(lightAt, 30, Paint()..color = light);
    canvas.drawCircle(
      lightAt,
      30,
      Paint()
        ..color = ElevarColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    _chip(canvas, '6', const Offset(945, Arena.machineBottom + 34), 30,
        WallCricketColors.forRuns(6));
  }

  void _paintStumps(Canvas canvas) {
    final fly = game.stumpsFly;
    const height = Arena.groundY - Arena.stumpsTop;
    for (var i = 0; i < 3; i++) {
      final x = Arena.stumpsLeft + 6 + i * 14.0;
      canvas.save();
      canvas.translate(x, Arena.groundY);
      if (fly > 0) {
        final t = 1 - fly;
        canvas.translate(-t * (80 + i * 40), -t * 160 + t * t * 260);
        canvas.rotate(-t * (1.2 + i * 0.6));
      }
      final stump = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-6, -height, 12, height),
        const Radius.circular(5),
      );
      canvas.drawRRect(stump, Paint()..color = WallCricketColors.wood);
      canvas.drawRRect(
        stump,
        Paint()
          ..color = ElevarColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
      canvas.restore();
    }
    // Bails.
    final bailY = Arena.stumpsTop - 6 - (fly > 0 ? (1 - fly) * 300 : 0);
    final bail = RRect.fromRectAndRadius(
      Rect.fromLTWH(Arena.stumpsLeft - 2 - (fly > 0 ? (1 - fly) * 140 : 0),
          bailY, 44, 10),
      const Radius.circular(5),
    );
    canvas.drawRRect(bail, Paint()..color = WallCricketColors.woodDeep);
    canvas.drawRRect(
      bail,
      Paint()
        ..color = ElevarColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  void _paintBatter(Canvas canvas) {
    final outline = Paint()
      ..color = ElevarColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = _outline
      ..strokeJoin = StrokeJoin.round;
    const hip = Offset(196, 1262);
    final swing = game.simulation.swing;

    // Legs with pads. The front foot strides toward the ball as the swing
    // comes through.
    final stride = clampD((swing - 0.3) * 1.6, 0, 1) * 44;
    for (final foot in <Offset>[const Offset(168, 1416), Offset(246 + stride, 1416)]) {
      final leg = Path()
        ..moveTo(hip.dx - 20, hip.dy)
        ..lineTo(foot.dx - 18, foot.dy)
        ..lineTo(foot.dx + 22, foot.dy)
        ..lineTo(hip.dx + 20, hip.dy)
        ..close();
      canvas.drawPath(leg, Paint()..color = WallCricketColors.pads);
      canvas.drawPath(leg, outline);
      final shoe = RRect.fromRectAndRadius(
        Rect.fromLTWH(foot.dx - 24, foot.dy - 16, 58, 22),
        const Radius.circular(10),
      );
      canvas.drawRRect(shoe, Paint()..color = ElevarColors.ink);
    }

    // The body goes with the swing: rocked back in the backlift, leaning
    // over the front foot through the shot.
    final lean = (swing - 0.35) * 34;
    final torso = RRect.fromRectAndRadius(
      Rect.fromLTWH(154 + lean, 1112, 92, 160),
      const Radius.circular(34),
    );
    canvas.drawRRect(torso.shift(const Offset(0, 6)),
        Paint()..color = WallCricketColors.shirtDeep);
    canvas.drawRRect(torso, Paint()..color = WallCricketColors.shirt);
    canvas.drawRRect(torso, outline);
    _label(canvas, '10', Offset(200 + lean, 1190), 40,
        ElevarColors.white.withValues(alpha: 0.9));

    // Arm from the shoulder to the hands on the handle.
    final shoulder = Offset(214 + lean, 1140);
    final hands = Offset(Arena.pivot.x, Arena.pivot.y);
    canvas.drawLine(
      shoulder,
      hands,
      Paint()
        ..color = ElevarColors.ink
        ..strokeWidth = 34
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      shoulder,
      hands,
      Paint()
        ..color = WallCricketColors.shirt
        ..strokeWidth = 22
        ..strokeCap = StrokeCap.round,
    );

    // Head and helmet.
    final head = Offset(198 + lean, 1062);
    canvas.drawCircle(head, 44, Paint()..color = WallCricketColors.skin);
    final helmet = Path()
      ..addArc(Rect.fromCircle(center: head, radius: 48), math.pi, math.pi)
      ..lineTo(head.dx + 60, head.dy - 2)
      ..close();
    canvas.drawPath(helmet, Paint()..color = WallCricketColors.helmet);
    canvas.drawCircle(head, 44, outline);
    // Grille.
    final grille = Paint()
      ..color = ElevarColors.ink
      ..strokeWidth = 5;
    for (var i = 0; i < 3; i++) {
      canvas.drawLine(Offset(head.dx + 14, head.dy + 4 + i * 12),
          Offset(head.dx + 46, head.dy + 4 + i * 12), grille);
    }
    canvas.drawCircle(Offset(head.dx + 10, head.dy - 6), 5,
        Paint()..color = ElevarColors.ink);
  }

  void _paintSwoosh(Canvas canvas) {
    final trail = game.batTrail;
    if (trail.length < 2) return;
    for (var i = 1; i < trail.length; i++) {
      final speed = trail[i].speed;
      if (speed < 2200) continue;
      final alpha = clampD((speed - 2200) / 6000, 0, 0.55) * (i / trail.length);
      final path = Path()
        ..moveTo(Arena.pivot.x, Arena.pivot.y)
        ..lineTo(trail[i - 1].tip.x, trail[i - 1].tip.y)
        ..lineTo(trail[i].tip.x, trail[i].tip.y)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = ElevarColors.white.withValues(alpha: alpha),
      );
    }
  }

  void _paintBat(Canvas canvas) {
    final sim = game.simulation;
    final alpha = game.interpolation;
    final direction =
        (sim.batPrevious + (sim.batDirection - sim.batPrevious) * alpha)
            .normalized;
    final normal = Vec2(-direction.y, direction.x);
    const pivot = Arena.pivot;
    final bladeStart = pivot + direction * (Arena.batLength * Arena.bladeFrom);
    final tip = pivot + direction * Arena.batLength;

    // Grip.
    canvas.drawLine(
      Offset(pivot.x - direction.x * 20, pivot.y - direction.y * 20),
      Offset(bladeStart.x, bladeStart.y),
      Paint()
        ..color = WallCricketColors.grip
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round,
    );

    // Blade: slightly wider toward the toe, like the real thing.
    final a = bladeStart + normal * 15;
    final b = tip + normal * 21;
    final c = tip - normal * 17;
    final d = bladeStart - normal * 13;
    final blade = Path()
      ..moveTo(a.x, a.y)
      ..lineTo(b.x, b.y)
      ..lineTo(c.x, c.y)
      ..lineTo(d.x, d.y)
      ..close();
    canvas.drawPath(blade, Paint()..color = WallCricketColors.wood);
    // Sweet spot band.
    final s1 = pivot + direction * (Arena.batLength * Arena.sweetFrom);
    final s2 = pivot + direction * (Arena.batLength * Arena.sweetTo);
    canvas.drawLine(
      Offset(s1.x, s1.y),
      Offset(s2.x, s2.y),
      Paint()
        ..color = WallCricketColors.woodDeep.withValues(alpha: 0.55)
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      blade,
      Paint()
        ..color = ElevarColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeJoin = StrokeJoin.round,
    );
    // Hands over the grip.
    canvas.drawCircle(Offset(pivot.x, pivot.y), 20,
        Paint()..color = ElevarColors.white);
    canvas.drawCircle(
      Offset(pivot.x, pivot.y),
      20,
      Paint()
        ..color = ElevarColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
  }

  void _paintBall(Canvas canvas) {
    final sim = game.simulation;
    if (!sim.ballVisible) {
      // Loaded in the machine: peek it out of the mouth during the windup.
      if (sim.phase == WallCricketPhase.windup) {
        _drawBall(canvas, Offset(Arena.machineMouth.x + 24, Arena.machineMouth.y),
            sim.windupProgress);
      }
      return;
    }
    for (var i = 0; i < game.ballTrail.length; i++) {
      final t = (i + 1) / game.ballTrail.length;
      final p = game.ballTrail[i];
      canvas.drawCircle(
        Offset(p.x, p.y),
        Arena.ballRadius * t,
        Paint()..color = WallCricketColors.ball.withValues(alpha: t * 0.25),
      );
    }
    final p = sim.ballPrevious + (sim.ballPosition - sim.ballPrevious) * game.interpolation;

    // Shadow on the turf, shrinking with height so depth reads side on.
    final height = clampD((Arena.groundY - p.y) / 900, 0, 1);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(p.x, Arena.groundY + 6),
        width: 46 * (1 - height * 0.6),
        height: 12 * (1 - height * 0.6),
      ),
      Paint()..color = ElevarColors.ink.withValues(alpha: 0.35 * (1 - height)),
    );
    _drawBall(canvas, Offset(p.x, p.y), sim.tick / 8.0);
  }

  void _drawBall(Canvas canvas, Offset at, double spin) {
    const r = Arena.ballRadius + 4;
    canvas.drawCircle(at, r, Paint()..color = WallCricketColors.ball);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(spin);
    canvas.drawLine(
      const Offset(-r * 0.8, 0),
      const Offset(r * 0.8, 0),
      Paint()
        ..color = ElevarColors.white.withValues(alpha: 0.85)
        ..strokeWidth = 3,
    );
    canvas.restore();
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..color = ElevarColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    canvas.drawCircle(at.translate(-7, -7), 5,
        Paint()..color = ElevarColors.white.withValues(alpha: 0.6));
  }

  void _paintParticles(Canvas canvas) {
    for (final p in game.particles) {
      canvas.drawCircle(
        Offset(p.position.x, p.position.y),
        p.size * p.fade,
        Paint()..color = p.colour.withValues(alpha: p.fade),
      );
    }
  }

  void _paintFloaters(Canvas canvas) {
    for (final f in game.floaters) {
      final t = f.age / 1.1;
      final scale = t < 0.15 ? 0.6 + t / 0.15 * 0.6 : 1.2 - (t - 0.15) * 0.3;
      final at = Offset(
        clampD(f.at.x, 120, Arena.width - 140),
        clampD(f.at.y + 120 - t * 160, 150, Arena.groundY - 100),
      );
      _chip(canvas, f.text, at, 70 * scale, f.colour,
          alpha: clampD(1.6 - t * 1.6, 0, 1));
    }
  }

  // --- text ----------------------------------------------------------------

  TextPainter _painter(String text, double size, Color colour) {
    final key = '$text|${size.round()}|${colour.toARGB32()}';
    return _text.putIfAbsent(key, () {
      if (_text.length > 200) _text.clear();
      return TextPainter(
        text: TextSpan(text: text, style: ElevarType.display(size, color: colour)),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  void _label(Canvas canvas, String text, Offset center, double size, Color colour) {
    final painter = _painter(text, size, colour);
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  /// A number in a chunky outlined pill.
  void _chip(Canvas canvas, String text, Offset center, double size, Color colour,
      {double alpha = 1}) {
    final painter = _painter(text, size, ElevarColors.ink);
    final rect = Rect.fromCenter(
      center: center,
      width: painter.width + size * 0.7,
      height: painter.height + size * 0.25,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(size * 0.45));
    // A layer only when fading: saveLayer is an offscreen pass, and eight
    // opaque wall numbers do not need one every frame.
    final layered = alpha < 0.99;
    if (layered) {
      canvas.saveLayer(
          rect.inflate(20), Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    } else {
      canvas.save();
    }
    canvas.drawRRect(rrect.shift(const Offset(0, 6)), Paint()..color = ElevarColors.ink);
    canvas.drawRRect(rrect, Paint()..color = colour);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = ElevarColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2 - 2));
    canvas.restore();
  }
}
