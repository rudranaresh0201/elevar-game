import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:flame/components.dart';
import 'package:flutter/widgets.dart';
import 'package:game_core/game_core.dart';
import 'package:racing_sim/racing_sim.dart';

import 'racing_game.dart';

/// Paints the circuit.
///
/// One component drawing the whole scene rather than a component per entity,
/// for the same reason the pong table is: everything here shares one coordinate
/// transform, one stroke width and one shadow convention, and the chunky
/// outline style depends on controlling draw order exactly.
class RaceScene extends Component {
  RaceScene({required this.game});

  final RacingGame game;

  static const double _outline = 7;

  /// Size of the squares in the grass checkerboard, in field units.
  static const double _checker = 96;

  @override
  void render(Canvas canvas) {
    final state = game.simulation.state;
    final alpha = game.interpolation;

    _paintLetterbox(canvas);

    canvas.save();
    canvas.translate(
      game.fieldOrigin.dx + game.shakeOffset.dx,
      game.fieldOrigin.dy + game.shakeOffset.dy,
    );
    canvas.scale(game.fieldScale);
    // Nothing outside the circuit's own rectangle may bleed into the control
    // bands, whatever the scenery does near the edges.
    canvas.clipRect(
      const Rect.fromLTWH(0, 0, RaceField.width, RaceField.height),
    );

    _paintGrass(canvas);
    _paintTrack(canvas);
    _paintStartLine(canvas);
    _paintSkids(canvas);
    _paintDecorations(canvas);
    _paintObstacles(canvas);
    _paintCar(canvas, state.p2, RacingColors.carP2, RacingColors.carP2Deep, alpha);
    _paintCar(canvas, state.p1, RacingColors.carP1, RacingColors.carP1Deep, alpha);
    _paintDust(canvas);

    canvas.restore();

    if (game.flash > 0.01) {
      canvas.drawRect(
        Offset.zero & Size(game.size.x, game.size.y),
        Paint()
          ..color = ElevarColors.white.withValues(alpha: game.flash * 0.28),
      );
    }
  }

  /// The bands above and below the circuit, where the controls live.
  void _paintLetterbox(Canvas canvas) {
    canvas.drawRect(
      Offset.zero & Size(game.size.x, game.size.y),
      Paint()..color = ElevarColors.surface,
    );
  }

