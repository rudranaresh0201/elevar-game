import 'package:game_core/game_core.dart';

/// Where a point sits relative to the racing line.
///
/// Every question the race needs to answer — am I on the dirt, how far round am
/// I, which way is forward, is that car ahead of me — is answered by projecting
/// a position onto the centreline and reading this back. One query, one source
/// of truth, used by the physics, the lap counter, the bot and the renderer
/// alike.
class TrackPoint {
  const TrackPoint({
    required this.segment,
    required this.distance,
    required this.lateral,
    required this.closest,
    required this.forward,
  });

  /// Index of the centreline segment the point projected onto.
  final int segment;

  /// Arc length from the start line, in field units. This is *the* progress
  /// measure — laps, race position and the bot's lookahead are all derived
  /// from it.
  final double distance;

  /// Signed perpendicular offset from the centreline. Positive is to the right
  /// of the direction of travel. Its magnitude decides the surface underfoot.
  final double lateral;

  /// The nearest point on the centreline itself.
  final Vec2 closest;

  /// Unit direction of travel at [closest].
  final Vec2 forward;

  double get lateralAbs => lateral < 0 ? -lateral : lateral;
}

/// A closed-loop circuit: a centreline, a width, and the scenery bolted to it.
///
/// The track is defined by control points and smoothed at construction with a
/// Catmull-Rom spline, so a circuit is authored as ~20 readable coordinates
/// rather than 120 hand-placed ones. The smoothing is polynomial arithmetic —
/// no trigonometry — which matters because a track built differently on the
/// server than on the phone would fail every replay it verified.
class RaceTrack {
  RaceTrack({
    required this.name,
    required this.nodes,
    required this.halfWidth,
    this.obstacles = const <Obstacle>[],
    this.decorations = const <Decoration>[],
  }) : assert(nodes.length >= 8, 'A loop needs at least 8 nodes') {
    final count = nodes.length;
    _directions = List<Vec2>.filled(count, Vec2.zero);
    _lengths = List<double>.filled(count, 0);
    _cumulative = List<double>.filled(count, 0);

    var running = 0.0;
    for (var i = 0; i < count; i++) {
      final a = nodes[i];
      final b = nodes[(i + 1) % count];
      final span = b - a;
      _lengths[i] = span.length;
      _directions[i] = span.normalized;
      _cumulative[i] = running;
      running += _lengths[i];
    }
    totalLength = running;
  }

  /// Builds a track by smoothing [controlPoints] into a dense centreline.
  ///
  /// [subdivisions] segments are generated between each pair of control
  /// points. Six is enough that the densest corner is straighter than a car is
  /// long, which is what stops the surface test from flickering as a car
  /// rounds it.
  factory RaceTrack.smooth({
    required String name,
    required List<Vec2> controlPoints,
    required double halfWidth,
    int subdivisions = 6,
    List<Obstacle> obstacles = const <Obstacle>[],
    List<Decoration> decorations = const <Decoration>[],
  }) {
    final count = controlPoints.length;
    final nodes = <Vec2>[];
    for (var i = 0; i < count; i++) {
      final p0 = controlPoints[(i - 1 + count) % count];
      final p1 = controlPoints[i];
      final p2 = controlPoints[(i + 1) % count];
      final p3 = controlPoints[(i + 2) % count];
      for (var s = 0; s < subdivisions; s++) {
        nodes.add(_catmullRom(p0, p1, p2, p3, s / subdivisions));
      }
    }
    return RaceTrack(
      name: name,
      nodes: nodes,
      halfWidth: halfWidth,
      obstacles: obstacles,
      decorations: decorations,
    );
  }

  final String name;

  /// The dense centreline, closed: the last node joins back to the first.
  final List<Vec2> nodes;

  /// Half the width of the driveable dirt. Beyond it is grass, which is slow.
  final double halfWidth;

  /// Solid scenery. Cars bounce off these.
  final List<Obstacle> obstacles;

  /// Purely visual scenery, ignored by the simulation.
  final List<Decoration> decorations;

  late final List<Vec2> _directions;
  late final List<double> _lengths;
  late final List<double> _cumulative;

  /// One lap, in field units.
  late final double totalLength;

  int get segmentCount => nodes.length;

