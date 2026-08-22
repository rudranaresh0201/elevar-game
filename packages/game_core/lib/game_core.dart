/// Deterministic simulation primitives shared by every Elevar game.
///
/// Nothing in this package imports Flutter, Flame, or `dart:ui`. That is a hard
/// rule, not a preference: the same code must run inside the app *and* inside a
/// headless server worker that re-simulates a submitted match to verify its
/// score (see `docs/PLAN.md` §9, replay verification).
///
/// ## The determinism contract
///
/// Given the same seed and the same input log, a simulation built on these
/// primitives must produce a bit-identical result on every platform. That holds
/// only if you obey three rules:
///
/// 1. **Fixed timestep only.** Never integrate by wall-clock delta. Use
///    [FixedLoop], which converts variable frame times into a whole number of
///    identical steps.
/// 2. **No transcendental math.** `sin`, `cos`, `tan`, `atan2`, `exp` and `pow`
///    are implemented by the platform's libm and are *not* guaranteed to agree
///    bit-for-bit across architectures. `sqrt` is safe — IEEE-754 requires it to
///    be correctly rounded — so all direction math here is vector math, never
///    angle math.
/// 3. **No ambient randomness.** `dart:math`'s `Random` is unseeded and unsafe.
///    Use [DeterministicRng], seeded from the server-issued match nonce.
library;

export 'src/aabb.dart';
export 'src/fixed_loop.dart';
export 'src/game_result.dart';
export 'src/replay.dart';
export 'src/rng.dart';
export 'src/sweep.dart';
export 'src/vec2.dart';
