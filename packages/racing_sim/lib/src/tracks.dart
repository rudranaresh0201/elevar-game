import 'package:game_core/game_core.dart';

import 'track.dart';

/// The circuits that ship with the game.
///
/// Every coordinate here is a literal. That looks laborious next to generating
/// a ring with `sin` and `cos`, and it is the point: a track built from
/// trigonometry would be built *slightly* differently by the server's libm than
/// by the phone's, and every replay it verified would be checked against a
/// circuit fractionally the wrong shape. Literals plus the polynomial spline in
/// `RaceTrack.smooth` are bit-identical everywhere.
abstract final class Tracks {
  /// The circuit from the reference art: a peanut, pinched in the middle so the
  /// two long straights run within sight of each other with a tyre wall
  /// between. Fast down the flanks, hard on the brakes into both lobes.
  static RaceTrack dustbowl() => RaceTrack.smooth(
        name: 'DUSTBOWL',
        halfWidth: 132,
        controlPoints: const <Vec2>[
          // The start line is drawn at the first node, so the first node has to
          // be somewhere the track is straight — on a curve the chequered band
          // comes out at an angle and the grid starts mid-corner.
          Vec2(500, 1330), // start / finish, on the bottom straight
          Vec2(700, 1290),
          Vec2(805, 1150),
          Vec2(805, 975),
          Vec2(705, 855),
          Vec2(655, 775), // right side of the pinch
          Vec2(705, 695),
          Vec2(805, 555),
          Vec2(805, 375),
          Vec2(700, 225),
          Vec2(500, 180),
          Vec2(300, 225),
          Vec2(195, 375),
          Vec2(195, 555),
          Vec2(295, 695),
          Vec2(345, 775), // left side of the pinch
          Vec2(295, 855),
          Vec2(195, 975),
          Vec2(195, 1150),
          Vec2(300, 1290),
        ],
        obstacles: <Obstacle>[
          // The tyre chain down the pinch. Without it the gap between the two
          // straights is only 100 units of grass, and the fastest line round
          // this circuit would be straight through the middle of it.
          ..._tyreWall(x: 500, fromY: 545, toY: 1010, spacing: 34, radius: 22),
          // Trees hugging the outside of the quick bits, close enough to
          // punish a wide exit.
          const Obstacle(position: Vec2(917, 717), radius: 32, kind: ObstacleKind.tree),
          const Obstacle(position: Vec2(979, 943), radius: 30, kind: ObstacleKind.tree),
          const Obstacle(position: Vec2(73, 703), radius: 32, kind: ObstacleKind.tree),
          const Obstacle(position: Vec2(26, 934), radius: 28, kind: ObstacleKind.tree),
          const Obstacle(position: Vec2(905, 1342), radius: 34, kind: ObstacleKind.tree),
          const Obstacle(position: Vec2(101, 1345), radius: 30, kind: ObstacleKind.tree),
          const Obstacle(position: Vec2(97, 188), radius: 26, kind: ObstacleKind.rock),
          const Obstacle(position: Vec2(892, 178), radius: 24, kind: ObstacleKind.rock),
        ],
        decorations: const <Decoration>[
          // The pond sits in the bottom infield, where the reference art puts
          // it — behind the tyre wall, so it is scenery and never geometry.
          Decoration(position: Vec2(500, 1085), radius: 100, kind: DecorationKind.pond),
          Decoration(position: Vec2(500, 400), radius: 70, kind: DecorationKind.bush),
          Decoration(position: Vec2(430, 470), radius: 42, kind: DecorationKind.bush),
          Decoration(position: Vec2(575, 468), radius: 38, kind: DecorationKind.bush),
          Decoration(position: Vec2(940, 480), radius: 46, kind: DecorationKind.tree),
          Decoration(position: Vec2(62, 480), radius: 44, kind: DecorationKind.tree),
          Decoration(position: Vec2(940, 1180), radius: 40, kind: DecorationKind.tree),
          Decoration(position: Vec2(58, 1160), radius: 42, kind: DecorationKind.tree),
          Decoration(position: Vec2(250, 60), radius: 52, kind: DecorationKind.rock),
          Decoration(position: Vec2(760, 1430), radius: 48, kind: DecorationKind.bush),
          Decoration(position: Vec2(215, 1440), radius: 40, kind: DecorationKind.bush),
        ],
      );

  /// Wider, faster, and kinked rather than pinched. The one to learn on: there
  /// is room to be untidy and still get round.
  static RaceTrack sunsetLoop() => RaceTrack.smooth(
        name: 'SUNSET LOOP',
        halfWidth: 150,
        controlPoints: const <Vec2>[
          Vec2(500, 1310), // start / finish, on the bottom straight
          Vec2(700, 1275),
          Vec2(828, 1120),
          Vec2(828, 905),
          Vec2(752, 762), // the kink — an S rather than a squeeze
          Vec2(828, 618),
          Vec2(828, 400),
          Vec2(700, 232),
          Vec2(500, 192),
          Vec2(300, 232),
          Vec2(172, 400),
          Vec2(172, 618),
          Vec2(248, 762),
          Vec2(172, 905),
          Vec2(172, 1120),
          Vec2(300, 1275),
        ],
        obstacles: <Obstacle>[
          const Obstacle(position: Vec2(500, 700), radius: 46, kind: ObstacleKind.rock),
          const Obstacle(position: Vec2(500, 820), radius: 40, kind: ObstacleKind.rock),
          const Obstacle(position: Vec2(438, 723), radius: 30, kind: ObstacleKind.rock),
          const Obstacle(position: Vec2(562, 801), radius: 30, kind: ObstacleKind.rock),
        ],
        decorations: const <Decoration>[
          Decoration(position: Vec2(500, 1080), radius: 118, kind: DecorationKind.pond),
          Decoration(position: Vec2(500, 420), radius: 96, kind: DecorationKind.bush),
          Decoration(position: Vec2(940, 300), radius: 44, kind: DecorationKind.tree),
          Decoration(position: Vec2(60, 300), radius: 44, kind: DecorationKind.tree),
          Decoration(position: Vec2(940, 1240), radius: 40, kind: DecorationKind.tree),
          Decoration(position: Vec2(60, 1240), radius: 40, kind: DecorationKind.tree),
          Decoration(position: Vec2(760, 90), radius: 46, kind: DecorationKind.rock),
          Decoration(position: Vec2(500, 1452), radius: 40, kind: DecorationKind.bush),
          Decoration(position: Vec2(966, 800), radius: 34, kind: DecorationKind.tree),
          Decoration(position: Vec2(34, 780), radius: 34, kind: DecorationKind.tree),
        ],
      );

  /// Every circuit, in the order the picker shows them.
  static List<RaceTrack Function()> get all => <RaceTrack Function()>[
        dustbowl,
        sunsetLoop,
      ];

  static List<String> get names => <String>['DUSTBOWL', 'SUNSET LOOP'];

  static RaceTrack byName(String name) => switch (name) {
        'SUNSET LOOP' => sunsetLoop(),
        _ => dustbowl(),
      };

  static List<Obstacle> _tyreWall({
    required double x,
    required double fromY,
    required double toY,
    required double spacing,
    required double radius,
  }) {
    final tyres = <Obstacle>[];
    for (var y = fromY; y <= toY; y += spacing) {
      tyres.add(Obstacle(position: Vec2(x, y), radius: radius));
    }
    return tyres;
  }
}
