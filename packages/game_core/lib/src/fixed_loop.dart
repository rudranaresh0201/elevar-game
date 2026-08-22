/// Converts variable frame times into a whole number of identical simulation
/// steps.
///
/// This is the single most important piece of the determinism contract. A
/// simulation that integrates by raw frame delta produces a different result on
/// a 90 Hz phone than on a 60 Hz one, and a different result again on a frame
/// that happened to drop — which makes server-side replay verification
/// impossible. Here, rendering runs at whatever rate the device manages while
/// the simulation always advances in exact `1 / tickHz` increments.
class FixedLoop {
  FixedLoop({this.tickHz = 120, this.maxFrameSeconds = 0.25})
      : assert(tickHz > 0);

  /// Simulation frequency. 120 Hz gives a fast ball two steps per rendered
  /// frame at 60 fps, which keeps collision response visually smooth.
  final int tickHz;

  /// Longest frame the loop will honour. Without this cap, a frame stalled by a
  /// GC pause or a backgrounded app would queue hundreds of steps, which take
  /// longer to run than the frame budget, which queues more steps — the classic
  /// "spiral of death". Time past the cap is discarded.
  final double maxFrameSeconds;

  double get stepSeconds => 1.0 / tickHz;

  int _tick = 0;
  double _accumulator = 0;

  /// Number of steps run since construction.
  int get tick => _tick;

  /// Fraction of a step already accumulated, in `[0, 1)`.
  ///
  /// Renderers use this to interpolate between the previous and current
  /// simulation state, so motion looks smooth even though the simulation runs
  /// at a different rate than the display.
  double get alpha => _accumulator / stepSeconds;

  /// Advances by [dtSeconds] of real time, invoking [step] once per elapsed
  /// simulation tick. Returns how many steps ran.
  int advance(double dtSeconds, void Function(int tick) step) {
    var dt = dtSeconds;
    if (dt < 0) dt = 0;
    if (dt > maxFrameSeconds) dt = maxFrameSeconds;

    _accumulator += dt;
    var steps = 0;
    while (_accumulator >= stepSeconds) {
      step(_tick);
      _tick++;
      _accumulator -= stepSeconds;
      steps++;
    }
    return steps;
  }

  /// Runs exactly [count] steps, ignoring wall-clock time entirely.
  ///
  /// This is how the headless verifier replays a match: no frames, no real
  /// time, just the tick sequence the player's device produced.
  void advanceTicks(int count, void Function(int tick) step) {
    for (var i = 0; i < count; i++) {
      step(_tick);
      _tick++;
    }
  }

  void reset() {
    _tick = 0;
    _accumulator = 0;
  }
}
