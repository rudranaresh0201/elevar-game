import 'dart:math' as math;

import 'package:cricket_sim/cricket_sim.dart';
import 'package:flutter/painting.dart';
import 'package:game_core/game_core.dart';

/// Turns the simulation's flat 1000 × 1500 field into a view from behind the
/// stumps.
///
/// The first version of this game drew the field exactly as the simulation
/// stores it: straight down, from directly above. Everything was *correct* and
/// it was unplayable to look at — the batter was a six-pixel dot, the ball
/// never grew as it arrived, and the whole thing read as a radar display
/// rather than a game. Nobody plays a diagram twice.
///
/// So the simulation is unchanged and this sits between it and the canvas. It
/// is a plain pinhole projection:
///
/// ```
///   depth  d = how far in front of the eye a point is
///   screenX  = centreX + lateral * focal / d
///   screenY  = horizon + (lift - height * rise) / d
/// ```
///
/// Everything worth having falls out of those two lines. The pitch becomes a
/// trapezoid that is wide at your feet and narrow at the bowler's end. The
/// mown stripes bunch up towards the horizon. Fielders in the deep are small.
/// And — the one that actually matters for playing it — **the ball more than
/// doubles in size on its way down the pitch**, which is what makes timing
/// something you can see coming instead of something you guess.
///
/// The camera is deliberately much higher than a person's eye. A true 1.7m
/// viewpoint puts the pitch almost edge-on and you cannot read length at all.
/// Every cricket game cheats this and so does this one.
class PitchCamera {
  const PitchCamera({
    required this.eyeY,
    required this.facing,
    required this.focal,
    required this.lift,
    required this.rise,
    required this.horizon,
    required this.centreX,
    required this.screenWidth,
    required this.screenHeight,
  });

  /// A camera that has not been sized yet. Replaced on the first resize.
  static const PitchCamera unset = PitchCamera(
    eyeY: 1206,
    facing: -1,
    focal: 186,
    lift: 60000,
    rise: 300,
    horizon: 100,
    centreX: 195,
    screenWidth: 390,
    screenHeight: 660,
  );

  /// Where the eye stands, on the pitch's centre line.
  final double eyeY;

  /// -1 when looking down the pitch from behind the batter (you are batting),
  /// +1 when looking from behind the bowler (you are bowling).
  ///
  /// Two cameras rather than one because watching from behind the person you
  /// are bowling *to* is disorienting — the ball would travel away from you on
  /// your own delivery. Flipping the sign is the whole implementation.
  final int facing;

  /// Horizontal focal length, in screen pixels × field units.
  final double focal;

  /// Vertical constant: eye height × vertical focal length. Kept pre-multiplied
  /// because nothing needs the two separately.
  final double lift;

  /// How much a unit of height off the ground lifts something up the screen,
  /// before the perspective divide. Deliberately larger than [focal] — see
  /// [PitchCamera.forScreen].
  final double rise;

  /// Screen y that infinitely distant ground converges to. Everything above it
  /// is stand and sky.
  final double horizon;

  /// Screen x of the pitch's centre line.
  final double centreX;

  final double screenWidth;

  /// Screen height available to the scene — the band is already subtracted.
  final double screenHeight;

  /// Nothing closer than this is drawn: at the eye itself the divide explodes.
  static const double minDepth = 120;

  /// How tall a player is drawn, in field units.
  ///
  /// Nothing like life size — a real person is about twelve units against a
  /// 468-unit ground radius, and at twelve units nobody is visible at all. But
  /// the first version used 178, which is a twenty-six-metre human, and the
  /// result was a screen full of enormous people with a cricket ground
  /// somewhere behind them.
  static const double personHeight = 120;

  /// Whether somebody standing here is in front of the camera at all.
  ///
  /// Depth culling alone is not enough. Standing behind the striker, the
  /// keeper and slip are only a little nearer than the batter, so they survive
  /// [minDepth] and then fill the bottom of the screen with their backs. They
  /// are behind the player's own shoulder in real life and they belong off
  /// screen.
  bool showsSomeoneAt(double fieldY) {
    if (!isVisible(fieldY)) return false;
    return facing == -1
        ? fieldY <= CricketField.strikerCreaseY
        : fieldY >= CricketField.bowlerCreaseY;
  }

