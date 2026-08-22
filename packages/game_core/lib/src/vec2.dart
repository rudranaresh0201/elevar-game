import 'dart:math' as math;

/// An immutable 2D vector.
///
/// Deliberately has no angle-based constructors or accessors — see the
/// determinism contract in `game_core.dart`. Directions are built and rotated
/// with arithmetic and [normalized] (which uses only `sqrt`).
class Vec2 {
  const Vec2(this.x, this.y);

  const Vec2.all(double v) : x = v, y = v;

  static const Vec2 zero = Vec2(0, 0);

  final double x;
  final double y;

  Vec2 operator +(Vec2 o) => Vec2(x + o.x, y + o.y);
  Vec2 operator -(Vec2 o) => Vec2(x - o.x, y - o.y);
  Vec2 operator *(double s) => Vec2(x * s, y * s);
  Vec2 operator /(double s) => Vec2(x / s, y / s);
  Vec2 operator -() => Vec2(-x, -y);

  double dot(Vec2 o) => x * o.x + y * o.y;

  double get lengthSquared => x * x + y * y;

  double get length => math.sqrt(lengthSquared);

  /// Unit vector in the same direction, or [zero] for a zero-length vector.
  Vec2 get normalized {
    final len2 = lengthSquared;
    if (len2 == 0) return zero;
    final len = math.sqrt(len2);
    return Vec2(x / len, y / len);
  }

  /// This vector rescaled to [newLength], preserving direction.
  Vec2 withLength(double newLength) => normalized * newLength;

  /// Reflects this vector about a unit-length [normal].
  Vec2 reflect(Vec2 normal) => this - normal * (2 * dot(normal));

  Vec2 copyWith({double? x, double? y}) => Vec2(x ?? this.x, y ?? this.y);

  @override
  bool operator ==(Object other) =>
      other is Vec2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() =>
      'Vec2(${x.toStringAsFixed(4)}, ${y.toStringAsFixed(4)})';
}

/// Clamps [v] into the inclusive range [lo]..[hi].
double clampD(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);
