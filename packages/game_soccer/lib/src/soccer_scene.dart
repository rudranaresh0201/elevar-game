import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flame/components.dart';
import 'package:flutter/widgets.dart';
import 'package:game_core/game_core.dart';
import 'package:soccer_sim/soccer_sim.dart';

import 'soccer_game.dart';

/// Paints the pitch.
///
/// Deliberately one component drawing the whole scene rather than a component
/// per entity, for the same reason ping pong is: there are a dozen things on
/// screen, they share a coordinate transform, a stroke width and a shadow
/// convention, and splitting them into a component tree would cost the ability
/// to control draw order exactly — which the chunky outline style depends on.
class SoccerScene extends Component {
  SoccerScene({required this.game});

  final SoccerGame game;

  static const double _outline = 7;
  static const double _lineWidth = 9;

  @override
  void render(Canvas canvas) {
    final state = game.simulation.state;
    final alpha = game.interpolation;

    _paintSurround(canvas);

    canvas.save();
    canvas.translate(
      game.fieldOrigin.dx + game.shakeOffset.dx,
      game.fieldOrigin.dy + game.shakeOffset.dy,
    );
    canvas.scale(game.fieldScale);

    _paintGoal(canvas, SoccerSide.p2);
    _paintGoal(canvas, SoccerSide.p1);
    _paintTurf(canvas);
    _paintMarkings(canvas);
    _paintPosts(canvas);
    _paintTrail(canvas);

    // Discs first, ball last: the ball is the thing the eye has to follow and
    // it is the smallest object on the pitch, so it is never allowed to end up
    // underneath a counter.
    for (var i = 0; i < SoccerWorld.ballIndex; i++) {
      _paintDisc(canvas, state, i, alpha);
    }
    _paintAim(canvas, state);
    _paintBall(canvas, state, alpha);
    _paintParticles(canvas);

    canvas.restore();

    if (game.flash > 0.01) {
      canvas.drawRect(
        Offset.zero & Size(game.size.x, game.size.y),
        Paint()
          ..color = ElevarColors.white.withValues(alpha: game.flash * 0.32),
      );
    }
  }

  // --- the ground ----------------------------------------------------------

  void _paintSurround(Canvas canvas) {
    canvas.drawRect(
      Offset.zero & Size(game.size.x, game.size.y),
      Paint()..color = SoccerColors.surround,
    );
  }

  void _paintTurf(Canvas canvas) {
    const rect = Rect.fromLTRB(
      SoccerField.left,
      SoccerField.topGoalLine,
      SoccerField.right,
      SoccerField.bottomGoalLine,
    );
    canvas.drawRect(rect, Paint()..color = SoccerColors.turf);

    // Mown bands. A single flat green gives the eye nothing to measure the
    // ball's travel against; ten bands do, and cost one loop.
    const bands = 10;
    const bandHeight =
        (SoccerField.bottomGoalLine - SoccerField.topGoalLine) / bands;
    final band = Paint()..color = SoccerColors.turfBand;
    for (var i = 0; i < bands; i += 2) {
      canvas.drawRect(
        Rect.fromLTWH(
          SoccerField.left,
          SoccerField.topGoalLine + i * bandHeight,
          SoccerField.right - SoccerField.left,
          bandHeight,
        ),
        band,
      );
    }
  }

  void _paintMarkings(Canvas canvas) {
    final line = Paint()
      ..color = SoccerColors.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = _lineWidth;

    const inset = _lineWidth / 2;
    canvas.drawRect(
      const Rect.fromLTRB(
        SoccerField.left + inset,
        SoccerField.topGoalLine + inset,
        SoccerField.right - inset,
        SoccerField.bottomGoalLine - inset,
      ),
      line,
    );

    canvas.drawLine(
      const Offset(SoccerField.left, SoccerField.halfwayY),
      const Offset(SoccerField.right, SoccerField.halfwayY),
      line,
    );
    canvas.drawCircle(
      const Offset(SoccerField.centreX, SoccerField.halfwayY),
      SoccerField.centreCircleRadius,
      line,
    );
    canvas.drawCircle(
      const Offset(SoccerField.centreX, SoccerField.halfwayY),
      12,
      Paint()..color = SoccerColors.line,
    );

    // Penalty area and six-yard box at each end.
    for (final atTop in <bool>[true, false]) {
      final goalLine =
          atTop ? SoccerField.topGoalLine : SoccerField.bottomGoalLine;
      final into = atTop ? 1.0 : -1.0;
      for (final box in <(double, double)>[(310, 250), (200, 120)]) {
        canvas.drawRect(
          Rect.fromLTRB(
            SoccerField.centreX - box.$1,
            atTop ? goalLine : goalLine - box.$2 * into.abs(),
            SoccerField.centreX + box.$1,
            atTop ? goalLine + box.$2 : goalLine,
          ),
          line,
        );
      }
    }
  }

