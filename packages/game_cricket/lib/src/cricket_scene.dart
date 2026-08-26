import 'dart:math' as math;

import 'package:cricket_sim/cricket_sim.dart';
import 'package:design_system/design_system.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';

import 'camera.dart';
import 'cricket_game.dart';

/// Paints the ground from behind the stumps.
///
/// One component, one canvas, painted back to front: stands, outfield, pitch,
/// then everybody on it in depth order, then the ball. Flame components per
/// fielder would be eleven objects to keep in step with a simulation that
/// already knows where they all are — this reads the state and draws it.
///
/// The projection lives in [PitchCamera]. Everything here is *what* to draw;
/// nothing here decides where the world is.
class CricketScene extends Component {
  CricketScene({required this.game});

  final CricketGame game;

  /// The ball is nine units across, which at the far end of the pitch is under
  /// two pixels. Drawing it life-size is technically right and useless, so it
  /// is drawn fat. This is the single biggest readability cheat in the game.
  static const double _ballDrawRadius = 27;

  @override
  void render(Canvas canvas) {
    final state = game.simulation.state;
    final camera = game.pitchCamera;

    canvas
      ..save()
      ..translate(game.shakeOffset.dx, game.shakeOffset.dy);

    _paintStands(canvas, camera);
    _paintOutfield(canvas, camera);
    _paintPitch(canvas, camera);
    _paintPeople(canvas, camera, state);
    _paintSparks(canvas, camera);

    canvas.restore();

    _paintMinimap(canvas, state);

    if (game.flash > 0.01) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, game.size.x, game.size.y),
        Paint()
          ..color = ElevarColors.white.withValues(alpha: game.flash * 0.42),
      );
    }
  }

  // --- the world -----------------------------------------------------------

  /// Sky, stands and a crowd.
  ///
  /// None of it is simulated and all of it matters: a green oval on a flat
  /// background reads as a screensaver, and the same oval with something
  /// behind it reads as a ground. The crowd is a few hundred dots on a fixed
  /// seed, so it does not shimmer between frames.
  void _paintStands(Canvas canvas, PitchCamera camera) {
    final width = camera.screenWidth;
    final horizon = camera.horizon;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, horizon),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[CricketColors.sky, CricketColors.skyLow],
        ).createShader(Rect.fromLTWH(0, 0, width, horizon)),
    );

    // The stand: a solid band sitting on the horizon, with the crowd in it.
    final standTop = horizon * 0.34;
    final standRect = Rect.fromLTWH(0, standTop, width, horizon - standTop);
    canvas.drawRect(standRect, Paint()..color = CricketColors.stand);

    final random = math.Random(9182);
    for (var i = 0; i < 340; i++) {
      final x = random.nextDouble() * width;
      final y = standTop + 3 + random.nextDouble() * (standRect.height - 6);
      canvas.drawCircle(
        Offset(x, y),
        1.5,
        Paint()
          ..color = CricketColors
              .crowd[random.nextInt(CricketColors.crowd.length)]
              .withValues(alpha: 0.9),
      );
    }

    // Floodlights, because the night game is the one everybody pictures.
    for (final fraction in <double>[0.16, 0.84]) {
      final x = width * fraction;
      canvas
        ..drawRect(
          Rect.fromLTWH(x - 2, standTop * 0.2, 4, standTop * 0.85),
          Paint()..color = CricketColors.standDark,
        )
        ..drawCircle(
          Offset(x, standTop * 0.2),
          24,
          Paint()
            ..color = CricketColors.floodlight.withValues(alpha: 0.15)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11),
        )
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(x, standTop * 0.2),
              width: 32,
              height: 13,
            ),
            const Radius.circular(4),
          ),
          Paint()..color = CricketColors.floodlight,
        );
    }

    // A dark strip at the foot of the stand, so the rope has something to sit
    // against rather than floating.
    canvas.drawRect(
      Rect.fromLTWH(0, horizon - 4, width, 4),
      Paint()..color = CricketColors.standDark,
    );
  }

  /// The grass: everything beyond the rope, then the ground itself, then the
  /// mown stripes, the rope and the inner ring.
  void _paintOutfield(Canvas canvas, PitchCamera camera) {
    final width = camera.screenWidth;
    final height = camera.screenHeight;

    canvas.drawRect(
      Rect.fromLTWH(0, camera.horizon, width, height - camera.horizon),
      Paint()..color = CricketColors.beyondRope,
    );

    final ground = _groundPath(camera);
    canvas
      ..save()
      ..clipPath(ground)
      ..drawRect(
        Rect.fromLTWH(0, camera.horizon, width, height - camera.horizon),
        Paint()..color = CricketColors.outfield,
      );

    // Stripes laid out in even *screen* bands rather than even field bands.
    // Even field bands crush into an unreadable smear near the horizon; this
    // way each stripe stays visible and the bunching happens where the eye
    // expects it.
    const bands = 11;
    final top = camera.horizon;
    for (var i = 0; i < bands; i++) {
      if (i.isOdd) continue;
      final bandTop = top + (height - top) * (i / bands);
      final bandBottom = top + (height - top) * ((i + 1) / bands);
      canvas.drawRect(
        Rect.fromLTRB(0, bandTop, width, bandBottom),
        Paint()..color = CricketColors.outfieldStripe,
      );
    }
    canvas.restore();

    canvas
      ..drawPath(
        ground,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = ElevarColors.white.withValues(alpha: 0.92),
      )
      ..drawPath(
        _ellipsePath(
          camera,
          radiusX: CricketField.innerCircleRadiusX,
          radiusY: CricketField.innerCircleRadiusY,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = ElevarColors.white.withValues(alpha: 0.34),
      );
  }

  Path _groundPath(PitchCamera camera) => _ellipsePath(
        camera,
        radiusX: CricketField.groundRadiusX,
        radiusY: CricketField.groundRadiusY,
        closeToBottom: true,
      );

  /// Projects an ellipse centred on the ground, dropping the part of it that
  /// is behind the camera.
  ///
  /// Standing at one end, the boundary behind you is genuinely off screen — so
  /// the shape is an arc, not a loop, and it gets closed off along the bottom.
  Path _ellipsePath(
    PitchCamera camera, {
    required double radiusX,
    required double radiusY,
    bool closeToBottom = false,
  }) {
    const samples = 128;
    final points = <Offset>[];
    var started = false;

    // Sweep from the point nearest the camera, which is guaranteed to be
    // behind it. The visible part of the boundary is one arc that wraps across
    // angle zero, so starting anywhere inside that arc splits it in two and
    // most of the rope goes missing.
    for (var i = 0; i <= samples; i++) {
      final angle = camera.nearestAngle + (i / samples) * math.pi * 2;
      final x = CricketField.groundCentreX + math.cos(angle) * radiusX;
      final y = CricketField.groundCentreY + math.sin(angle) * radiusY;
      if (!camera.isVisible(y)) {
        if (started) break;
        continue;
      }
      started = true;
      points.add(camera.project(x, y));
    }

    final path = Path();
    if (points.length < 2) return path;

    path.moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }

    if (closeToBottom) {
      // Down past the bottom of the screen and back, so the near grass is
      // filled rather than cut off along a chord halfway up.
      final bottom = camera.screenHeight + 60;
      path
        ..lineTo(points.last.dx, bottom)
        ..lineTo(points.first.dx, bottom);
    }
    path.close();
    return path;
  }

  /// The strip, as a trapezoid. This is what sells the whole view: wide at
  /// your feet, narrow at the far end.
  void _paintPitch(Canvas canvas, PitchCamera camera) {
    const nearEnd = CricketField.strikerCreaseY + 70;
    const farEnd = CricketField.bowlerCreaseY - 70;
    const halfWidth = CricketField.pitchHalfWidth;

    final path = Path();
    var first = true;
    void corner(double x, double y) {
      final p = camera.project(x, y);
      if (first) {
        path.moveTo(p.dx, p.dy);
        first = false;
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }

    corner(CricketField.pitchCentreX - halfWidth, nearEnd);
    corner(CricketField.pitchCentreX + halfWidth, nearEnd);
    corner(CricketField.pitchCentreX + halfWidth, farEnd);
    corner(CricketField.pitchCentreX - halfWidth, farEnd);
    path.close();

    canvas
      ..drawPath(path, Paint()..color = CricketColors.pitch)
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = CricketColors.pitchEdge,
      );

    // A worn patch on a good length — the one bit of the pitch a bowler is
    // aiming at, and the only coaching the screen offers for free.
    final worn = Path();
    first = true;
    for (final (x, y) in <(double, double)>[
      (
        CricketField.pitchCentreX - halfWidth * 0.72,
        CricketField.strikerCreaseY - 150
      ),
      (
        CricketField.pitchCentreX + halfWidth * 0.72,
        CricketField.strikerCreaseY - 150
      ),
      (
        CricketField.pitchCentreX + halfWidth * 0.62,
        CricketField.strikerCreaseY - 270
      ),
      (
        CricketField.pitchCentreX - halfWidth * 0.62,
        CricketField.strikerCreaseY - 270
      ),
    ]) {
      final p = camera.project(x, y);
      if (first) {
        worn.moveTo(p.dx, p.dy);
        first = false;
      } else {
        worn.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      worn..close(),
      Paint()..color = CricketColors.pitchWorn.withValues(alpha: 0.5),
    );

    for (final y in <double>[
      CricketField.bowlerCreaseY,
      CricketField.strikerCreaseY,
    ]) {
      if (!camera.isVisible(y)) continue;
      canvas.drawLine(
        camera.project(CricketField.pitchCentreX - halfWidth, y),
        camera.project(CricketField.pitchCentreX + halfWidth, y),
        Paint()
          ..strokeWidth = math.max(1.5, camera.scaleAt(y) * 5)
          ..color = ElevarColors.white.withValues(alpha: 0.8),
      );
    }
  }

  void _paintStumps(Canvas canvas, PitchCamera camera, double y) {
    if (!camera.isVisible(y)) return;
    final scale = camera.scaleAt(y);

    // Sized the same way a person is: pixel height straight off the
    // perspective scale. Projecting the top of the stumps through the camera's
    // `rise` instead made them four times a bowler's height, because `rise` is
    // deliberately exaggerated for the ball's flight and is not a sane way to
    // measure a solid object.
    final stumpHeight = 62 * scale;
    if (stumpHeight < 3) return;

    final paint = Paint()
      ..color = CricketColors.stumps
      ..strokeWidth = math.max(1.6, 7 * scale)
      ..strokeCap = StrokeCap.round;

    for (var i = -1; i <= 1; i++) {
      final x = CricketField.pitchCentreX +
          i * (CricketField.stumpsHalfWidth * 0.85);
      final base = camera.project(x, y);
      canvas.drawLine(base, base.translate(0, -stumpHeight), paint);
    }

    final left = camera
        .project(CricketField.pitchCentreX - CricketField.stumpsHalfWidth, y)
        .translate(0, -stumpHeight);
    canvas.drawLine(
      left,
      camera
          .project(CricketField.pitchCentreX + CricketField.stumpsHalfWidth, y)
          .translate(0, -stumpHeight),
      Paint()
        ..color = CricketColors.stumps
        ..strokeWidth = math.max(1.2, 4 * scale),
    );
  }

  // --- the people, in depth order ------------------------------------------

  void _paintPeople(Canvas canvas, PitchCamera camera, CricketState state) {
    // Everything standing on the grass, sorted so the far ones are painted
    // first and the near ones overlap them. Getting this wrong is the classic
    // tell of a fake 3D scene.
    final drawables = <(double, void Function())>[];

    void at(double fieldY, void Function() paint) =>
        drawables.add((camera.depthOf(fieldY), paint));

    at(CricketField.bowlerCreaseY,
        () => _paintStumps(canvas, camera, CricketField.bowlerCreaseY));
    at(CricketField.strikerCreaseY,
        () => _paintStumps(canvas, camera, CricketField.strikerCreaseY));

    for (final fielder in state.fielding) {
      final position = _lerp(fielder.previousPosition, fielder.position);
      if (!camera.isVisible(position.y)) continue;
      at(position.y, () => _paintFielder(canvas, camera, fielder, position));
    }

    at(_bowlerY(state), () => _paintBowler(canvas, camera, state));
    at(CricketField.strikerY, () => _paintBatter(canvas, camera, state));

    final ballAt = _lerp(state.ball.previousPosition, state.ball.position);
    at(ballAt.y, () => _paintBall(canvas, camera, state, ballAt));

    drawables.sort((a, b) => b.$1.compareTo(a.$1));
    for (final (_, paint) in drawables) {
      paint();
    }
  }

  void _paintFielder(
    Canvas canvas,
    PitchCamera camera,
    Fielder fielder,
    Vec2 position,
  ) {
    final running = (fielder.position - fielder.previousPosition).length > 0.4;
    _paintPerson(
      canvas,
      camera,
      fieldX: position.x,
      fieldY: position.y,
      shirt: fielder.hasBall
          ? ElevarColors.ball
          : (fielder.name == 'keeper'
              ? CricketColors.keeperShirt
              : CricketColors.fielderShirt),
      stride: running ? 0.95 : 0.25,
      armsUp: fielder.hasBall,
    );
  }

  double _bowlerY(CricketState state) {
    // Runs in during the run-up, then stands where they finished.
    final progress = state.phase == CricketPhase.runUp
        ? 1 - (state.phaseTicks / 138.0).clamp(0.0, 1.0)
        : 1.0;
    return CricketField.bowlerCreaseY - 240 + 240 * progress;
  }

  void _paintBowler(Canvas canvas, PitchCamera camera, CricketState state) {
    final y = _bowlerY(state);
    if (!camera.isVisible(y)) return;

    final runningIn = state.phase == CricketPhase.runUp;
    // The arm comes over as the ball is released. It is the cue a real batter
    // times off, and without it the ball simply appears.
    final delivering =
        state.phase == CricketPhase.delivery && state.phaseTicks < 26;

    _paintPerson(
      canvas,
      camera,
      fieldX: CricketField.pitchCentreX - 24,
      fieldY: y,
      shirt: CricketColors.bowlerShirt,
      stride: runningIn ? 1.0 : 0.2,
      bowlingArm: delivering
          ? (state.phaseTicks / 26.0).clamp(0.0, 1.0)
          : (runningIn ? 0.0 : null),
    );
  }

  void _paintBatter(Canvas canvas, PitchCamera camera, CricketState state) {
    final ball = state.ball;

    // How far through the swing we are, taken straight off the tick the
    // simulation recorded — no animation state of our own to drift out of
    // sync with the thing that decides whether it connected.
    double? swing;
    if (ball.swingTick >= 0) {
      final since = game.simulation.tick - ball.swingTick;
      if (since >= 0 && since < 48) swing = (since / 48.0).clamp(0.0, 1.0);
    }

    _paintPerson(
      canvas,
      camera,
      // Beside the stumps rather than in front of them. Far enough across
      // that the wicket being defended is actually visible — a batter who
      // hides his own stumps takes the stakes off the screen.
      fieldX: CricketField.pitchCentreX + 62,
      fieldY: CricketField.strikerY,
      shirt: CricketColors.batterShirt,
      stride: 0.2,
      pads: true,
      bat: swing ?? -1,
      // Facing us when we are the ones bowling at them.
      mirrored: camera.facing == 1,
    );
  }

  /// One player: legs, body, head, and whatever they are holding.
  ///
  /// Chunky strokes with an ink outline, the same language as the rest of the
  /// app. The whole figure is sized from the perspective scale at its feet, so
  /// a fielder on the rope is genuinely small and the batter genuinely fills
  /// the bottom of the screen — which is the entire reason this view exists.
  void _paintPerson(
    Canvas canvas,
    PitchCamera camera, {
    required double fieldX,
    required double fieldY,
    required Color shirt,
    double stride = 0.3,
    bool armsUp = false,
    bool pads = false,
    bool mirrored = false,
    double? bat,
    double? bowlingArm,
  }) {
    final scale = camera.scaleAt(fieldY);
    // In field units, so a player is about a third the width of the pitch.
    const personHeight = 178.0;
    final h = personHeight * scale;
    if (h < 6) return;

    final feet = camera.project(fieldX, fieldY);
    final flip = mirrored ? -1.0 : 1.0;

    final hip = feet.translate(0, -h * 0.46);
    final shoulder = feet.translate(0, -h * 0.78);
    final head = feet.translate(0, -h * 0.90);

    // Shadow first, on the deck.
    canvas.drawOval(
      Rect.fromCenter(
        center: feet.translate(0, h * 0.03),
        width: h * 0.44,
        height: h * 0.13,
      ),
      Paint()..color = ElevarColors.ink.withValues(alpha: 0.26),
    );

    // Legs. `stride` opens them for somebody running.
    final spread = h * 0.11 * (0.5 + stride);
    for (final side in <double>[-1, 1]) {
      final foot = feet.translate(side * spread * flip, 0);
      canvas
        ..drawLine(
          hip,
          foot,
          Paint()
            ..color = ElevarColors.ink
            ..strokeWidth = h * 0.155
            ..strokeCap = StrokeCap.round,
        )
        ..drawLine(
          hip,
          foot,
          Paint()
            ..color = pads ? CricketColors.pads : CricketColors.trousers
            ..strokeWidth = h * 0.10
            ..strokeCap = StrokeCap.round,
        );
    }

    // Body.
    canvas
      ..drawLine(
        hip,
        shoulder,
        Paint()
          ..color = ElevarColors.ink
          ..strokeWidth = h * 0.30
          ..strokeCap = StrokeCap.round,
      )
      ..drawLine(
        hip,
        shoulder,
        Paint()
          ..color = shirt
          ..strokeWidth = h * 0.23
          ..strokeCap = StrokeCap.round,
      )
      // Head, helmeted for the batter.
      ..drawCircle(head, h * 0.128, Paint()..color = ElevarColors.ink)
      ..drawCircle(
        head,
        h * 0.10,
        Paint()..color = pads ? CricketColors.helmet : CricketColors.skin,
      );
    if (pads) {
      canvas.drawLine(
        head.translate(flip * h * 0.02, h * 0.03),
        head.translate(flip * h * 0.115, h * 0.03),
        Paint()
          ..color = ElevarColors.ink
          ..strokeWidth = h * 0.04,
      );
    }

    // Arms.
    if (bowlingArm != null) {
      // Over the top: from behind the back, up past the head, and through.
      final angle = -2.5 + 3.4 * bowlingArm;
      final hand = shoulder.translate(
        math.sin(angle) * h * 0.44 * flip,
        math.cos(angle) * h * 0.44,
      );
      canvas
        ..drawLine(
          shoulder,
          hand,
          Paint()
            ..color = ElevarColors.ink
            ..strokeWidth = h * 0.13
            ..strokeCap = StrokeCap.round,
        )
        ..drawLine(
          shoulder,
          hand,
          Paint()
            ..color = shirt
            ..strokeWidth = h * 0.09
            ..strokeCap = StrokeCap.round,
        );
    } else if (bat != null) {
      _paintBat(canvas, shoulder, h, bat, flip, shirt);
    } else {
      for (final side in <double>[-1, 1]) {
        final hand = shoulder.translate(
          side * h * 0.26 * flip,
          armsUp ? -h * 0.22 : h * 0.20,
        );
        canvas
          ..drawLine(
            shoulder,
            hand,
            Paint()
              ..color = ElevarColors.ink
              ..strokeWidth = h * 0.12
              ..strokeCap = StrokeCap.round,
          )
          ..drawLine(
            shoulder,
            hand,
            Paint()
              ..color = shirt
              ..strokeWidth = h * 0.08
              ..strokeCap = StrokeCap.round,
          );
      }
    }
  }

  /// The bat, swung around the hands.
  ///
  /// [progress] is -1 for the stance, otherwise 0..1 through the shot: back
  /// over the shoulder, down through the line, and round into the
  /// follow-through. It is the most important animation in the game — it is
  /// the only confirmation the player gets that their thumb did anything.
  void _paintBat(
    Canvas canvas,
    Offset shoulder,
    double h,
    double progress,
    double flip,
    Color shirt,
  ) {
    final double angle;
    if (progress < 0) {
      // Waiting: bat tapping the crease, just off the ground.
      angle = 0.30;
    } else {
      // Eased, so the bat is quick through the ball and slows into the
      // follow-through rather than sweeping at one flat rate.
      final eased = 1 - math.pow(1 - progress, 2.2).toDouble();
      angle = -2.35 + 4.35 * eased;
    }

    final hands = shoulder.translate(flip * h * 0.17, h * 0.15);
    final tip = hands.translate(
      math.sin(angle) * h * 0.62 * flip,
      math.cos(angle) * h * 0.62,
    );

    // A smear behind the blade while it is moving fastest. Cheap, and it reads
    // as bat speed rather than as a bat teleporting.
    if (progress > 0.05 && progress < 0.55) {
      final trailAngle = angle - 0.95;
      canvas.drawLine(
        hands,
        hands.translate(
          math.sin(trailAngle) * h * 0.60 * flip,
          math.cos(trailAngle) * h * 0.60,
        ),
        Paint()
          ..color = ElevarColors.white.withValues(alpha: 0.24)
          ..strokeWidth = h * 0.10
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas
      // Arms down to the hands.
      ..drawLine(
        shoulder,
        hands,
        Paint()
          ..color = ElevarColors.ink
          ..strokeWidth = h * 0.13
          ..strokeCap = StrokeCap.round,
      )
      ..drawLine(
        shoulder,
        hands,
        Paint()
          ..color = shirt
          ..strokeWidth = h * 0.09
          ..strokeCap = StrokeCap.round,
      )
      // The blade.
      ..drawLine(
        hands,
        tip,
        Paint()
          ..color = ElevarColors.ink
          ..strokeWidth = h * 0.18
          ..strokeCap = StrokeCap.round,
      )
      ..drawLine(
        hands,
        tip,
        Paint()
          ..color = CricketColors.bat
          ..strokeWidth = h * 0.12
          ..strokeCap = StrokeCap.round,
      );
  }

  // --- the ball ------------------------------------------------------------

  void _paintBall(
    Canvas canvas,
    PitchCamera camera,
    CricketState state,
    Vec2 at,
  ) {
    final ball = state.ball;
    if (state.phase == CricketPhase.runUp) return;
    if (state.phase == CricketPhase.betweenBalls && !ball.struck) return;
    if (!camera.isVisible(at.y)) return;

    final scale = camera.scaleAt(at.y);
    final radius = math.max(2.0, _ballDrawRadius * scale);

    // The shadow stays on the deck. With the ball lifted off it, this is the
    // only thing that says how high a shot actually is.
    canvas.drawOval(
      Rect.fromCenter(
        center: camera.project(at.x, at.y),
        width: radius * 2.1,
        height: radius * 0.85,
      ),
      Paint()
        ..color = ElevarColors.ink
            .withValues(alpha: 0.32 / (1 + ball.height / 130)),
    );

    final drawn = camera.project(at.x, at.y, ball.height);

    // A short trail from where it was to where it is. Sells the speed of a
    // delivery far better than the ball on its own does.
    final previous = camera.projectVec(ball.previousPosition, ball.height);
    if ((drawn - previous).distance > radius * 0.8) {
      canvas.drawLine(
        previous,
        drawn,
        Paint()
          ..color = CricketColors.ball.withValues(alpha: 0.34)
          ..strokeWidth = radius * 1.4
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas
      ..drawCircle(drawn, radius, Paint()..color = CricketColors.ball)
      ..drawCircle(
        drawn,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, radius * 0.24)
          ..color = ElevarColors.ink,
      )
      ..drawLine(
        drawn.translate(-radius * 0.65, 0),
        drawn.translate(radius * 0.65, 0),
        Paint()
          ..color = ElevarColors.white
          ..strokeWidth = math.max(1, radius * 0.16),
      );
  }

  void _paintSparks(Canvas canvas, PitchCamera camera) {
    for (final spark in game.sparks) {
      if (!camera.isVisible(spark.position.y)) continue;
      final fade = 1 - spark.t;
      final scale = camera.scaleAt(spark.position.y);
      canvas.drawCircle(
        camera.projectVec(spark.position, 40),
        // Screen-sized, and capped. These radii were written for the old
        // top-down canvas where everything was drawn at one flat scale; once
        // the camera came in, a burst near the bat rendered as a single
        // fifty-pixel disc sitting on the pitch.
        math.max(1.2, math.min(9.0, (2.5 + 6 * fade) * scale)),
        Paint()
          // Red through gold. The teal that used to be in here was invisible
          // against grass, which is the only thing sparks are ever seen
          // against.
          ..color = Color.lerp(
            CricketColors.ball,
            spark.hue < 0.5 ? CricketColors.floodlight : ElevarColors.ball,
            spark.hue,
          )!
              .withValues(alpha: fade),
      );
    }
  }

  // --- the field map -------------------------------------------------------

  /// A small top-down oval in the corner: where the fielders are, and where the
  /// ball went.
  ///
  /// The perspective view is far better to play in but it hides the one thing
  /// a batter needs in order to *aim* — where the gaps are. This is the same
  /// information the old full-screen view showed, in the corner where it
  /// belongs, and it is what makes the swipe direction a decision rather than
  /// a shrug.
  void _paintMinimap(Canvas canvas, CricketState state) {
    final width = math.min(game.size.x * 0.25, 96.0);
    final oval = Rect.fromLTWH(
      12,
      game.size.y - game.bandHeight - width * 1.16 - 10,
      width,
      width * 1.16,
    );

    Offset toMap(Vec2 at) => Offset(
          oval.center.dx +
              (at.x - CricketField.groundCentreX) /
                  CricketField.groundRadiusX *
                  (oval.width / 2),
          oval.center.dy +
              (at.y - CricketField.groundCentreY) /
                  CricketField.groundRadiusY *
                  (oval.height / 2),
        );

    canvas
      ..drawOval(
        oval,
        Paint()..color = CricketColors.beyondRope.withValues(alpha: 0.86),
      )
      ..drawOval(
        oval,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = ElevarColors.white.withValues(alpha: 0.7),
      )
      // The strip, so the map has an orientation.
      ..drawLine(
        toMap(const Vec2(
            CricketField.pitchCentreX, CricketField.bowlerCreaseY)),
        toMap(const Vec2(
            CricketField.pitchCentreX, CricketField.strikerCreaseY)),
        Paint()
          ..color = CricketColors.pitch
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );

    for (final fielder in state.fielding) {
      canvas.drawCircle(
        toMap(fielder.position),
        2.6,
        Paint()
          ..color = fielder.hasBall
              ? ElevarColors.ball
              : ElevarColors.white.withValues(alpha: 0.9),
      );
    }

    if (state.phase == CricketPhase.ballInPlay) {
      canvas.drawCircle(
        toMap(state.ball.position),
        3.4,
        Paint()..color = CricketColors.ball,
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
  static const Color pitchWorn = Color(0xFFAF8F58);

  static const Color ball = Color(0xFFE23B2E);
  static const Color stumps = Color(0xFFF2E6C9);
  static const Color bat = Color(0xFFD8B06A);

  static const Color batterShirt = ElevarColors.p1;
  static const Color bowlerShirt = Color(0xFF2C6BE8);
  static const Color fielderShirt = Color(0xFF3E7BF0);
  static const Color keeperShirt = Color(0xFF9B5CF0);

  static const Color trousers = Color(0xFFE8EDF2);
  static const Color pads = Color(0xFFF6F7F2);
  static const Color helmet = Color(0xFF2A3038);
  static const Color skin = Color(0xFFC98D5E);

  /// Behind the rope: a night sky, the stands, and the crowd in them.
  static const Color sky = Color(0xFF10192B);
  static const Color skyLow = Color(0xFF1E3350);
  static const Color stand = Color(0xFF232B38);
  static const Color standDark = Color(0xFF161C25);
  static const Color floodlight = Color(0xFFFFF3C4);

  static const List<Color> crowd = <Color>[
    Color(0xFFE8E3D8),
    Color(0xFFE23B2E),
    Color(0xFF3E7BF0),
    Color(0xFFF0B93E),
    Color(0xFF9B5CF0),
  ];

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
