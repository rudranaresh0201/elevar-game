import 'dart:math' as math;

import 'package:game_core/game_core.dart';

import 'field.dart';

/// Where a fielder stands, and what to call them.
///
/// Positions are literal coordinates rather than derived from angles, for the
/// same reason the racing circuits are: anything built out of `sin` and `cos`
/// is built fractionally differently by the server's libm, and every replay it
/// verified would be checked against a field that is not quite the one the
/// player saw.
class FieldingPosition {
  const FieldingPosition(this.name, this.home);

  final String name;
  final Vec2 home;
}

/// A field setting — nine fielders and a keeper.
///
/// The bowler is included as a fielder. They are standing on the pitch when
/// the ball is hit straight back, and leaving them out would make the one
/// shot every player tries first — straight down the ground — a free boundary.
class FieldSetting {
  const FieldSetting(this.name, this.positions);

  final String name;
  final List<FieldingPosition> positions;

  /// The default. Two catchers up, the rest saving the single.
  static const FieldSetting standard = FieldSetting('STANDARD', <FieldingPosition>[
    FieldingPosition('keeper', Vec2(500, 1012)),
    FieldingPosition('slip', Vec2(436, 1000)),
    FieldingPosition('point', Vec2(240, 900)),
    FieldingPosition('cover', Vec2(214, 730)),
    FieldingPosition('mid off', Vec2(340, 548)),
    FieldingPosition('bowler', Vec2(500, 500)),
    FieldingPosition('mid on', Vec2(660, 548)),
    FieldingPosition('midwicket', Vec2(786, 730)),
    FieldingPosition('square leg', Vec2(760, 900)),
    FieldingPosition('fine leg', Vec2(600, 1180)),
  ]);

  /// Everyone back. Concedes the single, defends the rope — what a captain
  /// does at the death.
  static const FieldSetting spread = FieldSetting('SPREAD', <FieldingPosition>[
    FieldingPosition('keeper', Vec2(500, 1012)),
    FieldingPosition('third man', Vec2(286, 1146)),
    FieldingPosition('point', Vec2(120, 890)),
    FieldingPosition('cover', Vec2(96, 700)),
    FieldingPosition('long off', Vec2(300, 250)),
    FieldingPosition('bowler', Vec2(500, 500)),
    FieldingPosition('long on', Vec2(700, 250)),
    FieldingPosition('deep midwicket', Vec2(904, 700)),
    FieldingPosition('deep square', Vec2(880, 890)),
    FieldingPosition('fine leg', Vec2(714, 1146)),
  ]);

  static const List<FieldSetting> all = <FieldSetting>[standard, spread];
}

/// A fielder, mid-chase.
class Fielder {
  Fielder({required this.name, required this.home})
      : position = home,
        previousPosition = home;

  final String name;
  final Vec2 home;

  Vec2 position;
  Vec2 previousPosition;

  /// True for the one who got to the ball. Purely so the renderer can make
  /// them the centre of attention.
  bool hasBall = false;

  void resetToHome() {
    position = home;
    previousPosition = home;
    hasBall = false;
  }
}

/// Ground geometry: one ellipse, and everything that can be asked of it.
abstract final class Ground {
  /// How far out a point is, as a fraction of the way to the rope. Exactly 1
  /// is on the rope; above it is four runs or six.
  ///
  /// This is the squared ellipse form, so it never takes a square root and
  /// never forms an angle.
  static double boundaryFraction(Vec2 p) {
    final dx = (p.x - CricketField.groundCentreX) / CricketField.groundRadiusX;
    final dy = (p.y - CricketField.groundCentreY) / CricketField.groundRadiusY;
    return dx * dx + dy * dy;
  }

  static bool isOverBoundary(Vec2 p) => boundaryFraction(p) >= 1.0;

  /// Clamps a point back inside the rope, along the line from the middle.
  ///
  /// Used to park a ball exactly where it crossed rather than wherever it had
  /// reached by the end of the tick, so the renderer draws the ball on the
  /// rope and not in the car park.
  static Vec2 clampInside(Vec2 p) {
    final fraction = boundaryFraction(p);
    if (fraction <= 1.0) return p;
    // sqrt is safe under the determinism contract — IEEE-754 requires it to be
    // correctly rounded, so this is identical on a phone and on the server.
    final scale = 1.0 / math.sqrt(fraction);
    return Vec2(
      CricketField.groundCentreX +
          (p.x - CricketField.groundCentreX) * scale,
      CricketField.groundCentreY +
          (p.y - CricketField.groundCentreY) * scale,
    );
  }
}
