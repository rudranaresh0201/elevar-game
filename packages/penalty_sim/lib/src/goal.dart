/// The penalty area, in metres.
///
/// Three axes: **x** across the goal (right is positive), **y** up, and **z**
/// out from the goal line toward the penalty spot and the camera. The goal
/// line is `z = 0`.
abstract final class Goal {
  static const double halfWidth = 3.66;
  static const double height = 2.44;
  static const double postRadius = 0.07;

  static const double spotZ = 11;
  static const double ballRadius = 0.11;

  /// How far off the line the keeper stands.
  static const double keeperZ = 0.4;

  /// How deep the net goes behind the line.
  static const double netDepth = 1.6;

  static const double gravity = 9.8;

  /// The limits a shot can be aimed at: wider and higher than the frame, so
  /// that missing is possible.
  static const double aimHalfWidth = 6;
  static const double aimHeight = 4;
}

/// A position in the goal plane.
class GoalPoint {
  const GoalPoint(this.x, this.y);

  final double x;
  final double y;

  /// Maps to the replay's `[0, 1]` range.
  double get normalisedX => (x + Goal.aimHalfWidth) / (Goal.aimHalfWidth * 2);
  double get normalisedY => y / Goal.aimHeight;

  static GoalPoint fromNormalised(double nx, double ny) => GoalPoint(
        nx * Goal.aimHalfWidth * 2 - Goal.aimHalfWidth,
        ny * Goal.aimHeight,
      );

  @override
  String toString() => 'GoalPoint(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

/// A three-dimensional vector. Simulation-only; no angles, per the
/// determinism contract.
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  static const Vec3 zero = Vec3(0, 0, 0);

  final double x;
  final double y;
  final double z;

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);

  Vec3 copyWith({double? x, double? y, double? z}) =>
      Vec3(x ?? this.x, y ?? this.y, z ?? this.z);

  static Vec3 lerp(Vec3 a, Vec3 b, double t) => a + (b - a) * t;

  @override
  String toString() => 'Vec3(${x.toStringAsFixed(2)}, '
      '${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})';
}