  /// Projects [p] onto the centreline, searching only near [hintSegment].
  ///
  /// The window stops the projection *jumping*. In the pinch, a point in the
  /// infield is nearly equidistant from two straights half a lap apart, and an
  /// unconstrained search is free to flip between them from one tick to the
  /// next — banking hundreds of units of progress for a car that moved three.
  /// Confining the search to segments adjacent to last tick's answer makes the
  /// projection walk rather than teleport.
  ///
  /// It is worth being precise about what this does *not* do. A car creeping
  /// across the infield still advances its projection segment by segment, so
  /// the window is not what stops corner cutting. **Grass drag is.** Off the
  /// dirt, terminal velocity falls from 331 units/s to 80, and a car coasting
  /// off the racing line carries momentum for barely 74 units — so the 1,138-
  /// unit shortcut across this circuit's middle takes about 14 seconds against
  /// 8 for the 1,660 units round it. Cutting is a loss on the clock, which is a
  /// far better deterrent than a rule that tells a player their lap did not
  /// count. `tool/cutcheck.dart` re-derives those numbers from the constants.
  ///
  /// Pass a [hintSegment] of -1 for an unconstrained search — correct when
  /// placing a car on the grid, wrong every tick after that.
  TrackPoint project(Vec2 p, {int hintSegment = -1, int window = 5}) {
    final count = nodes.length;
    var bestSegment = 0;
    var bestDistanceSquared = double.infinity;
    var bestAlong = 0.0;

    void consider(int index) {
      final i = index % count;
      final a = nodes[i];
      final direction = _directions[i];
      final length = _lengths[i];
      final relative = p - a;
      var along = relative.dot(direction);
      if (along < 0) along = 0;
      if (along > length) along = length;
      final closest = a + direction * along;
      final gap = (p - closest).lengthSquared;
      if (gap < bestDistanceSquared) {
        bestDistanceSquared = gap;
        bestSegment = i;
        bestAlong = along;
      }
    }

    if (hintSegment < 0) {
      for (var i = 0; i < count; i++) {
        consider(i);
      }
    } else {
      for (var offset = -window; offset <= window; offset++) {
        consider(hintSegment + offset + count);
      }
    }

    final direction = _directions[bestSegment];
    final closest = nodes[bestSegment] + direction * bestAlong;
    // Perpendicular to the direction of travel, pointing right. Built by
    // swapping components rather than from an angle — see the determinism
    // contract in `game_core`.
    final right = Vec2(-direction.y, direction.x);

    return TrackPoint(
      segment: bestSegment,
      distance: _cumulative[bestSegment] + bestAlong,
      lateral: (p - closest).dot(right),
      closest: closest,
      forward: direction,
    );
  }

  /// The centreline position [distance] units round the loop.
  Vec2 pointAt(double distance) {
    final (segment, along) = _locate(distance);
    return nodes[segment] + _directions[segment] * along;
  }

  /// The direction of travel [distance] units round the loop.
  Vec2 directionAt(double distance) => _directions[_locate(distance).$1];

  /// How sharply the track bends over the next [span] units, on a 0..1 scale
  /// where 0 is dead straight and 1 is a hairpin.
  ///
  /// Measured as the dot product between the direction here and the direction
  /// [span] ahead — arithmetic only, no angles. This is what tells the bot to
  /// lift off before a corner rather than after it, which is most of the
  /// difference between a bot that looks like it is driving and one that looks
  /// like it is being dragged round.
  double curvatureAhead(double distance, double span) {
    final here = directionAt(distance);
    final there = directionAt(distance + span);
    final alignment = here.dot(there);
    // dot is 1 when straight and -1 when doubled back; map onto 0..1.
    final bend = (1.0 - alignment) / 2.0;
    return clampD(bend, 0, 1);
  }

  /// Wraps [distance] into `[0, totalLength)`.
  double wrapDistance(double distance) {
    var d = distance % totalLength;
    if (d < 0) d += totalLength;
    return d;
  }

  /// The shortest signed way round from [from] to [to], in `(-L/2, L/2]`.
  ///
  /// Used to turn a raw projection into a per-tick delta. Without folding it
  /// this way, the tick where a car crosses the start line reads as a full lap
  /// backwards.
  double shortestDelta(double from, double to) {
    var delta = to - from;
    final half = totalLength / 2;
    while (delta > half) {
      delta -= totalLength;
    }
    while (delta <= -half) {
      delta += totalLength;
    }
    return delta;
  }

  (int, double) _locate(double distance) {
    final target = wrapDistance(distance);
    // Linear scan. The centreline is ~120 segments and this is called a
    // handful of times per tick; a binary search would be faster and harder to
    // read for no measurable gain.
    for (var i = nodes.length - 1; i >= 0; i--) {
      if (target >= _cumulative[i]) {
        final along = target - _cumulative[i];
        return (i, along > _lengths[i] ? _lengths[i] : along);
      }
    }
    return (0, 0);
  }

  /// The standard Catmull-Rom basis, evaluated in plain arithmetic.
  static Vec2 _catmullRom(Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, double t) {
    final t2 = t * t;
    final t3 = t2 * t;
    final x = 0.5 *
        ((2 * p1.x) +
            (-p0.x + p2.x) * t +
            (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
            (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3);
    final y = 0.5 *
        ((2 * p1.y) +
            (-p0.y + p2.y) * t +
            (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
            (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3);
    return Vec2(x, y);
  }
}

/// Solid scenery — a rock, a tree trunk, a tyre stack. Cars bounce off it.
class Obstacle {
  const Obstacle({
    required this.position,
    required this.radius,
    this.kind = ObstacleKind.tyre,
  });

  final Vec2 position;
  final double radius;
  final ObstacleKind kind;
}

enum ObstacleKind { tyre, rock, tree }

/// Scenery the simulation does not know about: ponds, bushes, the checkerboard
/// on the grass. Kept in the track so a circuit is one object the renderer can
/// draw without a second lookup table.
class Decoration {
  const Decoration({
    required this.position,
    required this.radius,
    required this.kind,
  });

  final Vec2 position;
  final double radius;
  final DecorationKind kind;
}

enum DecorationKind { tree, bush, pond, rock }
