import 'dart:math' as math;

import 'package:cricket_sim/cricket_sim.dart';
import 'package:design_system/design_system.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';

import 'cricket_game.dart';

/// Paints the ground.
///
/// One component, one canvas, painted back to front. Flame components per
/// fielder would be eleven objects to keep in step with a simulation that
/// already knows where everything is — this reads the state and draws it.
class CricketScene extends Component {
  CricketScene({required this.game});

  final CricketGame game;

  @override
  void render(Canvas canvas) {
    final state = game.simulation.state;

    canvas
      ..save()
      ..translate(
        game.fieldOrigin.dx + game.shakeOffset.dx,
        game.fieldOrigin.dy + game.shakeOffset.dy,
      )
      ..scale(game.fieldScale);

    _paintOutfield(canvas);
    _paintInnerCircle(canvas);
    _paintPitch(canvas);
    _paintCreases(canvas);
    _paintFielders(canvas, state);
    _paintBatter(canvas, state);
    _paintBowler(canvas, state);
    _paintBallShadow(canvas, state);
    _paintBall(canvas, state);
    _paintSparks(canvas);

    canvas.restore();

    if (game.flash > 0.01) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, game.size.x, game.size.y),
        Paint()
          ..color = ElevarColors.white.withValues(alpha: game.flash * 0.42),
      );
    }
  }

  // --- the ground ----------------------------------------------------------

  Rect get _groundRect => Rect.fromCenter(
        center: const Offset(
          CricketField.groundCentreX,
          CricketField.groundCentreY,
        ),
        width: CricketField.groundRadiusX * 2,
        height: CricketField.groundRadiusY * 2,
      );

  void _paintOutfield(Canvas canvas) {
    // Everything beyond the rope.
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, CricketField.width, CricketField.height),
      Paint()..color = CricketColors.beyondRope,
    );

    canvas
      ..drawOval(_groundRect, Paint()..color = CricketColors.outfield)
      // Mown stripes, which is most of what makes a cricket ground read as a
      // cricket ground at a glance.
      ..save()
      ..clipPath(Path()..addOval(_groundRect));

    for (var i = 0; i < 14; i++) {
      if (i.isOdd) continue;
      final top = _groundRect.top + i * (_groundRect.height / 14);
      canvas.drawRect(
        Rect.fromLTWH(
          _groundRect.left,
          top,
          _groundRect.width,
          _groundRect.height / 14,
        ),
        Paint()..color = CricketColors.outfieldStripe,
      );
    }
    canvas.restore();

    // The rope.
    canvas.drawOval(
      _groundRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..color = ElevarColors.white,
    );
  }

  void _paintInnerCircle(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(
          CricketField.groundCentreX,
          CricketField.groundCentreY,
        ),
        width: CricketField.innerCircleRadiusX * 2,
        height: CricketField.innerCircleRadiusY * 2,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = ElevarColors.white.withValues(alpha: 0.45),
    );
  }

  void _paintPitch(Canvas canvas) {
    const pitch = Rect.fromLTRB(
      CricketField.pitchCentreX - CricketField.pitchHalfWidth,
      CricketField.bowlerCreaseY - 56,
      CricketField.pitchCentreX + CricketField.pitchHalfWidth,
      CricketField.strikerCreaseY + 56,
    );
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(pitch, const Radius.circular(6)),
        Paint()..color = CricketColors.pitch,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(pitch, const Radius.circular(6)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = CricketColors.pitchEdge,
      );
  }

  void _paintCreases(Canvas canvas) {
    final chalk = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = ElevarColors.white.withValues(alpha: 0.85);

    for (final y in <double>[
      CricketField.bowlerCreaseY,
      CricketField.strikerCreaseY,
    ]) {
      canvas.drawLine(
        Offset(CricketField.pitchCentreX - CricketField.pitchHalfWidth, y),
        Offset(CricketField.pitchCentreX + CricketField.pitchHalfWidth, y),
        chalk,
      );
    }

    _paintStumps(canvas, CricketField.strikerCreaseY);
    _paintStumps(canvas, CricketField.bowlerCreaseY);
  }

  void _paintStumps(Canvas canvas, double y) {
    final paint = Paint()
      ..color = CricketColors.stumps
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    for (var i = -1; i <= 1; i++) {
      final x = CricketField.pitchCentreX +
          i * (CricketField.stumpsHalfWidth * 0.8);
      canvas.drawLine(Offset(x, y - 24), Offset(x, y + 4), paint);
    }
  }

  // --- the people ----------------------------------------------------------

  void _paintFielders(Canvas canvas, CricketState state) {
    for (final fielder in state.fielding) {
      final at = _lerp(fielder.previousPosition, fielder.position);
      final isKeeper = fielder.name == 'keeper';

      canvas
        ..drawCircle(
          Offset(at.x, at.y + 6),
          15,
          Paint()..color = ElevarColors.ink.withValues(alpha: 0.22),
        )
        ..drawCircle(
          Offset(at.x, at.y),
          15,
          Paint()
            ..color = fielder.hasBall
                ? ElevarColors.ball
                : (isKeeper
                    ? CricketColors.keeperShirt
                    : CricketColors.fielderShirt),
        )
        ..drawCircle(
          Offset(at.x, at.y),
          15,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5
            ..color = ElevarColors.ink,
        );
    }
  }

  void _paintBatter(Canvas canvas, CricketState state) {
    const at = Offset(CricketField.pitchCentreX, CricketField.strikerY);
    final swinging = state.ball.struck &&
        state.phase == CricketPhase.ballInPlay;

    canvas
      ..drawCircle(
        at.translate(0, 7),
        19,
        Paint()..color = ElevarColors.ink.withValues(alpha: 0.25),
      )
      ..drawCircle(at, 19, Paint()..color = CricketColors.batterShirt)
      ..drawCircle(
        at,
        19,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = ElevarColors.ink,
      )
      // The bat. Swung round on contact, which is a cheap trick and reads
      // instantly as "that was hit".
      ..drawLine(
        at.translate(swinging ? 22 : -20, swinging ? -6 : 6),
        at.translate(swinging ? 40 : -26, swinging ? 22 : 34),
        Paint()
          ..color = CricketColors.bat
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round,
      );
  }

  void _paintBowler(Canvas canvas, CricketState state) {
    // Runs in during the run-up, then stands where they finished.
    final progress = state.phase == CricketPhase.runUp
        ? 1 - (state.phaseTicks / 138.0).clamp(0.0, 1.0)
        : 1.0;
    final y = CricketField.bowlerCreaseY - 92 + 92 * progress;
    final at = Offset(CricketField.pitchCentreX, y);

    canvas
      ..drawCircle(
        at.translate(0, 7),
        18,
        Paint()..color = ElevarColors.ink.withValues(alpha: 0.25),
      )
      ..drawCircle(at, 18, Paint()..color = CricketColors.bowlerShirt)
      ..drawCircle(
        at,
        18,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = ElevarColors.ink,
      );
  }

  // --- the ball ------------------------------------------------------------

  void _paintBallShadow(Canvas canvas, CricketState state) {
    final ball = state.ball;
    if (ball.height <= 1) return;
    final at = _lerp(ball.previousPosition, ball.position);
    // The shadow stays on the deck and shrinks as the ball climbs, which is
    // the only cue the player gets that a shot is in the air at all.
    final shrink = 1 / (1 + ball.height / 90);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(at.x, at.y + ball.height * 0.10),
        width: CricketField.ballRadius * 2.4 * shrink,
        height: CricketField.ballRadius * 1.7 * shrink,
      ),
      Paint()..color = ElevarColors.ink.withValues(alpha: 0.30 * shrink),
    );
  }

  void _paintBall(Canvas canvas, CricketState state) {
    final ball = state.ball;
    if (state.phase == CricketPhase.betweenBalls && !ball.struck) return;

    final at = _lerp(ball.previousPosition, ball.position);
    // Lifted up the screen with height, so a ball in the air reads as being
    // above the ground rather than somewhere else on it.
    final drawn = Offset(at.x, at.y - ball.height * 0.42);
    final radius = CricketField.ballRadius * (1 + ball.height / 260);

    canvas
      ..drawCircle(drawn, radius, Paint()..color = CricketColors.ball)
      ..drawCircle(
        drawn,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = ElevarColors.ink,
      )
      // The seam.
      ..drawLine(
        drawn.translate(-radius * 0.7, 0),
        drawn.translate(radius * 0.7, 0),
        Paint()
          ..color = ElevarColors.white
          ..strokeWidth = 2,
      );
  }

  void _paintSparks(Canvas canvas) {
    for (final spark in game.sparks) {
      final fade = 1 - spark.t;
      canvas.drawCircle(
        Offset(spark.position.x, spark.position.y),
        3 + 7 * fade,
        Paint()
          ..color = Color.lerp(
            CricketColors.ball,
            spark.hue < 0.5 ? ElevarColors.p1 : ElevarColors.table,
            spark.hue,
          )!
              .withValues(alpha: fade),
      );
    }
  }

  /// Between simulation ticks, so things glide rather than step.
  Vec2 _lerp(Vec2 from, Vec2 to) {
    final t = game.interpolation;
    return Vec2(
      from.x + (to.x - from.x) * t,
      from.y + (to.y - from.y) * t,
    );
  }
}

