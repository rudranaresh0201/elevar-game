import 'aabb.dart';
import 'vec2.dart';

/// The result of a swept collision test.
class SweepHit {
  const SweepHit(this.t, this.normal);

  /// Fraction of the attempted motion completed before contact, in `[0, 1]`.
  /// Zero means the circle already overlapped the box when the sweep began.
  final double t;

  /// Unit surface normal at the contact point, pointing out of the box.
  final Vec2 normal;

  @override
  String toString() => 'SweepHit(t: ${t.toStringAsFixed(4)}, n: $normal)';
}

/// Sweeps a circle of [radius] from [origin] along [delta] against [box],
/// returning the first contact or null if there is none.
///
/// Uses the slab method against the box expanded by the radius (a Minkowski
/// sum with square corners). Because this solves for the exact time of impact
/// rather than testing overlap after moving, **a ball can never tunnel through
/// a paddle**, no matter how fast it is travelling or how thin the paddle is.
/// Discrete overlap checks fail exactly when the game is most exciting.
SweepHit? sweepCircleAgainstAabb(
  Vec2 origin,
  Vec2 delta,
  Aabb box,
  double radius,
) {
  final e = box.expanded(radius);

  var tEnter = double.negativeInfinity;
  var tExit = double.infinity;
  var enterNormal = Vec2.zero;

  // X slab.
  if (delta.x.abs() < 1e-12) {
    if (origin.x < e.left || origin.x > e.right) return null;
  } else {
    var t1 = (e.left - origin.x) / delta.x;
    var t2 = (e.right - origin.x) / delta.x;
    var n = const Vec2(-1, 0);
    if (t1 > t2) {
      final tmp = t1;
      t1 = t2;
      t2 = tmp;
      n = const Vec2(1, 0);
    }
    if (t1 > tEnter) {
      tEnter = t1;
      enterNormal = n;
    }
    if (t2 < tExit) tExit = t2;
  }

  // Y slab.
  if (delta.y.abs() < 1e-12) {
    if (origin.y < e.top || origin.y > e.bottom) return null;
  } else {
    var t1 = (e.top - origin.y) / delta.y;
    var t2 = (e.bottom - origin.y) / delta.y;
    var n = const Vec2(0, -1);
    if (t1 > t2) {
      final tmp = t1;
      t1 = t2;
      t2 = tmp;
      n = const Vec2(0, 1);
    }
    if (t1 > tEnter) {
      tEnter = t1;
      enterNormal = n;
    }
    if (t2 < tExit) tExit = t2;
  }

  if (tEnter > tExit) return null;
  if (tEnter > 1.0) return null;
  if (tExit < 0.0) return null;

  // Already overlapping when the sweep started — usually because a paddle moved
  // into the ball rather than the other way round. Report contact immediately,
  // with the normal of the shallowest escape, so the caller can push the ball
  // out instead of letting it sink further in.
  if (tEnter < 0.0) return SweepHit(0, _shallowestEscapeNormal(origin, e));

  return SweepHit(tEnter, enterNormal);
}

/// The axis-aligned direction out of [e] requiring the least movement.
Vec2 _shallowestEscapeNormal(Vec2 p, Aabb e) {
  final toLeft = p.x - e.left;
  final toRight = e.right - p.x;
  final toTop = p.y - e.top;
  final toBottom = e.bottom - p.y;

  var best = toLeft;
  var normal = const Vec2(-1, 0);
  if (toRight < best) {
    best = toRight;
    normal = const Vec2(1, 0);
  }
  if (toTop < best) {
    best = toTop;
    normal = const Vec2(0, -1);
  }
  if (toBottom < best) {
    normal = const Vec2(0, 1);
  }
  return normal;
}

/// Reflects a horizontal position across the walls of a corridor, as a ball
/// bouncing between them would arrive.
///
/// Used to predict where a ball will end up after an arbitrary number of wall
/// bounces without stepping the simulation forward — the bot's intercept solver
/// needs this, and it must stay pure arithmetic to remain deterministic.
double foldIntoRange(double value, double lo, double hi) {
  final span = hi - lo;
  if (span <= 0) return lo;
  final period = span * 2;
  var u = (value - lo) % period;
  if (u < 0) u += period;
  return u <= span ? lo + u : lo + (period - u);
}
