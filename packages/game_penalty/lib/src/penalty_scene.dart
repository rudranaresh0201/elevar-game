import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flame/components.dart';
import 'package:flutter/widgets.dart';
import 'package:game_core/game_core.dart';
import 'package:penalty_sim/penalty_sim.dart';

import 'camera.dart';
import 'penalty_game.dart';

abstract final class PenaltyColors {
  static const Color sky = Color(0xFF0E1A3A);
  static const Color skyLow = Color(0xFF1B2E63);
  static const Color stand = Color(0xFF26345E);
  static const Color turf = Color(0xFF3FAE3A);
  static const Color turfBand = Color(0xFF379A33);
  static const Color line = Color(0xFFFFFFFF);
  static const Color net = Color(0xFFE8F1F8);
  static const Color board = Color(0xFF111111);
  static const Color boardText = Color(0xFFFFF200);
  static const Color keeperShirt = Color(0xFFB6F23A);
  static const Color keeperShirtDeep = Color(0xFF7FB514);
  static const Color gloves = Color(0xFFFFFFFF);
  static const Color skin = Color(0xFFD99A6C);
  static const Color p1 = ElevarColors.p1;
  static const Color p2 = Color(0xFF29B6F0);
}

/// Paints the stadium, the goal, the keeper, the kicker and the ball.
class PenaltyScene extends Component {
  PenaltyScene({required this.game});

  final PenaltyGame game;
  final Map<String, TextPainter> _text = <String, TextPainter>{};
  double _time = 0;

  static final Paint _ink = Paint()
    ..color = ElevarColors.ink
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  PenaltyCamera get cam => game.camera3d;

  @override
  void update(double dt) => _time += dt;

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(game.shakeOffset.dx, game.shakeOffset.dy);
    _paintSky(canvas);
    _paintStands(canvas);
    _paintPitch(canvas);
    _paintNetBack(canvas);

    // The keeper stands in front of the back netting and behind the posts'
    // front face only when the ball is beyond him; drawing him before the
    // frame is right for every shot that matters.
    final ballBehindKeeper = game.simulation.ball.z < Goal.keeperZ;
    if (ballBehindKeeper) _paintBall(canvas);
    _paintKeeper(canvas);
    _paintFrame(canvas);
    _paintDiveMarker(canvas);
    _paintAimMarker(canvas);
    _paintKicker(canvas);
    if (!ballBehindKeeper) _paintBall(canvas);
    _paintSwipe(canvas);
    _paintConfetti(canvas);
    canvas.restore();