/// The cricket palette, alongside the table and the circuit.
///
/// Lives in this package rather than `design_system` for now because nothing
/// else reuses it; the moment a second game wants a grass green it should move
/// next to [RacingColors] rather than be sampled again slightly differently.
abstract final class CricketColors {
  static const Color outfield = Color(0xFF3FAE45);
  static const Color outfieldStripe = Color(0xFF379C3D);
  static const Color beyondRope = Color(0xFF176B33);

  static const Color pitch = Color(0xFFCBAE73);
  static const Color pitchEdge = Color(0xFFA98C55);

  static const Color ball = Color(0xFFE23B2E);
  static const Color stumps = Color(0xFFF2E6C9);
  static const Color bat = Color(0xFFD8B06A);

  static const Color batterShirt = ElevarColors.p1;
  static const Color bowlerShirt = Color(0xFF2C6BE8);
  static const Color fielderShirt = Color(0xFF3E7BF0);
  static const Color keeperShirt = Color(0xFF9B5CF0);

  /// The timing ring, from far too early through perfect to far too late.
  static const Color early = Color(0xFF2CC8F0);
  static const Color perfect = Color(0xFF39D353);
  static const Color late = Color(0xFFF0A93E);

  static Color timingColour(double offset) {
    final magnitude = offset.abs();
    if (magnitude < 0.28) return perfect;
    return offset < 0 ? early : late;
  }

  static double lerp(double a, double b, double t) => a + (b - a) * t;

  static double clamp01(double v) => math.max(0, math.min(1, v));
}
