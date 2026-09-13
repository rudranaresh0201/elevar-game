import 'dart:math' as math;
import 'dart:ui';

import 'package:penalty_sim/penalty_sim.dart';

/// A pinhole camera standing behind the penalty spot, looking at the goal.
///
/// The simulation knows nothing about it. The same projection is used to draw
/// the scene and, inverted, to turn a finger on the glass into a point in the
/// goal mouth — which is why it lives in one place.
class PenaltyCamera {
  PenaltyCamera(Size screen) {
    width = screen.width;
    height = screen.height;
    horizon = height * 0.3;
    final byWidth = 0.86 * width * cameraZ / (Goal.halfWidth * 2);
    // Keep the ball on screen on short, wide devices.
    final byHeight =
        (height * 0.8 - horizon) * (cameraZ - Goal.spotZ) / cameraY;
    focal = math.min(byWidth, byHeight);
  }

  static const double cameraY = 3.1;
  static const double cameraZ = 17.5;

  late final double width;
  late final double height;
  late final double horizon;
  late final double focal;

  /// Screen position and pixels-per-metre at that depth.
  (Offset, double) project(double x, double y, double z) {
    final depth = math.max(0.5, cameraZ - z);
    final scale = focal / depth;
    return (
      Offset(width / 2 + x * scale, horizon + (cameraY - y) * scale),
      scale,
    );
  }

  Offset at(double x, double y, double z) => project(x, y, z).$1;

  /// The point in the plane `z = [planeZ]` under a screen position.
  GoalPoint unproject(Offset screen, {double planeZ = 0}) {
    final depth = cameraZ - planeZ;
    return GoalPoint(
      (screen.dx - width / 2) * depth / focal,
      cameraY - (screen.dy - horizon) * depth / focal,
    );
  }
}
