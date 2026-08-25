import 'package:game_core/game_core.dart';
import 'package:racing_sim/racing_sim.dart';
import 'package:test/test.dart';

void main() {
  group('RaceTrack geometry', () {
    final track = Tracks.dustbowl();

    test('smooths control points into a closed loop', () {
      expect(track.segmentCount, 120);
      expect(track.totalLength, greaterThan(2000));

      // Closed means the last node joins the first without a jump. If it did
      // not, a car would teleport once a lap.
      final last = track.nodes.last;
      final first = track.nodes.first;
      final closingGap = (first - last).length;
      final averageSegment = track.totalLength / track.segmentCount;
      expect(closingGap, lessThan(averageSegment * 2));
    });

    test('every segment is shorter than the car is long', () {
      // The surface test samples once per tick at a point. Segments longer than
      // a car would let the projection skip detail the car actually drove
      // through.
      for (var i = 0; i < track.segmentCount; i++) {
        final a = track.nodes[i];
        final b = track.nodes[(i + 1) % track.segmentCount];
        expect((b - a).length, lessThan(RaceField.carLength));
      }
    });

    test('stays inside the field once its width is counted', () {
      for (final node in track.nodes) {
        expect(node.x - track.halfWidth, greaterThan(0));
        expect(node.x + track.halfWidth, lessThan(RaceField.width));
        expect(node.y - track.halfWidth, greaterThan(0));
        expect(node.y + track.halfWidth, lessThan(RaceField.height));
      }
    });

    test('no obstacle is parked in the middle of the road', () {
      for (final obstacle in track.obstacles) {
        final projection = track.project(obstacle.position);
        // Tyres along the pinch sit just off the racing surface; nothing should
        // be sitting where a car has to drive.
        expect(
          projection.lateralAbs,
          greaterThan(track.halfWidth - 10),
          reason: 'obstacle at ${obstacle.position} blocks the track',
        );
      }
    });
  });

  group('projection', () {
    final track = Tracks.dustbowl();

    test('a point on the centreline has no lateral offset', () {
      for (var d = 0.0; d < track.totalLength; d += 137) {
        final point = track.pointAt(d);
        final projection = track.project(point);
        expect(projection.lateralAbs, lessThan(1.0));
        expect(projection.distance, closeTo(d, 2.0));
      }
    });

    test('lateral offset is signed by which side of the road you are on', () {
      const d = 400.0;
      final centre = track.pointAt(d);
      final forward = track.directionAt(d);
      final right = Vec2(-forward.y, forward.x);

      expect(track.project(centre + right * 60).lateral, greaterThan(0));
      expect(track.project(centre - right * 60).lateral, lessThan(0));
    });

    test('pointAt and directionAt agree with the node list', () {
      final atZero = track.pointAt(0);
      expect((atZero - track.nodes.first).length, lessThan(1.0));

      // A direction is a unit vector, everywhere.
      for (var d = 0.0; d < track.totalLength; d += 211) {
        expect(track.directionAt(d).length, closeTo(1.0, 1e-9));
      }
    });

    test('wrapDistance folds any input into one lap', () {
      expect(track.wrapDistance(0), 0);
      expect(track.wrapDistance(track.totalLength), closeTo(0, 1e-9));
      expect(
        track.wrapDistance(track.totalLength * 3 + 50),
        closeTo(50, 1e-6),
      );
      expect(track.wrapDistance(-10), closeTo(track.totalLength - 10, 1e-6));
    });

    test('shortestDelta reads crossing the line as a small step forward', () {
      // The tick a car crosses the start line, the raw projection drops from
      // nearly a full lap to nearly zero. Read literally that is a lap
      // backwards; folded, it is the few units the car actually moved.
      final justBefore = track.totalLength - 5;
      const justAfter = 3.0;
      expect(track.shortestDelta(justBefore, justAfter), closeTo(8, 1e-6));
      expect(track.shortestDelta(justAfter, justBefore), closeTo(-8, 1e-6));
    });

    test('curvature reads low on a straight and high in a corner', () {
      var lowest = 1.0;
      var highest = 0.0;
      for (var d = 0.0; d < track.totalLength; d += 40) {
        final bend = track.curvatureAhead(d, 200);
        if (bend < lowest) lowest = bend;
        if (bend > highest) highest = bend;
      }
      expect(lowest, lessThan(0.02));
      expect(highest, greaterThan(0.15));
    });
  });

  group('the windowed search stops the projection teleporting', () {
    final track = Tracks.dustbowl();

    /// Segment indices live on a ring, so "near" has to be measured the long
    /// way round as well as the short way.
    int ringGap(int a, int b, int count) {
      final raw = (a - b).abs();
      return raw < count - raw ? raw : count - raw;
    }

    test('a hint confines the answer to the hint neighbourhood', () {
      // A point in the middle of the pinch is nearly equidistant from two
      // straights half a lap apart. An unconstrained search may snap to
      // whichever is marginally nearer; a hinted one may not.
      const infield = Vec2(500, 780);

      final unconstrained = track.project(infield);
      final hinted = track.project(infield, hintSegment: 4);

      expect(ringGap(hinted.segment, 4, track.segmentCount),
          lessThanOrEqualTo(5));

      // The free search landed somewhere else entirely — which is exactly the
      // one-tick jump the window exists to prevent.
      final jump =
          track.shortestDelta(hinted.distance, unconstrained.distance);
      expect(jump.abs(), greaterThan(200));
    });

    test('a large single step cannot bank a lap of progress', () {
      // The pathological case: a position that moves clear across the circuit
      // between two ticks. The projection must refuse to follow it.
      final start = track.project(track.pointAt(0));
      final farSide = track.project(
        track.pointAt(track.totalLength / 2),
        hintSegment: start.segment,
      );

      final banked = track.shortestDelta(start.distance, farSide.distance);
      expect(
        banked.abs(),
        lessThan(400),
        reason: 'one tick must never be worth a meaningful part of a lap',
      );
    });

    test('cutting the infield costs more time than it saves', () {
      // This — not the projection window — is what actually makes the circuit
      // shaped. A cut is only ever worth taking if it is quicker, so the check
      // that matters is against the clock, not against the lap counter.
      final from = track.pointAt(0);
      final to = track.pointAt(track.totalLength / 2);

      final shortcut = (to - from).length;
      final theLongWay = track.totalLength / 2;

      const dirtTerminal = RaceField.engineForce / RaceField.dragOnTrack;
      const grassTerminal = RaceField.engineForce / RaceField.dragOnGrass;

      // Generous to the cheat: full grass terminal all the way across, against
      // a merely tidy 62% of dirt terminal for the driver going round.
      final cutSeconds = shortcut / grassTerminal;
      final raceSeconds = theLongWay / (dirtTerminal * 0.62);

      expect(
        cutSeconds,
        greaterThan(raceSeconds),
        reason: 'grass drag is the anti-cut mechanism; if this fails the '
            'fastest line round this circuit is through the middle of it',
      );
    });
  });
}