    if (game.flash > 0.01) {
      canvas.drawRect(
        Offset.zero & Size(game.size.x, game.size.y),
        Paint()..color = ElevarColors.white.withValues(alpha: game.flash * 0.35),
      );
    }
  }

  void _paintSky(Canvas canvas) {
    final w = game.size.x;
    final h = game.size.y;
    canvas.drawRect(Offset.zero & Size(w, h), Paint()..color = PenaltyColors.sky);
    canvas.drawRect(
      Rect.fromLTWH(0, cam.horizon * 0.45, w, h),
      Paint()..color = PenaltyColors.skyLow,
    );
    // Floodlights.
    for (final x in <double>[w * 0.12, w * 0.88]) {
      final at = Offset(x, cam.horizon * 0.18);
      canvas.drawCircle(at, 60, Paint()..color = const Color(0x22FFFFFF));
      canvas.drawCircle(at, 30, Paint()..color = const Color(0x44FFFFFF));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: at, width: 46, height: 22), const Radius.circular(6)),
        Paint()..color = const Color(0xFFFFF7D6),
      );
    }
  }

  void _paintStands(Canvas canvas) {
    final w = game.size.x;
    final top = cam.horizon * 0.42;
    final bottom = cam.at(0, 0.7, -7).dy;
    canvas.drawRect(
      Rect.fromLTRB(0, top, w, bottom),
      Paint()..color = PenaltyColors.stand,
    );
    // The crowd: rows of heads, bobbing a little after a goal.
    const colours = <Color>[
      Color(0xFFFF2B2B),
      Color(0xFFFFFFFF),
      Color(0xFF29B6F0),
      Color(0xFFFFF200),
      Color(0xFF3DFF6E),
      Color(0xFFFF9F1C),
    ];
    final rng = math.Random(21);
    final cheer = game.netBulge;
    for (var row = 0; row < 7; row++) {
      final y = top + 12 + row * ((bottom - top - 16) / 7);
      for (var x = 6.0; x < w; x += 14) {
        final bob = cheer > 0.05
            ? math.sin(_time * 18 + x * 0.3 + row) * 5 * cheer
            : 0.0;
        canvas.drawCircle(
          Offset(x + (row.isEven ? 0 : 7), y + bob),
          5,
          Paint()
            ..color = colours[rng.nextInt(colours.length)]
                .withValues(alpha: 0.55 + 0.1 * row / 7),
        );
      }
    }
    // Ad boards.
    final boardTop = cam.at(0, 0.7, -7).dy;
    final boardBottom = cam.at(0, 0, -7).dy;
    canvas.drawRect(
      Rect.fromLTRB(0, boardTop, w, boardBottom),
      Paint()..color = PenaltyColors.board,
    );
    final boardHeight = boardBottom - boardTop;
    final painter = _painter('ELEVAR  ·  PLAY  ·  ', boardHeight * 0.62,
        PenaltyColors.boardText);
    final scroll = (_time * 40) % painter.width;
    for (var x = -scroll; x < w; x += painter.width) {
      painter.paint(canvas,
          Offset(x, boardTop + (boardHeight - painter.height) / 2));
    }
  }

  void _paintPitch(Canvas canvas) {
    final w = game.size.x;
    final top = cam.at(0, 0, -7).dy;
    canvas.drawRect(
      Rect.fromLTRB(0, top, w, game.size.y),
      Paint()..color = PenaltyColors.turf,
    );
    // Mown bands across the pitch, in perspective.
    for (var z = -3.0; z < 17; z += 2) {
      if (((z + 3) / 2).round().isOdd) continue;
      final a = cam.at(-30, 0, z);
      final b = cam.at(30, 0, z);
      final c = cam.at(30, 0, z + 1);
      final d = cam.at(-30, 0, z + 1);
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(c.dx, c.dy)
          ..lineTo(d.dx, d.dy)
          ..close(),
        Paint()..color = PenaltyColors.turfBand,
      );
    }
    final line = Paint()
      ..color = PenaltyColors.line.withValues(alpha: 0.9)
      ..strokeWidth = 3;
    void seg(double x1, double z1, double x2, double z2) =>
        canvas.drawLine(cam.at(x1, 0, z1), cam.at(x2, 0, z2), line);
    seg(-30, 0, 30, 0);
    // Six-yard box.
    seg(-9.16, 0, -9.16, 5.5);
    seg(9.16, 0, 9.16, 5.5);
    seg(-9.16, 5.5, 9.16, 5.5);
    // Penalty spot.
    final (spot, spotScale) = cam.project(0, 0, Goal.spotZ);
    canvas.drawOval(
      Rect.fromCenter(center: spot, width: 0.4 * spotScale, height: 0.12 * spotScale),
      Paint()..color = PenaltyColors.line,
    );
  }

  /// Where a net point sits, bulged back if the ball has just gone in.
  Offset _net(double x, double y, double z) {
    final at = game.bulgeAt;
    var push = 0.0;
    if (at != null && game.netBulge > 0.02 && z < -0.1) {
      final dx = x - at.x;
      final dy = y - at.y;
      final falloff = math.exp(-(dx * dx + dy * dy) / 1.2);
      push = 0.9 * game.netBulge * falloff;
    }
    return cam.at(x, y, z - push);
  }

  void _paintNetBack(Canvas canvas) {
    const back = -Goal.netDepth;
    const w = Goal.halfWidth;
    const h = Goal.height;
    // Back panel fill.
    final panel = Path()
      ..moveTo(_net(-w, 0, back).dx, _net(-w, 0, back).dy)
      ..lineTo(_net(w, 0, back).dx, _net(w, 0, back).dy)
      ..lineTo(_net(w, h - 0.3, back).dx, _net(w, h - 0.3, back).dy)
      ..lineTo(_net(-w, h - 0.3, back).dx, _net(-w, h - 0.3, back).dy)
      ..close();
    canvas.drawPath(panel, Paint()..color = const Color(0x22FFFFFF));

    final mesh = Paint()
      ..color = PenaltyColors.net.withValues(alpha: 0.5)
      ..strokeWidth = 1.2;
    const cells = 18;
    for (var i = 0; i <= cells; i++) {
      final x = -w + 2 * w * i / cells;
      _polyline(canvas, <Offset>[
        for (var j = 0; j <= 6; j++) _net(x, (h - 0.3) * j / 6, back),
      ], mesh);
      // Roof lines from the bar back to the net.
      canvas.drawLine(cam.at(x, h, 0), _net(x, h - 0.3, back), mesh);
    }
    for (var j = 0; j <= 6; j++) {
      final y = (h - 0.3) * j / 6;
      _polyline(canvas, <Offset>[
        for (var i = 0; i <= cells; i++) _net(-w + 2 * w * i / cells, y, back),
      ], mesh);
    }
    // Side netting.
    for (final side in <double>[-w, w]) {
      for (var j = 0; j <= 6; j++) {
        final y = h * j / 6;
        canvas.drawLine(cam.at(side, y, 0), _net(side, y * (h - 0.3) / h, back), mesh);
      }
      for (var k = 0; k <= 4; k++) {
        final z = back * k / 4;
        canvas.drawLine(
            cam.at(side, 0, z), cam.at(side, h - 0.3 * k / 4, z), mesh);
      }
    }
  }

  void _polyline(Canvas canvas, List<Offset> points, Paint paint) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint..style = PaintingStyle.stroke);
    paint.style = PaintingStyle.fill;
  }

  void _paintFrame(Canvas canvas) {
    final (bl, scale) = cam.project(-Goal.halfWidth, 0, 0);
    final tl = cam.at(-Goal.halfWidth, Goal.height, 0);
    final tr = cam.at(Goal.halfWidth, Goal.height, 0);
    final br = cam.at(Goal.halfWidth, 0, 0);
    final thickness = Goal.postRadius * 2 * scale;
    final frame = Path()
      ..moveTo(bl.dx, bl.dy)
      ..lineTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy);
    canvas.drawPath(
      frame,
      Paint()
        ..color = ElevarColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness + 5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      frame,
      Paint()
        ..color = PenaltyColors.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _paintKeeper(Canvas canvas) {
    final sim = game.simulation;
    final body = sim.keeperBody();
    final (a, scale) = cam.project(body.a.x, body.a.y, Goal.keeperZ);
    final b = cam.at(body.b.x, body.b.y, Goal.keeperZ);
    final axis = b - a;
    final length = axis.distance;
    if (length < 1) return;
    final dir = axis / length;
    final normal = Offset(-dir.dy, dir.dx);
    final mid = a + axis * 0.48;

    // Shadow on the grass.
    final shadow = cam.at(sim.keeper.x, 0, Goal.keeperZ);
    canvas.drawOval(
      Rect.fromCenter(center: shadow, width: 1.2 * scale, height: 0.18 * scale),
      Paint()..color = ElevarColors.ink.withValues(alpha: 0.3),
    );

    final outline = _ink..strokeWidth = 4;
    // Legs.
    for (final side in <double>[-1, 1]) {
      final hip = mid + normal * (0.12 * scale * side);
      final foot = a + normal * (0.2 * scale * side);
      canvas.drawLine(hip, foot, Paint()
        ..color = ElevarColors.ink
        ..strokeWidth = 0.22 * scale + 4
        ..strokeCap = StrokeCap.round);
      canvas.drawLine(hip, foot, Paint()
        ..color = const Color(0xFF1B1B1B)
        ..strokeWidth = 0.22 * scale
        ..strokeCap = StrokeCap.round);
    }
    // Torso.
    final chest = a + axis * 0.8;
    final torso = Path()
      ..moveTo((mid + normal * 0.24 * scale).dx, (mid + normal * 0.24 * scale).dy)
      ..lineTo((chest + normal * 0.28 * scale).dx, (chest + normal * 0.28 * scale).dy)
      ..lineTo((chest - normal * 0.28 * scale).dx, (chest - normal * 0.28 * scale).dy)
      ..lineTo((mid - normal * 0.24 * scale).dx, (mid - normal * 0.24 * scale).dy)
      ..close();
    canvas.drawPath(torso, Paint()..color = PenaltyColors.keeperShirt);
    canvas.drawPath(torso, outline);
    // Arms out to gloves beyond the head end, spread wider as he dives.
    final spread = 0.34 + 0.25 * sim.diveProgress;
    for (final side in <double>[-1, 1]) {
      final shoulder = chest + normal * (0.26 * scale * side);
      final glove = b + dir * (0.12 * scale) + normal * (spread * scale * side);
      canvas.drawLine(shoulder, glove, Paint()
        ..color = ElevarColors.ink
        ..strokeWidth = 0.14 * scale + 4
        ..strokeCap = StrokeCap.round);
      canvas.drawLine(shoulder, glove, Paint()
        ..color = PenaltyColors.keeperShirtDeep
        ..strokeWidth = 0.14 * scale
        ..strokeCap = StrokeCap.round);
      canvas.drawCircle(glove, 0.12 * scale, Paint()..color = PenaltyColors.gloves);
      canvas.drawCircle(glove, 0.12 * scale, outline);
    }
    // Head.
    final head = b - dir * (0.08 * scale);
    canvas.drawCircle(head, 0.15 * scale, Paint()..color = PenaltyColors.skin);
    canvas.drawCircle(head, 0.15 * scale, outline);
  }

  void _paintKicker(Canvas canvas) {
    final sim = game.simulation;
    if (sim.phase == PenaltyPhase.complete) return;
    final t = sim.runUpProgress;
    final colour = sim.shooter == PenaltySide.p1 ? PenaltyColors.p1 : PenaltyColors.p2;
    // Once the ball is on its way the kicker steps out of the picture: this
    // close to the camera a full-size player hides the goal, and the ball is
    // what everyone is watching.
    final gone = sim.phase == PenaltyPhase.flight || sim.phase == PenaltyPhase.outcome;
    if (gone && game.ballTrail.length > 6) return;
    // Runs in from behind and to the left, standing off the ball's line.
    final z = Goal.spotZ + 0.35 + (1 - t) * 1.2;
    final x = -0.75 - (1 - t) * 0.7;
    final (feet, depthScale) = cam.project(x, 0, z);
    // Drawn at two-thirds size. At true scale he is a third of the screen
    // tall and the shot is played through his shirt.
    final scale = depthScale * 0.62;
    final stride = sim.phase == PenaltyPhase.runUp ? math.sin(t * 14) : 0.0;
    final kick = sim.phase == PenaltyPhase.flight ? 1.0 : 0.0;

    Offset p(double dx, double dy) => feet + Offset(dx * scale, -dy * scale);
    final outline = _ink..strokeWidth = 5;

    canvas.drawOval(
      Rect.fromCenter(center: feet, width: 0.9 * scale, height: 0.18 * scale),
      Paint()..color = ElevarColors.ink.withValues(alpha: 0.3),
    );
    // Legs.
    final legPaint = Paint()
      ..color = const Color(0xFF1B1B1B)
      ..strokeWidth = 0.17 * scale
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(p(-0.12, 0.85), p(-0.18 + stride * 0.1, 0.05), legPaint);
    canvas.drawLine(p(0.12, 0.85),
        p(0.2 - stride * 0.1 + kick * 0.25, 0.05 + kick * 0.35), legPaint);
    // Shorts and shirt.
    final shorts = RRect.fromRectAndRadius(
      Rect.fromLTRB(p(-0.26, 1.05).dx, p(0, 1.05).dy, p(0.26, 0).dx, p(0, 0.72).dy),
      Radius.circular(0.08 * scale),
    );
    canvas.drawRRect(shorts, Paint()..color = ElevarColors.white);
    canvas.drawRRect(shorts, outline);
    final shirt = RRect.fromRectAndRadius(
      Rect.fromLTRB(p(-0.3, 1.65).dx, p(0, 1.65).dy, p(0.3, 0).dx, p(0, 1.0).dy),
      Radius.circular(0.14 * scale),
    );
    canvas.drawRRect(shirt, Paint()..color = colour);
    canvas.drawRRect(shirt, outline);
    final number = _painter('10', 0.34 * scale, ElevarColors.white);
    number.paint(canvas, p(0, 1.33) - Offset(number.width / 2, number.height / 2));
    // Head, from behind: hair.
    canvas.drawCircle(p(0, 1.85), 0.17 * scale, Paint()..color = const Color(0xFF2B1A10));
    canvas.drawCircle(p(0, 1.85), 0.17 * scale, outline);
  }

  void _paintBall(Canvas canvas) {
    final sim = game.simulation;
    final alpha = game.interpolation;
    final ball = Vec3.lerp(sim.ballPrevious, sim.ball, alpha);

    for (var i = 0; i < game.ballTrail.length; i++) {
      final t = (i + 1) / game.ballTrail.length;
      final q = game.ballTrail[i];
      final (at, s) = cam.project(q.x, q.y, q.z);
      canvas.drawCircle(at, Goal.ballRadius * 1.5 * s * t,
          Paint()..color = ElevarColors.white.withValues(alpha: 0.18 * t));
    }

    final (shadow, shadowScale) = cam.project(ball.x, 0, ball.z);
    final lift = clampD(ball.y / 3, 0, 1);
    canvas.drawOval(
      Rect.fromCenter(
        center: shadow,
        width: 0.34 * shadowScale * (1 - lift * 0.5),
        height: 0.1 * shadowScale * (1 - lift * 0.5),
      ),
      Paint()..color = ElevarColors.ink.withValues(alpha: 0.4 * (1 - lift)),
    );

    final (at, scale) = cam.project(ball.x, ball.y, ball.z);
    // Drawn half as big again as life — at true size a ball on the spot is a
    // dozen pixels, which reads as a dot rather than a football.
    final r = math.max(4.0, Goal.ballRadius * 1.5 * scale);
    canvas.drawCircle(at, r, Paint()..color = ElevarColors.white);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(-ball.z * 2.2);
    final patch = Paint()..color = const Color(0xFF1A1A1A);
    canvas.drawCircle(Offset.zero, r * 0.32, patch);
    for (var i = 0; i < 5; i++) {
      final angle = i * math.pi * 2 / 5;
      canvas.drawCircle(Offset(math.cos(angle) * r * 0.78, math.sin(angle) * r * 0.78),
          r * 0.2, patch);
    }
    canvas.restore();
    canvas.drawCircle(at, r, _ink..strokeWidth = math.max(2, r * 0.18));
  }

  void _paintAimMarker(Canvas canvas) {
    final aim = game.aimMarker;
    if (aim == null || game.aimMarkerAge > 1.2) return;
    final fade = clampD(1 - game.aimMarkerAge / 1.2, 0, 1);
    final at = cam.at(aim.x, aim.y, 0);
    final paint = Paint()
      ..color = const Color(0xFFFFF200).withValues(alpha: fade)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final r = 16 + (1 - fade) * 20;
    canvas.drawCircle(at, r, paint);
    canvas.drawLine(at - Offset(r + 6, 0), at + Offset(r + 6, 0), paint);
    canvas.drawLine(at - Offset(0, r + 6), at + Offset(0, r + 6), paint);
  }

  void _paintDiveMarker(Canvas canvas) {
    final sim = game.simulation;
    final marker = game.diveMarker;
    if (sim.keeperIsHuman && sim.acceptsDive) {
      // Pulse the goal mouth so a keeper knows where to tap.
      final pulse = 0.5 + 0.5 * math.sin(_time * 6);
      final tl = cam.at(-Goal.halfWidth, Goal.height, Goal.keeperZ);
      final br = cam.at(Goal.halfWidth, 0, Goal.keeperZ);
      canvas.drawRect(
        Rect.fromPoints(tl, br),
        Paint()
          ..color = const Color(0xFFFFF200).withValues(alpha: 0.08 + 0.1 * pulse),
      );
    }
    if (marker == null) return;
    final at = cam.at(marker.x, marker.y, Goal.keeperZ);
    canvas.drawCircle(at, 14, Paint()..color = PenaltyColors.gloves.withValues(alpha: 0.8));
    canvas.drawCircle(at, 14, _ink..strokeWidth = 3);
  }

  void _paintSwipe(Canvas canvas) {
    final swipe = game.swipe;
    if (swipe == null || swipe.points.length < 2) return;
    final points = swipe.points;
    for (var i = 1; i < points.length; i++) {
      final t = i / points.length;
      canvas.drawLine(
        points[i - 1].at,
        points[i].at,
        Paint()
          ..color = const Color(0xFFFFF200).withValues(alpha: 0.25 + 0.6 * t)
          ..strokeWidth = 4 + 10 * t
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _paintConfetti(Canvas canvas) {
    for (final c in game.confetti) {
      canvas.save();
      canvas.translate(c.position.dx, c.position.dy);
      canvas.rotate(c.spin);
      canvas.drawRect(
        const Rect.fromLTWH(-5, -3, 10, 6),
        Paint()..color = c.colour.withValues(alpha: clampD(c.life, 0, 1)),
      );
      canvas.restore();
    }
  }

  TextPainter _painter(String text, double size, Color colour) {
    final key = '$text|${size.round()}|${colour.toARGB32()}';
    return _text.putIfAbsent(key, () {
      if (_text.length > 100) _text.clear();
      return TextPainter(
        text: TextSpan(text: text, style: ElevarType.display(size, color: colour)),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }
}
