import 'vec2.dart';

/// An axis-aligned bounding box, stored as a centre and half-extents.
///
/// Centre/half-extent form (rather than min/max) is what the Minkowski
/// expansion in `sweep.dart` needs, and it matches how paddles are positioned.
class Aabb {
  const Aabb(this.center, this.halfExtents);

  Aabb.fromLTWH(double left, double top, double width, double height)
      : center = Vec2(left + width / 2, top + height / 2),
        halfExtents = Vec2(width / 2, height / 2);

  final Vec2 center;
  final Vec2 halfExtents;

  double get left => center.x - halfExtents.x;
  double get right => center.x + halfExtents.x;
  double get top => center.y - halfExtents.y;
  double get bottom => center.y + halfExtents.y;

  /// This box grown by [r] on every side — the Minkowski sum of the box and a
  /// circle of radius [r], approximated with square corners. Sweeping a *point*
  /// against the expanded box is equivalent to sweeping the circle against this
  /// one, which is what makes tunnelling impossible at any speed.
  Aabb expanded(double r) => Aabb(center, halfExtents + Vec2.all(r));

  bool containsPoint(Vec2 p) =>
      p.x >= left && p.x <= right && p.y >= top && p.y <= bottom;

  Aabb movedTo(Vec2 newCenter) => Aabb(newCenter, halfExtents);

  @override
  String toString() => 'Aabb(center: $center, half: $halfExtents)';
}
