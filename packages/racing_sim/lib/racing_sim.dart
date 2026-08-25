/// The car racing simulation, with no rendering in it.
///
/// This package imports `game_core` and nothing else — no Flutter, no Flame. It
/// is the half of the game the server can run: given a race seed and the
/// recorded driver input, [RaceSimulation] reproduces the exact finishing order
/// the players saw. If it doesn't, the submission was tampered with.
///
/// Two rules from `game_core`'s determinism contract bite harder here than they
/// did in ping pong, and both have a named answer in this package:
///
/// * **No trigonometry.** A car has a heading, and steering rotates it. The
///   rotation is a complex multiply by `(1, k)` followed by a normalise —
///   `RaceSimulation._rotate` — so no angle is ever formed and `sin`/`cos`
///   never appear. The circuits are literal coordinates smoothed by a
///   polynomial spline for the same reason.
/// * **Input must be quantised on the live path.** Steering is one of three
///   values, and [CarInput.fromChannels] snaps the replay's 16-bit grid back
///   onto exactly those three. Without it, a "straight" car drifts a fraction
///   of a degree per lap and the replay eventually disagrees about who won.
library;

export 'src/bot.dart';
export 'src/field.dart';
export 'src/replay_harness.dart';
export 'src/simulation.dart';
export 'src/state.dart';
export 'src/track.dart';
export 'src/tracks.dart';
