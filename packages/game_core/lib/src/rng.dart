/// A seeded xorshift128 generator.
///
/// `dart:math`'s `Random` is unsuitable here: it is not specified to produce
/// the same sequence across SDK versions or platforms, so a match replayed on
/// the server could diverge from the one the player actually saw. xorshift128
/// is fully specified in integer arithmetic, so it does not.
///
/// All state is held in four 32-bit words and every operation is masked back to
/// 32 bits, which keeps the generator identical on 64-bit native and on the web
/// (where Dart ints are doubles and only exact below 2^53).
class DeterministicRng {
  /// Seeds a generator from a 64-bit [seed] — in production, the match nonce
  /// issued by the server.
  DeterministicRng(int seed) {
    // A 32-bit LCG expands the seed into four state words. The multiply stays
    // under 2^53 so it is exact on every platform.
    var s = seed & 0xFFFFFFFF;
    int next() {
      s = (s * 1664525 + 1013904223) & 0xFFFFFFFF;
      return s;
    }

    _x = next();
    _y = next();
    _z = next();
    _w = next();
    // xorshift's one degenerate state is all-zero; it would emit zeros forever.
    if ((_x | _y | _z | _w) == 0) _x = 0x9E3779B9;
  }

  /// An independent stream derived from the same match [seed].
  ///
  /// Use a distinct [streamId] per consumer (serves, bot aim, bot mistakes) so
  /// that adding a random call in one system cannot shift the sequence another
  /// system sees — which would otherwise silently change replay behaviour.
  factory DeterministicRng.stream(int seed, int streamId) =>
      DeterministicRng(seed ^ (streamId * 0x9E3779B1));

  late int _x, _y, _z, _w;

  /// The next raw 32-bit value.
  int nextUint32() {
    final t = (_x ^ ((_x << 11) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    _x = _y;
    _y = _z;
    _z = _w;
    _w = (_w ^ (_w >> 19) ^ t ^ (t >> 8)) & 0xFFFFFFFF;
    return _w;
  }

  /// A double in `[0, 1)`.
  double nextDouble() => nextUint32() / 4294967296.0;

  /// A double in `[lo, hi)`.
  double nextRange(double lo, double hi) => lo + (hi - lo) * nextDouble();

  /// An int in `[0, max)`.
  int nextInt(int max) => nextUint32() % max;

  /// True with probability [p].
  bool chance(double p) => nextDouble() < p;

  /// `-1.0` or `1.0`, evenly.
  double nextSign() => nextUint32() & 1 == 0 ? -1.0 : 1.0;
}