  /// The net behind one goal, drawn outside the pitch in the surround.
  void _paintGoal(Canvas canvas, SoccerSide defending) {
    final atTop = defending == SoccerSide.p2;
    final goalLine =
        atTop ? SoccerField.topGoalLine : SoccerField.bottomGoalLine;
    final back = atTop
        ? goalLine - SoccerField.goalDepth
        : goalLine + SoccerField.goalDepth;

    final mouth = Rect.fromLTRB(
      SoccerField.centreX - SoccerField.goalHalfWidth,
      math.min(goalLine, back),
      SoccerField.centreX + SoccerField.goalHalfWidth,
      math.max(goalLine, back),
    );

    canvas.drawRect(mouth, Paint()..color = SoccerColors.net);

    // A woven mesh rather than a texture: two families of diagonals, clipped
    // to the mouth. Cheap, and it reads as a net at any scale.
    canvas.save();
    canvas.clipRect(mouth);
    final mesh = Paint()
      ..color = SoccerColors.netMesh
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (var x = mouth.left - mouth.height; x < mouth.right; x += 22) {
      canvas.drawLine(
        Offset(x, mouth.top),
        Offset(x + mouth.height, mouth.bottom),
        mesh,
      );
      canvas.drawLine(
        Offset(x + mouth.height, mouth.top),
        Offset(x, mouth.bottom),
        mesh,
      );
    }
    canvas.restore();

    // The frame, in the defending side's colour, so at a glance you know which
    // end you are shooting at. On a shared screen that is not decoration —
    // half the players are reading the pitch upside down.
    canvas.drawRect(
      mouth,
      Paint()
        ..color = _teamColour(defending)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10,
    );
  }

  void _paintPosts(Canvas canvas) {
    final fill = Paint()..color = SoccerColors.post;
    for (final post in SoccerWorld.postPositions) {
      canvas.drawCircle(
        Offset(post.x, post.y),
        SoccerField.postRadius,
        fill,
      );
    }
  }

  // --- the pieces ----------------------------------------------------------

  void _paintDisc(Canvas canvas, SoccerState state, int index, double alpha) {
    final body = state.world.bodies[index];
    final at = _interpolated(body.previousPosition, body.position, alpha);
    final side = body.team!;
    final radius = SoccerField.discRadius;

    final hit = game.impact[index] ?? 0;
    final squash = 1 + hit * 0.18;

    // A hard offset shadow rather than a blur: the reference art has no
    // gaussian anywhere, and one soft shadow reads immediately as a different
    // app.
    canvas.drawCircle(
      Offset(at.x + 4, at.y + 7),
      radius,
      Paint()..color = ElevarColors.ink.withValues(alpha: 0.30),
    );

    canvas.drawCircle(
      Offset(at.x, at.y),
      radius * squash,
      Paint()..color = _teamColour(side),
    );
    canvas.drawCircle(
      Offset(at.x, at.y),
      radius * squash,
      Paint()
        ..color = ElevarColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = _outline,
    );
    // A darker crescent along the bottom, for a little roundness without a
    // gradient.
    canvas.drawArc(
      Rect.fromCircle(center: Offset(at.x, at.y), radius: radius - 9),
      0,
      math.pi,
      false,
      Paint()
        ..color = _teamColourDeep(side).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9,
    );

    _paintStar(canvas, Offset(at.x, at.y), radius * 0.52);

    // The dashed halo the reference art puts around the pieces you may play.
    // It is the single most useful thing on the screen for a first-timer: it
    // answers "what can I touch" before they have to guess.
    if (state.phase == SoccerPhase.aiming &&
        side == state.turn &&
        !game.simulation.botToPlay) {
      _paintSelectableHalo(
        canvas,
        Offset(at.x, at.y),
        radius + 14,
        state.aim.discIndex == index,
      );
    }
  }

