import 'package:game_core/game_core.dart';

/// The hills, side on. **y points up** here — height above the bottom of the
/// world — because every question the game asks is "is the arrow below the
/// ground yet", and that reads better the right way up.
class Terrain {
  Terrain._(this.heights);

  /// A seeded landscape: two standing ledges and a hill between them.
  ///
  /// No noise functions and no trigonometry. The hill is a smooth polynomial
  /// bump, `(1 - u²)²`, which is flat where it meets the ground and costs
  /// nothing to evaluate identically on every platform.
  factory Terrain.generate(int seed) {
    final rng = DeterministicRng.stream(seed, 9);
    final leftLedge = rng.nextRange(140, 320);
    final rightLedge = rng.nextRange(140, 320);
    final hillCentre = rng.nextRange(1000, 1400);
    final hillHalfWidth = rng.nextRange(380, 560);
    final hillHeight = rng.nextRange(180, 620);
    final bumps = List<double>.generate(8, (_) => rng.nextRange(-28, 28));

    final heights = List<double>.generate(sampleCount, (i) {
      final x = i * spacing;
      final t = clampD((x - 300) / (width - 600), 0, 1);
      final smooth = t * t * (3 - 2 * t);
      var h = leftLedge + (rightLedge - leftLedge) * smooth;

      final u = (x - hillCentre) / hillHalfWidth;
      if (u.abs() < 1) {
        final k = 1 - u * u;
        h += hillHeight * k * k;
      }
      // Gentle lumps, faded out near the ledges so nobody stands on a slope.
      final lumpIndex = (x / width * (bumps.length - 1));
      final lo = _clampInt(lumpIndex.floor(), 0, bumps.length - 2);
      final f = lumpIndex - lo;
      final lump = bumps[lo] + (bumps[lo + 1] - bumps[lo]) * f;
      final nearLedge = (x - p1X).abs() < 220 || (x - p2X).abs() < 220;
      if (!nearLedge) h += lump;
      return h;
    });
    return Terrain._(heights);
  }

  static const double width = 2400;
  static const double spacing = 20;
  static const int sampleCount = 121;

  static const double p1X = 300;
  static const double p2X = 2100;

  final List<double> heights;

  double heightAt(double x) {
    final f = clampD(x, 0, width) / spacing;
    final i = _clampInt(f.floor(), 0, sampleCount - 2);
    final t = f - i;
    return heights[i] + (heights[i + 1] - heights[i]) * t;
  }

  static int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
}