  void _paintGrass(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, RaceField.width, RaceField.height),
      Paint()..color = RacingColors.grass,
    );

    // The checkerboard from the reference art: two greens a shade apart, big
    // enough to read as texture rather than as a pattern.
    final alt = Paint()..color = RacingColors.grassAlt;
    var row = 0;
    for (var y = 0.0; y < RaceField.height; y += _checker) {
      var column = 0;
      for (var x = 0.0; x < RaceField.width; x += _checker) {
        if ((row + column).isEven) {
          canvas.drawRect(Rect.fromLTWH(x, y, _checker, _checker), alt);
        }
        column++;
      }
      row++;
    }
  }

  /// The dirt, drawn as one thick stroke along the centreline.
  ///
  /// Stroking the centreline rather than filling an outlined polygon is what
  /// makes the drawn track and the simulated one the same shape by
  /// construction: the simulation's surface test is "within `halfWidth` of the
  /// centreline", and a round-capped, round-joined stroke of width
  /// `halfWidth * 2` is exactly that set of points. There is no way for the
  /// picture and the physics to drift apart.
  void _paintTrack(Canvas canvas) {
    final path = _centrelinePath();
    final track = game.track;

    // Sandy rim first, then the dirt on top of it.
    canvas.drawPath(
      path,
      Paint()
        ..color = RacingColors.rim
        ..style = PaintingStyle.stroke
        ..strokeWidth = (track.halfWidth + 16) * 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = RacingColors.dirt
        ..style = PaintingStyle.stroke
        ..strokeWidth = track.halfWidth * 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    // A lighter inner band gives the flat brown some depth without a gradient.
    canvas.drawPath(
      path,
      Paint()
        ..color = RacingColors.dirtLight.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = track.halfWidth * 1.1
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  Path _centrelinePath() {
    final nodes = game.track.nodes;
    final path = Path()..moveTo(nodes.first.x, nodes.first.y);
    for (var i = 1; i < nodes.length; i++) {
      path.lineTo(nodes[i].x, nodes[i].y);
    }
    return path..close();
  }

  /// The chequered band across the road at the start line.
  void _paintStartLine(Canvas canvas) {
    final track = game.track;
    final centre = track.pointAt(0);
    final forward = track.directionAt(0);
    final right = Vec2(-forward.y, forward.x);

    const rows = 2;
    const squares = 8;
    final squareWidth = (track.halfWidth * 2) / squares;
    const squareDepth = 22.0;

    canvas.save();
    canvas.transform(_rotationAbout(centre, forward));

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < squares; column++) {
        final light = (row + column).isEven;
        canvas.drawRect(
          Rect.fromLTWH(
            -squareDepth * rows / 2 + row * squareDepth,
            -track.halfWidth + column * squareWidth,
            squareDepth,
            squareWidth,
          ),
          Paint()
            ..color = light ? ElevarColors.white : ElevarColors.ink,
        );
      }
    }
    canvas.restore();
    // `right` is only needed to reason about the transform above; referencing
    // it keeps the intent explicit for the next reader.
    assert(right.length > 0);
  }

  void _paintSkids(Canvas canvas) {
    for (final skid in game.skids) {
      canvas.drawLine(
        Offset(skid.from.x, skid.from.y),
        Offset(skid.to.x, skid.to.y),
        Paint()
          ..color = RacingColors.skid.withValues(alpha: skid.alpha)
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _paintDecorations(Canvas canvas) {
    for (final decoration in game.track.decorations) {
      final centre = Offset(decoration.position.x, decoration.position.y);
      switch (decoration.kind) {
        case DecorationKind.pond:
          _blob(canvas, centre, decoration.radius, RacingColors.waterDeep,
              RacingColors.water);
        case DecorationKind.bush:
          _blob(canvas, centre, decoration.radius, RacingColors.foliageDeep,
              RacingColors.foliage);
        case DecorationKind.rock:
          _blob(canvas, centre, decoration.radius, RacingColors.stoneDeep,
              RacingColors.stone);
        case DecorationKind.tree:
          _tree(canvas, centre, decoration.radius);
      }
    }
  }

  void _paintObstacles(Canvas canvas) {
    for (final obstacle in game.track.obstacles) {
      final centre = Offset(obstacle.position.x, obstacle.position.y);
      switch (obstacle.kind) {
        case ObstacleKind.tyre:
          canvas.drawCircle(
            centre.translate(0, 4),
            obstacle.radius,
            Paint()..color = ElevarColors.ink.withValues(alpha: 0.3),
          );
          canvas.drawCircle(
            centre,
            obstacle.radius,
            Paint()..color = RacingColors.tyre,
          );
          canvas.drawCircle(
            centre,
            obstacle.radius * 0.42,
            Paint()..color = RacingColors.foliageDeep,
          );
        case ObstacleKind.rock:
          _blob(canvas, centre, obstacle.radius, RacingColors.stoneDeep,
              RacingColors.stone);
        case ObstacleKind.tree:
          _tree(canvas, centre, obstacle.radius);
      }
    }
  }

  /// A flat two-tone lump with a hard outline — the whole art style in one
  /// helper. No gradients, no blur; the reference has neither anywhere.
  void _blob(
    Canvas canvas,
    Offset centre,
    double radius,
    Color deep,
    Color fill,
  ) {
    canvas.drawCircle(centre.translate(0, 6), radius, Paint()..color = deep);
    canvas.drawCircle(centre, radius, Paint()..color = fill);
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = ElevarColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = _outline,
    );
  }

  void _tree(Canvas canvas, Offset centre, double radius) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: centre.translate(radius * 0.55, radius * 0.15),
          width: radius * 0.42,
          height: radius * 0.9,
        ),
        Radius.circular(radius * 0.2),
      ),
      Paint()..color = RacingColors.trunk,
    );
    // Two overlapping lumps read as a canopy more convincingly than one.
    _blob(canvas, centre, radius, RacingColors.foliageDeep,
        RacingColors.foliage);
    canvas.drawCircle(
      centre.translate(-radius * 0.3, -radius * 0.28),
      radius * 0.42,
      Paint()..color = RacingColors.foliage.withValues(alpha: 0.65),
    );
  }

  void _paintCar(
    Canvas canvas,
    CarState car,
    Color fill,
    Color deep,
    double alpha,
  ) {
    final position = _lerp(car.previousPosition, car.position, alpha);
    // Heading is interpolated and re-normalised rather than lerped raw: a
    // straight lerp between two unit vectors is shorter than one, which would
    // make the car visibly shrink through fast corners if it scaled anything.
    final heading = _lerp(car.previousHeading, car.heading, alpha).normalized;

    canvas.save();
    canvas.transform(_rotationAbout(position, heading));

    const length = RaceField.carLength;
    const width = RaceField.carWidth;
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: length, height: width),
      const Radius.circular(9),
    );

    // Hard offset shadow, never a blur.
    canvas.drawRRect(body.shift(const Offset(0, 6)), Paint()..color = deep);
    canvas.drawRRect(body, Paint()..color = fill);

    // Windscreen toward the nose, so which way the car points is readable at a
    // glance even when it is sliding sideways.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: const Offset(length * 0.16, 0),
          width: length * 0.3,
          height: width * 0.62,
        ),
        const Radius.circular(5),
      ),
      Paint()..color = RacingColors.glass,
    );

    // Wheels, poking out either side.
    for (final along in <double>[-length * 0.28, length * 0.3]) {
      for (final across in <double>[-width * 0.56, width * 0.56]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(along, across),
              width: length * 0.24,
              height: width * 0.24,
            ),
            const Radius.circular(4),
          ),
          Paint()..color = RacingColors.tyre,
        );
      }
    }

    canvas.drawRRect(
      body,
      Paint()
        ..color = ElevarColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = _outline,
    );

    canvas.restore();
  }

  void _paintDust(Canvas canvas) {
    for (final mote in game.dust) {
      canvas.drawCircle(
        Offset(mote.position.x, mote.position.y),
        mote.size * (1.4 - mote.fade * 0.4),
        Paint()
          ..color = RacingColors.dust.withValues(alpha: mote.fade * 0.55),
      );
    }
  }

  /// A canvas transform that translates to [centre] and rotates so local `+x`
  /// points along [direction].
  ///
  /// Built straight from the direction vector's components. Flutter would
  /// happily take an angle here, but forming one means `atan2`, and the whole
  /// simulation is built to never need it — there is no reason for the
  /// renderer to reintroduce the dependency.
  static Float64List _rotationAbout(Vec2 centre, Vec2 direction) {
    final dx = direction.x;
    final dy = direction.y;
    return Float64List.fromList(<double>[
      dx, dy, 0, 0, // column 0: local +x maps to the direction
      -dy, dx, 0, 0, // column 1: local +y maps to its right normal
      0, 0, 1, 0,
      centre.x, centre.y, 0, 1, // translation
    ]);
  }

  static Vec2 _lerp(Vec2 from, Vec2 to, double t) =>
      Vec2(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t);
}