  void _paintStar(Canvas canvas, Offset centre, double radius) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? radius : radius * 0.46;
      // -pi/2 puts a point at the top. Trigonometry in the renderer only.
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point =
          centre + Offset(math.cos(angle) * r, math.sin(angle) * r);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = ElevarColors.white);
  }

  void _paintSelectableHalo(
    Canvas canvas,
    Offset centre,
    double radius,
    bool held,
  ) {
    final paint = Paint()
      ..color = held
          ? ElevarColors.white
          : ElevarColors.ink.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = held ? 7 : 5
      ..strokeCap = StrokeCap.round;

    const segments = 8;
    const sweep = math.pi * 2 / segments * 0.55;
    for (var i = 0; i < segments; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        i * math.pi * 2 / segments,
        sweep,
        false,
        paint,
      );
    }
  }

  void _paintBall(Canvas canvas, SoccerState state, double alpha) {
    final ball = state.world.ball;
    final at = _interpolated(ball.previousPosition, ball.position, alpha);
    final radius = SoccerField.ballRadius * (1 + game.goalPulse * 0.35);

    canvas.drawCircle(
      Offset(at.x + 3, at.y + 5),
      radius,
      Paint()..color = ElevarColors.ink.withValues(alpha: 0.28),
    );
    canvas.drawCircle(
      Offset(at.x, at.y),
      radius,
      Paint()..color = SoccerColors.ball,
    );
    canvas.drawCircle(
      Offset(at.x, at.y),
      radius,
      Paint()
        ..color = ElevarColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    // Three panels. Enough to read as a football at 26 units across, which is
    // about 5 mm on a phone.
    for (var i = 0; i < 3; i++) {
      final angle = -math.pi / 2 + i * math.pi * 2 / 3;
      canvas.drawCircle(
        Offset(at.x, at.y) +
            Offset(math.cos(angle), math.sin(angle)) * (radius * 0.48),
        radius * 0.26,
        Paint()..color = SoccerColors.ballMark,
      );
    }
  }

  void _paintTrail(Canvas canvas) {
    if (game.ballTrail.length < 2) return;
    for (var i = 0; i < game.ballTrail.length; i++) {
      final fade = i / game.ballTrail.length;
      final point = game.ballTrail[i];
      canvas.drawCircle(
        Offset(point.x, point.y),
        SoccerField.ballRadius * (0.25 + fade * 0.55),
        Paint()
          ..color = ElevarColors.white.withValues(alpha: fade * 0.30),
      );
    }
  }

  // --- the slingshot -------------------------------------------------------

  /// The aim band, read straight out of the simulation.
  ///
  /// Nothing here recomputes the shot from the gesture. The direction, the
  /// power and the cancel threshold are all the simulation's answers, so the
  /// band cannot promise a flick the match will not take — including the case
  /// that matters, where the drag is too short and the shot is about to be
  /// cancelled.
  void _paintAim(Canvas canvas, SoccerState state) {
    final aim = state.aim;
    if (!aim.isHolding) return;

    final origin = Offset(aim.origin.x, aim.origin.y);
    final anchor = Offset(aim.anchor.x, aim.anchor.y);

    if (aim.tooShort) {
      // Say so, rather than drawing a tiny band that looks like a tiny shot.
      canvas.drawCircle(
        origin,
        SoccerField.discRadius + 22,
        Paint()
          ..color = ElevarColors.white.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
      return;
    }

    final colour = _powerColour(aim.power);

    // The band the finger is stretching, behind the disc.
    canvas.drawLine(
      origin,
      anchor,
      Paint()
        ..color = ElevarColors.ink.withValues(alpha: 0.45)
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      origin,
      anchor,
      Paint()
        ..color = colour
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(anchor, 15, Paint()..color = colour);
    canvas.drawCircle(
      anchor,
      15,
      Paint()
        ..color = ElevarColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );

    // Where it is going: dotted, in front of the disc, scaled by power. Dots
    // rather than a solid line, because a solid line reads as a guarantee and
    // the first thing this ball does is hit something.
    final direction = Offset(aim.direction.x, aim.direction.y);
    final reach = 150 + 620 * aim.power;
    const spacing = 46.0;
    for (var travelled = 70.0; travelled < reach; travelled += spacing) {
      final fade = 1 - travelled / reach;
      canvas.drawCircle(
        origin + direction * travelled,
        7 * fade + 3,
        Paint()..color = colour.withValues(alpha: 0.20 + fade * 0.55),
      );
    }

    // The arrowhead, so the direction is unmistakable at a glance.
    final tip = origin + direction * reach;
    final side = Offset(-direction.dy, direction.dx);
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        (tip - direction * 34 + side * 20).dx,
        (tip - direction * 34 + side * 20).dy,
      )
      ..lineTo(
        (tip - direction * 34 - side * 20).dx,
        (tip - direction * 34 - side * 20).dy,
      )
      ..close();
    canvas.drawPath(head, Paint()..color = colour);
    canvas.drawPath(
      head,
      Paint()
        ..color = ElevarColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }

  void _paintParticles(Canvas canvas) {
    for (final particle in game.particles) {
      canvas.drawCircle(
        Offset(particle.position.x, particle.position.y),
        particle.size * particle.fade,
        Paint()
          ..color = SoccerColors.turfBand
              .withValues(alpha: particle.fade * 0.9),
      );
    }
  }

  // --- helpers -------------------------------------------------------------

  static Vec2 _interpolated(Vec2 from, Vec2 to, double alpha) =>
      from + (to - from) * alpha;

  static Color _teamColour(SoccerSide side) =>
      side == SoccerSide.p1 ? SoccerColors.discP1 : SoccerColors.discP2;

  static Color _teamColourDeep(SoccerSide side) => side == SoccerSide.p1
      ? SoccerColors.discP1Deep
      : SoccerColors.discP2Deep;

  static Color _powerColour(double power) => power < 0.5
      ? Color.lerp(
          SoccerColors.powerLow,
          SoccerColors.powerMid,
          power * 2,
        )!
      : Color.lerp(
          SoccerColors.powerMid,
          SoccerColors.powerHigh,
          (power - 0.5) * 2,
        )!;
}