  /// Builds the camera for a screen, with the near and far ends of the ground
  /// pinned where they look right.
  ///
  /// The two anchors are the whole tuning surface: the batting crease sits low
  /// enough to leave room for the batter's feet, and the far rope sits just
  /// under the horizon so there is somewhere for the stands to be.
  factory PitchCamera.forScreen({
    required double width,
    required double height,
    required Role role,
  }) {
    final bowling = role == Role.bowling;

    // Just behind whichever end the player is at.
    //
    // How far back is not a taste decision. [minDepth] culls anything nearer
    // than 120 units, so putting the eye 154 units behind the striker puts the
    // keeper (y 1012), slip (1000) and fine leg (1180) *behind the camera* and
    // out of the picture. An earlier version stood further back and the first
    // thing on screen was the wicketkeeper's back, filling a third of it.
    final eyeY = bowling
        ? CricketField.bowlerCreaseY - 300
        : CricketField.strikerY + 230;
    final facing = bowling ? 1 : -1;

    // The depth of the player whose end this is: the anchor for everything.
    final nearDepth = bowling ? 300.0 : 230.0;
    final farDepth = bowling
        ? (CricketField.groundCentreY + CricketField.groundRadiusY) - eyeY
        : eyeY - (CricketField.groundCentreY - CricketField.groundRadiusY);

    const horizonFraction = 0.22;
    const nearFraction = 0.84;

    final horizon = height * horizonFraction;
    // screenY(nearDepth) == height * nearFraction
    final lift = (height * nearFraction - horizon) * nearDepth;

    // Sanity: the far rope has to land above the near crease and below the
    // horizon. It does for any sane eye position, but the arithmetic is worth
    // stating rather than assuming.
    assert(farDepth > nearDepth, 'the camera is inside the ground');

    // Wide enough that the ground fills the screen at its widest point.
    final middleDepth = (eyeY - CricketField.groundCentreY).abs();
    final focal = width * 0.47 * middleDepth / CricketField.groundRadiusX;

    return PitchCamera(
      eyeY: eyeY,
      facing: facing,
      focal: focal,
      lift: lift,
      // How far a unit of *height* lifts something up the screen.
      //
      // A physically honest camera would make this equal to `focal`, so a ball
      // one metre up moves exactly as far on screen as a ball one metre
      // sideways. But an honest camera that also fits the ground on a phone
      // has to sit almost on the deck, and from there you cannot read length
      // at all. So the vertical is stretched, as it is in every cricket game
      // ever made. 1.6x is where a six looks like a six and still lands back
      // in frame.
      rise: focal * 1.6,
      horizon: horizon,
      centreX: width / 2,
      screenWidth: width,
      screenHeight: height,
    );
  }

  /// How far in front of the eye a field point is. Negative means behind it.
  double depthOf(double fieldY) =>
      facing == -1 ? eyeY - fieldY : fieldY - eyeY;

  bool isVisible(double fieldY) => depthOf(fieldY) > minDepth;

  /// The perspective divide, once.
  double scaleAt(double fieldY) =>
      focal / math.max(depthOf(fieldY), minDepth);

  /// Field point to screen point. [height] is off the ground, in field units.
  Offset project(double fieldX, double fieldY, [double height = 0]) {
    final d = math.max(depthOf(fieldY), minDepth);
    // Looking the other way mirrors left and right, so that "off side" stays
    // on the same side of the screen as the player's own body.
    final lateral = (fieldX - CricketField.pitchCentreX) * -facing;
    return Offset(
      centreX + lateral * focal / d,
      horizon + (lift - height * rise) / d,
    );
  }

  Offset projectVec(Vec2 at, [double height = 0]) =>
      project(at.x, at.y, height);

  /// The angle on a ground-centred ellipse that is *nearest* the camera, and
  /// therefore certainly behind it.
  ///
  /// Sampling an ellipse has to start somewhere invisible and sweep, because
  /// the visible part is one arc that wraps across angle zero. Starting at
  /// angle zero instead splits that arc in two and you get a quarter of the
  /// boundary drawn and three quarters missing — which is exactly what the
  /// first version did.
  double get nearestAngle => facing == -1 ? math.pi / 2 : -math.pi / 2;
}
