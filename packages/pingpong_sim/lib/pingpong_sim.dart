/// The ping pong simulation, with no rendering in it.
///
/// This package imports `game_core` and nothing else — no Flutter, no Flame. It
/// is the half of the game that the server can run: given a match seed and the
/// recorded human input, [PingPongSimulation] reproduces the exact final score
/// the player saw. If it doesn't, the submission was tampered with.
library;

export 'src/bot.dart';
export 'src/field.dart';
export 'src/replay_harness.dart';
export 'src/simulation.dart';
export 'src/state.dart';
