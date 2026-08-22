import 'package:design_system/design_system.dart';
import 'package:flame/components.dart';
import 'package:flutter/widgets.dart';
import 'package:game_core/game_core.dart';
import 'package:pingpong_sim/pingpong_sim.dart';

import 'pingpong_game.dart';

/// Paints the table.
///
/// Deliberately one component drawing the whole scene rather than a component
/// per entity. There are five things on screen and they share a coordinate
/// transform, a stroke width and a shadow convention; splitting them into a
/// component tree would buy nothing and cost the ability to control draw order
/// exactly, which the chunky outline style depends on.
class PongScene extends Component {
  PongScene({required this.game});

  final PingPongGame game;

  static const double _outline = 8;

  @override
  void render(Canvas canvas) {
    final state = game.simulation.state;
    final alpha = game.interpolation;

    _paintBackdrop(canvas);

    canvas.save();
    canvas.translate(
      game.fieldOrigin.dx + game.shakeOffset.dx,
      game.fieldOrigin.dy + game.shakeOffset.dy,
    );
    canvas.scale(game.fieldScale);

    _paintTable(canvas);
    _paintTrail(canvas);
    _paintPaddle(canvas, state.p1, ElevarColors.p1, ElevarColors.p1Deep,
        game.p1Squash, alpha);
    _paintPaddle(canvas, state.p2, ElevarColors.p2, ElevarColors.p2Deep,
        game.p2Squash, alpha);
    _paintBall(canvas, state, alpha);
    _paintParticles(canvas);

    canvas.restore();

    if (game.flash > 0.01) {
      canvas.drawRect(
        Offset.zero & Size(game.size.x, game.size.y),
        Paint()..color = ElevarColors.white.withValues(alpha: game.flash * 0.35),
      );
    }
  }

  /// The diagonal red/blue split behind the table, from the reference art.
  void _paintBackdrop(Canvas canvas) {
    final w = game.size.x;
    final h = game.size.y;
    canvas.drawRect(
      Offset.zero & Size(w, h),
      Paint()..color = ElevarColors.backdropBlue,
    );
    final diagonal = Path()
      ..moveTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(diagonal, Paint()..color = ElevarColors.backdropRed);
  }

  void _paintTable(Canvas canvas) {
    final table = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, PongField.width, PongField.height),
      const Radius.circular(46),
    );

    canvas.drawRRect(table, Paint()..color = ElevarColors.table);

    // A lighter inner panel gives the flat green some depth without a gradient.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(26, 26, PongField.width - 52, PongField.height - 52),
        const Radius.circular(30),
      ),
      Paint()..color = ElevarColors.tableLight.withValues(alpha: 0.28),
    );

    // Centre net.
    canvas.drawRect(
      const Rect.fromLTWH(0, PongField.netY - 9, PongField.width, 18),
      Paint()..color = ElevarColors.white,
    );

    // Centre service line, dashed down the length of the table.
    final dash = Paint()..color = ElevarColors.white.withValues(alpha: 0.55);
    for (var y = 70.0; y < PongField.height - 70; y += 90) {
      if ((y - PongField.netY).abs() < 70) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(PongField.width / 2 - 5, y, 10, 46),
          const Radius.circular(5),
        ),
        dash,
      );
    }

    canvas.drawRRect(
      table,
      Paint()
        ..color = ElevarColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = _outline,
    );
  }

  void _paintPaddle(
    Canvas canvas,
    PaddleState paddle,
    Color fill,
    Color deep,
    double squash,
    double alpha,
  ) {
    final position = _lerp(paddle.previousPosition, paddle.position, alpha);

    // Squash on contact: wider and flatter for a moment after a hit.
    final halfWidth = paddle.currentHalfWidth * (1 + squash * 0.16);
    final halfHeight = paddle.halfExtents.y * paddle.scale * (1 - squash * 0.3);

    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(position.x, position.y),
        width: halfWidth * 2,
        height: halfHeight * 2,
      ),
      Radius.circular(halfHeight),
    );

    // Hard offset shadow, never a blur — the whole art style is flat.
    canvas.drawRRect(rect.shift(const Offset(0, 7)), Paint()..color = deep);
    canvas.drawRRect(rect, Paint()..color = fill);
    canvas.drawRRect(
      rect,
      Paint()
        ..color = ElevarColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7,
    );
  }

  void _paintTrail(Canvas canvas) {
    if (game.ballTrail.length < 2) return;
    for (var i = 0; i < game.ballTrail.length; i++) {
      final t = (i + 1) / game.ballTrail.length;
      final point = game.ballTrail[i];
      canvas.drawCircle(
        Offset(point.x, point.y),
        PongField.ballRadius * t * 0.8,
        Paint()..color = ElevarColors.ball.withValues(alpha: t * 0.30),
      );
    }
  }

  void _paintBall(Canvas canvas, PongState state, double alpha) {
    final position = _lerp(state.ball.previousPosition, state.ball.position, alpha);
    final center = Offset(position.x, position.y);

    canvas.drawCircle(
      center.translate(0, 6),
      PongField.ballRadius,
      Paint()..color = ElevarColors.ink.withValues(alpha: 0.28),
    );
    canvas.drawCircle(
      center,
      PongField.ballRadius,
      Paint()..color = ElevarColors.ball,
    );
    canvas.drawCircle(
      center,
      PongField.ballRadius,
      Paint()
        ..color = ElevarColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    // A small highlight sells it as a sphere rather than a dot.
    canvas.drawCircle(
      center.translate(-PongField.ballRadius * 0.3, -PongField.ballRadius * 0.3),
      PongField.ballRadius * 0.26,
      Paint()..color = ElevarColors.white.withValues(alpha: 0.7),
    );
  }

  void _paintParticles(Canvas canvas) {
    for (final particle in game.particles) {
      canvas.drawCircle(
        Offset(particle.position.x, particle.position.y),
        particle.size * particle.fade,
        Paint()
          ..color = ElevarColors.white.withValues(alpha: particle.fade * 0.9),
      );
    }
  }

  static Vec2 _lerp(Vec2 from, Vec2 to, double t) =>
      Vec2(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t);
}
