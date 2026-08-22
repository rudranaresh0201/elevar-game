import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  group('sweepCircleAgainstAabb', () {
    const paddle = Aabb(Vec2(500, 1600), Vec2(96, 24));

    test('a ball moving fast enough to skip the paddle still hits it', () {
      // The whole reason for swept collision: this delta is 40x the paddle's
      // thickness, so an overlap test after moving would find nothing at all
      // and the ball would sail through into the goal.
      final hit = sweepCircleAgainstAabb(
        const Vec2(500, 600),
        const Vec2(0, 2000),
        paddle,
        26,
      );
      expect(hit, isNotNull);
      expect(hit!.normal.y, lessThan(0), reason: 'hit the top face');
      // Contact happens when the ball centre reaches the expanded top edge.
      final contactY = 600 + 2000 * hit.t;
      expect(contactY, closeTo(1600 - 24 - 26, 0.001));
    });

    test('returns null when the path misses', () {
      final hit = sweepCircleAgainstAabb(
        const Vec2(100, 600),
        const Vec2(0, 2000),
        paddle,
        26,
      );
      expect(hit, isNull);
    });

    test('a grazing pass along the side registers on the side face', () {
      final hit = sweepCircleAgainstAabb(
        const Vec2(200, 1600),
        const Vec2(400, 0),
        paddle,
        26,
      );
      expect(hit, isNotNull);
      expect(hit!.normal.x, lessThan(0));
    });

    test('an already-overlapping ball is pushed out the shallow way', () {
      // Happens when a paddle is dragged into a ball rather than the reverse.
      final hit = sweepCircleAgainstAabb(
        const Vec2(500, 1585),
        const Vec2(0, 10),
        paddle,
        26,
      );
      expect(hit, isNotNull);
      expect(hit!.t, 0);
      expect(hit.normal.y, lessThan(0), reason: 'nearest exit is upward');
    });

    test('motion stopping short of the box is not a hit', () {
      final hit = sweepCircleAgainstAabb(
        const Vec2(500, 600),
        const Vec2(0, 100),
        paddle,
        26,
      );
      expect(hit, isNull);
    });
  });

  group('foldIntoRange', () {
    test('leaves values already inside alone', () {
      expect(foldIntoRange(500, 26, 974), closeTo(500, 1e-9));
    });

    test('reflects a single overshoot', () {
      expect(foldIntoRange(1000, 26, 974), closeTo(948, 1e-9));
    });

    test('reflects repeatedly, like a ball between two walls', () {
      // Two full widths past the right wall lands back where it started.
      const lo = 0.0;
      const hi = 100.0;
      expect(foldIntoRange(250, lo, hi), closeTo(50, 1e-9));
      expect(foldIntoRange(-30, lo, hi), closeTo(30, 1e-9));
      expect(foldIntoRange(430, lo, hi), closeTo(30, 1e-9));
    });
  });

  group('Vec2', () {
    test('normalized is unit length and survives zero', () {
      expect(const Vec2(3, 4).normalized.length, closeTo(1, 1e-12));
      expect(Vec2.zero.normalized, Vec2.zero);
    });

    test('reflect mirrors about a normal', () {
      final r = const Vec2(1, -1).reflect(const Vec2(0, 1));
      expect(r.x, closeTo(1, 1e-12));
      expect(r.y, closeTo(1, 1e-12));
    });
  });
}
