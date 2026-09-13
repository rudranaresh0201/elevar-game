import 'package:game_core/game_core.dart';

/// The room the innings is played in, side on.
///
/// Field units, y pointing **down**, so the renderer can draw state without
/// flipping anything. The batter stands on the left in front of the stumps,
/// the bowling machine is built into the right-hand wall, and every other wall
/// is a scoreboard.
///
/// This is the Top Spinner shape rather than a cricket ground, on purpose. A
/// ground needs fielders, a boundary a long way off and a camera to follow the
/// ball there; a room gives every hit an answer within a second, on screen,
/// and turns "where did it go" into a number painted on the wall it hit.
abstract final class Arena {
  static const double width = 1000;
  static const double height = 1600;

  /// The playing surface. Everything below it is scenery.
  static const double groundY = 1420;

  static const double ballRadius = 20;

  /// Stumps: three of them, drawn inside this box.
  static const double stumpsLeft = 92;
  static const double stumpsRight = 132;
  static const double stumpsTop = groundY - 215;

  /// The batter's hands. The bat pivots here.
  static const Vec2 pivot = Vec2(230, 1210);
  static const double batLength = 270;

  /// Half the blade's thickness, for collision. Generous on purpose: a blade
  /// drawn 32 units wide that only collides on a hairline would feel like
  /// the ball went through it.
  static const double batRadius = 26;

  /// Where the blade rests when nobody is holding it: raised up over the
  /// shoulder, clear of the line.
  ///
  /// It used to rest at guard, down in front of the stumps, and the first
  /// numbers showed what that meant: an innings where nobody touched the
  /// screen was never bowled and scored 50 on hard, because a still blade
  /// across the line is a wall. Leaving a ball has to actually leave it.
  static const Vec2 restDirection = Vec2(-0.3486, -0.9373);

  /// The handle, in the batter's hands, is not a collider. Only the blade
  /// beyond this fraction of the length is — otherwise a ball passing the
  /// batter's hip glances off a grip nobody can see.
  static const double bladeFrom = 0.3;

  /// The part of the blade that hits hardest, as a fraction of its length.
  static const double sweetFrom = 0.52;
  static const double sweetTo = 0.92;

  /// The bowling machine, set into the right wall.
  static const double machineLeft = 890;
  static const double machineTop = 1030;
  static const double machineBottom = 1160;
  static const Vec2 machineMouth = Vec2(880, 1092);

  static const double gravity = 1800;

  /// How hard surfaces give the ball back.
  static const double wallRestitution = 0.55;
  static const double groundRestitution = 0.6;
  static const double groundFriction = 0.9;

  static const double maxBallSpeed = 4200;

  /// The scoring walls, in the order the renderer paints their numbers.
  static const List<WallZone> zones = <WallZone>[
    WallZone(Wall.left, 0, stumpsTop - 60, 1),
    WallZone(Wall.ceiling, 0, 340, 2),
    WallZone(Wall.ceiling, 340, 680, 4),
    WallZone(Wall.ceiling, 680, width, 6),
    WallZone(Wall.right, 0, 560, 6),
    WallZone(Wall.right, 560, machineTop, 4),
    WallZone(Wall.machine, machineTop, machineBottom, 6),
    WallZone(Wall.right, machineBottom, groundY, 2),
  ];

  /// The zone a contact at [along] on [wall] belongs to, or null for a part of
  /// the room that does not score (the wall behind the stumps, low down).
  static int? zoneIndexAt(Wall wall, double along) {
    for (var i = 0; i < zones.length; i++) {
      final zone = zones[i];
      if (zone.wall == wall && along >= zone.from && along < zone.to) return i;
    }
    return null;
  }
}

enum Wall { left, ceiling, right, machine }

/// A numbered stretch of wall.
class WallZone {
  const WallZone(this.wall, this.from, this.to, this.runs);

  final Wall wall;

  /// Extent along the wall: y for the side walls and the machine, x for the
  /// ceiling.
  final double from;
  final double to;
  final int runs;
}
